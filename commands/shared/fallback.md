---
user-invocable: false
---
<!-- Shared partial: fallback rules when OpenCode returns empty or fails -->
<!-- Referenced by: audit, verify, bug-analyze, review-plan. Do not use standalone. -->

## Fallback — Manual Analysis

**CRITICAL**: If OpenCode returns empty, errors out, or provides incomplete results, you MUST perform the task manually. Never stop just because OpenCode failed.

### Steps

1. **Read each file in scope as determined by scope-parse.md** using the Read tool
2. **Analyze** using the calling command's dimensions, criteria, or review framework
3. **Use Grep** to search for common patterns relevant to the task (e.g. security markers, dead code indicators, TODO/FIXME/HACK)
4. **Report findings** in the same structured format the calling command specifies

### Rules

- Do NOT say "OpenCode didn't return findings" and stop
- Do NOT skip dimensions or criteria — cover everything the calling command requires
- Do NOT reduce quality — manual analysis should match the same standard as an OpenCode-powered analysis
- If the fallback was triggered by a setup failure, note "OpenCode unavailable — manual analysis" in the report header
