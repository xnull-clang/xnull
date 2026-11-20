#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
D=$(mktemp -d)
cleanup() { rm -rf "$D"; }
trap cleanup EXIT

sha() { shasum -a 256 "$1" | awk '{print $1}'; }

# 0. 默认 CLI：不显式传 --bootstrap 也必须可用。
env -u XNULL_BOOTSTRAP -u XNULL_ENGINE \
  XNULL_OUT="$D/default-out" "$XNULL" run "$HERE/project/src/main/x/main.x" \
  >"$D/default-run.txt" 2>"$D/default-run.err"
grep -qx 'project ok' "$D/default-run.txt"

# 1. file build/run JSON
"$XNULL" --bootstrap --engine=mini build --json "$HERE/project/src/main/x/main.x" >"$D/build.json"
python3 -m json.tool "$D/build.json" >/dev/null
python3 - "$D/build.json" <<'PY'
import json, sys
r=json.load(open(sys.argv[1]))
assert r["ok"] is True and r["exitCode"] == 0 and r["diagnostics"] == []
PY
"$XNULL" --bootstrap --engine=mini run --json "$HERE/project/src/main/x/main.x" >"$D/run.json"
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
[ "$rc" -eq 1 ] || { echo "expected exit 1, got $rc" >&2; cat "$D/bad.err" >&2; exit 1; }
python3 - "$D/bad.json" <<'PY'
import json, sys
r=json.load(open(sys.argv[1]))
assert r["ok"] is False and r["exitCode"] == 1
assert any(d["code"] == "SEM-001" for d in r["diagnostics"])
PY
grep -q 'SEM-001' "$D/bad.err"

# 3. exit-code matrix
printf 'static Int main() { return 7 }\n' >"$D/exit7.x"
set +e
"$XNULL" --bootstrap --engine=mini run --json "$D/exit7.x" >"$D/exit7.json" 2>"$D/exit7.err"
rc=$?
set -e
[ "$rc" -eq 7 ] || { echo "expected program exit 7, got $rc" >&2; cat "$D/exit7.err" >&2; exit 1; }
python3 - "$D/exit7.json" <<'PYCHECK'
import json, sys
r=json.load(open(sys.argv[1]))
assert r["ok"] is False and r["exitCode"] == 7
PYCHECK
# 3b. Fatal program maps to 134; JSON remains the only stdout payload.
cat >"$D/fatal.x" <<'X'
static Int main() {
    throw "fatal probe"
}
X
set +e
"$XNULL" --bootstrap --engine=mini run --json "$D/fatal.x" >"$D/fatal.json" 2>"$D/fatal.err"
rc=$?
set -e
[ "$rc" -eq 134 ] || { echo "expected fatal exit 134, got $rc" >&2; cat "$D/fatal.err" >&2; exit 1; }
python3 - "$D/fatal.json" <<'PY'
import json, sys
r=json.load(open(sys.argv[1]))
assert r["ok"] is False and r["exitCode"] == 134
PY
grep -q 'runtime fatal' "$D/fatal.json"

# 3c. SIGINT maps to 130.
cat >"$D/loop.x" <<'X'
static Int main() {
    while true {
    }
    return 0
}
X
python3 - "$XNULL" "$D/loop.x" <<'PY'
import os, signal, subprocess, sys, time
xnull, script = sys.argv[1:3]
p = subprocess.Popen([xnull, "--bootstrap", "--engine=mini", "run", script],
                     stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                     start_new_session=True, text=True)
time.sleep(1.0)
os.killpg(p.pid, signal.SIGINT)
out, err = p.communicate(timeout=10)
if p.returncode != 130:
    sys.stderr.write("expected SIGINT exit 130, got %s\n%s\n" % (p.returncode, err))
    sys.exit(1)
PY

# 4. modules/dependencies/topology + lock/install/repro

echo "mini m8: PASS"
