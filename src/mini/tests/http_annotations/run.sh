#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
PLATFORM="$ROOT/src/toolchain/annotation_platform.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

python3 "$PLATFORM" generate --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/http.manifest.json" --generated-dir "$TMP/generated"
diff -u "$HERE/generated/CodecGenerated.x" "$TMP/generated/CodecGenerated.x"
diff -u "$HERE/generated/HttpGenerated.x" "$TMP/generated/HttpGenerated.x"

"$ROOT/src/cli/xnull" --bootstrap --engine=mini build "$HERE/run.x" -o "$TMP/run" >"$TMP/build.log" 2>&1
"$TMP/run" >"$TMP/run.out"
diff -u "$HERE/run.out" "$TMP/run.out"

python3 "$PLATFORM" check --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/http.manifest.json" --generated-dir "$HERE/generated" >/dev/null

python3 "$PLATFORM" generate --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/http.manifest.json" --generated-dir "$TMP/generated2"
cmp "$TMP/generated/CodecGenerated.x" "$TMP/generated2/CodecGenerated.x"
cmp "$TMP/generated/HttpGenerated.x" "$TMP/generated2/HttpGenerated.x"

expect_check_fail() {
    name="$1"
    if python3 "$PLATFORM" check --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
        --manifest "$HERE/http.manifest.json" --generated-dir "$TMP/$name" >"$TMP/$name.log" 2>&1; then
        echo "http_annotations: $name unexpectedly passed" >&2
        exit 1
    fi
}

cp -R "$HERE/generated" "$TMP/drift"
printf '\n// drift\n' >>"$TMP/drift/HttpGenerated.x"
expect_check_fail drift

cp -R "$HERE/generated" "$TMP/missing"
rm "$TMP/missing/HttpGenerated.x"
expect_check_fail missing

cp -R "$HERE/generated" "$TMP/extra"
printf '// extra\n' >"$TMP/extra/Extra.x"
expect_check_fail extra

case_fail() {
    name="$1"
    expected="$2"
    src="$3"
    printf '%s\n' "$src" >"$TMP/$name.x"
    if python3 "$PLATFORM" generate --entry "$TMP/$name.x" --xdk-root "$ROOT/src/xdk" \
        --manifest "$HERE/http.manifest.json" --generated-dir "$TMP/out_$name" >"$TMP/$name.log" 2>&1; then
        echo "http_annotations: $name accepted" >&2
        exit 1
    fi
    grep -q "$expected" "$TMP/$name.log"
}

case_fail route_on_field 'AN1301' 'package app.http
import xdk.net.http
class A {
    @HttpRoute("/x")
    String field
}
static Int main() { return 0 }'

case_fail empty_query 'AN1302' 'package app.http
import xdk.net.http
class A {
    @HttpRoute("/x")
    HttpResponse x(@Query("") String q) {
        return HttpResponse.of(200)
    }
}
static Int main() { return 0 }'

case_fail duplicate_route 'AN1303' 'package app.http
import xdk.net.http
class A {
    @HttpRoute("/dup", HttpMethod.Get)
    HttpResponse a() { return HttpResponse.of(200) }
    @HttpRoute("/dup", HttpMethod.Get)
    HttpResponse b() { return HttpResponse.of(200) }
}
static Int main() { return 0 }'

case_fail unbindable 'AN1304' 'package app.http
import xdk.net.http
class A {
    @HttpRoute("/x")
    HttpResponse x(String missing) { return HttpResponse.of(200) }
}
static Int main() { return 0 }'

case_fail body_no_codec 'AN1305' 'package app.http
import xdk.net.http
class Payload {
    String name
}
class A {
    @HttpRoute("/x", HttpMethod.Post)
    HttpResponse x(@Body Payload body) { return HttpResponse.of(200) }
}
static Int main() { return 0 }'

case_fail bad_return 'AN1306' 'package app.http
import xdk.net.http
class A {
    @HttpRoute("/x")
    Int x() { return 1 }
}
static Int main() { return 0 }'

case_fail bad_template 'AN1307' 'package app.http
import xdk.net.http
class A {
    @HttpRoute("/x/{id")
    HttpResponse x(String id) { return HttpResponse.of(200) }
}
static Int main() { return 0 }'

echo "http_annotations: PASS"
