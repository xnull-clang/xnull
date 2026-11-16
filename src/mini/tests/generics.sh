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

# 类型实参数量错误必须显式失败，不能静默产出未实例化调用。
cat >"$E.neg2.x" <<'X'
static T identity<T>(T value) {
    return value
}

static Int main() {
    return identity<Int, String>(1)
}
X
if "$ROOT/src/mini/bin/mini" --sema "$E.neg2.x" >"$E.neg2.out" 2>"$E.neg2.err"; then
    echo "generic arity negative unexpectedly passed" >&2
    exit 1
fi
grep -q 'SEM-' "$E.neg2.out" "$E.neg2.err" || { cat "$E.neg2.out" "$E.neg2.err" >&2; exit 1; }

# 嵌套泛型实参不匹配必须显式失败。
cat >"$E.neg3.x" <<'X'
class Box<T> {
    T value
    Box(T v) { self.value = v }
    T get() { return self.value }
}

class Pair<A, B> {
    A left
    B right
    Pair(A a, B b) {
        self.left = a
        self.right = b
    }
}

static Int main() {
    Box<Pair<Int, String>> b = new Box<Pair<String, Int>>(new Pair<String, Int>("x", 1))
    return 0
}
X
if "$ROOT/src/mini/bin/mini" --sema "$E.neg3.x" >"$E.neg3.out" 2>"$E.neg3.err"; then
    echo "nested generic negative unexpectedly passed" >&2
    exit 1
fi
grep -q 'SEM-' "$E.neg3.out" "$E.neg3.err" || { cat "$E.neg3.out" "$E.neg3.err" >&2; exit 1; }

# 未声明的类型实参必须失败。
cat >"$E.neg4.x" <<'X'
static T identity<T>(T value) {
    return value
}

static Int main() {
    return identity<Missing>(1)
}
X
if "$ROOT/src/mini/bin/mini" --sema "$E.neg4.x" >"$E.neg4.out" 2>"$E.neg4.err"; then
    echo "unknown generic type negative unexpectedly passed" >&2
    exit 1
fi
grep -q 'SEM-' "$E.neg4.out" "$E.neg4.err" || { cat "$E.neg4.out" "$E.neg4.err" >&2; exit 1; }

echo "mini generics: PASS"
