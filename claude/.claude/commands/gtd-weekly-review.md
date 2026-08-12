---
description: Guided GTD weekly review of the Linear system
---

Walk John through the weekly review. It is the ritual that keeps the system trusted — skipping it is how the last one went stale and stopped being believed.

Read the **GTD Operating Manual** team doc at `~/jra3/linear/teams/GTD/docs/` first; its weekly-review section is canonical.

## Run the mechanical checks first, before asking John anything

Three of Allen's Get Current checks are scriptable. Do them yourself and bring results, not questions:

1. **Stalled projects** — run `~/.claude/skills/gtd/scripts/gtd-stalled` (also on PATH as `gtd-stalled`). Do not re-derive this by counting; the script is verified against the API and runs in ~30ms. Allen names this as the thing the review exists to do.
2. **`Capture` not empty** — if anything is there, offer `/gtd-inbox-process` before going further. Reviewing around an unprocessed inbox is reviewing a lie.
3. **Orphan actions** — an issue in `Next` whose project is `Completed` or `Canceled`.

## Then the parts needing John

Work these in order, one at a time:

- **`Waiting`** — read each aloud with its age. Which need chasing? A `Waiting` item nobody has chased in a month is usually a `Next` action in disguise.
- **`Next`** — is every item still a physical action you could start? Anything that has quietly become an outcome gets turned into a project.
- **`Someday`** — promote, drop, or leave. Ask about each; the commitment question is the whole point of the list.
- **Projects** — is each still wanted? A project you would not start today belongs in `Backlog` status or gone.
- **Areas** — reread the `## Standard` block on each Area's Notion page. Is reality still meeting it? This is the layer that quietly rots because nothing forces you to look.
- **Calendar** — look backward one week and forward two. Anything that happened needing follow-up? Anything coming that needs preparation now?

## Close

Summarise what changed: items moved, projects opened or closed, what John committed to for the week. Keep it short enough to reread.

## Judgement notes

- **Never mutate without John.** The review proposes; he decides. That is the standing rule of this system.
- If John is short on time, run the three mechanical checks and `Waiting`, and say plainly what you skipped. A partial review that happened beats a full one that did not.
- Do not congratulate. Report what is true.
