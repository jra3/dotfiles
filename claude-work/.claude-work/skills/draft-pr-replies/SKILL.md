---
name: draft-pr-replies
description: "Draft replies to PR inline review threads as pending-review comments. Claude posts drafts; user edits in browser and publishes the whole review at once."
user_invocable: true
arguments: <PR-number> [thread-selector...]
allowed-tools: "Bash(command:*), Read"
---

# Draft PR Inline Thread Replies (Pending Review)

John's preferred workflow for replying to GitHub PR inline review threads.

Claude **drafts** the replies and posts them to GitHub in `PENDING` state, attached to John's pending review on the PR. Nothing is published. John then opens the PR in the browser, edits the drafts to taste, and submits the whole review at once.

## Why this workflow

- Batches all replies into a single published review → one notification for the reviewer, not N.
- John always gets the last edit pass — Claude's text is a starting point, never the final word.
- Aligns with `feedback_pr_writing_user_voice.md` (user writes PR comments) and `feedback_slack_drafts_first.md` (drafts by default). The skill is the explicit go-ahead for Claude to publish-as-pending; submission stays with John.

## When NOT to use this skill

- **Code fixes in response to a thread** → use `/address-pr-feedback` instead. That skill edits code, commits, pushes, and resolves threads.
- **Top-level (non-inline) PR comments** → drafting those doesn't require this dance; just write the text and let John paste/post.

This skill is exclusively for *inline thread replies that should land as drafts inside a pending review*.

## Arguments

- `$ARGUMENTS` — PR number (required), optionally followed by a thread selector.
- Thread selector forms (any combination):
  - Omitted → Claude prompts John per-thread among all unresolved threads.
  - `--all-unresolved` → draft a reply on every unresolved thread (rare; usually you only want a subset).
  - One or more thread node IDs (`PRRT_…`) → draft replies on exactly those.
  - One or more `path:line` refs (e.g. `app/foo.ts:42`) → resolve to thread IDs.

If parsing fails, print `Usage: /draft-pr-replies <PR_NUMBER> [thread-selector...]` and stop.

## Voice and content

Drafts must sound like **John writing**, not Claude narrating. Concrete defaults:

- First person, terse, lowercase-start is fine.
- No "Thanks for the review!" filler, no "Great point —", no signed sign-offs.
- If acknowledging something the reviewer is right about: short, e.g. `yeah agreed, fixing.` or `good catch, will update in a follow-up.`
- If pushing back: state the reason, then the position. `this is intentional — we need X because Y.`
- If the thread needs a code fix that John will do later: link to the Linear issue if one exists, else say `tracking as follow-up.`

When unsure what John wants to say on a given thread, **ask** before drafting. Don't invent positions on design questions.

## Execution Steps

### Step 1: Detect repository and validate PR

```bash
gh repo view --json owner,name -q '.owner.login + "/" + .name'
gh pr view "$PR_NUMBER" --json number,state,title,headRefName,url
```

If state is not `OPEN`, stop with `PR #$PR_NUMBER is $STATE, not open.`

Save `OWNER`, `REPO`, `PR_URL`, `TITLE`.

### Step 2: Find or create John's pending review

There's **only one pending review per user per PR**. Reusing an existing one is mandatory; creating a second is a silent failure waiting to happen.

Look up the current user and any pending review they own:

```bash
VIEWER=$(gh api graphql -f query='{ viewer { login } }' -q .data.viewer.login)

gh api graphql -F owner="$OWNER" -F repo="$REPO" -F num="$PR_NUMBER" -f query='
query($owner:String!,$repo:String!,$num:Int!) {
  repository(owner:$owner, name:$repo) {
    pullRequest(number:$num) {
      reviews(first:50, states:PENDING) {
        nodes { id author { login } }
      }
    }
  }
}'
```

Filter the result for `author.login == $VIEWER`. There will be 0 or 1 match.

- **If 1 match**: use its `id` as `REVIEW_ID`. Tell John: `Reusing your existing pending review (<id-short>) on PR #N. It already has K draft comments.` (Count via the same query, expanding `comments(first:0){totalCount}` if useful.)
- **If 0 matches**: create one with empty body and no event:

  ```bash
  gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER/reviews" \
    -f body='' --jq '.node_id'
  ```

  Use the returned `node_id` (the GraphQL ID, `PRR_…`) as `REVIEW_ID`. Tell John: `Created a new pending review (<id-short>) on PR #N.`

### Step 3: Fetch threads

```bash
gh api graphql -F owner="$OWNER" -F repo="$REPO" -F num="$PR_NUMBER" -f query='
query($owner:String!,$repo:String!,$num:Int!) {
  repository(owner:$owner, name:$repo) {
    pullRequest(number:$num) {
      reviewThreads(first:100) {
        nodes {
          id isResolved isOutdated path line startLine
          comments(first:20) {
            nodes { id body author { login } createdAt }
          }
        }
      }
    }
  }
}'
```

Filter to `isResolved == false`. Map `path:line` → thread `id` for any selector matching.

If the selector resolves to zero threads, stop and tell John what was matched vs. unmatched.

### Step 4: Decide what each reply says

For each target thread:

1. Read the thread comments (most recent last) and the relevant file at `path:line` for context.
2. If John provided per-thread reply text inline in the chat, use it verbatim.
3. Otherwise, draft per the **Voice and content** rules above. When the thread is a design question or anything where John's position isn't obvious, **ask him** before drafting — don't guess.
4. Present each draft back to John in chat **before** posting:

   ```
   Thread 1: app/foo.ts:42 — reviewer @alice asked …
     Draft: yeah agreed, fixing in a follow-up PR.

   Thread 2: …
   ```

   Wait for explicit "post these" / "looks good, post" before Step 5. Edits in chat replace the draft for that thread.

### Step 5: Post each draft reply attached to the pending review

For each approved draft:

```bash
gh api graphql \
  -F thread="$THREAD_ID" \
  -F review="$REVIEW_ID" \
  -F body="$BODY" \
  -f query='
mutation($thread:ID!, $review:ID!, $body:String!) {
  addPullRequestReviewThreadReply(input:{
    pullRequestReviewThreadId: $thread,
    pullRequestReviewId: $review,
    body: $body
  }) {
    comment { id state url }
  }
}'
```

Confirm `comment.state == "PENDING"` in the response. If it comes back `SUBMITTED`, something is wrong — the `pullRequestReviewId` was missing or the review was submitted between Step 2 and Step 5. Stop and tell John.

Pass `$BODY` via `-F` (string form) so newlines/quotes survive intact. For very long bodies, write to a tempfile and `-F body=@/tmp/draft-N.txt`.

If a single reply fails, log the error, continue with the remaining threads, and report failures at the end.

### Step 6: Hand off to John

Print the PR's "Files changed" URL — that's where pending review drafts are visible and editable:

```
Drafted N replies on PR #1234 ("$TITLE") as pending review.

Open and edit:
  https://github.com/$OWNER/$REPO/pull/$PR_NUMBER/files

Submit the whole review with "Finish your review" → choose comment / approve / request changes.
```

**Do NOT** submit the review. That's John's step, in the browser, after his edits.

## Gotchas

- **One pending review per user per PR** — always look up before creating. Step 2 enforces this.
- **Drafts are only visible to John** until the review is submitted. The reviewer sees nothing.
- **`gh pr review --comment/--approve/--request-changes` will submit the pending review**, publishing every draft inside it — including these. Don't run those commands while drafts are pending unless that's what John wants.
- **Thread node IDs (`PRRT_…`) and review node IDs (`PRR_…`) are GraphQL IDs**, not REST integers. The mutation rejects integer IDs.
- **Outdated threads** (`isOutdated: true`) still accept replies; reviewers can see them. Don't auto-skip them, but flag them in the chat preview so John knows.
- **Bot threads** (Coderabbit, Renovate, etc.) — drafting replies to bots is usually noise. Flag them in the preview and confirm before drafting.

## Error Recovery

- **`gh` not authenticated** → tell John to run `gh auth login`.
- **PR is closed/merged** → stop in Step 1; pending reviews on closed PRs are weird.
- **Mutation returns `Could not resolve to a node with the global id` for the thread ID** → the thread was probably resolved/deleted between fetch and post. Re-fetch and retry once.
- **`addPullRequestReviewThreadReply` returns `state: SUBMITTED`** → the review got submitted mid-flow. Stop; the remaining drafts can't be drafts anymore.
