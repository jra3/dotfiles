# voxtype

Push-to-talk voice-to-text. The binary is `omarchy/voxtype-bin` from Omarchy's own
pacman repo, tracked in `pacman/packages-arch.txt`. The daemon and its
`voxtype.service` are installed by `voxtype setup systemd`, not stowed.

## `config.toml` is deliberately NOT in this package

`~/.config/voxtype/config.toml` is host-local. Only `meeting-toggle` is stowed.

It was tracked and shared until 2026-08-25. Two independent reasons it can't be:

- **`model` is a per-machine answer.** The right model is a function of the CPU and
  iGPU in front of you. chonky can run `large-v3-turbo`; cupcake is a 15W i3-1315U
  with plain UHD graphics and needs something far lighter. One shared string can't
  hold both, and voxtype has no config layering — one file, no includes, no drop-ins.
- **voxtype writes to this file itself.** `voxtype setup` rewrites it, and
  `voxtype config set <key> <value>` edits it in place "preserving comments and other
  settings". Anything voxtype persists lands wherever that path points.

The second one bit hard on 2026-08-25. `~/.config/voxtype` had been stow-**folded**
— only this package provided the directory, so stow replaced the whole directory with
a symlink into the repo rather than linking the file. `voxtype setup` then wrote its
stock defaults *straight into the tracked file*: `model` silently reverted to
`base.en` and the entire `[meeting]` block was deleted. 20 lines, no error, and
nothing in `git status` to notice unless you looked.

If you ever re-stow something into `~/.config/voxtype`, use
`stow --no-folding voxtype`. With the directory real and only the file linked, an
overwrite replaces the *symlink* with a regular file — which `ls -l` shows and the
repo survives. Folded, the write goes through and there is nothing to see.

## Reference config

What the shared version carried, for rebuilding a machine's file by hand. `model` is
the one line that should differ per host.

```toml
state_file = "auto"           # $XDG_RUNTIME_DIR/voxtype/state; needed by `record toggle` + `status`

[hotkey]
enabled = false               # Hyprland owns the binding, not voxtype

[audio]
device = "default"
sample_rate = 16000           # whisper expects this
max_duration_secs = 60
pause_media = true            # pause MPRIS players while recording

[whisper]
model = "large-v3-turbo"      # PER-HOST. See "Choosing a model" below.
language = "en"
translate = false

[output]
mode = "type"                 # types at the cursor; needs wtype (or ydotool)
fallback_to_clipboard = true
type_delay_ms = 1             # raise if characters get dropped

[output.notification]
on_recording_start = false    # the OSD already shows state; notifications would double it
on_recording_stop = false
on_transcription = false

[meeting]
enabled = true                # long-form capture, chunked + crash-safe, to
retain_audio = true           # ~/.local/share/voxtype/meetings/. Keep the audio
                              # until the generated notes are confirmed good.
[meeting.audio]
source = "both"               # mic + system loopback (remote participants), with
                              # GTCRN echo cancellation so your own voice isn't doubled

[meeting.diarization]
backend = "simple"            # attributes by audio source (You vs Remote) — right for
                              # 1:1 calls. "ml" (ECAPA-TDNN) for multi-speaker.
```

`meeting-toggle` (SUPER+CTRL+M, stowed to `~/.local/bin`) drives the `[meeting]` mode:
it exports the transcript and has Claude write notes.

## Choosing a model

voxtype 0.7.5 ships two engines — Whisper (`ggml`, optional Vulkan via
`voxtype setup gpu`) and ONNX/Parakeet (`voxtype setup onnx`). Parakeet TDT is
RNN-T rather than Whisper's autoregressive attention decoder, and the `-int8`
variant targets CPU, so it is the one to try first on a weak iGPU.

Measure, don't guess — record one ~15s sample of your own voice and time each
candidate against that same file, comparing latency *and* transcript:

```bash
voxtype setup --download --model small.en
time voxtype transcribe --model small.en /path/to/sample.wav
```

Latency after key-release is the whole experience for push-to-talk; accuracy
differences mostly show up on proper nouns and technical vocabulary.

| Host | CPU / GPU | Model |
|---|---|---|
| chonky | — | `large-v3-turbo` |
| cupcake | i3-1315U (2P+4E, 15W), UHD graphics | TBD — benchmark pending |
| paperweight | Ryzen AI Max+ 395 (Strix Halo), Radeon 8060S iGPU, 128 GB unified | `large-v3-turbo`, Vulkan via RADV |
