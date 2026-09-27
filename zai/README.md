# zai

A fourth tab — z.ai's GLM Coding Plan — in Omarchy's agents panel, alongside
Claude Code, Codex and Fireworks.

## What's tracked

- `.local/bin/omarchy-agent-usage-zai` — the collector. Prints the record
  contract the agents panel reads; `--write` puts it in the panel's usage
  directory as `zai.json`.
- `.config/systemd/user/omarchy-agent-usage-zai.{service,timer}` — runs it
  every 5 minutes.

## Why a timer and not `omarchy-agent-usage-update`

The panel is strictly a display: it watches
`~/.local/state/omarchy/agents/usage/*.json` and draws whatever records are
there, whoever wrote them. So a new agent is a new collector and nothing else —
`$OMARCHY_PATH/shell/plugins/agents/README.md` says as much.

What that README does not say is that `omarchy-agent-usage-update` only
iterates `$OMARCHY_PATH/bin/omarchy-agent-usage-*`. That directory is
root-owned and rewritten by `omarchy update`, so a user collector can never
join the loop and the panel's own refresh (its 15-minute timer, and `r` in the
panel) will never run this one. Hence the systemd timer, on a shorter interval
than the panel's so the numbers are never much staler than what the panel
fetches for itself.

Two consequences worth knowing:

- **The panel's refresh key does not refresh this tab.** Its data is as fresh
  as the last timer run. `systemctl --user start omarchy-agent-usage-zai` for
  an immediate one.
- **If Omarchy ever ships its own `omarchy-agent-usage-zai`, delete this
  package.** Both would write `zai.json` and fight over it.

## The API

Undocumented, and the same three endpoints the
[opencode-glm-quota](https://github.com/guyinwonder168/opencode-glm-quota)
plugin uses. Base URL `https://api.z.ai` (the CN platform is
`https://open.bigmodel.cn`; set `baseUrl` in the config file below).

| Endpoint | Gives |
|---|---|
| `/api/monitor/usage/quota/limit` | the rolling 5-hour and weekly token windows, the monthly MCP tool-call quota, each as an integer percentage with an epoch-ms reset, plus the plan level |
| `/api/monitor/usage/model-usage` | tokens per bucket per model over a requested window |
| `/api/monitor/usage/tool-usage` | MCP calls per bucket per tool — **not used**; the quota endpoint already carries the MCP total, and the panel has nowhere to put a per-tool breakdown |

`Authorization` takes the raw key with **no `Bearer` prefix**.

### Every bucket is in UTC+8

z.ai labels usage buckets in China Standard Time regardless of where the caller
is, and reads the request window in that frame too. Measured 2026-09-11: asking
from an EDT machine for `today 00:00 -> tomorrow 23:59` came back labelled
`00:00..23:00`, newest non-empty bucket `23:00`, while the local clock said
11:12 and Shanghai's said 23:12.

Taking the date off a bucket label would therefore file a whole EDT afternoon
under tomorrow — from noon onward, local "today" is already tomorrow in
Shanghai, and the panel's today row would read zero for half of every day. So
the collector converts each hourly bucket to a local day before summing.

### Which forces two queries

The hourly series only comes back for a span under 8 days; ask for more and the
API answers in daily buckets, which cannot be re-cut across a 12-hour gap. So:

- **7 days hourly** → the seven local days of the "tokens by day" chart, and
  today's total.
- **30 days daily** → "tokens by model" and the active-day count. These dates
  are z.ai's own, up to a day off at the edges, which does not show in a
  30-day total or a day count.

### What z.ai does not report

- **No input/output/cache split** — one total per model. The panel sums the
  four token fields to size its bars, so the whole figure goes in
  `inputTokens` and the model row is right. **The hover split is not**: it will
  claim every token was input.
- **No prompt or session counts.** `hasPromptStats` is false, so the panel
  leaves them out of today's tooltip rather than showing zeros.
- Usage is account-wide, not per-machine, so the record carries
  `"scope": "account"` and synced devices take the widest value instead of
  summing.

## Credentials

In order: `$ZAI_API_KEY`, then `apiKey` or `keyFile` in
`~/.config/omarchy/agents/zai.json`, then `~/.config/zai/anthropic-key` — the
same key `claude-zai` uses (`zsh/.zshrc`), so on this machine there is nothing
to configure.

The optional config file takes the same shape as Omarchy's own
`~/.config/omarchy/agents/fireworks.json`:

```json
{
  "keyFile": "~/.config/zai/anthropic-key",
  "baseUrl": "https://api.z.ai"
}
```

With no key the collector prints an empty record, the panel finds nothing worth
showing, and the tab stays away.

## No mark

`Panel.qml` resolves an agent's logo as `assets/<id>.svg` **inside the packaged
plugin**, so a z.ai mark would mean cloning the whole plugin
(`omarchy plugin clone omarchy.agents`) and maintaining a fork of 60KB of QML
that upstream keeps changing. Not worth a logo: the panel falls back to the
module's bar glyph, which is what this tab shows.

## Deploy

```bash
stow zai
systemctl --user daemon-reload
systemctl --user enable --now omarchy-agent-usage-zai.timer
```

Verify with `omarchy-agent-usage-zai | jq` (prints, writes nothing), or
`systemctl --user start omarchy-agent-usage-zai` then check
`~/.local/state/omarchy/agents/usage/zai.json`.

## Overlap with the Claude Code tab

`claude-zai` runs Claude Code against z.ai's Anthropic-compatible endpoint, and
Claude Code's own transcripts are what the `claude` collector reads — so those
sessions are counted in both tabs, as `glm-5.3-flash` under Claude Code and as
`GLM-5.3-Flash` here. Different accounting (transcripts vs. z.ai's billing
side), so the two numbers will not match.
