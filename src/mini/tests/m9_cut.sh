#!/bin/sh
# M9-CUT gate: default commands use mini, while legacy remains selectable.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

default_engine=$(env -u XNULL_ENGINE "$XNULL" --bootstrap version | awk '/^engine:/{print $2}')
[ "$default_engine" = "mini" ] || {
    echo "m9-cut: default engine is $default_engine, expected mini" >&2
    exit 1
}

legacy_engine=$("$XNULL" --bootstrap --engine=legacy version | awk '/^engine:/{print $2}')
[ "$legacy_engine" = "legacy" ] || {
    echo "m9-cut: explicit legacy engine is $legacy_engine" >&2
    exit 1
}

env_legacy=$(XNULL_ENGINE=legacy "$XNULL" --bootstrap version | awk '/^engine:/{print $2}')
[ "$env_legacy" = "legacy" ] || {
    echo "m9-cut: XNULL_ENGINE=legacy override is $env_legacy" >&2
    exit 1
}

env -u XNULL_ENGINE "$XNULL" --bootstrap run "$ROOT/src/examples/hello.x" > "$TMP" 2>"$TMP.err" || {
    cat "$TMP.err" >&2
    exit 1
}
printf 'hello, XNull\n1 + 2 = 3\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP"

"$XNULL" --bootstrap --engine=legacy run "$ROOT/src/examples/hello.x" > "$TMP" 2>"$TMP.err" || {
    cat "$TMP.err" >&2
    exit 1
}
diff -u "$TMP.exp" "$TMP"

echo "mini m9-cut: PASS"
