#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
PLATFORM="$ROOT/src/toolchain/annotation_platform.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

python3 "$PLATFORM" generate --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/validate.manifest.json" --generated-dir "$TMP/generated" 2>"$TMP/gen.log"
diff -u "$HERE/generated/ValidateGenerated.x" "$TMP/generated/ValidateGenerated.x"
grep -q 'AN1205' "$TMP/gen.log"
grep -q 'Rules.email()' "$TMP/generated/ValidateGenerated.x"
string_line=$(grep -n 'Rules.string()' "$TMP/generated/ValidateGenerated.x" | head -1 | cut -d: -f1)
min_line=$(grep -n 'Rules.minLength(3)' "$TMP/generated/ValidateGenerated.x" | head -1 | cut -d: -f1)
pattern_line=$(grep -n 'Rules.pattern(' "$TMP/generated/ValidateGenerated.x" | head -1 | cut -d: -f1)
email_line=$(grep -n 'Rules.email()' "$TMP/generated/ValidateGenerated.x" | head -1 | cut -d: -f1)
[ "$string_line" -lt "$min_line" ]
[ "$min_line" -lt "$pattern_line" ]
[ "$pattern_line" -lt "$email_line" ]

"$ROOT/src/cli/xnull" check "$HERE/generated/ValidateGenerated.x"
"$ROOT/src/cli/xnull" --bootstrap --engine=mini build "$HERE/run.x" -o "$TMP/run" >"$TMP/build.log" 2>&1
"$TMP/run" >"$TMP/run.out"
diff -u "$HERE/run.out" "$TMP/run.out"

python3 "$PLATFORM" check --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/validate.manifest.json" --generated-dir "$HERE/generated" >/dev/null

python3 "$PLATFORM" generate --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/validate.manifest.json" --generated-dir "$TMP/generated2" 2>/dev/null
cmp "$TMP/generated/ValidateGenerated.x" "$TMP/generated2/ValidateGenerated.x"

expect_check_fail() {
    name="$1"
    if python3 "$PLATFORM" check --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
        --manifest "$HERE/validate.manifest.json" --generated-dir "$TMP/$name" >"$TMP/$name.log" 2>&1; then
        echo "validate_annotations: $name unexpectedly passed" >&2
        exit 1
    fi
}

cp -R "$HERE/generated" "$TMP/drift"
printf '\n// drift\n' >>"$TMP/drift/ValidateGenerated.x"
expect_check_fail drift

cp -R "$HERE/generated" "$TMP/missing"
rm "$TMP/missing/ValidateGenerated.x"
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
        --manifest "$HERE/validate.manifest.json" --generated-dir "$TMP/out_$name" >"$TMP/$name.log" 2>&1; then
        echo "validate_annotations: $name accepted" >&2
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
        --manifest "$HERE/validate.manifest.json" --generated-dir "$TMP/warn_$name" >"$TMP/$name.log" 2>&1
    grep -q "$expected" "$TMP/$name.log"
}

case_fail validate_on_field 'AN1201' 'package app.validate
import xdk.validate
class A {
    @Validate
    String name
}
static Int main() { return 0 }'

case_fail min_on_type 'AN1202' 'package app.validate
import xdk.validate
@Min(1)
class A {
    Int x
}
static Int main() { return 0 }'

case_fail min_gt_max 'AN1203' 'package app.validate
import xdk.validate
@Validate
class A {
    @Min(10) @Max(5)
    Int x
}
static Int main() { return 0 }'

case_fail bad_pattern 'AN1206' 'package app.validate
import xdk.validate
@Validate
class A {
    @Pattern("(")
    String x
}
static Int main() { return 0 }'

case_warn unsupported_list 'AN1205' 'package app.validate
import xdk.validate
@Validate
class WithList {
    String name
    List<String> items
}
static Int main() { return 0 }'

case_warn no_fields 'AN1204' 'package app.validate
import xdk.validate
@Validate
class Empty {
}
static Int main() { return 0 }'

case_warn email_int 'AN1207' 'package app.validate
import xdk.validate
@Validate
class A {
    @Email
    Int count
}
static Int main() { return 0 }'

grep -q 'Rules.integer()' "$TMP/warn_email_int/ValidateGenerated.x"
if grep -q 'Rules.email()' "$TMP/warn_email_int/ValidateGenerated.x"; then
    echo "validate_annotations: AN1207 still emitted email rule" >&2
    exit 1
fi

case_fail email_method 'AN1202' 'package app.validate
import xdk.validate
@Validate
class A {
    @Email
    String email() { return "" }
}
static Int main() { return 0 }'

echo "validate_annotations: PASS"
