#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)

if [ "${ANNOTATION_GATE_CHAIN:-1}" = "1" ]; then
    ANNOTATION_GATE_CHAIN=0 "$HERE/../codec_annotations/m3_gate.sh"
    ANNOTATION_GATE_CHAIN=0 "$HERE/../annotation_platform/m0_gate.sh"
fi
"$HERE/run.sh"

python3 - "$ROOT/docs/design/ANNOTATION-PLATFORM-PLAN.md" "$ROOT/docs/design/ANNOTATION-CATALOG.md" <<'PY'
import re, sys
from pathlib import Path
plan = Path(sys.argv[1]).read_text(encoding="utf-8")
catalog = Path(sys.argv[2]).read_text(encoding="utf-8")
for n in ("01", "02", "03", "04"):
    if not re.search(rf"^\| P4-{n} \|.*\|\s*implemented \(M4\.[123](?:/M4\.[123])?\)[^|]*\|", plan, flags=re.M):
        raise SystemExit(f"m4_gate: P4-{n} not implemented")
if not re.search(r"^\| M4 \|.*\|\s*implemented \(M4\.1/M4\.2/M4\.3\)[^|]*\|", plan, flags=re.M):
    raise SystemExit("m4_gate: M4 not implemented")
for name in ("Validate", "Min", "Max", "Pattern", "Email"):
    if not re.search(rf"^\| `@{name}` \|.*implemented \(M4\.[123](?:/M4\.[123])?\)[^|]*\|", catalog, flags=re.M):
        raise SystemExit(f"m4_gate: @{name} not implemented")
if not re.search(r"^\| `@Email` \|.*\|\s*implemented \(M4\.3\)[^|]*\|", catalog, flags=re.M):
    raise SystemExit("m4_gate: @Email not implemented")
PY
echo "m4_gate: PASS"
