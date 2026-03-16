#!/usr/bin/env bash
# opencode-preflight.sh — Discover available OpenCode providers and models.
#
# Usage:  bash scripts/opencode-preflight.sh
# Output: JSON to stdout  (human summary to stderr)
#
# Caching: Results are cached for 5 minutes in $TMPDIR/opencode-preflight-cache.json.
#          Set OPENCODE_PREFLIGHT_NO_CACHE=1 to skip cache.
#
# How it works:
#   Runs `opencode models` to list available providers and models.
#   Parses the output to build a structured JSON response.
#   Falls back to checking opencode.json config if CLI discovery fails.

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────

CACHE_TTL=300            # seconds (5 minutes) for our own preflight cache

# ── Helpers ──────────────────────────────────────────────────────────────────

info() { echo "$*" >&2; }

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

json_array() {
  if [[ $# -eq 0 ]]; then
    echo "[]"
    return
  fi
  local result="["
  local first=true
  for item in "$@"; do
    if $first; then first=false; else result+=","; fi
    result+="\"$item\""
  done
  result+="]"
  echo "$result"
}

file_age_seconds() {
  local file="$1"
  if [[ "$(uname)" == "Darwin" ]]; then
    echo $(( $(date +%s) - $(stat -f %m "$file") ))
  else
    echo $(( $(date +%s) - $(stat -c %Y "$file") ))
  fi
}

# ── Step 0: Check our own preflight cache ────────────────────────────────────

CACHE_FILE="${TMPDIR:-/tmp}/opencode-preflight-cache.json"

if [[ -z "${OPENCODE_PREFLIGHT_NO_CACHE:-}" && -f "$CACHE_FILE" ]]; then
  cache_age=$(file_age_seconds "$CACHE_FILE")
  if [[ $cache_age -lt $CACHE_TTL ]]; then
    info "Using cached results (${cache_age}s old, TTL ${CACHE_TTL}s)"
    cat "$CACHE_FILE"
    exit 0
  fi
fi

# ── Step 1: Check opencode CLI ───────────────────────────────────────────────

if ! command -v opencode &>/dev/null; then
  cat <<'JSON'
{"status":"error","error":"opencode CLI not found. Install: curl -fsSL https://opencode.ai/install | bash","providers":[],"models":[],"models_detail":[]}
JSON
  exit 1
fi

# ── Step 2: Get opencode version ─────────────────────────────────────────────

OPENCODE_VERSION=$(opencode --version 2>/dev/null || echo "unknown")
info "OpenCode version: $OPENCODE_VERSION"

# ── Step 3: Check authentication ─────────────────────────────────────────────

AUTH_STATUS="unknown"
PROVIDERS=()

# Try `opencode auth list` to see configured providers
AUTH_OUTPUT=$(opencode auth list 2>&1) || true

if echo "$AUTH_OUTPUT" | grep -qiE "anthropic|openai|google|kimi|deepseek|ollama|openrouter"; then
  AUTH_STATUS="authenticated"
  # Extract provider names from auth output
  while IFS= read -r line; do
    # Look for provider names in the output
    provider=$(echo "$line" | grep -oiE "^[a-z_-]+" | head -1)
    if [[ -n "$provider" ]]; then
      PROVIDERS+=("$provider")
    fi
  done <<< "$AUTH_OUTPUT"
  info "Auth status: authenticated"
else
  # Check for common API key environment variables
  if [[ -n "${ANTHROPIC_API_KEY:-}" || -n "${OPENAI_API_KEY:-}" || -n "${GOOGLE_API_KEY:-}" || -n "${KIMI_API_KEY:-}" ]]; then
    AUTH_STATUS="api_key"
    [[ -n "${ANTHROPIC_API_KEY:-}" ]] && PROVIDERS+=("anthropic")
    [[ -n "${OPENAI_API_KEY:-}" ]] && PROVIDERS+=("openai")
    [[ -n "${GOOGLE_API_KEY:-}" ]] && PROVIDERS+=("google")
    [[ -n "${KIMI_API_KEY:-}" ]] && PROVIDERS+=("kimi-for-coding")
    info "Auth status: api_key"
  fi

  # Check opencode.json configs for provider keys
  for config_path in "./opencode.json" "$HOME/.config/opencode/opencode.json"; do
    if [[ -f "$config_path" ]]; then
      if command -v python3 &>/dev/null; then
        config_providers=$(python3 -c "
import json, sys
try:
    with open('$config_path') as f:
        data = json.load(f)
    providers = data.get('provider', {})
    for name in providers:
        if providers[name].get('apiKey') or providers[name].get('api_key'):
            print(name)
except Exception:
    pass
" 2>/dev/null) || true
        while IFS= read -r p; do
          [[ -n "$p" ]] && PROVIDERS+=("$p") && AUTH_STATUS="config"
        done <<< "$config_providers"
      fi
    fi
  done
fi

if [[ "$AUTH_STATUS" == "unknown" ]]; then
  OPENCODE_VERSION_SAFE=$(json_escape "$OPENCODE_VERSION")
  cat <<JSON
{"status":"error","error":"No providers configured. Run: opencode auth login","auth_status":"none","opencode_version":"$OPENCODE_VERSION_SAFE","providers":[],"models":[],"models_detail":[]}
JSON
  exit 1
fi

# Deduplicate providers
UNIQUE_PROVIDERS=($(printf '%s\n' "${PROVIDERS[@]}" | sort -u))
PROVIDERS=("${UNIQUE_PROVIDERS[@]}")
info "Providers: ${PROVIDERS[*]}"

# ── Step 4: Discover models ──────────────────────────────────────────────────

MODELS=()
MODELS_DETAIL="[]"

# Try to get models via `opencode models` for each provider
if command -v python3 &>/dev/null; then
  ALL_MODELS_JSON="[]"

  for provider in "${PROVIDERS[@]}"; do
    MODELS_OUTPUT=$(opencode models "$provider" 2>/dev/null) || true
    if [[ -n "$MODELS_OUTPUT" ]]; then
      # Parse model list from CLI output
      provider_models=$(python3 -c "
import sys, json, re

output = '''$MODELS_OUTPUT'''
models = []
for line in output.strip().split('\n'):
    line = line.strip()
    if not line or line.startswith('─') or line.startswith('=') or line.lower().startswith('model'):
        continue
    # Try to extract model identifier (provider/model or just model name)
    parts = line.split()
    if parts:
        model_id = parts[0]
        # Skip table decoration
        if model_id.startswith('|') or model_id.startswith('+'):
            model_id = model_id.strip('|').strip()
        if model_id and not model_id.startswith('─'):
            # Ensure provider/model format
            if '/' not in model_id:
                model_id = '$provider/' + model_id
            desc = ' '.join(parts[1:]).strip('|').strip() if len(parts) > 1 else model_id
            models.append({'slug': model_id, 'description': desc})
print(json.dumps(models))
" 2>/dev/null) || true

      if [[ -n "$provider_models" && "$provider_models" != "[]" ]]; then
        ALL_MODELS_JSON=$(python3 -c "
import json
existing = json.loads('''$ALL_MODELS_JSON''')
new = json.loads('''$provider_models''')
existing.extend(new)
print(json.dumps(existing))
" 2>/dev/null) || true
      fi
    fi
  done

  MODELS_DETAIL="$ALL_MODELS_JSON"

  # Extract model slugs
  while IFS= read -r slug; do
    [[ -n "$slug" ]] && MODELS+=("$slug")
  done < <(python3 -c "
import json
for m in json.loads('''$MODELS_DETAIL'''):
    print(m['slug'])
" 2>/dev/null)
fi

# If no models discovered via CLI, add well-known models for detected providers
if [[ ${#MODELS[@]} -eq 0 ]]; then
  info "No models discovered via CLI, using well-known defaults for configured providers"
  WELL_KNOWN_DETAIL="["
  first=true
  for provider in "${PROVIDERS[@]}"; do
    case "$provider" in
      anthropic)
        for m in "anthropic/claude-sonnet-4-5" "anthropic/claude-haiku-3-5"; do
          if $first; then first=false; else WELL_KNOWN_DETAIL+=","; fi
          WELL_KNOWN_DETAIL+="{\"slug\":\"$m\",\"description\":\"$m\"}"
          MODELS+=("$m")
        done
        ;;
      openai)
        for m in "openai/gpt-4o" "openai/o3-mini"; do
          if $first; then first=false; else WELL_KNOWN_DETAIL+=","; fi
          WELL_KNOWN_DETAIL+="{\"slug\":\"$m\",\"description\":\"$m\"}"
          MODELS+=("$m")
        done
        ;;
      google)
        for m in "google/gemini-2.0-flash" "google/gemini-2.5-pro"; do
          if $first; then first=false; else WELL_KNOWN_DETAIL+=","; fi
          WELL_KNOWN_DETAIL+="{\"slug\":\"$m\",\"description\":\"$m\"}"
          MODELS+=("$m")
        done
        ;;
      kimi-for-coding|kimi)
        for m in "kimi-for-coding/k2p5"; do
          if $first; then first=false; else WELL_KNOWN_DETAIL+=","; fi
          WELL_KNOWN_DETAIL+="{\"slug\":\"$m\",\"description\":\"$m\"}"
          MODELS+=("$m")
        done
        ;;
      deepseek)
        for m in "deepseek/deepseek-chat" "deepseek/deepseek-reasoner"; do
          if $first; then first=false; else WELL_KNOWN_DETAIL+=","; fi
          WELL_KNOWN_DETAIL+="{\"slug\":\"$m\",\"description\":\"$m\"}"
          MODELS+=("$m")
        done
        ;;
      ollama)
        for m in "ollama/llama3.1" "ollama/codellama"; do
          if $first; then first=false; else WELL_KNOWN_DETAIL+=","; fi
          WELL_KNOWN_DETAIL+="{\"slug\":\"$m\",\"description\":\"$m (local)\"}"
          MODELS+=("$m")
        done
        ;;
    esac
  done
  WELL_KNOWN_DETAIL+="]"
  MODELS_DETAIL="$WELL_KNOWN_DETAIL"
fi

if [[ ${#MODELS[@]} -eq 0 ]]; then
  OPENCODE_VERSION_SAFE=$(json_escape "$OPENCODE_VERSION")
  AUTH_STATUS_SAFE=$(json_escape "$AUTH_STATUS")
  cat <<JSON
{"status":"error","error":"No models available. Check provider configuration.","opencode_version":"$OPENCODE_VERSION_SAFE","auth_status":"$AUTH_STATUS_SAFE","providers":$(json_array "${PROVIDERS[@]}"),"models":[],"models_detail":[]}
JSON
  exit 1
fi

info "Found ${#MODELS[@]} models"
for model in "${MODELS[@]}"; do
  info "  $model"
done

# ── Step 5: Output JSON ─────────────────────────────────────────────────────

models_json=$(json_array "${MODELS[@]+"${MODELS[@]}"}")
providers_json=$(json_array "${PROVIDERS[@]+"${PROVIDERS[@]}"}")

OPENCODE_VERSION_SAFE=$(json_escape "$OPENCODE_VERSION")
AUTH_STATUS_SAFE=$(json_escape "$AUTH_STATUS")

OUTPUT=$(cat <<JSON
{"status":"ok","opencode_version":"$OPENCODE_VERSION_SAFE","auth_status":"$AUTH_STATUS_SAFE","providers":$providers_json,"models":$models_json,"models_detail":$MODELS_DETAIL}
JSON
)

echo "$OUTPUT" > "$CACHE_FILE"
echo "$OUTPUT"
