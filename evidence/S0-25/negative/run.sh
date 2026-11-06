#!/bin/sh
# S0-25 负向用例：非法名、断链、越界符号链接、目录符号链接、缺目录。
# 全部 fixture 建在临时目录，日志写回本目录；退出码约定：dev res 一律 2（用法/输入错误）。
set -u
here=$(cd "$(dirname "$0")" && pwd)
bin=${1:-"$here/../bin/xnull"}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/badname/sub" "$tmp/broken" "$tmp/escape" "$tmp/dirlink/sub"
printf x > "$tmp/badname/sub/bad name.txt"
printf x > "$tmp/broken/real.txt"
ln -s "$tmp/broken/gone.txt" "$tmp/broken/broken.txt"
printf s > "$tmp/secret.txt"
ln -s "$tmp/secret.txt" "$tmp/escape/escape.txt"
printf x > "$tmp/dirlink/sub/x.txt"
ln -s "$tmp/dirlink/sub" "$tmp/dirlink/dirlink"

for c in badname broken escape dirlink; do
    "$bin" dev res "$tmp/$c" "$tmp/$c.c" > "$here/$c.out" 2> "$here/$c.err"
    echo "$?" > "$here/$c.exit"
    printf '%-12s exit=%s stderr=%s\n' "$c" "$(cat "$here/$c.exit")" "$(cat "$here/$c.err")"
done

"$bin" dev res "$tmp/nonexistent" "$tmp/nonexistent.c" > "$here/nonexistent.out" 2> "$here/nonexistent.err"
echo "$?" > "$here/nonexistent.exit"
printf '%-12s exit=%s stderr=%s\n' nonexistent "$(cat "$here/nonexistent.exit")" "$(cat "$here/nonexistent.err")"
