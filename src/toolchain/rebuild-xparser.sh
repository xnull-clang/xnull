#!/usr/bin/env bash
# 用现有 bootstrap 工具从 src/compiler/parser/Parser.x 重建 xparser（冻结基线 自举链）。
# 用法：src/toolchain/rebuild-xparser.sh <out-binary> [out-c]
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
OUT=${1:-/tmp/xparser-rebuilt}
OUTC=${2:-/tmp/xparser-rebuilt.c}
XP="${XPARSER:-$ROOT/src/bootstrap/bin/xparser}"
XN="$ROOT/src/bootstrap/bin/xn-s4"
RT="$ROOT/src/runtime"
W=$(mktemp -d "${TMPDIR:-/tmp}/xprebuild.XXXXXX")
trap 'rm -rf "$W"' EXIT

python3 "$ROOT/src/toolchain/native-bundle.py" "$ROOT" "$XP" src/compiler/parser/Parser.x > "$W/b.json"
python3 - "$W/b.json" "$W/a.ast" <<'PY'
import json, sys
bundle = json.load(open(sys.argv[1], encoding="utf-8"))
open(sys.argv[2], "w", encoding="utf-8").write(bundle["files"][-1]["ast"])
PY
python3 "$ROOT/src/toolchain/proj-b.py" "$ROOT" src/compiler/parser/Parser.x > "$W/p.txt"
"$XN" src/compiler/parser/Parser.x --ast-file "$W/a.ast" --project "$(cat "$W/p.txt")" --bundle-file "$W/b.json" > "$OUTC"
cc -std=c11 -O2 -w -pthread -I "$RT" -o "$OUT" "$OUTC" \
  "$RT"/rt.c "$RT"/rt_gc.c "$RT"/rt_policy.c "$RT"/rt_weak.c "$RT"/xrt_abi.c \
  "$RT"/rt_std_runtime.c "$RT"/rt_std_text.c "$RT"/rt_std_sys.c "$RT"/rt_std_bytes.c "$RT"/rt_std_net.c \
  "$RT"/rt_task.c "$RT"/rt_sync.c "$RT"/rt_std_res.c "$RT"/rt_std_res_empty.c "$ROOT/src/bootstrap/bin/res.c"
echo "rebuilt: $OUT ($(wc -c < "$OUTC") bytes C)"
