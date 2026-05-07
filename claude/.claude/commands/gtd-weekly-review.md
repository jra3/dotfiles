---
description: Guided GTD weekly review
argument-hint: ""
---

Walk through a complete GTD weekly review using Vikunja MCP tools.

## Instructions

Read `skills/brainbox/references/gtd-structure.md` to get all project and label IDs. If IDs are unpopulated (TODO), use `mcp__vikunja__vikunja_projects` with `subcommand: "list"` and `mcp__vikunja__vikunja_labels` with `subcommand: "list"` to look them up by name.

## Phase 1: Get Clear

### Process Inbox
1. List all tasks in the Inbox project using `mcp__vikunja__vikunja_task_crud` with `operation: "list"`
2. If inbox is not empty, offer to process items (same workflow as `/gtd-inbox-process`)
3. After processing, remind user to also check:
   - Email inbox
   - Obsidian `00-inbox/` folder
   - Physical inbox / notes apps
   - Voicemails, texts, browser tabs

## Phase 2: Get Current

### Review Next Actions
1. List all tasks in Next Actions using `mcp__vikunja__vikunja_task_crud` with `operation: "list"`
2. Present each task and ask: "Still relevant? Done? Needs updating?"
3. Mark done, update, or leave as-is based on user response

### Review Waiting For
1. List all tasks in Waiting For
2. For each: "Any response? Follow up needed?"
3. Mark done if resolved, move to Next Actions if user needs to act, or leave

### Review Projects
1. List child projects under the Projects parent using `mcp__vikunja__vikunja_projects` with `subcommand: "get-children"` and `projectId` of the Projects parent
2. For each active project, list its tasks
3. Ask: "Does this project have a defined next action? Is it stalled?"
4. Create next actions as needed

### Review Calendar
Remind the user to check:
- Past week: anything to follow up on?
- Next 2 weeks: any prep needed?

## Phase 3: Get Creative

### Review Someday Maybe
1. List all tasks in Someday Maybe
2. Ask: "Promote any of these to active?"
3. Move promoted items to Next Actions or create as new Projects

### Areas of Responsibility
Remind user to review their areas in Obsidian `20-areas/`:
- Is anything being neglected?
- Any new projects needed?

### Open Capture
Ask: "Anything else on your mind to capture?" Add items to Inbox if so.

## Summary

After all phases, report:
- Tasks completed during review
- Tasks added during review
- Current counts: Inbox, Next Actions, Waiting For, Active Projects, Someday Maybe
- Any overdue tasks
