#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export ANNOTATION_GATE_CHAIN=0

cat >"$TMP/gates" <<GATES
m0 $HERE/m0_gate.sh
m2 $HERE/../cli_annotations/m2_gate.sh
m3 $HERE/../codec_annotations/m3_gate.sh
m4 $HERE/../validate_annotations/m4_gate.sh
m5 $HERE/../http_annotations/m5_gate.sh
m6 $HERE/../sql_annotations/m6_gate.sh
m6_5 $HERE/../db_annotations/m6_5_gate.sh
m8_2 $HERE/../resilience_annotations/m8_2_gate.sh
m8_4 $HERE/../cache_annotations/m8_4_gate.sh
m10_2 $HERE/../audit_annotations/m10_2_gate.sh
GATES
: >"$TMP/pids"
while read -r name gate; do
    "$gate" >"$TMP/$name.log" 2>&1 &
    echo "$! $name" >>"$TMP/pids"
done <"$TMP/gates"

failed=0
while read -r pid name; do
    if ! wait "$pid"; then
        failed=1
    fi
done <"$TMP/pids"
while read -r name gate; do
    cat "$TMP/$name.log"
done <"$TMP/gates"
[ "$failed" -eq 0 ] || { echo "m7_gate: milestone gate failed" >&2; exit 1; }

"$HERE/m7_registry_gate.sh"
"$HERE/cache.sh"
python3 "$ROOT/src/toolchain/check_annotation_surface.py"

python3 - "$ROOT" <<'PY'
import re, sys
from pathlib import Path
root = Path(sys.argv[1])
plan = (root / "docs/design/ANNOTATION-PLATFORM-PLAN.md").read_text(encoding="utf-8")
catalog = (root / "docs/design/ANNOTATION-CATALOG.md").read_text(encoding="utf-8")
for milestone in range(0, 8):
    if not re.search(rf"^\| M{milestone} \|.*\|\s*implemented[^|]*\|", plan, flags=re.M):
        raise SystemExit(f"m7_gate: M{milestone} is not implemented")
if not re.search(r"^\| M3\.3 \|.*\|\s*implemented[^|]*\|", plan, flags=re.M):
    raise SystemExit("m7_gate: M3.3 must be implemented")
if not re.search(r"^\| M5\.3 \|.*\|\s*planned[^|]*\|", plan, flags=re.M):
    raise SystemExit("m7_gate: M5.3 must stay planned")

decls = {}
for path in sorted((root / "src/xdk").rglob("*.x")):
    text = path.read_text(encoding="utf-8")
    for match in re.finditer(r"@annotation\s+([A-Za-z_][A-Za-z0-9_]*)\s*\{", text):
        decls[match.group(1)] = path
rows = {}
for line in catalog.splitlines():
    match = re.match(r"^\|\s*`@([A-Za-z_][A-Za-z0-9_]*)`\s*\|", line)
    if match:
        rows[match.group(1)] = line
for name in sorted(decls):
    if name not in rows:
        raise SystemExit(f"m7_gate: @{name} missing from catalog")
    if "implemented" not in rows[name]:
        raise SystemExit(f"m7_gate: declared @{name} is not implemented")

packages = [
    ("xdk.cli", "cli_processor.py", "cli_annotations/m2_gate.sh", "cli_annotations/generated/CliGenerated.x"),
    ("xdk.codec", "codec_processor.py", "codec_annotations/m3_gate.sh", "codec_annotations/generated/CodecGenerated.x"),
    ("xdk.codec", "csv_processor.py", "csv_annotations/m3_3_gate.sh", "csv_annotations/generated/CsvGenerated.x"),
    ("xdk.validate", "validate_processor.py", "validate_annotations/m4_gate.sh", "validate_annotations/generated/ValidateGenerated.x"),
    ("xdk.net.http", "http_processor.py", "http_annotations/m5_gate.sh", "http_annotations/generated/HttpGenerated.x"),
    ("xdk.sql", "sql_processor.py", "sql_annotations/m6_gate.sh", "sql_annotations/generated/SqlGenerated.x"),
    ("xdk.db", "db_processor.py", "db_annotations/m6_5_gate.sh", "db_annotations/generated/DbGenerated.x"),
    ("xdk.resilience", "resilience_processor.py", "resilience_annotations/m8_2_gate.sh", "resilience_annotations/generated/ResilienceGenerated.x"),
    ("xdk.cache", "cache_processor.py", "cache_annotations/m8_4_gate.sh", "cache_annotations/generated/CacheGenerated.x"),
    ("xdk.audit", "audit_processor.py", "audit_annotations/m10_2_gate.sh", "audit_annotations/generated/AuditGenerated.x"),
]
tests = root / "src/mini/tests"
for package, processor, gate, generated in packages:
    for relative, kind in ((Path("src/toolchain/processors") / processor, "processor"),
                           (tests / gate, "m_gate"),
                           (tests / generated, "generated test")):
        if not relative.is_file():
            raise SystemExit(f"m7_gate: {package} missing {kind}: {relative}")
print("m7_gate: milestones/catalog/shells PASS")
PY

echo "m7_gate: PASS"
