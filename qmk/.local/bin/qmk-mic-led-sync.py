#!/usr/bin/env python3
"""Sync system state (mic mute, DND, voxtype, pomodoro) to the Framework 16
ANSI keyboard LEDs.

Polls system state on a short interval. When something changes, sends a
32-byte raw-HID packet to the keyboard:

    [cmd, payload, 0, 0, ..., 0]
       cmd 0x10 = mic mute state — payload 0=unmuted, 1=muted
       cmd 0x11 = DND state      — payload 0=active,  1=silenced
       cmd 0x12 = voxtype state  — payload 0=idle,    1=active
       cmd 0x13 = pomodoro state — payload [phase, paused, segments_lit]

Also listens for inbound reports from the keyboard:

       cmd 0x20 = pomodoro control event — payload [event]
                  event 1=toggle, 2=skip, 3=reset

Reopens the device on disconnect so the daemon survives keyboard unplug/replug.
"""

from __future__ import annotations

import glob
import math
import random
import subprocess
import sys
import threading
import time

import hid
import serial

VID = 0x32AC          # Framework
PID = 0x0012          # Laptop 16 ANSI
USAGE_PAGE = 0xFF60   # raw HID
USAGE = 0x61
PACKET_LEN = 32
CMD_MIC  = 0x10
CMD_DND  = 0x11
CMD_VOX  = 0x12
CMD_POMO = 0x13
EVT_POMO = 0x20
POLL_INTERVAL = 0.2   # seconds

# Pomodoro phase IDs (must match keymap.c)
PH_IDLE  = 0
PH_WORK  = 1
PH_SHORT = 2
PH_LONG  = 3

# Phase durations in seconds.
PHASE_SECS = {
    PH_WORK:  25 * 60,
    PH_SHORT:  5 * 60,
    PH_LONG:  15 * 60,
}
# How many work intervals before a long break.
WORKS_PER_LONG = 4

PHASE_NAMES = {
    PH_WORK: "Work", PH_SHORT: "Short break", PH_LONG: "Long break",
}


class Pomodoro:
    """In-memory pomodoro state machine. Time is monotonic seconds."""

    def __init__(self) -> None:
        self.phase = PH_IDLE
        self.phase_started_at = 0.0
        self.paused_at: float | None = None
        self.accumulated_pause = 0.0
        self.works_done = 0  # work phases completed in the current cycle
        # When a phase's timer expires we no longer auto-advance: we sit in an
        # "awaiting ack" state until the user taps the pomodoro key. The matrix
        # driver shows fireworks (post-work) or bubbles (post-break) during this.
        self.awaiting_ack = False
        self.finished_phase = PH_IDLE  # the phase that just expired (valid while awaiting_ack)

    # --- queries ---

    def now_elapsed(self, now: float) -> float:
        if self.phase == PH_IDLE:
            return 0.0
        pause = self.accumulated_pause
        if self.paused_at is not None:
            pause += now - self.paused_at
        return now - self.phase_started_at - pause

    def remaining(self, now: float) -> float:
        total = PHASE_SECS.get(self.phase, 0)
        return max(0.0, total - self.now_elapsed(now))

    def segments(self, now: float) -> int:
        total = PHASE_SECS.get(self.phase, 0)
        if total <= 0:
            return 0
        # ceil so the bar shows "10 of 10" until the first tenth elapses.
        return max(0, min(10, math.ceil(self.remaining(now) / total * 10)))

    def is_paused(self) -> bool:
        return self.paused_at is not None

    # --- transitions ---

    def _enter(self, phase: int, now: float) -> None:
        self.phase = phase
        self.phase_started_at = now
        self.paused_at = None
        self.accumulated_pause = 0.0

    def _phase_after(self, finished: int) -> int:
        # work → short (or long after WORKS_PER_LONG works) → work → ...
        if finished == PH_WORK:
            return PH_LONG if self.works_done % WORKS_PER_LONG == 0 else PH_SHORT
        return PH_WORK

    def toggle(self, now: float) -> str:
        if self.awaiting_ack:
            nxt = self._phase_after(self.finished_phase)
            self._enter(nxt, now)
            self.awaiting_ack = False
            return f"{PHASE_NAMES[nxt]} started"
        if self.phase == PH_IDLE:
            self.works_done = 0
            self._enter(PH_WORK, now)
            return "Work session started"
        if self.paused_at is None:
            self.paused_at = now
            return f"{PHASE_NAMES[self.phase]} paused"
        self.accumulated_pause += now - self.paused_at
        self.paused_at = None
        return f"{PHASE_NAMES[self.phase]} resumed"

    def skip(self, now: float) -> str:
        if self.awaiting_ack:
            nxt = self._phase_after(self.finished_phase)
            self._enter(nxt, now)
            self.awaiting_ack = False
            return f"Skipped to {PHASE_NAMES[nxt].lower()}"
        if self.phase == PH_IDLE:
            return ""
        # Mid-phase skip: count it as completed if it was a work phase, then jump.
        finished = self.phase
        if finished == PH_WORK:
            self.works_done += 1
        nxt = self._phase_after(finished)
        self._enter(nxt, now)
        return f"Skipped to {PHASE_NAMES[nxt].lower()}"

    def reset(self) -> str:
        was_active = self.phase != PH_IDLE or self.awaiting_ack
        self.phase = PH_IDLE
        self.paused_at = None
        self.accumulated_pause = 0.0
        self.works_done = 0
        self.awaiting_ack = False
        return "Pomodoro reset" if was_active else ""

    def tick(self, now: float) -> str | None:
        """Mark phase done if its timer expired. Does NOT auto-advance —
        sets awaiting_ack and waits for the user to tap pomodoro-toggle."""
        if self.phase == PH_IDLE or self.paused_at is not None or self.awaiting_ack:
            return None
        if self.remaining(now) > 0:
            return None
        finished = self.phase
        if finished == PH_WORK:
            self.works_done += 1
        self.finished_phase = finished
        self.awaiting_ack = True
        return f"{PHASE_NAMES[finished]} done — tap pomodoro to continue"


def notify(summary: str) -> None:
    if not summary:
        return
    try:
        subprocess.Popen(
            ["notify-send", "-a", "pomodoro", summary],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except FileNotFoundError:
        pass


def find_raw_hid_path() -> bytes | None:
    """Return the hidraw path of the keyboard's raw-HID interface, or None."""
    for d in hid.enumerate(VID, PID):
        if d.get("usage_page") == USAGE_PAGE and d.get("usage") == USAGE:
            return d["path"]
    return None


def query_mic_muted() -> bool | None:
    """True if mic is muted, False if not, None on error."""
    try:
        out = subprocess.check_output(
            ["pactl", "get-source-mute", "@DEFAULT_SOURCE@"],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=1.0,
        ).strip()
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError):
        return None
    return out.endswith("yes")  # "Mute: yes" / "Mute: no"


def query_dnd_silenced() -> bool | None:
    """True if mako mode is do-not-disturb, False otherwise, None on error."""
    try:
        out = subprocess.check_output(
            ["makoctl", "mode"],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=1.0,
        ).strip()
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError):
        return None
    # `makoctl mode` lists active modes one per line.
    return "do-not-disturb" in out.splitlines()


def query_vox_active() -> bool | None:
    """True if voxtype is recording/active, False if idle, None if unavailable.

    `voxtype status --format json` returns one JSON object per state. Without
    --follow it should print the current state once. The "class" field is
    something like "idle", "recording", "transcribing".
    """
    try:
        out = subprocess.check_output(
            ["voxtype", "status", "--format", "json"],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=1.0,
        ).strip()
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError):
        return None
    # Take the first JSON line (last is also fine — we expect one).
    first = out.splitlines()[0] if out else ""
    try:
        import json
        cls = json.loads(first).get("class", "")
    except (ValueError, json.JSONDecodeError):
        return None
    return cls != "idle" and cls != ""


# ---------------------------------------------------------------------------
# Framework LED Matrix input module driver
# ---------------------------------------------------------------------------
# Protocol (over USB-CDC at 115200): each frame stages 9 columns of 34
# greyscale bytes via [0x32,0xAC, 0x07, x] + vals, then commits with
# [0x32,0xAC, 0x08, 0x00].

MATRIX_W = 9
MATRIX_H = 34
MATRIX_MAGIC = bytes([0x32, 0xAC])
MATRIX_CMD_BRIGHTNESS  = 0x00
MATRIX_CMD_STAGE_COL   = 0x07
MATRIX_CMD_DRAW_BUFFER = 0x08
MATRIX_DEV_GLOB = "/dev/serial/by-id/usb-Framework_Computer_Inc_LED_Matrix_Input_Module_*-if00"
MATRIX_FPS = 15


# A tiny 3x5 font for digits 0-9, used to stamp the pomodoro count after a work
# phase. Each glyph is 5 rows of 3 columns; '#' = on, '.' = off. Top row first.
_DIGIT_GLYPHS = {
    "0": ["###", "#.#", "#.#", "#.#", "###"],
    "1": [".#.", "##.", ".#.", ".#.", "###"],
    "2": ["###", "..#", "###", "#..", "###"],
    "3": ["###", "..#", ".##", "..#", "###"],
    "4": ["#.#", "#.#", "###", "..#", "..#"],
    "5": ["###", "#..", "###", "..#", "###"],
    "6": ["###", "#..", "###", "#.#", "###"],
    "7": ["###", "..#", "..#", "..#", "..#"],
    "8": ["###", "#.#", "###", "#.#", "###"],
    "9": ["###", "#.#", "###", "..#", "###"],
}


def _stamp_digits(frame: list[list[int]], text: str, top_row: int, val: int) -> None:
    """Draw a digit string centered horizontally onto `frame` at row `top_row`."""
    glyphs = [_DIGIT_GLYPHS.get(c) for c in text if c in _DIGIT_GLYPHS]
    if not glyphs:
        return
    width = len(glyphs) * 4 - 1  # 3-wide digits, 1-col gap between
    x0 = max(0, (MATRIX_W - width) // 2)
    for gi, g in enumerate(glyphs):
        gx = x0 + gi * 4
        for ry, row in enumerate(g):
            y = top_row + ry
            if not (0 <= y < MATRIX_H):
                continue
            for cx, ch in enumerate(row):
                x = gx + cx
                if 0 <= x < MATRIX_W and ch == "#":
                    frame[x][y] = val


class MatrixDriver(threading.Thread):
    """Renders pomodoro state to the Framework LED matrix.

    Reads pomodoro state from the shared Pomodoro object (no locking — Python
    GIL makes our individual attribute reads atomic, and we tolerate a frame's
    worth of staleness). Reopens the serial device on disconnect.
    """

    def __init__(self, pomo: Pomodoro) -> None:
        super().__init__(daemon=True)
        self.pomo = pomo
        self._stop = threading.Event()
        self._serial: serial.Serial | None = None
        # Particle systems for the awaiting-ack animations.
        self._fw_rockets: list[dict] = []
        self._fw_particles: list[dict] = []
        self._fw_next_spawn = 0.0
        self._bubbles: list[dict] = []
        self._bubble_next_spawn = 0.0
        # Track state transitions so we can clear particle lists.
        self._last_render_state: tuple = ()

    def stop(self) -> None:
        self._stop.set()

    # -- serial port management -------------------------------------------------

    def _open(self) -> bool:
        if self._serial is not None:
            return True
        paths = sorted(glob.glob(MATRIX_DEV_GLOB))
        if not paths:
            return False
        try:
            self._serial = serial.Serial(paths[0], 115200, timeout=0.1, write_timeout=0.5)
        except (OSError, serial.SerialException):
            self._serial = None
            return False
        return True

    def _close(self) -> None:
        if self._serial is not None:
            try:
                self._serial.close()
            except Exception:
                pass
        self._serial = None

    def _write(self, data: bytes) -> bool:
        if self._serial is None:
            return False
        try:
            self._serial.write(data)
            return True
        except (OSError, serial.SerialException):
            self._close()
            return False

    def _send_brightness(self, b: int) -> None:
        self._write(MATRIX_MAGIC + bytes([MATRIX_CMD_BRIGHTNESS, b & 0xFF]))

    def _send_frame(self, frame: list[list[int]]) -> None:
        # Stage all 9 columns, then commit. One write per column keeps each
        # message under the controller's input buffer.
        for x in range(MATRIX_W):
            col = bytes(max(0, min(255, v)) for v in frame[x])
            if not self._write(MATRIX_MAGIC + bytes([MATRIX_CMD_STAGE_COL, x]) + col):
                return
        self._write(MATRIX_MAGIC + bytes([MATRIX_CMD_DRAW_BUFFER, 0x00]))

    def _blank(self) -> list[list[int]]:
        return [[0] * MATRIX_H for _ in range(MATRIX_W)]

    # -- animations ------------------------------------------------------------

    def _render_breathing(self, t: float) -> list[list[int]]:
        # 10-second breath cycle. Gamma-corrected so perceived brightness ramps
        # smoothly even at the dim end (raw PWM values <30 jump visibly without
        # gamma). Peak ~110/255, valley ~0.
        phase = (math.sin(t * 2.0 * math.pi / 10.0) + 1.0) * 0.5  # 0..1
        v = int((phase ** 2.6) * 110)
        return [[v] * MATRIX_H for _ in range(MATRIX_W)]

    def _render_fireworks(self, t: float, dt: float, count: int) -> list[list[int]]:
        # Spawn a rocket every ~0.9-1.4s.
        if t >= self._fw_next_spawn:
            self._fw_rockets.append({
                "x": float(random.randint(1, MATRIX_W - 2)),
                "y": float(MATRIX_H - 1),
                "vy": -random.uniform(14.0, 20.0),  # cells/s upward
                "burst_y": float(random.randint(4, 14)),
            })
            self._fw_next_spawn = t + random.uniform(0.9, 1.4)

        # Advance rockets; explode on reaching burst altitude.
        next_rockets = []
        for r in self._fw_rockets:
            r["y"] += r["vy"] * dt
            if r["y"] <= r["burst_y"]:
                # Explode: 12-18 particles in a ring, slight gravity.
                n = random.randint(12, 18)
                for i in range(n):
                    a = (i / n) * 2.0 * math.pi + random.uniform(-0.1, 0.1)
                    speed = random.uniform(5.0, 9.0)
                    self._fw_particles.append({
                        "x": r["x"], "y": r["y"],
                        "vx": math.cos(a) * speed,
                        "vy": math.sin(a) * speed,
                        "life": 1.0,  # 1.0 → 0.0 over ~1s
                    })
            else:
                next_rockets.append(r)
        self._fw_rockets = next_rockets

        # Advance particles.
        next_parts = []
        for p in self._fw_particles:
            p["x"] += p["vx"] * dt
            p["y"] += p["vy"] * dt
            p["vy"] += 6.0 * dt  # gravity
            p["life"] -= dt * 1.1
            if p["life"] > 0 and 0 <= p["y"] < MATRIX_H and 0 <= p["x"] < MATRIX_W:
                next_parts.append(p)
        self._fw_particles = next_parts

        frame = self._blank()
        # Rocket trails: bright head + fading tail of 2 cells below.
        for r in self._fw_rockets:
            x, y = int(round(r["x"])), int(round(r["y"]))
            for dy, b in ((0, 220), (1, 110), (2, 50)):
                yy = y + dy
                if 0 <= x < MATRIX_W and 0 <= yy < MATRIX_H:
                    frame[x][yy] = max(frame[x][yy], b)
        # Particles, brightness scaled by life.
        for p in self._fw_particles:
            x, y = int(round(p["x"])), int(round(p["y"]))
            b = int(220 * max(0.0, p["life"]))
            if 0 <= x < MATRIX_W and 0 <= y < MATRIX_H:
                frame[x][y] = max(frame[x][y], b)

        # Stamp the pomodoro count near the top in dim white so it persists.
        if count > 0:
            _stamp_digits(frame, str(count), top_row=1, val=80)
        return frame

    def _render_bubbles(self, t: float, dt: float) -> list[list[int]]:
        if t >= self._bubble_next_spawn:
            self._bubbles.append({
                "x": float(random.randint(0, MATRIX_W - 1)),
                "y": float(MATRIX_H - 1),
                "vy": -random.uniform(2.5, 5.5),  # cells/s upward
                "r": random.choice([0, 0, 1]),    # 0 = single pixel, 1 = small ring
                "phase": random.uniform(0, 2 * math.pi),
            })
            self._bubble_next_spawn = t + random.uniform(0.25, 0.55)

        next_bubbles = []
        for b in self._bubbles:
            b["y"] += b["vy"] * dt
            # Gentle horizontal wobble.
            b["x"] += math.sin(t * 2.0 + b["phase"]) * 0.6 * dt
            if b["y"] > -2:
                next_bubbles.append(b)
        self._bubbles = next_bubbles

        frame = self._blank()
        for b in self._bubbles:
            x, y = int(round(b["x"])), int(round(b["y"]))
            # Fade in last ~5 rows at top; full brightness elsewhere.
            fade = 1.0 if b["y"] > 4 else max(0.0, b["y"] / 5.0)
            core = int(180 * fade)
            ring = int(70 * fade)
            if 0 <= x < MATRIX_W and 0 <= y < MATRIX_H:
                frame[x][y] = max(frame[x][y], core)
            if b["r"] >= 1:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    xx, yy = x + dx, y + dy
                    if 0 <= xx < MATRIX_W and 0 <= yy < MATRIX_H:
                        frame[xx][yy] = max(frame[xx][yy], ring)
        return frame

    # -- main loop -------------------------------------------------------------

    def run(self) -> None:
        period = 1.0 / MATRIX_FPS
        last_t = time.monotonic()
        last_state_kind: str | None = None
        while not self._stop.is_set():
            if not self._open():
                time.sleep(1.0)
                last_t = time.monotonic()
                continue

            now = time.monotonic()
            dt = max(0.0, min(0.1, now - last_t))
            last_t = now

            # Snapshot pomo state.
            phase = self.pomo.phase
            awaiting = self.pomo.awaiting_ack
            paused = self.pomo.is_paused()
            finished = self.pomo.finished_phase
            count = self.pomo.works_done

            if awaiting:
                kind = "fireworks" if finished == PH_WORK else "bubbles"
            elif phase == PH_IDLE:
                kind = "idle"
            elif paused:
                kind = "paused"
            else:
                kind = "active"

            # On state change, reset particle state and ensure full brightness.
            if kind != last_state_kind:
                self._fw_rockets.clear()
                self._fw_particles.clear()
                self._bubbles.clear()
                self._fw_next_spawn = now
                self._bubble_next_spawn = now
                self._send_brightness(0xFF)
                last_state_kind = kind

            if kind == "idle":
                self._send_frame(self._blank())
            elif kind == "active":
                # Matrix stays dark during active phases — keyboard bar carries it.
                self._send_frame(self._blank())
            elif kind == "paused":
                # Hold a dim static glow so it's clearly different from active breathing.
                v = 4
                self._send_frame([[v] * MATRIX_H for _ in range(MATRIX_W)])
            elif kind == "fireworks":
                self._send_frame(self._render_fireworks(now, dt, count))
            elif kind == "bubbles":
                self._send_frame(self._render_bubbles(now, dt))

            # Frame pacing: sleep the remainder of the period.
            elapsed = time.monotonic() - now
            time.sleep(max(0.0, period - elapsed))

        # Clean shutdown: blank the matrix.
        if self._serial is not None:
            self._send_frame(self._blank())
            self._close()


def send_packet(dev: "hid.Device", cmd: int, payload: int) -> None:
    # Report ID 0x00 (unnumbered) + payload, 33 bytes total for hidraw write.
    pkt = bytes([0x00, cmd, payload]) + bytes(PACKET_LEN - 2)
    dev.write(pkt)


def send_pomo(dev: "hid.Device", phase: int, paused: bool, segments: int) -> None:
    pkt = bytes([0x00, CMD_POMO, phase, 1 if paused else 0, segments]) + bytes(PACKET_LEN - 4)
    dev.write(pkt)


def handle_inbound(dev: "hid.Device", pomo: Pomodoro, now: float) -> str | None:
    """Drain any pending inbound reports; return notification text if any."""
    msg: str | None = None
    while True:
        try:
            data = dev.read(PACKET_LEN, timeout=0)
        except (OSError, hid.HIDException):
            raise
        if not data:
            return msg
        if len(data) >= 2 and data[0] == EVT_POMO:
            event = data[1]
            if event == 1:
                msg = pomo.toggle(now)
            elif event == 2:
                msg = pomo.skip(now)
            elif event == 3:
                msg = pomo.reset()


def main() -> int:
    last_mic: bool | None = None
    last_dnd: bool | None = None
    last_vox: bool | None = None
    last_pomo: tuple[int, bool, int] | None = None
    dev: "hid.Device | None" = None
    pomo = Pomodoro()
    matrix = MatrixDriver(pomo)
    matrix.start()
    while True:
        try:
            if dev is None:
                path = find_raw_hid_path()
                if path is None:
                    time.sleep(1.0)
                    continue
                dev = hid.Device(path=path)
                last_mic = last_dnd = last_vox = None  # force resync after (re)connect
                last_pomo = None

            now = time.monotonic()

            # Inbound: keyboard control events.
            ctrl_msg = handle_inbound(dev, pomo, now)
            if ctrl_msg:
                notify(ctrl_msg)

            # Pomodoro phase expiry.
            expiry_msg = pomo.tick(now)
            if expiry_msg:
                notify(expiry_msg)

            mic = query_mic_muted()
            if mic is not None and mic != last_mic:
                send_packet(dev, CMD_MIC, 1 if mic else 0)
                last_mic = mic

            dnd = query_dnd_silenced()
            if dnd is not None and dnd != last_dnd:
                send_packet(dev, CMD_DND, 1 if dnd else 0)
                last_dnd = dnd

            vox = query_vox_active()
            if vox is not None and vox != last_vox:
                send_packet(dev, CMD_VOX, 1 if vox else 0)
                last_vox = vox

            pomo_state = (pomo.phase, pomo.is_paused(), pomo.segments(now))
            if pomo_state != last_pomo:
                send_pomo(dev, *pomo_state)
                last_pomo = pomo_state

            time.sleep(POLL_INTERVAL)
        except (OSError, hid.HIDException):
            # Likely device disconnect — clean up and try to reopen.
            if dev is not None:
                try:
                    dev.close()
                except Exception:
                    pass
            dev = None
            time.sleep(1.0)
        except KeyboardInterrupt:
            matrix.stop()
            matrix.join(timeout=1.0)
            return 0


if __name__ == "__main__":
    sys.exit(main())
