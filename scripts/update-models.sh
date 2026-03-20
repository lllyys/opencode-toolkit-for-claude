#!/usr/bin/env bash
# update-models.sh — Refresh well-known-models.json from the live OpenCode MCP server.
#
# Usage:  bash scripts/update-models.sh
#
# Requires: npx, python3
# Starts the opencode-mcp server, queries opencode_setup for ready providers,
# then queries opencode_provider_models for each, and writes the result to
# scripts/well-known-models.json.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="$SCRIPT_DIR/well-known-models.json"

info() { echo ":: $*" >&2; }

# Start MCP server and query via stdio JSON-RPC
query_mcp() {
  local method="$1"
  local params="$2"
  local id="$1"
  local request="{\"jsonrpc\":\"2.0\",\"id\":\"$id\",\"method\":\"tools/call\",\"params\":{\"name\":\"$method\",\"arguments\":$params}}"
  echo "$request"
}

# Use python3 to drive the MCP server via subprocess stdin/stdout
python3 - "$OUTPUT" <<'PYEOF'
import subprocess, json, sys, time

output_path = sys.argv[1]

# Start opencode-mcp server
proc = subprocess.Popen(
    ["npx", "-y", "opencode-mcp"],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    text=True
)

msg_id = 0

def send_rpc(method, params=None):
    global msg_id
    msg_id += 1
    req = {"jsonrpc": "2.0", "id": msg_id, "method": method}
    if params is not None:
        req["params"] = params
    line = json.dumps(req)
    proc.stdin.write(line + "\n")
    proc.stdin.flush()

    # Read response (may have notifications before it)
    while True:
        resp_line = proc.stdout.readline()
        if not resp_line:
            return None
        try:
            resp = json.loads(resp_line.strip())
            if resp.get("id") == msg_id:
                return resp
        except json.JSONDecodeError:
            continue

def call_tool(name, arguments=None):
    params = {"name": name}
    if arguments:
        params["arguments"] = arguments
    return send_rpc("tools/call", params)

# Initialize
print(":: Initializing MCP server...", file=sys.stderr)
init_resp = send_rpc("initialize", {
    "protocolVersion": "2024-11-05",
    "capabilities": {},
    "clientInfo": {"name": "update-models", "version": "1.0.0"}
})
if not init_resp:
    print("ERROR: Failed to initialize MCP server", file=sys.stderr)
    proc.terminate()
    sys.exit(1)

send_rpc("notifications/initialized")
time.sleep(1)

# Get setup info to find ready providers
print(":: Querying opencode_setup...", file=sys.stderr)
setup_resp = call_tool("opencode_setup")

if not setup_resp or "result" not in setup_resp:
    print("ERROR: opencode_setup failed", file=sys.stderr)
    proc.terminate()
    sys.exit(1)

# Parse setup response to find provider IDs
setup_text = ""
for content in setup_resp.get("result", {}).get("content", []):
    if content.get("type") == "text":
        setup_text = content["text"]

# Extract all provider IDs from the setup text
# Look for lines like "- providername (Display Name): ..."
import re
all_providers = re.findall(r'^- (\w[\w-]*) \(', setup_text, re.MULTILINE)
# Also find the "ready" providers (they have "detected via" or similar)
ready_section = setup_text.split("**Ready to use:**")
ready_providers = []
if len(ready_section) > 1:
    ready_text = ready_section[1].split("**Quick setup")[0] if "**Quick setup" in ready_section[1] else ready_section[1]
    ready_providers = re.findall(r'^- (\w[\w-]*) \(', ready_text, re.MULTILINE)

# Query models for each ready provider
print(f":: Found ready providers: {ready_providers}", file=sys.stderr)
models = {}

for provider_id in ready_providers:
    print(f":: Querying models for {provider_id}...", file=sys.stderr)
    resp = call_tool("opencode_provider_models", {"providerId": provider_id, "limit": 0})
    if resp and "result" in resp:
        text = ""
        for content in resp["result"].get("content", []):
            if content.get("type") == "text":
                text = content["text"]
        # Parse "- model_id — Description" lines
        provider_models = re.findall(r'^- ([\w./-]+) —', text, re.MULTILINE)
        if provider_models:
            models[provider_id] = [
                m if "/" in m else f"{provider_id}/{m}"
                for m in provider_models
            ]

# Also query common providers that might not be "ready" but should have well-known defaults
common_providers = ["anthropic", "openai", "google", "deepseek"]
for p in common_providers:
    if p not in models:
        # Keep existing defaults from the current file if present
        try:
            with open(output_path) as f:
                existing = json.load(f)
            if p in existing:
                models[p] = existing[p]
        except (FileNotFoundError, json.JSONDecodeError):
            pass

# Write output
models["_comment"] = "Fallback model list used when `opencode models` CLI discovery fails. Run `bash scripts/update-models.sh` to refresh from the live MCP server."
with open(output_path, "w") as f:
    json.dump(models, f, indent=2)
    f.write("\n")

print(f":: Written {sum(len(v) for k, v in models.items() if k != '_comment')} models to {output_path}", file=sys.stderr)

proc.terminate()
PYEOF

info "Done. Check $OUTPUT"
