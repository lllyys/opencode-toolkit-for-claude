---
user-invocable: false
---
<!-- Shared partial: OpenCode call pattern (availability test, prompt builder, call, session handling) -->
<!-- Referenced by: audit, audit-fix, verify, bug-analyze, review-plan, implement. Do not use standalone. -->

## OpenCode Call Pattern

### Availability Test

Before the real OpenCode call, verify the MCP server is running:

```
mcp__opencode__opencode_setup
```

This returns health status, providers, and project info. If it errors out or returns unhealthy status, skip to the calling command's **Fallback** section immediately. Do not retry.

### Build the prompt

Concatenate these parts into a single prompt string:

1. **Command persona** — the role-specific persona from the calling command's `Command persona` field (e.g. "You are a thorough security and code quality auditor.")
2. **Config focus instructions** — `{config_focus_instructions}` from `.opencode-toolkit.md` Audit Focus section (if present)
3. **Config project instructions** — `{config_project_instructions}` from `.opencode-toolkit.md` Project-Specific Instructions section (if present)
4. **Task prompt** — the command-specific task instructions (from the command's `prompt:` block)

If parts 2 or 3 are empty, omit them. Separate non-empty parts with a blank line.

**IMPORTANT**: The persona is injected here automatically from the `Command persona` field. Commands MUST NOT duplicate the persona text inside their `prompt:` block — that would cause it to appear twice.

### Canonical mcp__opencode__opencode_ask call (read-only tasks)

For tasks that only need to read and analyze (audits, reviews, bug analysis, verification):

```
mcp__opencode__opencode_ask with:
  prompt: "{built prompt string}"
  model: "{chosen_model}"
```

### Canonical mcp__opencode__opencode_run call (tasks that write)

For tasks that need to execute commands, write files, or run tests (implementation, fixes):

```
mcp__opencode__opencode_run with:
  prompt: "{built prompt string}"
  model: "{chosen_model}"
```

`opencode_run` polls until the task completes and returns the full result.

### Session Handling

1. **Save the `sessionId`** from every OpenCode response. Include it in the final report so the user can follow up with `/continue {sessionId}`.
2. **Reuse sessions** in multi-step workflows (audit→fix→verify) via `mcp__opencode__opencode_reply` to give OpenCode cumulative context.
3. **Fallback**: If `opencode_reply` fails (session not found), fall back to a fresh `mcp__opencode__opencode_ask` or `mcp__opencode__opencode_run` call with the same parameters. Update `{sessionId}` to the new value.
4. OpenCode sessions are **persistent** — they survive MCP server restarts (unlike Codex threads which are in-memory only). However, sessions may be cleaned up after extended periods.

### Sequential Execution

Run OpenCode calls **one at a time**. Wait for each call to complete before starting the next. Do NOT run multiple OpenCode calls in parallel.
