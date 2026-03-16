---
user-invocable: false
---
<!-- Shared partial: dynamic model selection via opencode-preflight -->
<!-- Referenced by all commands. Do not use as a standalone command. -->

## Model & Settings Selection

Before starting, discover which OpenCode providers and models are currently available and check for project-specific configuration.

### Step 0: Load project config (if exists)

Check if `.opencode-toolkit.md` exists in the current working directory. If it does, read it and extract these variables:

- `{config_default_model}` — Default model (provider/model format)
- `{config_default_audit_type}` — Default audit type (mini or full)
- `{config_focus_instructions}` — Audit Focus additional instructions text
- `{config_skip_patterns}` — Skip patterns (glob list)
- `{config_project_instructions}` — Project-Specific Instructions text

If `.opencode-toolkit.md` does not exist, leave all variables empty and use the calling command's built-in defaults. Do NOT ask the user to run `/init` — it's optional.

**Priority order** (highest wins):
1. User's explicit choice (from AskUserQuestion)
2. Project config (`.opencode-toolkit.md`)
3. Command's built-in defaults

### Step A: Run preflight discovery

Run the preflight script to probe available providers and models:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/opencode-preflight.sh"
```

Parse the JSON output. The structure is:

```json
{
  "status": "ok",
  "opencode_version": "...",
  "auth_status": "...",
  "providers": ["anthropic", "openai", ...],
  "models": ["anthropic/claude-sonnet-4-5", "openai/gpt-4o", ...],
  "models_detail": [
    {"slug": "anthropic/claude-sonnet-4-5", "description": "..."},
    ...
  ]
}
```

### Step B: Handle errors

- If `status` is `"error"` → display the `error` message to the user and **STOP**. Common fixes:
  - `"opencode CLI not found"` → tell user to run `curl -fsSL https://opencode.ai/install | bash`
  - `"No providers configured"` → tell user to run `opencode auth login`
- If `models` is an empty array → tell user "No models are currently available. Check your provider configuration." and **STOP**.

### Step C: Present choices via AskUserQuestion

Build the `AskUserQuestion` options **dynamically** from the preflight results.

**Question — Model** (from `models` and `models_detail` arrays):

Build the option list dynamically from the preflight results:

1. For each model in the `models` array, look up its `description` from the `models_detail` array (match by `slug`).
2. If `models_detail` is empty or a model has no matching entry, use the model slug as the description.
3. Present each model as an option with its description.

**Determining the recommended model**:
1. If `{config_default_model}` is set AND it's in the available list → use that
2. Otherwise → use the **first model** in the `models` array

Do NOT hardcode any specific model name as "recommended" — always derive it from the preflight results or config.

### Step D: Apply project config to OpenCode calls

After the user makes their choice, when building the OpenCode MCP call, you MUST apply config values as follows:

1. **Prompt prefix**: Start with the command's role persona, then MUST append:
   - `{config_focus_instructions}` (if non-empty)
   - `{config_project_instructions}` (if non-empty)

   These are NOT optional — if the config provides them, they MUST be included in every OpenCode call's prompt.

2. **Skip patterns**: Before sending files to OpenCode, you MUST filter out any files matching `{config_skip_patterns}`. If all files are filtered out, report that and stop.

See `commands/shared/opencode-call.md` for the canonical call pattern that enforces these rules.
