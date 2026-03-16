# opencode-toolkit

OpenCode MCP integration for Claude Code.

Use [OpenCode](https://opencode.ai) as an autonomous worker from within Claude Code — for code audits, implementation, verification, bug analysis, and plan review. OpenCode supports 75+ LLM providers (Anthropic, OpenAI, Google, Kimi, DeepSeek, Ollama, and more), giving you multi-model capabilities through a unified interface.

## Installation

### Prerequisites

1. Install [OpenCode CLI](https://opencode.ai/docs/cli/):

```bash
curl -fsSL https://opencode.ai/install | bash
```

Or via npm:

```bash
npm install -g opencode-ai
```

2. Authenticate with at least one provider:

```bash
opencode auth login
```

Or set API keys directly:

```bash
export ANTHROPIC_API_KEY="your-key"
export OPENAI_API_KEY="your-key"
export KIMI_API_KEY="your-key"
```

3. The plugin uses [opencode-mcp](https://www.npmjs.com/package/opencode-mcp) as the MCP bridge (installed automatically via npx).

### Install the plugin

```
/plugin install opencode-toolkit@liangyuansheng
```

Choose an install scope based on your needs:

| Scope | Command | Effect |
|-------|---------|--------|
| **User** (default) | `/plugin install opencode-toolkit@liangyuansheng` | Available in all your projects |
| **Project** | `/plugin install opencode-toolkit@liangyuansheng --scope project` | Shared with team via `.claude/settings.json` (committed to repo) |
| **Local** | `/plugin install opencode-toolkit@liangyuansheng --scope local` | Only you, only this repo (gitignored) |

### Configure for your project (optional)

Run `/init` inside your project to generate a `.opencode-toolkit.md` config file. This lets you set project-specific defaults:

- Default provider and model
- Audit focus (balanced, security-first, performance-first, quality-first)
- File patterns to skip during audits
- Project-specific instructions for OpenCode (your stack, conventions, constraints)

If no config file exists, commands use sensible built-in defaults.

## Commands

| Command | Description |
|---------|-------------|
| `/init` | Initialize project config — set default model, audit focus, skip patterns |
| `/preflight` | Check OpenCode connectivity, auth status, and discover available providers/models |
| `/implement` | Delegate an implementation plan to OpenCode for autonomous execution |
| `/audit` | Code audit — fast 5-dimension (`--mini`, default) or thorough 9-dimension (`--full`) |
| `/verify` | Verify that issues from a previous audit have been fixed |
| `/bug-analyze` | Root cause analysis for user-described bugs |
| `/review-plan` | Architectural review of implementation plans |
| `/audit-fix` | Full audit→fix→verify loop — runs until all issues are resolved or you stop |
| `/audit-plugin` | Audit a Claude Code plugin for schema, specification, security, and structural defects |
| `/continue` | Continue a previous OpenCode session — iterate on findings or request fixes |

> When installed as a plugin, commands appear as `/opencode-toolkit:<command>` (e.g. `/opencode-toolkit:audit`).

## How it works

Each command follows the same pattern:

1. **Choose model** — pick a provider/model from discovered options (e.g. `anthropic/claude-sonnet-4-5`, `openai/gpt-4o`)
2. **Send to OpenCode** — the task is dispatched via `opencode-mcp` MCP tools with a role-specific persona
3. **Fallback** — if OpenCode is unavailable or returns empty, Claude performs the task manually
4. **Report** — structured output with findings, verdicts, session ID, and next steps

Every command output includes a **session ID** that you can pass to `/continue` to iterate on findings, request fixes, or drill deeper — without re-sending the full context.

## Key differences from codex-toolkit

| Feature | codex-toolkit | opencode-toolkit |
|---------|---------------|------------------|
| Backend | OpenAI Codex | OpenCode (75+ providers) |
| MCP server | `codex mcp-server` | `opencode-mcp` (npm) |
| Model format | `slug` (e.g. `o3-pro`) | `provider/model` (e.g. `anthropic/claude-sonnet-4-5`) |
| Session persistence | In-memory (lost on restart) | Persistent (survives restarts) |
| Sandbox levels | read-only / workspace-write / danger-full-access | Managed by OpenCode config |
| Reasoning effort | low / medium / high | N/A (model-dependent) |
| Auth | `codex login` or `OPENAI_API_KEY` | `opencode auth login` or provider-specific env vars |

## Audit→Fix→Verify workflow

The `/audit-fix` command runs the full cycle automatically:

```
audit → fix → verify → (issues remain?) → fix → verify → ... → ACCEPTED
```

1. Audits your code (mini or full — your choice)
2. Sends findings to Claude or OpenCode to fix (your choice)
3. Verifies each fix was actually resolved
4. Repeats up to 3 rounds or until clean
5. Reports final status: ACCEPTED / PARTIAL / UNCHANGED

You can also run each step manually:

```
/audit               # find issues (defaults to --mini)
/audit --full        # thorough 9-dimension audit
# fix them yourself
/verify report.md    # check your fixes
```

## Available models

Models are discovered dynamically at runtime via `opencode models` CLI and the `opencode_setup` MCP tool. New models and providers appear automatically after configuring them in OpenCode.

To check availability manually:

```bash
bash scripts/opencode-preflight.sh    # JSON to stdout
```

Or run `/preflight` inside Claude Code for a human-friendly report.

## MCP server

This plugin bundles a `.mcp.json` that registers the OpenCode MCP server via `npx -y opencode-mcp`. The MCP bridge auto-starts `opencode serve` if it's not already running, providing seamless access to OpenCode's 79 tools, 10 resources, and 6 prompts.

Authentication is handled by OpenCode's own config — set API keys via `opencode auth login` or environment variables for your chosen providers.
