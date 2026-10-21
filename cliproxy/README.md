# cliproxy

Account ranking for the CLIProxyAPI server at
`https://cliproxy.corgi-hammerhead.ts.net` (management UI at `/management.html`).
The server itself is not managed here.

`cliproxy-rank` gives each Claude account a distinct `priority` so the account
whose **weekly quota resets soonest is used first**. That quota is lost soonest
if left unused. `cliproxy-rank.timer` re-ranks every 5 minutes.

```sh
cliproxy-rank                    # dry run: show the ranking and what would change
cliproxy-rank --apply            # write it
cliproxy-rank --provider codex   # Codex instead; repeat --provider for both
journalctl --user -u cliproxy-rank
```

## How it routes

CLIProxyAPI sends each request to the highest-priority account that is not in
cooldown, and only uses `routing.strategy` to break ties within one priority.
Distinct priorities leave no ties, so routing becomes fill-first whatever the
strategy says. The top account takes everything until a 429 cools it down,
then the next one does. The next timer run sees the rejection and moves the
account to the bottom.

Order:

1. **Live weekly window, not exhausted.** Soonest reset first.
2. **No live data.** Never used, or the window reset since its last response.
   Using it starts a fresh 7-day clock, so it has the most time left.
3. **Exhausted.** A 5h or 7d window is `rejected` or at ≥99% and has not reset
   yet. Whichever recovers first ranks first.

## Where the numbers come from

The proxy records the `anthropic-ratelimit-unified-*` headers off every Claude
response; `GET /v0/management/auth-files` returns them. On v8.0.11 they sit
under `model_quotas`, one snapshot per model, rather than the account-level
`quota`. The 5h and 7d windows in them are account-wide, so the newest
snapshot wins. Model-scoped windows such as `7d_oi` are ignored: they block
one model, and the proxy's per-model cooldown already fails over for those.

The proxy only learns an account's quota when that account serves a response.
An account ranked at the bottom keeps its last snapshot, which is why a reset
time in the past counts as "full again".

Priorities are written with `PATCH /v0/management/auth-files/fields`
(`{"name": <file>, "priority": n}`), which updates the auth JSON and the
router live. No restart is needed.

## Setup

Needs the management key in `~/.config/cliproxy/key`. The service is skipped
on machines without it.

```sh
stow cliproxy
systemctl --user daemon-reload
systemctl --user enable --now cliproxy-rank.timer
```

Running it on several machines is harmless. They all read the same data,
compute the same order, and only write when a priority differs.

## Limits

- Accounts on different plan sizes are ranked by reset time alone. A small
  plan resetting tomorrow outranks a large one resetting in two days.
- Codex is opt-in. Ranking it switches the Codex accounts from round-robin to
  fill-first as well.
- With `routing.session-affinity` on, a session already bound to an account
  stays there after a re-rank. Only new sessions follow the new order.
