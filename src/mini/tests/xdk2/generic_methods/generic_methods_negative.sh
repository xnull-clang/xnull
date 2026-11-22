#!/bin/sh
# Inference failure must not silently produce Any or a bogus specialization.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.neg.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/bad.x" <<'X'
class Box<T> {
    final T value
    Box(T v) { self.value = v }
    Box<R> map<R>(R(T) transform) { return new Box<R>(transform(self.value)) }
}
static Int main() {
    Box<Int> box = new Box<Int>(7)
    Box<Int> bad = box.map((String value) -> value)
    return 0
}
X
if "$XNULL" --bootstrap --engine=mini run "$TMP/bad.x" >"$TMP/out" 2>"$TMP/err"; then
    echo "generic_methods_negative: bad inference unexpectedly passed" >&2
    exit 1
fi
grep -q "SEM-" "$TMP/err" || { cat "$TMP/err" >&2; exit 1; }
echo "generic_methods_negative: PASS"
