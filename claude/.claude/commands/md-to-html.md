---
description: Convert markdown to HTML with CSS templates
argument-hint: <file.md> [template]
---

# Markdown to HTML Converter

Convert a markdown file to styled HTML using reusable CSS templates.

## Arguments

- **File**: `$ARGUMENTS` (first word is the markdown file path)
- **Template**: Second word, defaults to `default` if not specified

## Available Templates

Templates are stored in `~/.claude/templates/`:
- `default` — Clean, professional styling
- `prd` — Optimized for PRDs (tables, code blocks, technical docs)
- `minimal` — Lightweight, fast-loading

## Instructions

1. Parse the arguments to get the file path and template name
2. Verify the markdown file exists
3. Load the CSS from `~/.claude/templates/{template}.css`
4. Use pandoc to convert markdown to HTML:
   - Use `--standalone` for complete HTML document
   - Use `--embed-resources` to inline the CSS
   - Use `--metadata title` extracted from the first H1
5. Save the output as `{filename}.html` in the same directory
6. Report the output file path

## Example Commands

```bash
# With default template
/md-to-html docs/readme.md

# With specific template
/md-to-html docs/prd.md prd
```

## Pandoc Command Pattern

```bash
pandoc INPUT.md \
  --from markdown \
  --to html5 \
  --standalone \
  --css ~/.claude/templates/TEMPLATE.css \
  --embed-resources \
  --metadata title="TITLE" \
  --output OUTPUT.html
```
