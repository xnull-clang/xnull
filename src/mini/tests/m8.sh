#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
D=$(mktemp -d)
cleanup() { rm -rf "$D" "$HERE/modules/target"; }
trap cleanup EXIT

# 1. file build/run JSON
"$XNULL" --bootstrap --engine=mini build --json "$HERE/project/src/main/x/main.x" >"$D/build.json"
python3 -m json.tool "$D/build.json" >/dev/null
python3 - "$D/build.json" <<'PY'
import json, sys
r=json.load(open(sys.argv[1]))
assert r["ok"] is True and r["exitCode"] == 0 and r["diagnostics"] == []
PY
"$XNULL" --bootstrap --engine=mini run --json "$HERE/project" >"$D/run.json"
python3 - "$D/run.json" <<'PY'
import json, sys
r=json.load(open(sys.argv[1]))
assert r["ok"] is True and r["output"].strip() == "project ok"
PY

# 2. failure diagnostics
printf 'static Int main() { return missing }\n' >"$D/bad.x"
set +e
"$XNULL" --bootstrap --engine=mini build --json "$D/bad.x" >"$D/bad.json" 2>"$D/bad.err"
rc=$?
set -e
[ "$rc" -eq 1 ] || { echo "expected exit 1, got $rc" >&2; exit 1; }
python3 - "$D/bad.json" <<'PY'
import json, sys
r=json.load(open(sys.argv[1]))
assert r["ok"] is False and r["exitCode"] == 1
assert any(d["code"] == "SEM-001" for d in r["diagnostics"])
PY

# 3. exit-code matrix
printf 'static Int main() { return 7 }\n' >"$D/exit7.x"
set +e
"$XNULL" --bootstrap --engine=mini run --json "$D/exit7.x" >"$D/exit7.json" 2>"$D/exit7.err"
rc=$?
set -e
[ "$rc" -eq 7 ] || { echo "expected program exit 7, got $rc" >&2; exit 1; }
python3 - "$D/exit7.json" <<'PYCHECK'
import json, sys
r=json.load(open(sys.argv[1]))
assert r["ok"] is False and r["exitCode"] == 7
PYCHECK
set +e
"$XNULL" --bootstrap --engine=mini build --json "$D/missing.x" >"$D/missing.json" 2>"$D/missing.err"
rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "expected usage exit 2, got $rc" >&2; exit 1; }
python3 - "$D/missing.json" <<'PYCHECK'
import json, sys
r=json.load(open(sys.argv[1]))
assert r["ok"] is False and r["exitCode"] == 2
PYCHECK

# 4. modules/dependencies/topology + lock/install/repro
"$XNULL" --bootstrap --engine=legacy validate "$HERE/modules" >"$D/validate.txt"
grep -q 'validate: OK' "$D/validate.txt"
[ "$(grep -c '^module' "$D/validate.txt")" -eq 2 ]
"$XNULL" --bootstrap --engine=legacy lock --check "$HERE/modules" >"$D/lock.txt"
grep -q 'lock: OK' "$D/lock.txt"
"$XNULL" --bootstrap --engine=legacy build --json "$HERE/modules" -o "$D/out" >"$D/mbuild.json"
"$XNULL" --bootstrap --engine=legacy run --json "$HERE/modules" >"$D/mrun.json"
python3 - "$D/mbuild.json" "$D/mrun.json" <<'PY'
import json, sys
b=json.load(open(sys.argv[1])); r=json.load(open(sys.argv[2]))
assert b["ok"] and b["output"].endswith("/app")
assert r["ok"] and r["output"].strip() == "modules ok"
PY
XNULL_REPO="$D/repo" "$XNULL" --bootstrap --engine=legacy install "$HERE/modules" >"$D/install.txt"
grep -q '\.xlib$' "$D/install.txt"
"$XNULL" --bootstrap --engine=legacy repro "$HERE/modules" >"$D/repro.txt"
grep -q 'repro: same=' "$D/repro.txt"
grep -q 'diff=0' "$D/repro.txt"

echo "mini m8: PASS"
