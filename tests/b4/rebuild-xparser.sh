#!/usr/bin/env bash
# 用现有 bootstrap 工具从 impl/lib/b2/xparser.x 重建 xparser（B4c 自举链）。
# 用法：tests/b4/rebuild-xparser.sh <out-binary> [out-c]
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
OUT=${1:-/tmp/xparser-rebuilt}
OUTC=${2:-/tmp/xparser-rebuilt.c}
XP="${XPARSER:-$ROOT/bootstrap/bin/xparser}"
XN="$ROOT/bootstrap/bin/xn-s4"
RT="$ROOT/impl/runtime"
W=$(mktemp -d "${TMPDIR:-/tmp}/xprebuild.XXXXXX")
trap 'rm -rf "$W"' EXIT

"$XP" --file "$ROOT/impl/lib/b2/xparser.x" > "$W/a.ast"
python3 "$ROOT/tests/b4/native-bundle.py" "$ROOT" "$XP" impl/lib/b2/xparser.x > "$W/b.json"
python3 - "$ROOT" > "$W/p.txt" <<'PY'
import os, subprocess, sys
root = sys.argv[1]
os.chdir(root)
rel = "impl/lib/b2/xparser.x"
src = open(rel, encoding="utf-8").read()
for line in src.splitlines():
    if line.startswith("import xdk."):
        mod = line[len("import xdk."):].split()[0].rstrip(";")
        p = os.path.join("impl/lib/xdk", mod + ".x")
        if os.path.exists(p):
            src += open(p, encoding="utf-8").read()
allp = subprocess.run([sys.executable, "tests/b3/xfb-projection.py", "bindings"], capture_output=True, check=True).stdout.decode()
print("\n".join(l for l in allp.splitlines() if l.startswith("E|") and (l.split("|")[2] + "(") in src))
PY
"$XN" impl/lib/b2/xparser.x --ast-file "$W/a.ast" --project "$(cat "$W/p.txt")" --bundle-file "$W/b.json" > "$OUTC"
cc -std=c11 -O2 -w -pthread -I "$RT" -o "$OUT" "$OUTC" \
  "$RT"/rt.c "$RT"/rt_gc.c "$RT"/rt_policy.c "$RT"/rt_weak.c "$RT"/xrt_abi.c \
  "$RT"/rt_std_runtime.c "$RT"/rt_std_text.c "$RT"/rt_std_sys.c "$RT"/rt_std_bytes.c "$RT"/rt_std_net.c \
  "$RT"/rt_task.c "$RT"/rt_sync.c "$RT"/rt_std_res.c "$RT"/rt_std_res_empty.c "$ROOT/bootstrap/bin/res.c"
echo "rebuilt: $OUT ($(wc -c < "$OUTC") bytes C)"
