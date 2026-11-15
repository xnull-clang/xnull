#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
O=$(mktemp)
E=$(mktemp)
trap 'rm -f "$O" "$E" "$E.expected"' EXIT
"$ROOT/src/cli/xnull" --bootstrap --engine=mini run "$HERE/generics.x" >"$O" 2>"$E"
printf '7\ngeneric\n9\nboxed\n11\nsecond\n21\nnested\n21\n' >"$E.expected"
diff -u "$E.expected" "$O" || { cat "$E" >&2; exit 1; }

# 函数类型参数暂不支持；必须给出诊断，不能静默通过。
N="$E.neg.x"
cat >"$N" <<'X'
static T apply<T>(T value, T(T) fn) {
    return fn(value)
}

static Int main() {
    return apply<Int>(1, 2)
}
X
if "$ROOT/src/mini/bin/mini" --sema "$N" >"$E.neg.out" 2>"$E.neg.err"; then
    echo "function type negative unexpectedly passed" >&2
    exit 1
fi
grep -q 'SEM-' "$E.neg.out" "$E.neg.err" || { cat "$E.neg.out" "$E.neg.err" >&2; exit 1; }

echo "mini generics: PASS"
