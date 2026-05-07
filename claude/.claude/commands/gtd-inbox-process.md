---
description: Process GTD inbox items one at a time using the GTD workflow
argument-hint: "[number of items to process, default all]"
---

Process unprocessed items from the Vikunja GTD Inbox using the standard GTD decision tree.

## Instructions

Read `skills/brainbox/references/gtd-structure.md` to get all project and label IDs. If IDs are unpopulated (TODO), use `mcp__vikunja__vikunja_projects` with `subcommand: "list"` and `mcp__vikunja__vikunja_labels` with `subcommand: "list"` to look them up by name.

### 1. Fetch inbox

Use `mcp__vikunja__vikunja_task_crud` with `operation: "list"` on the Inbox project.

If the inbox is empty, report "Inbox zero!" and stop.

If `$ARGUMENTS` specifies a number, only process that many items.

### 2. Process each item

For each inbox item, present it to the user and walk through the GTD flowchart:

**"What is it? Is it actionable?"**

Present these options to the user and ask them to choose:
- **Not actionable: Trash** → delete the task
- **Not actionable: Reference** → tell user to file in Obsidian, delete from Vikunja
- **Not actionable: Someday Maybe** → move to Someday Maybe project
- **Actionable: < 2 minutes** → remind user to do it now, then mark done
- **Actionable: Delegate** → move to Waiting For, ask who/when, add to description
- **Actionable: Single next action** → move to Next Actions, ask for context label
- **Actionable: Multi-step project** → create child project under Projects parent, ask for first next action, create that in Next Actions

### MCP operations used

| Action | Tool | Params |
|--------|------|--------|
| Move task | `mcp__vikunja__vikunja_task_crud` | `operation: "update"`, `id`, new `projectId` |
| Delete task | `mcp__vikunja__vikunja_task_crud` | `operation: "delete"`, `id` |
| Mark done | `mcp__vikunja__vikunja_task_crud` | `operation: "update"`, `id`, `done: true` |
| Add context label | `mcp__vikunja__vikunja_task_labels` | `operation: "apply-label"`, `id`, `labels: [labelId]` |
| Create project | `mcp__vikunja__vikunja_projects` | `subcommand: "create"`, `title`, `parentProjectId` |
| Update description | `mcp__vikunja__vikunja_task_crud` | `operation: "update"`, `id`, `description` |

### 3. Show progress

After each item: "X/Y processed, Z remaining"

After all items: summary of actions taken (moved to Next Actions, Waiting For, Someday Maybe, trashed, completed).
