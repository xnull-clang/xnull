#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
PLATFORM="$ROOT/src/toolchain/annotation_platform.py"
MEMORY="$ROOT/src/mini/tests/xdk2/sql/MemoryFixture.x"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

python3 "$PLATFORM" generate --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/sql.manifest.json" --generated-dir "$TMP/generated"
diff -u "$HERE/generated/SqlGenerated.x" "$TMP/generated/SqlGenerated.x"

mkdir -p "$TMP/project/generated"
cp "$HERE/app.x" "$TMP/project/app.x"
cp "$HERE/run.x" "$TMP/project/run.x"
cp "$MEMORY" "$TMP/project/MemoryFixture.x"
cp "$TMP/generated/SqlGenerated.x" "$TMP/project/generated/SqlGenerated.x"
"$ROOT/src/cli/xnull" --bootstrap --engine=mini build "$TMP/project/run.x" -o "$TMP/run" >"$TMP/build.log" 2>&1
"$TMP/run" >"$TMP/run.out"
diff -u "$HERE/run.out" "$TMP/run.out"

python3 "$PLATFORM" check --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/sql.manifest.json" --generated-dir "$HERE/generated" >/dev/null

python3 "$PLATFORM" generate --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/sql.manifest.json" --generated-dir "$TMP/generated2"
cmp "$TMP/generated/SqlGenerated.x" "$TMP/generated2/SqlGenerated.x"

expect_check_fail() {
    name="$1"
    if python3 "$PLATFORM" check --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
        --manifest "$HERE/sql.manifest.json" --generated-dir "$TMP/$name" >/tmp/sql_ann_$name.log 2>&1; then
        echo "sql_annotations: $name unexpectedly passed" >&2
        exit 1
    fi
}

cp -R "$HERE/generated" "$TMP/drift"
printf '\n// drift\n' >>"$TMP/drift/SqlGenerated.x"
expect_check_fail drift

cp -R "$HERE/generated" "$TMP/missing"
rm "$TMP/missing/SqlGenerated.x"
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
        --manifest "$HERE/sql.manifest.json" --generated-dir "$TMP/out_$name" >"$TMP/$name.log" 2>&1; then
        echo "sql_annotations: $name accepted" >&2
        exit 1
    fi
    grep -q "$expected" "$TMP/$name.log"
}

case_fail sql_on_field 'AN1401' 'package app.sql
import xdk.sql
class A {
    @Sql("select 1")
    String field
}
static Int main() { return 0 }'

case_fail empty_sql 'AN1402' 'package app.sql
import xdk.sql
class A {
    @Sql("")
    Result<Long, Error> x() { return Err(sqlInvalidArgument("stub")) }
}
static Int main() { return 0 }'

case_fail placeholder 'AN1403' 'package app.sql
import xdk.sql
class A {
    @Sql("select * from t where id = :id")
    Result<Long, Error> x(Long name) { return Err(sqlInvalidArgument("stub")) }
}
static Int main() { return 0 }'

case_fail param_on_method 'AN1404' 'package app.sql
import xdk.sql
class A {
    @Param("x")
    Result<Long, Error> x() { return Err(sqlInvalidArgument("stub")) }
}
static Int main() { return 0 }'

case_fail row_on_struct 'AN1405' 'package app.sql
import xdk.sql
@Row
struct S {
    Long id
}
static Int main() { return 0 }'

case_fail bad_return 'AN1406' 'package app.sql
import xdk.sql
class A {
    @Sql("select 1")
    Bool x() { return true }
}
static Int main() { return 0 }'

case_fail bad_field 'AN1407' 'package app.sql
import xdk.sql
@Row
class R {
    List<String> values
}
static Int main() { return 0 }'

case_fail duplicate_column 'AN1408' 'package app.sql
import xdk.sql
@Row
class R {
    @Column("x")
    Long a
    @Column("x")
    String b
}
static Int main() { return 0 }'

case_fail row_not_annotated 'AN1409' 'package app.sql
import xdk.sql
class Plain {
    Long id
}
class A {
    @Sql("select id from plain")
    Result<Plain, Error> x() { return Err(sqlInvalidArgument("stub")) }
}
static Int main() { return 0 }'

echo "sql_annotations: PASS"
