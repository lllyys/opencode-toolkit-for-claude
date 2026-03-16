---
description: Check OpenCode connectivity, authentication, and discover available providers and models
---

# OpenCode Preflight Check

Run a preflight check to verify OpenCode is working and discover which providers and models are available.

## Workflow

### Step 1: Run the preflight script

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/opencode-preflight.sh"
```

Parse the JSON output from stdout. The script also prints a human-readable summary to stderr.

### Step 2: MCP server health check

After the script, also test the MCP server directly:

```
mcp__opencode__opencode_setup
```

This verifies the `opencode-mcp` bridge is running and can reach the OpenCode server.

### Step 3: Display results

Present the results in a clear, readable format:

```markdown
## OpenCode Preflight Results

**Status**: {status}
**OpenCode version**: {opencode_version}
**Auth status**: {auth_status}
**MCP server**: Connected / Not connected

### Configured Providers

| Provider | Status |
|----------|--------|
| {provider} | Available |
| ... | ... |

### Available Models

| Model | Provider | Description |
|-------|----------|-------------|
| {model} | {provider} | {description} |
| ... | ... | ... |
```

### Step 4: Handle errors

- If `status` is `"error"`:
  - Display the error message prominently
  - Suggest fixes:
    - `"opencode CLI not found"` → `curl -fsSL https://opencode.ai/install | bash`
    - `"No providers configured"` → `opencode auth login`
- If `models` is empty:
  - Warn: "No models are currently available"
  - Suggest: Check provider configuration, try `opencode auth login`

### Step 5: Summary

End with a one-line verdict:

- All good: "OpenCode is ready. {N} providers, {M} models available."
- Partial: "OpenCode is reachable but model discovery returned limited results."
- Error: "OpenCode is not ready. See errors above."
