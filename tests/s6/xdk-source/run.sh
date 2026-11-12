#!/usr/bin/env bash
# XDK 源码层 E2E（B5 过渡）：text / sys / resources / net。
# 前置：bootstrap/bin/{xparser,xn-s4} 已构建（无 Go 亦可）。
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
export XNULL_XDK_SOURCE=1
pass=0; fail=0
run_case() {
  local name=$1; shift
  local out rc want
  out=$(cd "$ROOT" && bin/xnull --bootstrap run "$HERE/$name.x" 2>&1); rc=$?
  want=$(cat "$HERE/$name.expect")
  if [ $rc -eq 0 ] && [ "$out" = "$want" ]; then
    echo "PASS $name"; pass=$((pass+1))
  else
    echo "FAIL ${name}（rc=${rc}）"; diff <(printf '%s\n' "$want") <(printf '%s\n' "$out") | head -20
    fail=$((fail+1))
  fi
}

rm -f /tmp/xdk-src-file.txt /tmp/xdk-src-none.txt
run_case text
run_case sys_file

export XNULL_RESOURCES="$HERE/resources"
run_case resources
unset XNULL_RESOURCES

(cd "$HERE" && python3 -m http.server 18081 >/dev/null 2>&1) &
srv=$!
sleep 1
run_case net_http
kill $srv 2>/dev/null

echo "XDK 源码层：PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
