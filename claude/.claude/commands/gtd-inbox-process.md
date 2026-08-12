---
description: Process the GTD Capture queue in Linear, one item at a time
---

Empty `Capture` by clarifying each item with John. **You propose; he decides.**

## Before you start

Read the **GTD Operating Manual** — the team doc in Linear, at `~/jra3/linear/teams/GTD/docs/`. It is canonical: the state semantics, the `Next` test, the project rule, and the clarify tree all live there, and it changes without this file changing. Read it every run rather than trusting your memory of it.

Then read the queue:

```
ls ~/jra3/linear/teams/GTD/by/status/Capture/
```

## Steps

### 1. Show John the queue

List it, oldest first, with a count. If it is empty, say so and stop.

### 2. Scan the whole queue for dispatchable work, and fire it in one batch

Before clarifying anything, read every item and ask of each: **can an agent do this end-to-end, and does it produce something John reviews rather than something the world sees?**

Bring John the whole list at once — item, and the specific work you would dispatch for it. **He approves the batch before anything is sent.** Dispatch is supervised, not automatic. Then fire all approved dispatches in parallel, set each issue to `Doing`, and comment on it with what was sent and when.

Doing this first is the point: the agents work while you and John clarify the rest of the queue by hand, so the results are back before the items that need them come up.

This is the two-minute rule recalibrated. The rule was never about two minutes — it is a proxy for *cheaper to do than to track*. Agents move that threshold a long way, but the binding constraint stops being time and becomes **reversibility and review burden**.

**May dispatch:** research, drafting, verification, file transformation, checking things that are already public.

**May never dispatch:** anything outward-facing (publishing, posting, emailing, submitting), anything that spends money, anything that creates an account or identity, anything that changes system config with lockout risk.

**These are instructions to the agent, not a sandbox.** A dispatched agent has run `elephant generate config` against the may-never list before now. Two mitigations, and neither is a guarantee:

* **Use the read-only agent type for research dispatches.** `Explore` has no Edit/Write/NotebookEdit. It still has Bash, so a shell command can still mutate — it removes the easy path, not the path. Reserve full-tool agents for dispatches that genuinely must write, and worktree-isolate those when they touch a repo.
* **Require a mutation report.** Every dispatched agent must end by listing every file it created, modified or deleted, or stating plainly that it made none. Read that report before closing the item. The `elephant` writes were only recoverable because the agent volunteered them; make that a contract rather than a habit.

Dispatching does not clarify the item. It comes back as a draft with a decision attached, and John clarifies it then — with better information than it had in `Capture`.

**The failure mode to design against:** a dispatched item sits in `Doing` forever because the agent died, and because `Doing` is type `started` it also falsely un-stalls its project. The issue comment is the audit trail; the close-the-loop step is the backstop.

### 3. Work one item at a time, and never put it back

For each, walk the clarify tree from the manual and bring John a **proposal**, not a question with no answer in it: what you think it is, where it should go, and — if it is an action — the retitled physical action you would use.

Capture text is raw. Clarifying almost always means **retitling**. Propose the new title explicitly; that is usually the substance of the decision.

Say what would make you wrong. "This looks like a one-step errand, but if framing and shipping are involved it is a project" is worth more than a confident guess.

### 4. Apply what John decides

Retitle, set state, set project, add a context label **only** if it genuinely constrains. Use the API, not the mount — failed mount writes return exit 0 (jra3/linear-fuse#455) and truncating writes corrupt descriptions (#454).

When an item becomes a project: create the Linear project first, then set the captured issue as its first action in `Next`. **A project with nothing in `Next`/`Doing`/`Waiting` is stalled on arrival** — do not leave one that way.

### 5. Close the loop

Report what moved where, in one short block. Then say what `Capture` holds now — ideally nothing.

**Report anything still in `Doing`** from a dispatch this run, and say plainly whether it returned. An unreported dispatch is worse than no dispatch.

## Judgement notes

- **Under two minutes → offer to do it now.** If it is something you can actually do, do it and mark it `Done`.
- **Under two minutes *for an agent* is a different threshold.** See step 3 — dispatch it and keep processing rather than making John wait.
- **`Next` means physical and startable.** If your proposed title still needs a decision before John could begin, it is a project, not an action.
- **`Someday` means uncommitted**, not "later". Ask which it is when unclear; do not infer commitment from enthusiasm.
- **Not every action needs a project.** A loose one-step errand is fine.
- Anything genuinely not actionable is reference — Drive for files, Notion for prose — or it gets deleted. Deleting is a real outcome; offer it.
