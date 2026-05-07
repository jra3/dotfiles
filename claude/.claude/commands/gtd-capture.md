---
description: Quick capture one or more items to GTD inbox
argument-hint: <item> [; more items separated by semicolons]
---

Capture items to the Vikunja GTD Inbox.

## Instructions

Read `skills/brainbox/references/gtd-structure.md` to get the Inbox project ID. If IDs are unpopulated (TODO), use `mcp__vikunja__vikunja_projects` with `subcommand: "list"` to find the Inbox project by title.

1. Parse `$ARGUMENTS` — split on semicolons if multiple items are provided
2. Trim whitespace from each item

**Single item:**
Use `mcp__vikunja__vikunja_task_crud` with:
- `operation`: `"create"`
- `projectId`: Inbox project ID
- `title`: the item text

**Multiple items:**
Use `mcp__vikunja__vikunja_task_bulk` with:
- `operation`: `"bulk-create"`
- `projectId`: Inbox project ID
- `tasks`: array of `{ "title": "..." }` objects

3. Report what was captured:
   - List each item with its task ID
   - Show the current inbox count
