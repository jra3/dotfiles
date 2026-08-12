---
description: Show a summary of the GTD system in Linear
---

Show John where his system stands. Read-only — change nothing.

Read the **GTD Operating Manual** team doc at `~/jra3/linear/teams/GTD/docs/` for what each state means before interpreting anything.

## What to show

Read from the mount — it is faster than the API and needs no key:

```
ls ~/jra3/linear/teams/GTD/by/status/{Capture,Next,Doing,Waiting,Someday}/
```

1. **Counts per state**, `Capture` first.
2. **Next Actions in full** — identifier, title, project, and any context label. This is the list John actually works from, so it earns the space.
3. **Doing** in full. If it is more than three or four, say so plainly; a long `Doing` list means nothing is finishing.
4. **Waiting** in full, with how long each has sat. Anything over two weeks is worth chasing.
5. **Stalled projects** — run `gtd-stalled` (or `~/.claude/skills/gtd/scripts/gtd-stalled`). The check most worth running and the one most often skipped.
6. `Someday` and `Capture` as counts only, unless asked.

## Tone

Report, do not nag. State what is true — "Capture has 14 items", "three projects have no next action" — and stop. John decides what that means. A dashboard that editorialises stops getting opened.

Close with the single most useful next move if one is obvious: a non-empty `Capture` means run `/gtd-inbox-process`; stalled projects mean run `/gtd-weekly-review`.
