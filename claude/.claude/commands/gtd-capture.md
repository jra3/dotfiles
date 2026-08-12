---
description: Quick capture one or more items to the GTD Capture state in Linear
argument-hint: <item> [; more items separated by semicolons]
---

Capture `$ARGUMENTS` into Linear. **Capture is dumb and lossless — do not clarify.**

## The one rule

Write down what John said, near-verbatim. Do not rephrase into an action, do not guess a project, do not add labels, do not set a state. Turning "G would like a king tut poster" into "Find a 1970s King Tut poster" is *clarify*, and it happens later with John in the loop. An agent that clarifies at capture time is making decisions John did not make.

## Steps

1. Split `$ARGUMENTS` on semicolons — each becomes one issue.
2. Create each with **no `stateId`**. The GTD team default is `Capture` and triage is off, so it lands there automatically. Setting a state explicitly is how that contract gets broken.

```
curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: $(grep -m1 LINEAR_API_KEY ~/.config/linearfs-personal/linearfs/env | cut -d= -f2-)" \
  -H 'Content-Type: application/json' \
  -d '{"query":"mutation($t:String!,$team:String!){ issueCreate(input:{title:$t, teamId:$team}){ success issue { identifier } } }","variables":{"t":"<text>","team":"8c27b78f-648f-408e-aefb-8eafd6fb7ca3"}}'
```

3. Report the identifiers back, one line each. Nothing else.

**Verify against the response, not `$?`.** Success is `data.issueCreate.success` — GraphQL returns HTTP 200 on failure too.

**Done when** every item has an identifier and John can see them.
