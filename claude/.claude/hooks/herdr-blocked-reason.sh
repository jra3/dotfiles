#!/bin/sh
# Reports *why* a Claude pane is blocked to the Herdr sidebar (SPY-5), plus
# the session's model and context usage as $model / $ctx tokens (SPY-6).
#
# Sits beside herdr-agent-state.sh, which is managed by Herdr and gets
# overwritten on integration updates. This file is ours.
#
# Herdr's own detection owns the semantic state (idle/working/blocked/done).
# This hook only supplies presentation metadata, which cannot override that
# state, corrupt notifications, or affect workspace rollups.
#
#   herdr-blocked-reason.sh pending   <- PreToolUse:  stash the tool being asked about
#   herdr-blocked-reason.sh blocked   <- Notification: publish the label
#   herdr-blocked-reason.sh clear     <- PostToolUse/Stop/UserPromptSubmit: drop it
#
# The clear path also refreshes $model / $ctx, so SPY-6 needed no new wiring in
# settings.json. Those three events are all async, and the refresh throttles
# itself down to a subprocess only when the rendered value actually changes.

set -eu

action="${1:-}"
hook_input_file="$(mktemp "${TMPDIR:-/tmp}/herdr-blocked-hook.XXXXXX")" || exit 0
trap 'rm -f "$hook_input_file"' EXIT HUP INT TERM
cat >"$hook_input_file" 2>/dev/null || true

case "$action" in
  pending|blocked|clear) ;;
  *) exit 0 ;;
esac

# Same guards the managed integration uses: only act inside a Herdr pane.
[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -n "${HERDR_SOCKET_PATH:-}" ] || exit 0
[ -n "${HERDR_PANE_ID:-}" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
command -v herdr >/dev/null 2>&1 || exit 0

HERDR_ACTION="$action" HERDR_HOOK_INPUT_FILE="$hook_input_file" python3 - <<'PY'
import json
import os
import re
import subprocess
import time

SOURCE = "user:blocked-reason"
TTL_MS = 1800000  # 30min backstop so a missed clear can't strand a label

# Tokens ride a separate source so clearing a blocked label never touches them.
TOKEN_SOURCE = "user:cc-hook"
TOKEN_TTL_MS = 7200000  # 2h; a killed Claude never gets to clean up after itself
TOKEN_REFRESH_S = 2700  # re-report well inside the TTL even when nothing changed
TRANSCRIPT_TAIL = 262144  # the last assistant turn is always within this much

action = os.environ.get("HERDR_ACTION", "")
pane_id = os.environ.get("HERDR_PANE_ID")
if not pane_id:
    raise SystemExit(0)

stash_dir = os.path.join(
    os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "herdr-blocked-reason"
)
slug = re.sub(r"[^A-Za-z0-9_-]", "_", pane_id)
stash = os.path.join(stash_dir, slug)
# Marker for "this pane currently has a label we published". PostToolUse fires
# after every single tool call; without this, each one would spawn a herdr
# subprocess and a socket round-trip just to clear nothing.
marker = os.path.join(stash_dir, slug + ".labeled")
# Last "<model>|<ctx>" we published, plus when. Lets the refresh skip the
# subprocess while the rendered value is unchanged.
tokens_cache = os.path.join(stash_dir, slug + ".tokens")


def hook_input():
    path = os.environ.get("HERDR_HOOK_INPUT_FILE")
    if not path:
        return {}
    try:
        with open(path, encoding="utf-8") as handle:
            content = handle.read()
        return json.loads(content) if content.strip() else {}
    except Exception:
        return {}


def run(args, source=SOURCE):
    try:
        subprocess.run(
            ["herdr", "pane", "report-metadata", pane_id, "--source", source,
             "--agent", "claude"] + args,
            check=False, timeout=5,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
    except Exception:
        pass


def summarize(tool, tool_input):
    """One short human phrase for what the tool is about to do."""
    if not isinstance(tool_input, dict):
        tool_input = {}

    def field(*names):
        for name in names:
            value = tool_input.get(name)
            if isinstance(value, str) and value.strip():
                return value.strip()
        return ""

    if tool == "Bash":
        detail = field("command")
    elif tool in ("Edit", "Write", "NotebookEdit", "Read"):
        detail = os.path.basename(field("file_path", "notebook_path"))
    elif tool in ("WebFetch", "WebSearch"):
        detail = field("url", "query")
    elif tool == "Agent":
        detail = field("description", "subagent_type")
    else:
        detail = field("command", "path", "pattern", "description")

    detail = " ".join(detail.split())
    if len(detail) > 48:
        detail = detail[:47] + "…"
    return f"{tool} {detail}".strip() if tool else detail


def latest_turn(transcript_path):
    """(model, context tokens) from the newest main-thread assistant turn."""
    try:
        size = os.path.getsize(transcript_path)
        with open(transcript_path, "rb") as handle:
            if size > TRANSCRIPT_TAIL:
                handle.seek(size - TRANSCRIPT_TAIL)
                handle.readline()  # drop the partial line the seek landed in
            lines = handle.read().decode("utf-8", "replace").splitlines()
    except Exception:
        return None

    for line in reversed(lines):
        if '"assistant"' not in line:
            continue  # cheap reject before paying for a parse
        try:
            row = json.loads(line)
        except Exception:
            continue
        # A subagent carries its own context; it is not this pane's.
        if row.get("type") != "assistant" or row.get("isSidechain"):
            continue
        message = row.get("message") or {}
        usage = message.get("usage") or {}
        if not isinstance(usage, dict):
            continue
        # Everything the next request will resend, including this turn's output.
        used = sum(
            usage.get(field) or 0
            for field in ("input_tokens", "cache_creation_input_tokens",
                          "cache_read_input_tokens", "output_tokens")
            if isinstance(usage.get(field), int)
        )
        if used:
            return str(message.get("model") or ""), used
    return None


def short_model(model):
    name = re.sub(r"^(claude-|us\.anthropic\.)", "", model)
    name = re.sub(r"-\d{8}(-v\d+[:.]\d+)?$", "", name)  # drop the date stamp
    return re.sub(r"-(\d+)-(\d+)$", r"-\1.\2", name)    # haiku-4-5 -> haiku-4.5


DEFAULT_WINDOW = 1000000  # the fleet runs 1M context as the norm


def context_pct(used):
    """Percent of the context window.

    The transcript records claude-opus-5 for both the 200k and the 1M variant,
    so the denominator cannot be read off the model string and is assumed. 1M
    is the standing default; HERDR_CTX_WINDOW overrides it per pane, and an
    observed count above the assumed window widens it rather than clamping to
    a false 100%.
    """
    override = os.environ.get("HERDR_CTX_WINDOW", "")
    window = int(override) if override.isdigit() and int(override) > 0 else DEFAULT_WINDOW
    while used > window:
        window *= 2
    return "{}%".format(int(round(used * 100.0 / window)))


def report_tokens(data):
    turn = latest_turn(str(data.get("transcript_path") or ""))
    if not turn:
        return
    model, used = turn
    label = short_model(model)
    ctx = context_pct(used)
    value = "{}|{}".format(label, ctx)

    now = time.time()
    try:
        with open(tokens_cache, encoding="utf-8") as handle:
            cached, stamp = handle.read().split("\n", 1)
        if cached == value and now - float(stamp) < TOKEN_REFRESH_S:
            return  # unchanged and nowhere near the TTL; skip the round-trip
    except Exception:
        pass

    args = ["--token", "ctx={}".format(ctx), "--ttl-ms", str(TOKEN_TTL_MS)]
    if label:
        args = ["--token", "model={}".format(label)] + args
    run(args, TOKEN_SOURCE)
    try:
        os.makedirs(stash_dir, mode=0o700, exist_ok=True)
        with open(tokens_cache, "w", encoding="utf-8") as handle:
            handle.write("{}\n{}".format(value, now))
    except Exception:
        pass


data = hook_input()

# Subagent tool calls are not what the user is being asked to approve.
if data.get("agent_id"):
    raise SystemExit(0)

if action == "pending":
    tool = str(data.get("tool_name") or "")
    if not tool:
        raise SystemExit(0)
    try:
        os.makedirs(stash_dir, mode=0o700, exist_ok=True)
        with open(stash, "w", encoding="utf-8") as handle:
            handle.write(summarize(tool, data.get("tool_input")))
    except Exception:
        pass
    raise SystemExit(0)

if action == "clear":
    # PostToolUse/Stop/UserPromptSubmit are all async, so this rides along for
    # free rather than needing three more hook entries of its own.
    report_tokens(data)
    try:
        os.unlink(stash)
    except Exception:
        pass
    if not os.path.exists(marker):
        raise SystemExit(0)  # nothing published; skip the socket round-trip
    try:
        os.unlink(marker)
    except Exception:
        pass
    run(["--clear-state-labels"])
    raise SystemExit(0)

# action == "blocked"
message = " ".join(str(data.get("message") or "").split())

pending = ""
try:
    with open(stash, encoding="utf-8") as handle:
        pending = handle.read().strip()
except Exception:
    pass

# A permission prompt names the tool; anything else (idle nudge, plan review)
# is better described by Claude's own message.
if pending and re.search(r"permission|approve|allow", message, re.I):
    label = f"approve: {pending}"
elif message:
    label = message
elif pending:
    label = f"approve: {pending}"
else:
    raise SystemExit(0)

if len(label) > 72:
    label = label[:71] + "…"

run(["--state-label", f"blocked={label}", "--ttl-ms", str(TTL_MS)])
try:
    os.makedirs(stash_dir, mode=0o700, exist_ok=True)
    open(marker, "w").close()
except Exception:
    pass
PY
