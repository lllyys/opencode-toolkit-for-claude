---
description: Continue a previous OpenCode session — iterate on findings, request fixes, or drill deeper
argument-hint: "<sessionId> <follow-up prompt>"
---

## User Input

```text
$ARGUMENTS
```

## What This Does

Uses the `mcp__opencode__opencode_reply` MCP tool to continue a previous OpenCode session. The session preserves full context from the original command, so you can:

> **Note**: OpenCode sessions are **persistent** — they survive MCP server restarts. However, sessions may be cleaned up after extended periods of inactivity.

- Iterate on audit findings: "Now fix the 3 Critical issues you found"
- Follow up on implementation: "Run the tests and fix any failures"
- Drill into bug analysis: "Show me the exact call stack for issue #2"
- Refine a review: "Explain the race condition you flagged in more detail"

## Workflow

### Step 1: Parse input

Extract the `sessionId` and follow-up prompt from `$ARGUMENTS`:

| Input | Interpretation |
|-------|----------------|
| `<sessionId> <prompt>` | Session ID + follow-up message |
| `<sessionId>` (no prompt) | Ask the user for the follow-up prompt |
| (empty) | Ask the user for both sessionId and prompt |

If `$ARGUMENTS` is empty or missing the sessionId:

```
AskUserQuestion:
  question: "What is the session ID from the previous OpenCode command?"
  header: "Session ID"
  options:
    - label: "Paste session ID"
      description: "The sessionId shown in the output of your previous command"
    - label: "I don't have one"
      description: "Start a new session with /audit, /implement, etc. instead"
```

If the user doesn't have a sessionId, suggest they run one of the main commands first and STOP.

If the follow-up prompt is missing:

```
AskUserQuestion:
  question: "What would you like to tell OpenCode?"
  header: "Follow-up"
  options:
    - label: "Fix the issues found"
      description: "Ask OpenCode to fix all Critical and High severity issues"
    - label: "Explain in more detail"
      description: "Ask OpenCode to elaborate on its findings"
    - label: "Run tests"
      description: "Ask OpenCode to run tests and report results"
```

### Step 2: Send follow-up to OpenCode

```
mcp__opencode__opencode_reply with:
  sessionId: {sessionId}
  prompt: "{follow_up_prompt}"
```

**If `opencode_reply` fails** (session not found or expired):

```
Session `{sessionId}` is no longer available.

Options:
- Start a fresh session: /audit, /implement, /bug-analyze, etc.
- Re-run the original command to create a new session
```
And STOP.

### Step 3: Display response

```markdown
## OpenCode Follow-up

**Session ID**: `{sessionId}`
**Prompt**: {follow_up_prompt}

---

{opencode response}

---

_Session ID: `{sessionId}` — run `/continue {sessionId}` to continue this conversation._
```

### Step 4: Offer to continue

Ask the user what to do next:
- Continue the conversation (another `/continue`)
- Start a fresh command
- Done
