---
name: wayfinder-next
description: Drive the next ticket on a wayfinder map through a foreground subagent, then record the resolution.
disable-model-invocation: true
---

Take one ticket off a wayfinder map's frontier, hand a fresh subagent everything it needs, and let it do the **legwork** in its own context window. The parent stays thin — it chooses, claims, hands off, and records — so the map advances a ticket at a time without the parent's context filling up with the detail of each one.

Read `~/jra3/linear/README.md` for how this tracker creates issues, comments, and relations. The wayfinder model itself — maps, fog, frontier, ticket types — lives in the `wayfinder` skill; this skill only drives it.

## Where legwork ends

Every wayfinder ticket is **AFK** (the agent works alone) or **HITL** (a human speaks for themselves). The subagent does legwork either way; the two differ in where legwork stops.

- **AFK** — `research`, and `task` where the agent has the access it needs. Legwork runs to the answer. The subagent returns a resolution.
- **HITL** — `grilling`, `prototype`, and `task` needing hands or credentials only John has. Legwork runs *up to* the point John's judgement is required, and stops there. The subagent returns prepared material — a question set with recommendations, a built prototype, a precise checklist — and the parent runs the live exchange.

A subagent has no channel to John. On a HITL ticket it produces the questions and leaves every answer blank, because an agent that answers John's grilling questions for him has resolved nothing and left a decision on the map that looks settled.

## Steps

### 1. Find the map and compute the frontier

Locate maps at `~/jra3/linear/teams/<TEAM>/by/label/wayfinder:map/`. More than one map is normal — each is a separate effort. Take the map from the arguments; when the arguments name none and several exist, ask John which effort he means.

Read the map body once. Its children are the tickets:

```
ls ~/jra3/linear/teams/<TEAM>/issues/<MAP>/children/
```

A child is on the **frontier** when all three hold:

- **Open** — `status:` is not `Done`, `Canceled`, or `Duplicate`
- **Unblocked** — every `blocked-by-*.rel` in its `relations/` names a closed issue
- **Unclaimed** — its `issue.md` frontmatter carries no `assignee:` key

**Done when** the frontier is listed by name with each ticket's `wayfinder:` type, and John can see what is takeable.

### 2. Choose and claim

Take the ticket John named; otherwise the first frontier ticket in map order. Claim it *before* any work by adding `assignee: theactualjohnallen@gmail.com` to its `issue.md`, so a concurrent session skips it.

`research` tickets are the exception to one-ticket-per-run: when the frontier holds several, claim and dispatch them together — they are independent and each gets its own context window.

**Done when** the ticket is assigned in Linear.

### 3. Write the handoff

Write to `<scratchpad>/handoff-<TICKET>.md`. It is scratch: the durable record is the resolution comment on the ticket and the line in the map's Decisions-so-far, and a third copy would only go stale.

The subagent starts blank, so the handoff carries everything it would otherwise re-derive:

- **Destination and Notes**, verbatim from the map — the standing preferences steer every decision it makes
- **Decisions so far**, the map's index
- **The ticket** — identifier, title, and full body
- **Zoomed blockers** — the resolution comment of every closed ticket that blocked this one, quoted in full. This is the detail the map deliberately does not hold, and the subagent cannot resolve well without it.
- **Environment facts** already established, so it re-runs no lookups — but re-verify each one against the environment as you write it, rather than copying the map forward. A map's facts age between the session that wrote them and the session that reads them, and a subagent handed a stale fact spends its whole run reasoning from it.
- **Its mission and completion criterion**, per the AFK/HITL split above
- **Which skills to invoke** — the map's Notes name them; `grilling` and `domain-modeling` for decision tickets, `research` for investigation

**Done when** the handoff answers every question the subagent would otherwise have to ask.

### 4. Dispatch a foreground subagent

Call `Agent` with `subagent_type: "general-purpose"` and `run_in_background: false` — foreground, because the next step depends on the result and nothing else usefully happens meanwhile.

The prompt points at the handoff path and states the return shape: the answer itself for an AFK ticket, the prepared material for a HITL one, plus any newly-surfaced tickets and any fog the work made specifiable.

**Done when** the subagent has returned.

### 5. Record the resolution

The parent is the single writer to the map and the ticket, so two runs never race each other.

For an **AFK** ticket, sanity-check the answer against the ticket's question before it lands — a subagent that drifted produces a confident answer to a question nobody asked.

For a **HITL** ticket, run the live exchange with John now, using the subagent's prepared material. The resolution is what John decides, not what the subagent proposed.

Then, once the answer is real:

- Post it as a resolution comment: `echo "..." > issues/<TICKET>/comments/_create`
- Close the ticket by setting `status: Done`
- Append one line to the map's **Decisions so far**: the ticket's name wrapping its link, plus a one-line gist
- Graduate any fog the answer sharpened into new tickets (create, then wire blocking in a second pass), clearing each graduated patch from **Not yet specified**
- Rule out of scope anything the answer exposed as sitting past the destination: close the ticket and leave a line in **Out of scope**

**Done when** the ticket is closed, the map reflects it, and the frontier has moved.

### 6. Relay

The subagent's report never reaches John — relay what matters. Give him the decision, what it unblocked, and the new frontier by name.

## Referring to tickets

Name every ticket by its title, with the name wrapping its link. A wall of bare identifiers is illegible; names read at a glance. This holds in the handoff, in the map, and in everything John reads.
