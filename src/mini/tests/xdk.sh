#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp)
trap 'rm -f "$TMP" "$TMP.cli" "$TMP.panic.x" "$TMP.panic.err"' EXIT

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_errors.x" > "$TMP" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf 'errors ok\ntrue\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP"

# Full errors surface: DetailedError, report steps, aggregation, ResultOps,
# kind names/codes, detail validation. Legacy lacks the new API.
"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_errors_full.x" > "$TMP" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf 'true\ntrue\nNotFound: missing\n[cfg.missing] NotFound: missing\n1\nload -> parse -> [cfg.missing] NotFound: missing\n2\n2\ntrue\n1\n2\ntrue\n7\ntrue\ntrue\ntrue\nfalse\n1\n2\nnot_found\ntrue\n6\ntrue\ntrue\ntrue\ntrue\n1\ntrue\ntrue\n1\nn=1\ntrue\nbad\nInvalidArgument: bad\ntrue\n1\ntrue\nv=1\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_meta.x" > "$TMP" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf '3.4.0\n1.0.0\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_errors.x" > "$TMP" 2>"$TMP.err" || {
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
printf '007\n7..\ncba\ntrue\ntrue\ntrue\nAbc\nabcd...\n3\n233\n0007\n..x\ntrue\n! x !\ntrue\n1\n233\n65\n2\n2\né\n128512\n1\ntrue\n1\n65533\n�\ntrue\ntrue\ntrue\nfalse\ntrue\n1\naaabb\naaa\nbb\ntrue\ntrue\ntrue\n0007|ok  |3.14|0xff|true|A|%%\n-00042\n1.235e+03\ntrue\ntrue\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_math.x" > "$TMP" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf '3\n7\n3\n10\ntrue\n3\n2\ntrue\n1\n170141183460469231731687303715884105726\n-170141183460469231731687303715884105726\n11\n170141183460469231731687303715884105727\n-170141183460469231731687303715884105728\n3\ntrue\ntrue\n12\ntrue\n3\ntrue\n-1\ntrue\n5\n120\ntrue\ntrue\n0\ntrue\ntrue\ntrue\ntrue\n4\n4\n0\n1\n3\n3\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\n0\ntrue\n5\n3\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\n0\ntrue\n5\n2147483647\n-2147483648\n2147483647\n-2147483648\n9223372036854775807\n-9223372036854775808\n9223372036854775807\n-9223372036854775808\n20\n1\ntrue\ntrue\ntrue\n10\n1\n1\ntrue\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_time.x" > "$TMP" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf '2000\ntrue\ntrue\ntrue\n2024-01-31 23:59:59\n01|Jan|January\n31|Wed|Wednesday\nWed, 31 Jan 2024\n1706745599000\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP"

XDK_SYS_PROBE=sys-env "$XNULL" --bootstrap --engine=mini run "$HERE/xdk_sys.x" > "$TMP" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf '3
hé
true
true
true
true
sys-env
true
true
true
true
true
true
true
4
true
ping
0
true
true
err
0
true
false
true
0
true
true
true
true
true
true
143
true
false
0
true
true
0
' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP"

XNULL_MINI_XDK_FULL=1 "$XNULL" --bootstrap --engine=mini run "$HERE/xdk_sys_full.x" > "$TMP" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf '3
abc
true
true
2
true
true
true
true
XY
1
true
XY!
true
3
true
1
Y!

true
true
true
true
true
xnull_xdk_sys_full.txt
tmp
txt
true
true
true
true
4
true
full
0
true
true
false
' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_integration.x" > "$TMP" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf '[Hello]\nhello\n007\n42\ntrue\nfalse\nerrors-ok\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_collections.x" > "$TMP.mini" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf '1\nfalse\n2\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP.mini"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_collections_algo.x" > "$TMP.mini" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf '1\n3\n3\n1\n3\nfalse\n5\ntrue\na\nb\nc\n3\nfalse\ny\n2\n3\n3\n1\n2\n3\n3\n1|2|3|4|5|6\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP.mini"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_containers.x" > "$TMP.mini" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf '1\n2\n1\ntrue\ntrue\nfalse\n1\n1\n2\ntrue\ntrue\ntwo\none\n2\nTWO\ntrue\n1\ntrue\n1\n3\n5\nthree\nthree\nthree\ntrue\n2\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP.mini"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_members.x" > "$TMP.mini" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf '0\ntrue\n2\n0\nfalse\ntrue\n2\ntrue\n1\n1\nfalse\ntrue\n9\n2\na\n1\n0\n2\ntrue\ntrue\n9\ntrue\n4\n9\n3\nfalse\nfalse\n2\n1\n10\n2\n20\n10\ntrue\n1\n1\n1\n2\ntrue\ntrue\ntrue\n0\nfalse\nalpha\nnone\na\nalpha\ntrue\ntrue\n0\n9000000000\n9000000000\n2\ntrue\ntrue\ntrue\n2\n2\ntrue\n2\nfirst\n11\n22\n7\nseven\n7\n2\ntrue\ntrue\n1\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP.mini"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_log.x" > "$TMP.mini" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf '[INFO] app: started\n[WARN] app: careful\n[ERROR] app: bad\n[DEBUG] dbg: visible\n[INFO] field: with field component=core\n1\n[WARN] mem: to memory k=v\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP.mini"

XDK_W5_NAME=from-env "$XNULL" --bootstrap --engine=mini run "$HERE/xdk_config.x" > "$TMP.mini" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf 'demo\n9090\nfalse\n2\nfrom-env\nfalse\ndev:app.name=demo,app.port=9090,XDK_W5_NAME=from-env\noverride\neu\ntrue\non\ntrue\nfile\n42\ntrue\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP.mini"

"$XNULL" --bootstrap --engine=mini build "$HERE/xdk_cli.x" -o "$TMP.cli" >"$TMP.err" 2>&1 || {
    cat "$TMP.err" >&2; exit 1
}
"$TMP.cli" --name Alpha pos1 -v > "$TMP.mini" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf '4\ntrue\nfalse\nAlpha\nfallback\n1\npos1\nusage: demo --name <name> [files]\n2\n1\ntrue\nrun\nusage: demo [--verbose]\ndemo tool\noptions:\n  --verbose  verbose output\ncommands:\n  run  run task\ntrue\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP.mini"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_bytes.x" > "$TMP.mini" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf '4142\n2\nAB\n6869\ntrue\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP.mini"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_bytes_extra.x" > "$TMP.mini" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf '414243\n4243\n-1\n1234\n3412\n4660\n13330\n12345678\n305419896\n414243\n3\n8\n14\n6\n12\n3\n41123478563412\n65\n4660\n305419896\n0\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP.mini"

# Strict/checked bytes surface: uppercase hex, checked range, copy semantics,
# u64 bit patterns, 32/64-bit bit counts, and checked reader position. Legacy
# does not have the new Result/Long surface yet, so this scenario is mini-only.
"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_bytes_strict.x" > "$TMP.mini" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf '4a4b\ntrue\ntrue\ntrue\n65\ntrue\ntrue\n42\ntrue\ntrue\n4142\n4342\n01\n0102\n0\nffffffff00000000\n00000000ffffffff\n4294967295\n4294967295\n-1\n-1\nffffffffffffffff\nffffffffffffffff\n0\n32\n31\n32\n3\n32\n64\n63\n3\n65\ntrue\n1\ntrue\n0\n41\ntrue\n67\ntrue\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP.mini"

# Contract errors: unchecked bytes APIs must fail loudly, not return a sentinel.
cat > "$TMP.panic.x" <<'X'
import xdk.bytes
static Int main() {
    Bytes bytes = fromHex("ABC")
    print(bytes.length())
    return 0
}
X
if "$XNULL" --bootstrap --engine=mini run "$TMP.panic.x" > /dev/null 2>"$TMP.panic.err"; then
    echo "expected fromHex odd length to fail" >&2
    exit 1
fi
grep -q "fromHex: odd length" "$TMP.panic.err"

cat > "$TMP.panic.x" <<'X'
import xdk.bytes
static Int main() {
    ByteReader reader = new ByteReader(fromHex("41"))
    print(reader.readU8())
    print(reader.readU8())
    return 0
}
X
if "$XNULL" --bootstrap --engine=mini run "$TMP.panic.x" > /dev/null 2>"$TMP.panic.err"; then
    echo "expected readU8 end of input to fail" >&2
    exit 1
fi
grep -q "readU8: end of input" "$TMP.panic.err"

cat > "$TMP.panic.x" <<'X'
import xdk.io
import xdk.bytes
static Int main() {
    Reader reader = new Reader(Bytes.fromString("A"))
    print(reader.readU8())
    print(reader.readU8())
    return 0
}
X
if "$XNULL" --bootstrap --engine=mini run "$TMP.panic.x" > /dev/null 2>"$TMP.panic.err"; then
    echo "expected io Reader readU8 end of input to fail" >&2
    exit 1
fi
grep -q "readU8: end of input" "$TMP.panic.err"

cat > "$TMP.panic.x" <<'X'
import xdk.io
import xdk.bytes
static Int main() {
    Reader reader = new Reader(Bytes.fromString("A"))
    print(reader.readBytes(-1).length())
    return 0
}
X
if "$XNULL" --bootstrap --engine=mini run "$TMP.panic.x" > /dev/null 2>"$TMP.panic.err"; then
    echo "expected io Reader readBytes negative count to fail" >&2
    exit 1
fi
grep -q "readBytes: negative count" "$TMP.panic.err"

cat > "$TMP.panic.x" <<'X'
import xdk.io
static Int main() {
    Writer writer = new Writer()
    writer.close()
    writer.writeU8(1)
    return 0
}
X
if "$XNULL" --bootstrap --engine=mini run "$TMP.panic.x" > /dev/null 2>"$TMP.panic.err"; then
    echo "expected io Writer writeU8 after close to fail" >&2
    exit 1
fi
grep -q "writeU8: closed" "$TMP.panic.err"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_sync_atomic.x" > "$TMP.mini" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf '1\n2\ntrue\n3\nfalse\ntrue\nfalse\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP.mini"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_sync_ref.x" > "$TMP.mini" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf 'a\nb\nfalse\nb\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP.mini"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_mutex.x" > "$TMP.mini" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf 'true\ntrue\n3\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP.mini"

# without the adapter prototypes, so it is not part of the comparison yet.
"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_tasks.x" > "$TMP.mini" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf 'false\ntrue\n42\nfalse\ntrue\nfalse\ntrue\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP.mini"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_cancel.x" > "$TMP.mini" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf 'true\n21\ntrue\ntrue\ntrue\n33\ntrue\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP.mini"

# codegen gap, so it is not part of the cross-engine comparison yet.
"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_channel.x" > "$TMP.mini" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf 'true\n7\ntrue\ntrue\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP.mini"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_channel_typed.x" > "$TMP.mini" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf 'true\ntrue\nhello\ntrue\ntrue\n7\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\n9000000000\ntrue\ntrue\ntrue\nx\ntrue\ntrue\nffi\ntrue\ntrue\n1.5\ntrue\n170141183460469231731687303715884105727\ntrue\ntrue\n1\ntrue\ntrue\nInvalidArgument: bad\ntrue\ntrue\ntrue\n2\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP.mini"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_io.x" > "$TMP.mini" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf '3\n65\n66\n67\n0\nfalse\n65\n1\n42\ntrue\ntrue\n0\n01\n0102\ntrue\ntrue\ntrue\ntrue\n5\n65\n424344\n1\ntrue\n1\n69\nfalse\ntrue\n3\n3\n0\ntrue\n3\n0\ntrue\nABCD\ntrue\ntrue\ntrue\n4\n414243\n1\n68\ntrue\n2\n88\n595a\nXYZ\nfalse\ntrue\nfalse\n3\n65\n4243\n0\ntrue\ntrue\none\ntwo\nthree\ntrue\nhello\n0\n4\ncopy\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP.mini"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_fs.x" > "$TMP.mini" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf 'true\n12\ntrue\nhello xdk.fs\n2\né\ntrue\ntrue\n2\n4142\ntrue\n12\ntrue\n6\nxd\nk.fs\ntrue\ntrue\ntrue\ntrue\n6\ntrue\n2\ntrue\ntrue\nabXYef\n1\ntrue\nabXYef!\n4\ntrue\ntrue\nc.txt\nsub\ntxt\ntrue\nd.txt\nb/c\ntrue\n12\ntrue\ntrue\ntrue\n384\n384\nfalse\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\nhello xdk.fs\ntrue\n6\natomic\ntrue\ntrue\n1\n6\n4\n5\ntrue\ntrue\ntrue\nfalse\ntrue\ntrue\ntrue\n1\n1\ntrue\nfalse\ntrue\nhello xdk.fs\ntrue\ntrue\nfalse\ntrue\nfalse\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP.mini"

diff -qr "$ROOT/src/xdk" "$ROOT/xdk/lib/xdk" >/dev/null || {
    echo "src/xdk and xdk/lib/xdk differ" >&2
    exit 1
}

python3 "$ROOT/src/toolchain/check_doc_naming.py" \
    "$ROOT/docs/design/t0"

echo "mini xdk: PASS"
