#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
O=$(mktemp)
E=$(mktemp)
trap 'rm -f "$O" "$E" "$E.expected"' EXIT
"$ROOT/src/cli/xnull" --bootstrap --engine=mini run "$HERE/features.x" >"$O" 2>"$E"
printf 'x=1.5 bits=243\nnone\n3\nsw-two\nsw-utf8\nswitch-break\ndo 0\ndo 1\nrange 0\nrange 1\nclosed 1\nclosed 2\ninherit 5\nlambda 5\nlambda-block 6\nlambda0 42\nlambda-capture 15\nlambda-capture-value 15\nlambda-rec 120\nlambda-nested 6\nlambda-object 5\nlambda-method 17\nlambda-direct 8\nprotocol hello\nprotocol bye\ndataenum 0 ready\ndataenum-ready\ndataenum-switch\nenum-blue\ngoto 2\n[AbC]\na-b-\nABC\nabc\néA\néa\neA\ntrue\nabc\ntrue\nfalse\nb\n1\n' >"$E.expected"
diff -u "$E.expected" "$O" || { cat "$E" >&2; exit 1; }
"$ROOT/src/mini/bin/mini" --sema "$HERE/throw.x" >/dev/null
cat >"$E.bad-enum.x" <<'X'
enum Color { Red, Blue }
static Int main() {
    Color c = Color.Blue
    switch c {
        case Color.Red:
            print("red")
    }
    return 0
}
X
if "$ROOT/src/mini/bin/mini" --sema "$E.bad-enum.x" >"$E.bad-enum.out" 2>"$E.bad-enum.err"; then
    echo "non-exhaustive enum switch unexpectedly passed" >&2
    exit 1
fi
grep -q 'non-exhaustive enum switch' "$E.bad-enum.out" "$E.bad-enum.err" || {
    cat "$E.bad-enum.out" "$E.bad-enum.err" >&2
    exit 1
}

echo "mini c4: PASS"
