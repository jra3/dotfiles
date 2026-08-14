---
description: Process the GTD Capture queue in Linear, one item at a time
---

Empty `Capture` by clarifying each item with John. **You propose; he decides.**

Steps 1–3 are **dry**: every decision gets made with nothing written to Linear. Step 4 is the **commit** — one batch, all of it. An API round-trip per item is the digital equivalent of walking to the filing cabinet after every piece of paper, and it destroys the rhythm that makes processing fast.

## Before you start

Read the **GTD Operating Manual** — the team doc at `~/jra3/linear/teams/GTD/docs/`. It is canonical: the state semantics, the `Next` test, the project rule, the clarify tree and the clarify discipline all live there, and it changes without this file changing. Read it every run rather than trusting your memory of it.

## Steps

### 1. Read everything, once

One pass collecting everything needed to decide, so nothing has to be looked up mid-queue:

* the `Capture` queue, oldest first, **with full descriptions**
* existing projects and the Areas they sit under
* workflow state IDs and label IDs

Read through the mount (`~/jra3/linear/teams/GTD/`) — reads are reliable there.

Then show John the queue, oldest first, **with a count**. If it is empty, say so and stop. That count is the bar for steps 2 and 3.

### 2. Decide, one item at a time

**Dry.** The only tool calls permitted here are two-minute-rule executions (below). Nothing else is read; nothing at all is written.

Walk the manual's clarify tree and bring John a **proposal**, not a question with no answer in it: what you think it is, where it should go, and — if it is an action — the retitled physical action you would use. The retitle is usually the substance of the decision, so propose it explicitly.

**Say what would make you wrong.** "This looks like a one-step errand, but if framing and shipping are involved it is a project" is worth more than a confident guess.

**The two-minute rule means two minutes.** If you can genuinely do it that fast — a DNS lookup, a quick fetch — do it, record the item as `Done`, and go straight back to deciding.

Done when every item in the count has a recorded decision.

### 3. Show the batch

Still dry. One reviewable block, one line per item, covering every retitle, state, project, label, and any new project to be created. Every item in the count appears in it.

**John's review of the batch is the approval.** Amend whatever he corrects. Do not ask for a second confirmation on something he has just read line by line.

### 4. Commit, once

Apply the whole batch in dependency order — create projects before the issues that reference them. When an item becomes a project, create the project first, then set the captured issue as its first action in `Next`, so the project has one from birth.

Write through the API rather than the mount, and **verify every write against the API response.**

Then close the loop in one short block: what moved where, anything that failed — say so plainly — and what `Capture` holds now, ideally nothing.

## Judgement notes

- **Containers are free. Schema is not.** Creating a new project, Area or label *is* clarifying — do it on the spot, without ceremony. Allen's own filing rule is that if making a new home takes more than about a minute, you stop filing and the system dies. But **changing what the containers mean** — inventing a workflow state, redefining an existing one, splitting or merging projects wholesale — changes every item already filed, and belongs to the weekly review rather than the middle of a pass.
- **When a schema gap genuinely blocks a decision, close it — minimally — and get back to the queue.** Sometimes an item has no correct home and that is real information: `Todo` was created mid-pass because a committed-but-not-startable item had nowhere to go, and the system was wrong until it existed. That was the right call. What went wrong was what followed — an hour of restructuring, a doc rewrite and a state merge, with the queue still full. Make the smallest change that unblocks the item, note the rest for later, and carry on.
- Anything genuinely not actionable is reference — Drive for files, Notion for prose — or it gets deleted. **Deleting is a real outcome; offer it.**
