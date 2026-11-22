#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)

if [ -n "${AGENT_ROOT:-}" ]; then
    CANDIDATES="$AGENT_ROOT"
else
    MAIN=$(git -C "$ROOT" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')
    CANDIDATES="$MAIN
$MAIN/../XNull-Lang
$ROOT/../XNull-Lang"
fi

AGENT_ROOT=""
SEARCHED=""
while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    SEARCHED="$SEARCHED
  $candidate"
    if [ -f "$candidate/.agent/bin/check_ui_scope.py" ]; then
        AGENT_ROOT=$candidate
        break
    fi
done <<CANDIDATES_EOF
$CANDIDATES
CANDIDATES_EOF

if [ -z "$AGENT_ROOT" ]; then
    echo "doc_gates: missing check_ui_scope.py; searched:$SEARCHED" >&2
    exit 1
fi

python3 "$ROOT/src/toolchain/check_doc_naming.py" "$ROOT/docs/design/t0"
python3 "$ROOT/src/toolchain/check_links.py"
python3 "$AGENT_ROOT/.agent/bin/check_ui_scope.py" "$ROOT/docs/design"
echo "doc_gates: PASS (agent root: $AGENT_ROOT)"
