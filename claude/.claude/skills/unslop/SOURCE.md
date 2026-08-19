Vendored from cursor/plugins, pstack v0.14.1, MIT licensed.

Source: https://github.com/cursor/plugins/tree/main/pstack/skills/unslop
Upstream commit: 60c641e4fad6
Vendored: 2026-08-19
Author: Lauren Tan

SKILL.md is byte-identical to upstream. To refresh:

  curl -sSfL https://raw.githubusercontent.com/cursor/plugins/main/pstack/skills/unslop/SKILL.md \
    -o ~/.dotfiles/claude/.claude/skills/unslop/SKILL.md

Rule numbers are load-bearing upstream: pstack's poteto-mode skill cites
"unslop rule 14" by number. Renumbering on a local edit breaks that reference,
though nothing here depends on it unless you also install poteto-mode.
