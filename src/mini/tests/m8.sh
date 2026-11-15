#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
D=$(mktemp -d)
cleanup() { rm -rf "$D" "$HERE/modules/target"; }
trap cleanup EXIT

# 自举工具放在测试私有目录：避免 /tmp 里旧的 xpd/reactor/tools 掩盖冷启动失败。
export XNULL_MODEL_DIR="$D/bootstrap"
export XNULL_TOOL_DIR="$D/bootstrap"
export XPD_BIN="$XNULL_MODEL_DIR/xpd"
export XMANIFEST_BIN="$XNULL_MODEL_DIR/xmanifest"
export REACTOR_BIN="$XNULL_MODEL_DIR/reactor"

sha() { shasum -a 256 "$1" | awk '{print $1}'; }

# 0. 默认 CLI：不显式传 --bootstrap 也必须可用。
env -u XNULL_BOOTSTRAP -u XNULLC_BIN -u XPARSER_BIN \
  XNULL_OUT="$D/default-out" "$XNULL" --engine=legacy run "$HERE/project" \
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
set +e
"$XNULL" --bootstrap --engine=mini build --json "$D/missing.x" >"$D/missing.json" 2>"$D/missing.err"
rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "expected usage exit 2, got $rc" >&2; cat "$D/missing.err" >&2; exit 1; }
python3 - "$D/missing.json" <<'PYCHECK'
import json, sys
r=json.load(open(sys.argv[1]))
assert r["ok"] is False and r["exitCode"] == 2
PYCHECK

# 3a. CLI usage errors in --json mode: stdout is JSON, stderr keeps the diagnostic.
set +e
"$XNULL" --bootstrap --engine=mini build --json >"$D/usage.json" 2>"$D/usage.err"
rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "expected CLI usage exit 2, got $rc" >&2; cat "$D/usage.err" >&2; exit 1; }
python3 - "$D/usage.json" <<'PY'
import json, sys
r=json.load(open(sys.argv[1]))
assert r["ok"] is False and r["exitCode"] == 2
assert any(d["code"] == "CLI-002" for d in r["diagnostics"])
PY
grep -q 'CLI-002' "$D/usage.err"

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
grep -q 'runtime fatal' "$D/fatal.err"

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
"$XNULL" --bootstrap --engine=legacy validate "$HERE/modules" >"$D/validate.txt"
grep -q 'validate: OK' "$D/validate.txt"
[ "$(grep -c '^module' "$D/validate.txt")" -eq 2 ]
"$XNULL" --bootstrap --engine=legacy tree "$HERE/modules" >"$D/tree.txt"
grep -q 'demo:root' "$D/tree.txt"
"$XNULL" --bootstrap --engine=legacy xmeta "$HERE/modules" >"$D/xmeta.txt"
grep -q 'xmeta' "$D/xmeta.txt"
"$XNULL" --bootstrap --engine=legacy lock --check "$HERE/modules" >"$D/lock.txt"
grep -q 'lock: OK' "$D/lock.txt"

# 4a. workspace lock entries must be stable and contain the deterministic xlib digest.
grep -q 'entry demo:common 1.0.0' "$HERE/modules/xnull.lock"
grep -q 'repository = workspace' "$HERE/modules/xnull.lock"
grep -Eq 'sha256     = [0-9a-f]{64}' "$HERE/modules/xnull.lock"

# 4b. external dependency: LOCK-002, no lock file.
cp -R "$HERE/external" "$D/external"
set +e
"$XNULL" --bootstrap --engine=legacy lock "$D/external" >"$D/ext.out" 2>"$D/ext.err"
rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "external lock expected 2, got $rc" >&2; cat "$D/ext.err" >&2; exit 1; }
grep -q 'XPD-401' "$D/ext.err"
[ ! -e "$D/external/xnull.lock" ] || { echo "external lock must not be written" >&2; exit 1; }

# 4c. missing dependency version must fail without writing a lock.
cp -R "$HERE/modules" "$D/missing-version"
python3 - "$D/missing-version/app/xnull.project" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s, n = re.subn(r'(dependency demo:common\s*\{)\s*version\s*=\s*[0-9.]+\s*', r'\1\n      ', s, count=1)
assert n == 1
open(p, "w", encoding="utf-8").write(s)
PY
rm -f "$D/missing-version/xnull.lock"
set +e
"$XNULL" --bootstrap --engine=legacy lock "$D/missing-version" >"$D/mv.out" 2>"$D/mv.err"
rc=$?
set -e
[ "$rc" -ne 0 ] || { echo "missing version expected failure" >&2; exit 1; }
[ ! -e "$D/missing-version/xnull.lock" ] || { echo "missing-version lock must not be written" >&2; exit 1; }

# 4d. missing coordinate must fail.
mkdir -p "$D/missing-coord"
cat >"$D/missing-coord/xnull.project" <<'EOF'
project {
  groupId = demo
  artifactId = missing-coord
  version = 1.0.0
  packaging = app
  dependencies {
    dependency {
      version = 1.0.0
    }
  }
}
EOF
set +e
"$XNULL" --bootstrap --engine=legacy lock "$D/missing-coord" >"$D/mc.out" 2>"$D/mc.err"
rc=$?
set -e
[ "$rc" -ne 0 ] || { echo "missing coordinate expected failure" >&2; exit 1; }
[ ! -e "$D/missing-coord/xnull.lock" ] || { echo "missing-coordinate lock must not be written" >&2; exit 1; }

# 4e. lock mismatch must fail with --check and not mutate the lock.
cp -R "$HERE/modules" "$D/lock-mismatch"
printf '\n' >>"$D/lock-mismatch/xnull.lock"
before=$(sha "$D/lock-mismatch/xnull.lock")
set +e
"$XNULL" --bootstrap --engine=legacy lock --check "$D/lock-mismatch" >"$D/lm.out" 2>"$D/lm.err"
rc=$?
set -e
[ "$rc" -eq 1 ] || { echo "lock mismatch expected 1, got $rc" >&2; cat "$D/lm.err" >&2; exit 1; }
[ "$(sha "$D/lock-mismatch/xnull.lock")" = "$before" ] || { echo "lock --check mutated the lock" >&2; exit 1; }
grep -q 'XPD-402' "$D/lm.err"

# 4f. install is deterministic and agrees with the lock digest.
XNULL_OUT="$D/install-a" XNULL_REPO="$D/repo-a" \
  "$XNULL" --bootstrap --engine=legacy install "$HERE/modules" >"$D/install-a.txt"
XNULL_OUT="$D/install-b" XNULL_REPO="$D/repo-b" \
  "$XNULL" --bootstrap --engine=legacy install "$HERE/modules" >"$D/install-b.txt"
xlib_a=$(find "$D/repo-a" -type f -name '*.xlib' -print -quit)
xlib_b=$(find "$D/repo-b" -type f -name '*.xlib' -print -quit)
[ -n "$xlib_a" ] && [ -n "$xlib_b" ] || { echo "install did not produce .xlib" >&2; exit 1; }
[ "$(sha "$xlib_a")" = "$(sha "$xlib_b")" ] || { echo "install .xlib is not deterministic" >&2; exit 1; }
lock_sha=$(awk '/sha256/{print $3; exit}' "$HERE/modules/xnull.lock")
[ "$(sha "$xlib_a")" = "$lock_sha" ] || { echo "lock digest does not match installed .xlib" >&2; exit 1; }

# 4g. repro twice, isolated output.
XNULL_OUT="$D/repro" "$XNULL" --bootstrap --engine=legacy repro "$HERE/modules" >"$D/repro.txt"
grep -q 'repro: same=' "$D/repro.txt"
grep -q 'diff=0' "$D/repro.txt"

echo "mini m8: PASS"
