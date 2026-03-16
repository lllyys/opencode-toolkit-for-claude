# opencode-toolkit

OpenCode MCP integration for Claude Code. Slash commands that delegate work to OpenCode running as an MCP server.

## Project structure

```
commands/           Slash command definitions (*.md with YAML frontmatter)
  shared/
    model-selection.md  Shared partial — dynamic model/provider discovery (user-invocable: false)
    opencode-call.md    Shared partial — availability test, call pattern, session handling (user-invocable: false)
    scope-parse.md      Shared partial — scope parsing, trivial check, skip patterns (user-invocable: false)
    fallback.md         Shared partial — manual fallback rules (user-invocable: false)
    plugin-discover.md  Shared partial — plugin artifact discovery for plugin directories (user-invocable: false)
  preflight.md        /preflight — connectivity + provider/model check
  implement.md        /implement — autonomous plan execution
  audit.md            /audit — code audit (--full 9-dim or --mini 5-dim)
  verify.md           /verify — verify fixes from previous audit
  bug-analyze.md      /bug-analyze — root cause analysis
  review-plan.md      /review-plan — architectural plan review
  audit-fix.md        /audit-fix — audit→fix→verify loop
  audit-plugin.md     /audit-plugin — plugin artifact audit (schema, spec, security, structure)
  continue.md         /continue — multi-turn follow-up via opencode_reply
  init.md             /init — generate .opencode-toolkit.md project config
scripts/
  opencode-preflight.sh  Provider/model discovery script
.mcp.json               Registers OpenCode MCP server (via opencode-mcp npm package)
.claude-plugin/
  plugin.json           Plugin metadata
  marketplace.json      Marketplace manifest for /plugin marketplace add
```

## Conventions

### MCP tool calls

- The MCP server is `opencode-mcp` (npm package), registered under the name `opencode` in `.mcp.json`.
- Primary tools used by commands:
  - `mcp__opencode__opencode_run` — execute a task with polling until completion (for implementation, fixes)
  - `mcp__opencode__opencode_ask` — single-shot prompt + response (for audits, reviews, analysis)
  - `mcp__opencode__opencode_reply` — continue an existing session (for multi-turn workflows)
  - `mcp__opencode__opencode_setup` — health check and provider/model discovery
  - `mcp__opencode__opencode_provider_test` — test provider connectivity
- Every command that calls OpenCode MUST include a role-specific persona as the first part of the prompt.
- Every command report MUST include the `sessionId` from the OpenCode response so users can follow up with `/continue`.
- Multi-step workflows (like audit→fix→verify) should **reuse the same session** via `mcp__opencode__opencode_reply` for cumulative context.
- OpenCode sessions are **persistent** — they survive server restarts (unlike Codex threads which are in-memory only).

### Model selection

- Models use `provider/model` format (e.g. `anthropic/claude-sonnet-4-5`, `openai/gpt-4o`, `google/gemini-2.0-flash`).
- OpenCode supports 75+ providers. The preflight script discovers available providers and models.
- There is no `model_reasoning_effort` parameter — this concept does not exist in OpenCode.
- There is no `sandbox` parameter — OpenCode manages permissions via its own configuration.

### Shared partials

Commands reference shared partials to eliminate boilerplate:

- **model-selection.md** → loads `.opencode-toolkit.md` config, runs preflight, presents model choices
- **opencode-call.md** → availability test (ping via `opencode_setup`), persona builder, canonical call pattern, session handling, sequential execution rule
- **scope-parse.md** → unified scope parsing table, skip pattern enforcement against `{config_skip_patterns}`, trivial scope check with AskUserQuestion
- **fallback.md** → universal "if OpenCode fails, do it manually" rules
- **plugin-discover.md** → plugin root resolution, manifest validation, artifact discovery, cross-reference map, inventory summary

Config enforcement chain: `model-selection.md` (extracts config variables) → `opencode-call.md` (applies them to calls) → `scope-parse.md` (applies skip patterns to files).

Commands that share logic with another command should reference it rather than duplicate.

### Project config (`.opencode-toolkit.md`)

Users can run `/init` to generate a `.opencode-toolkit.md` in their project root. This file is optional — all commands work without it.

When present, `commands/shared/model-selection.md` reads it at Step 0 and extracts variables: `{config_default_model}`, `{config_default_audit_type}`, `{config_focus_instructions}`, `{config_skip_patterns}`, `{config_project_instructions}`.

Priority: user choice > project config > command defaults.

### Command structure

All commands follow this pattern:
1. Load `.opencode-toolkit.md` project config if it exists (via model-selection.md Step 0)
2. Run `scripts/opencode-preflight.sh` via model-selection.md to discover providers/models
3. Present choices via `AskUserQuestion` (provider/model)
4. Ping OpenCode with availability test (via opencode-call.md using `opencode_setup`)
5. Send the real task to OpenCode via `mcp__opencode__opencode_ask` or `mcp__opencode__opencode_run` (via opencode-call.md)
6. If OpenCode fails or returns empty, fall back to manual analysis (via fallback.md)
7. Display structured report with sessionId

### Adding new commands

1. Create `commands/<name>.md` with YAML frontmatter (`description`, optional `argument-hint`)
2. Reference `commands/shared/model-selection.md` for model selection
3. Reference `commands/shared/opencode-call.md` for availability test and call pattern
4. Reference `commands/shared/scope-parse.md` if the command takes file/scope arguments
5. Reference `commands/shared/fallback.md` if manual fallback is needed
6. Include `sessionId` in the report output
7. Update `README.md` commands table
