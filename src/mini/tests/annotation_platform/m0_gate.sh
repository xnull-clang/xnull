#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
PLATFORM_RUN="$ROOT/src/mini/tests/annotation_platform/run.sh"
LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT

run_gate() {
    name="$1"
    script="$2"
    echo "m0_gate: running $name"
    if ! "$script" >>"$LOG" 2>&1; then
        echo "m0_gate: FAIL $name" >&2
        tail -40 "$LOG" >&2
        exit 1
    fi
}

run_gate annotation_ir "$ROOT/src/mini/tests/annotation_ir/run.sh"
run_gate annotation_platform "$PLATFORM_RUN"
run_gate a8_core "$ROOT/src/mini/tests/a8/a8_core.sh"
run_gate a8_delegate "$ROOT/src/mini/tests/a8/a8_delegate.sh"
run_gate a8_builder "$ROOT/src/mini/tests/a8/a8_builder.sh"

grep -q '^annotation_platform: PASS$' "$LOG" || {
    echo "m0_gate: missing annotation_platform PASS marker" >&2
    tail -20 "$LOG" >&2
    exit 1
}
BACKEND=$(grep -o 'annotation_platform: sandboxBackend=[a-z-]*' "$LOG" | tail -1 | sed 's/.*=//')
if [ "$(uname -s)" = "Darwin" ]; then
    [ "$BACKEND" = "darwin-sandbox-exec" ] || {
        echo "m0_gate: expected darwin-sandbox-exec, got $BACKEND" >&2
        exit 1
    }
else
    [ "$BACKEND" = "limits-only" ] || {
        echo "m0_gate: expected limits-only, got $BACKEND" >&2
        exit 1
    }
fi

python3 - "$ROOT/docs/design/ANNOTATION-PLATFORM-PLAN.md" <<'PY'
import re
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
problems = []
for n in range(1, 10):
    pattern = rf"^\| P0-0{n} \|.*\|\s*implemented[^|]*\|"
    if not re.search(pattern, text, flags=re.M):
        problems.append(f"P0-0{n} is not implemented")
m0 = re.search(r"^\| M0 \|.*\|\s*implemented[^|]*\|", text, flags=re.M)
if not m0:
    problems.append("M0 milestone is not implemented")
for n in (5, 6):
    if re.search(rf"^\| P0-0{n} \|.*\|\s*planned\s*\|", text, flags=re.M):
        problems.append(f"P0-0{n} still says planned")
if problems:
    for item in problems:
        print(f"m0_gate: {item}", file=sys.stderr)
    sys.exit(1)
PY

echo "m0_gate: PASS (backend=$BACKEND)"
