#!/usr/bin/env bash
# B3-08b：AST bundle 依赖后序 + 覆盖 import 闭包；AST 与 Go oracle 逐字节一致。
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${XNULL_ROOT:-$(cd "$HERE/../.." && pwd)}
BIN=${XNULL_BIN:-}
[ -n "$BIN" ] || BIN=$(command -v xnull || true)
if [ -z "$BIN" ]; then ( cd "$ROOT/impl" && go build -o /tmp/xnull-b3 ./cmd/xnull ) || exit 1; BIN=/tmp/xnull-b3; fi
( cd "$ROOT/impl" && go build -o /tmp/xnast-b3 ./cmd/xnast ) || exit 1
TMP=$(mktemp -d "${TMPDIR:-/tmp}/b3-bundle.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
pass=0 fail=0
check() {
  local entry=$1; shift
  "$BIN" --emit-ast-bundle "$entry" > "$TMP/b.json" 2>"$TMP/e.log" || { echo "FAIL bundle $entry"; cat "$TMP/e.log"; fail=$((fail+1)); return; }
  python3 - "$TMP/b.json" /tmp/xnast-b3 "$@" <<'PY'
import json,sys,subprocess
d=json.load(open(sys.argv[1])); orc=sys.argv[2]; want=sys.argv[3:]
names=[f["path"] for f in d["files"]]
if d.get("version")!="xnast-bundle v1": sys.exit("version 不符")
for f in d["files"]:
    out=subprocess.run([orc,"--ast",f["path"]],capture_output=True,text=True).stdout.strip()
    if out!=f["ast"].strip(): sys.exit("AST 与 Go oracle 不同："+f["path"])
for w in want:
    if not any(n.endswith(w) for n in names): sys.exit("缺少 "+w)
if not names[-1].endswith(want[-1]): sys.exit("入口不在最后")
PY
  if [ $? -eq 0 ]; then echo "PASS bundle $entry"; pass=$((pass+1)); else echo "FAIL bundle $entry"; fail=$((fail+1)); fi
}
check "$ROOT/tests/b2/corpus/examples/multi/main.x" shapes.x text.x main.x
check "$ROOT/tests/b3/fixtures/bundle/app.x" \
  impl/lib/xdk/text.x impl/lib/xdk/sync.x impl/lib/xdk/tasks.x impl/lib/xdk/collections.x app.x
echo "ast-bundle 汇总：PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
