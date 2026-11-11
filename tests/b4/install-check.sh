#!/usr/bin/env bash
# B4b-04b-1 自检：install 的仓库布局、清单一致性、产物可运行。
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${XNULL_ROOT:-$(cd "$HERE/../.." && pwd)}
S="$HERE/xnull-build.sh"
P="$HERE/fixtures/proj02"
REPO=${XNULL_INSTALL_REPO:-/tmp/b4-install-check}
pass=0 fail=0
ok()  { echo "PASS $1"; pass=$((pass+1)); }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

rm -rf "$REPO"
if "$S" install "$P" --repo "$REPO" > /tmp/install-check.log 2>&1; then
  ok "install 执行成功"
else
  bad "install 执行失败"; tail -5 /tmp/install-check.log
fi

for f in \
  io/xnull/lib-core/1.0.0/lib-core-1.0.0.xlib \
  io/xnull/lib-codec/1.0.0/lib-codec-1.0.0.xlib \
  io/xnull/lib-util/1.0.0/lib-util-1.0.0.xlib \
  io/xnull/proj02/1.0.0/reactor-summary.txt ; do
  if [ -s "$REPO/$f" ]; then ok "仓库存在 $f"; else bad "缺少 $f"; fi
done

for m in lib-core lib-codec lib-util; do
  if cmp -s "$P/$m/xnull.project" "$REPO/io/xnull/$m/1.0.0/xnull.project"; then
    ok "$m/xnull.project 与源一致"
  else
    bad "$m/xnull.project 不一致"
  fi
done

got=$("$HERE/xnull-build.sh" run-project "$P" 2>/dev/null)
want=$(cat "$HERE/fixtures/proj02/expected.app.out")
if [ "$got" = "$want" ]; then
  ok "安装的 app 运行输出与 golden 一致"
else
  bad "安装的 app 输出不一致"
  diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") | head -6
fi

echo "B4b-04b-1 install 自检：PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
