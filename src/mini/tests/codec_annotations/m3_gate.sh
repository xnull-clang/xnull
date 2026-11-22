#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)

"$HERE/../cli_annotations/m2_gate.sh"
"$HERE/../annotation_platform/m0_gate.sh"
"$HERE/run.sh"

python3 - "$ROOT/docs/design/ANNOTATION-PLATFORM-PLAN.md" "$ROOT/docs/design/ANNOTATION-CATALOG.md" <<'PY'
import re, sys
from pathlib import Path
plan = Path(sys.argv[1]).read_text(encoding="utf-8")
catalog = Path(sys.argv[2]).read_text(encoding="utf-8")
if not re.search(r"^\| M3 \|.*\|\s*implemented \(M3\.1/M3\.2\)[^|]*\|", plan, flags=re.M):
    raise SystemExit("m3_gate: M3 not implemented (M3.1/M3.2)")
if not re.search(r"^\| M3\.3 \|.*\|\s*planned[^|]*\|", plan, flags=re.M):
    raise SystemExit("m3_gate: M3.3 must stay planned")
if not re.search(r"^\| `@Serializable` \|.*implemented \(M3\.2\)[^|]*\|", catalog, flags=re.M):
    raise SystemExit("m3_gate: @Serializable not implemented (M3.2)")
if not re.search(r"^\| `@JsonName` \|.*implemented \(M3\.2\)[^|]*\|", catalog, flags=re.M):
    raise SystemExit("m3_gate: @JsonName not implemented (M3.2)")
if not re.search(r"^\| `@CsvName` \|.*\|\s*planned[^|]*\|", catalog, flags=re.M):
    raise SystemExit("m3_gate: @CsvName must stay planned")
PY
echo "m3_gate: PASS"
