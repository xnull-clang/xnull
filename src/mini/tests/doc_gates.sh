#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
AGENT_ROOT=${AGENT_ROOT:-$ROOT/../XNull-Lang}
python3 "$ROOT/src/toolchain/check_doc_naming.py" "$ROOT/docs/design/t0"
python3 "$ROOT/src/toolchain/check_links.py"
[ -f "$AGENT_ROOT/.agent/bin/check_ui_scope.py" ] || {
    echo "doc_gates: missing check_ui_scope.py under $AGENT_ROOT" >&2
    exit 1
}
python3 "$AGENT_ROOT/.agent/bin/check_ui_scope.py" "$ROOT/docs/design"
echo "doc_gates: PASS"
