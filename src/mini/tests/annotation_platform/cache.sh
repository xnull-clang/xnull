#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
PLATFORM="$ROOT/src/toolchain/annotation_platform.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
CACHE="$TMP/cache"
OUT="$TMP/out"
cp "$ROOT/src/toolchain/processors/toy_processor.py" "$TMP/processor.py"
cp "$HERE/source.x" "$TMP/entry.x"
python3 - "$TMP" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
manifest = {
    "manifestVersion": 1,
    "processors": [{
        "name": "toy",
        "phases": ["Generate"],
        "command": ["python3", str(root / "processor.py")],
        "outputs": ["toy_generated.x"],
        "timeoutSeconds": 30,
        "priority": 0,
    }],
}
(root / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
PY

run_generate() {
    python3 "$PLATFORM" generate --entry "$TMP/entry.x" --xdk-root "$ROOT/src/xdk" \
        --manifest "$TMP/manifest.json" --generated-dir "$OUT" \
        --cache-dir "$CACHE" "$@" >"$TMP/log" 2>&1
}

run_generate
grep -q 'cache: miss' "$TMP/log"
test -d "$OUT/.processors"
cp "$OUT/toy_generated.x" "$TMP/cold.x"

run_generate
grep -q 'cache: hit' "$TMP/log"
test ! -d "$OUT/.processors"
cmp "$TMP/cold.x" "$OUT/toy_generated.x"

printf '\nclass CacheSourceExtra { }\n' >>"$TMP/entry.x"
run_generate
grep -q 'cache: miss' "$TMP/log"
test -d "$OUT/.processors"

python3 - "$TMP/manifest.json" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
data = json.loads(p.read_text())
data["processors"][0]["timeoutSeconds"] = 31
p.write_text(json.dumps(data))
PY
run_generate
grep -q 'cache: miss' "$TMP/log"
test -d "$OUT/.processors"

printf '\n# processor content change\n' >>"$TMP/processor.py"
run_generate
grep -q 'cache: miss' "$TMP/log"
test -d "$OUT/.processors"

run_generate --force
grep -q 'cache: miss' "$TMP/log"
test -d "$OUT/.processors"

run_generate --no-cache
grep -q 'cache: miss' "$TMP/log"
cmp "$TMP/cold.x" "$OUT/toy_generated.x"

echo "annotation_cache: PASS"
