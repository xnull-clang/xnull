#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
PLATFORM="$ROOT/src/toolchain/annotation_platform.py"
MEMORY="$ROOT/src/mini/tests/xdk2/db/MemoryFixture.x"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

python3 "$PLATFORM" generate --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/db.manifest.json" --generated-dir "$TMP/generated"
diff -u "$HERE/generated/DbGenerated.x" "$TMP/generated/DbGenerated.x"

grep -q '^import xdk.db$' "$TMP/generated/DbGenerated.x"
grep -q '^import xdk.sql$' "$TMP/generated/DbGenerated.x"
grep -q '^import xdk.errors$' "$TMP/generated/DbGenerated.x"
grep -q 'readOnly requested; this driver version has no read-only transaction hint.' "$TMP/generated/DbGenerated.x"

mkdir -p "$TMP/project/generated"
cp "$HERE/run.x" "$TMP/project/run.x"
cp "$MEMORY" "$TMP/project/MemoryFixture.x"
cp "$TMP/generated/DbGenerated.x" "$TMP/project/generated/DbGenerated.x"
"$ROOT/src/cli/xnull" --bootstrap --engine=mini build "$TMP/project/run.x" -o "$TMP/run" >"$TMP/build.log" 2>&1
"$TMP/run" >"$TMP/run.out"
diff -u "$HERE/run.out" "$TMP/run.out"

python3 "$PLATFORM" check --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/db.manifest.json" --generated-dir "$HERE/generated" >/dev/null

python3 "$PLATFORM" generate --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/db.manifest.json" --generated-dir "$TMP/generated2"
cmp "$TMP/generated/DbGenerated.x" "$TMP/generated2/DbGenerated.x"

expect_check_fail() {
    name="$1"
    if python3 "$PLATFORM" check --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
        --manifest "$HERE/db.manifest.json" --generated-dir "$TMP/$name" >"$TMP/$name.log" 2>&1; then
        echo "db_annotations: $name unexpectedly passed" >&2
        exit 1
    fi
}

cp -R "$HERE/generated" "$TMP/drift"
printf '\n// drift\n' >>"$TMP/drift/DbGenerated.x"
expect_check_fail drift

cp -R "$HERE/generated" "$TMP/missing"
rm "$TMP/missing/DbGenerated.x"
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
        --manifest "$HERE/db.manifest.json" --generated-dir "$TMP/out_$name" >"$TMP/$name.log" 2>&1; then
        echo "db_annotations: $name accepted" >&2
        exit 1
    fi
    grep -q "$expected" "$TMP/$name.log"
}

case_warn() {
    name="$1"
    expected="$2"
    src="$3"
    printf '%s\n' "$src" >"$TMP/$name.x"
    python3 "$PLATFORM" generate --entry "$TMP/$name.x" --xdk-root "$ROOT/src/xdk" \
        --manifest "$HERE/db.manifest.json" --generated-dir "$TMP/warn_$name" >"$TMP/$name.log" 2>&1
    grep -q "$expected" "$TMP/$name.log"
}

case_fail entity_on_field 'AN1801' 'package app.db
import xdk.db
class A {
    @Entity("a")
    Long id
}
static Int main() { return 0 }'

case_fail both_annotations 'AN1802' 'package app.db
import xdk.db
@Entity("a")
@Table("a")
class A {
    @Id
    Long id
    A(Long id) { self.id = id }
}
static Int main() { return 0 }'

case_fail empty_table 'AN1803' 'package app.db
import xdk.db
@Entity("")
class A {
    @Id
    Long id
    A(Long id) { self.id = id }
}
static Int main() { return 0 }'

case_fail missing_id 'AN1804' 'package app.db
import xdk.db
@Entity("a")
class A {
    Long id
    A(Long id) { self.id = id }
}
static Int main() { return 0 }'

case_fail double_id 'AN1804' 'package app.db
import xdk.db
@Entity("a")
class A {
    @Id
    Long id
    @Id
    Long other
    A(Long id, Long other) {
        self.id = id
        self.other = other
    }
}
static Int main() { return 0 }'

case_fail id_on_class 'AN1805' 'package app.db
import xdk.db
@Id
@Entity("a")
class A {
    Long id
    A(Long id) { self.id = id }
}
static Int main() { return 0 }'

case_warn unsupported_field 'AN1806' 'package app.db
import xdk.db
@Entity("a")
class A {
    @Id
    Long id
    List<String> tags
    A(Long id, List<String> tags) {
        self.id = id
        self.tags = tags
    }
}
static Int main() { return 0 }'

case_fail transaction_signature 'AN1807' 'package app.db
import xdk.db
class Dao {
    @Transactional
    Result<Long, Error> write(Long id) {
        return Err(sqlInvalidArgument("stub"))
    }
}
static Int main() { return 0 }'

case_warn read_only 'AN1808' 'package app.db
import xdk.db
import xdk.sql
class Dao {
    @Transactional(true)
    Result<Long, Error> read(SqlTransaction tx) {
        return Ok(1)
    }
}
static Int main() { return 0 }'

case_fail duplicate_column 'AN1809' 'package app.db
import xdk.db
import xdk.sql
@Entity("a")
class A {
    @Id
    Long id
    @Column("id")
    Long other
    A(Long id, Long other) {
        self.id = id
        self.other = other
    }
}
static Int main() { return 0 }'

echo "db_annotations: PASS"
