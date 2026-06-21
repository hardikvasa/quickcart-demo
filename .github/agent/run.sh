#!/bin/bash
# Orchestrates an AgentTier fix-sandbox for one GitHub issue.
# Runs on the self-hosted runner (itself an AgentTier sandbox, in-cluster).
#
# Talks to the Router REST API to: create a Claude Code sandbox, launch the
# fix in the background (fire-and-poll, because the exec API has a short read
# timeout), wait for completion, surface the PR, comment on the issue, and
# delete the sandbox.
#
# Required env:
#   ROUTER_URL     in-cluster Router base URL
#   REPO           owner/name
#   ISSUE_NUMBER   issue number
#   ISSUE_TITLE    issue title
#   ISSUE_BODY     issue body
#   GH_TOKEN       token with repo + issues write (push, open PR, comment)
set -uo pipefail

: "${ROUTER_URL:?}"; : "${REPO:?}"; : "${ISSUE_NUMBER:?}"; : "${GH_TOKEN:?}"
export ISSUE_TITLE="${ISSUE_TITLE:-}"
export ISSUE_BODY="${ISSUE_BODY:-}"
export BRANCH="agent/issue-${ISSUE_NUMBER}"
SBX="fix-issue-${ISSUE_NUMBER}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_FIX="${SCRIPT_DIR}/agent-fix.sh"
WORK="$(mktemp -d)"

api() { curl -s -m 30 "$@"; }
status() { api "$ROUTER_URL/api/v1/sandboxes/$SBX" | python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("status",""))
except Exception: print("")'; }

echo "::group::Create sandbox ${SBX}"
api -X POST "$ROUTER_URL/api/v1/sandboxes" -H 'Content-Type: application/json' \
  -d "{\"name\":\"${SBX}\",\"templateRef\":{\"name\":\"claude-code-bedrock\",\"kind\":\"ClusterSandboxTemplate\"}}"
echo
for i in $(seq 1 45); do
  st="$(status)"; echo "status=${st}"
  [ "$st" = "Running" ] && break
  sleep 4
done
echo "::endgroup::"
[ "$(status)" = "Running" ] || { echo "sandbox did not reach Running"; exit 1; }

# Build the launch payload (writes issue files + agent-fix.sh via base64, then
# backgrounds the fix with a completion sentinel).
python3 - "$AGENT_FIX" > "$WORK/launch.json" <<'PY'
import base64, json, os, sys
b64 = lambda s: base64.b64encode(s.encode()).decode()
script_b64 = base64.b64encode(open(sys.argv[1]).read().encode()).decode()
launch = (
    f"export GH_TOKEN='{os.environ['GH_TOKEN']}'; export REPO='{os.environ['REPO']}'; "
    f"export BRANCH='{os.environ['BRANCH']}'; export ISSUE_NUMBER='{os.environ['ISSUE_NUMBER']}'; "
    f"echo '{b64(os.environ.get('ISSUE_TITLE',''))}' | base64 -d > /workspace/issue_title.txt; "
    f"echo '{b64(os.environ.get('ISSUE_BODY',''))}' | base64 -d > /workspace/issue_body.txt; "
    f"echo '{script_b64}' | base64 -d > /workspace/agent-fix.sh; "
    f"rm -f /workspace/fix.done /workspace/fix.log; "
    f"setsid bash -c 'bash /workspace/agent-fix.sh > /workspace/fix.log 2>&1; "
    f"echo EXIT=$? > /workspace/fix.done' >/dev/null 2>&1 </dev/null & echo LAUNCHED"
)
json.dump({"command": launch, "timeout": 15}, sys.stdout)
PY

cat > "$WORK/poll.json" <<'EOF'
{"command":"if [ -f /workspace/fix.done ]; then echo DONE; cat /workspace/fix.done; echo ----LOG----; tail -c 4000 /workspace/fix.log; else echo RUNNING; fi","timeout":15}
EOF

echo "::group::Launch Claude Code fix"
api -X POST "$ROUTER_URL/api/v1/sandboxes/$SBX/exec" -H 'Content-Type: application/json' --data @"$WORK/launch.json"
echo

RESULT=""
for i in $(seq 1 30); do
  sleep 8
  out="$(api -X POST "$ROUTER_URL/api/v1/sandboxes/$SBX/exec" -H 'Content-Type: application/json' --data @"$WORK/poll.json")"
  if printf '%s' "$out" | grep -q '"stdout":"DONE'; then
    RESULT="$(printf '%s' "$out" | python3 -c 'import sys,json; print(json.load(sys.stdin)["stdout"])')"
    break
  fi
  echo "  ...agent still working (${i})"
done
echo "::endgroup::"

echo "=== agent-fix output ==="
printf '%s\n' "$RESULT"

PR_URL="$(printf '%s' "$RESULT" | grep -o 'PR_OPENED https://[^ ]*' | awk '{print $2}' | head -1)"

if [ -n "$PR_URL" ]; then
  echo "PR opened: $PR_URL"
  CBODY="$(python3 -c 'import json,sys; print(json.dumps({"body":"An AgentTier sandbox picked up this issue, ran Claude Code to fix it, and opened a pull request: "+sys.argv[1]}))' "$PR_URL")"
  api -X POST "https://api.github.com/repos/$REPO/issues/$ISSUE_NUMBER/comments" \
    -H "Authorization: token $GH_TOKEN" -H 'Accept: application/vnd.github+json' -d "$CBODY" >/dev/null \
    && echo "Commented PR link on issue #$ISSUE_NUMBER"
fi

echo "::group::Delete sandbox ${SBX}"
api -X DELETE "$ROUTER_URL/api/v1/sandboxes/$SBX" >/dev/null && echo "deleted ${SBX}"
echo "::endgroup::"

rm -rf "$WORK"
[ -n "$PR_URL" ] || { echo "ERROR: no PR was produced"; exit 1; }
