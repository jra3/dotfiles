---
description: Show a summary dashboard of your GTD system
argument-hint: "[@context filter, e.g. @computer]"
---

Display a quick status overview of the GTD system from Vikunja.

## Instructions

Read `skills/brainbox/references/gtd-structure.md` to get all project and label IDs. If IDs are unpopulated (TODO), use `mcp__vikunja__vikunja_projects` with `subcommand: "list"` and `mcp__vikunja__vikunja_labels` with `subcommand: "list"` to look them up by name.

### 1. Gather data

Fetch task lists for each GTD project using `mcp__vikunja__vikunja_task_crud` with `operation: "list"`:
- Inbox (count of not-done tasks)
- Next Actions (count of not-done tasks)
- Waiting For (count of not-done tasks)
- Someday Maybe (count of not-done tasks)

Fetch active projects count using `mcp__vikunja__vikunja_projects` with `subcommand: "get-children"` and `projectId` of the Projects parent.

Identify overdue tasks (due date < today) and tasks due today across all projects.

### 2. Apply context filter

If `$ARGUMENTS` contains a context (e.g., `@computer`), filter Next Actions to show only tasks with that label.

### 3. Display dashboard

Format output as:

```
GTD Dashboard — {today's date}

Inbox:           {count} items {add "(needs processing!)" if > 0}
Next Actions:    {count} items
Waiting For:     {count} items
Active Projects: {count}
Someday Maybe:   {count} items

Due Today:  {count} tasks
Overdue:    {count} tasks

{If context filter applied:}
Next Actions (@computer): {count} items
  - {task title 1}
  - {task title 2}
  ...
```

If there are overdue tasks, list them with their due dates.
