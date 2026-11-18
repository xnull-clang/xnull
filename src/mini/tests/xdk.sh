#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_errors.x" > "$TMP" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf 'errors ok\ntrue\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_meta.x" > "$TMP" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf '3.4.0\n0.1.0\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP"

"$XNULL" --bootstrap --engine=auto run "$HERE/xdk_errors.x" > "$TMP" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf 'errors ok\ntrue\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_runtime.x" > "$TMP" 2>"$TMP.rt.err" || {
    cat "$TMP.err" "$TMP.rt.err" >&2; exit 1
}
printf 'true\ntrue\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP"
grep -q '^runtime ok$' "$TMP.rt.err"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_text.x" > "$TMP" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf '007\nabab\ntrue\n42\ntrue\n-1.25\n[x]\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_text_full.x" > "$TMP" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf '007\n7..\ncba\ntrue\ntrue\ntrue\nAbc\nabcd...\n3\n233\n0007\n..x\ntrue\n!b x !b\ntrue\n1\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_math.x" > "$TMP" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf '3\n7\n3\n10\ntrue\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_time.x" > "$TMP" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf '2000\ntrue\ntrue\ntrue\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_sys.x" > "$TMP" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf 'true\nfalse\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_integration.x" > "$TMP" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf '[Hello]\nhello\n007\n42\ntrue\nfalse\nerrors-ok\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_collections.x" > "$TMP.mini" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
"$XNULL" --bootstrap --engine=legacy run "$HERE/xdk_collections.x" > "$TMP.legacy" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf '1\nfalse\n2\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP.mini"
diff -u "$TMP.exp" "$TMP.legacy"
diff -u "$TMP.mini" "$TMP.legacy"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_bytes.x" > "$TMP.mini" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
"$XNULL" --bootstrap --engine=legacy run "$HERE/xdk_bytes.x" > "$TMP.legacy" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf '4142\n2\nAB\n6869\ntrue\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP.mini"
diff -u "$TMP.exp" "$TMP.legacy"
diff -u "$TMP.mini" "$TMP.legacy"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_bytes_extra.x" > "$TMP.mini" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
"$XNULL" --bootstrap --engine=legacy run "$HERE/xdk_bytes_extra.x" > "$TMP.legacy" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf '414243\n4243\n-1\n1234\n3412\n4660\n13330\n12345678\n305419896\n414243\n3\n8\n14\n6\n12\n3\n41123478563412\n65\n4660\n305419896\n0\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP.mini"
diff -u "$TMP.exp" "$TMP.legacy"
diff -u "$TMP.mini" "$TMP.legacy"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_sync_atomic.x" > "$TMP.mini" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
"$XNULL" --bootstrap --engine=legacy run "$HERE/xdk_sync_atomic.x" > "$TMP.legacy" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf '1\n2\nfalse\ntrue\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP.mini"
diff -u "$TMP.exp" "$TMP.legacy"
diff -u "$TMP.mini" "$TMP.legacy"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_io.x" > "$TMP.mini" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
"$XNULL" --bootstrap --engine=legacy run "$HERE/xdk_io.x" > "$TMP.legacy" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf '3\n65\n66\n67\n0\nfalse\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP.mini"
diff -u "$TMP.exp" "$TMP.legacy"
diff -u "$TMP.mini" "$TMP.legacy"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_fs.x" > "$TMP.mini" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
"$XNULL" --bootstrap --engine=legacy run "$HERE/xdk_fs.x" > "$TMP.legacy" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf '0\ntrue\nhello xdk.fs\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP.mini"
diff -u "$TMP.exp" "$TMP.legacy"
diff -u "$TMP.mini" "$TMP.legacy"

diff -qr "$ROOT/src/xdk" "$ROOT/xdk/lib/xdk" >/dev/null || {
    echo "src/xdk and xdk/lib/xdk differ" >&2
    exit 1
}

echo "mini xdk: PASS"
