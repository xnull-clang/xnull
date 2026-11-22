#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
PLATFORM="$ROOT/src/toolchain/annotation_platform.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

python3 "$PLATFORM" generate --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/cli.manifest.json" --generated-dir "$TMP/generated"
diff -u "$HERE/generated/CliGenerated.x" "$TMP/generated/CliGenerated.x"
"$ROOT/src/cli/xnull" --bootstrap --engine=mini run "$HERE/use_cli.x" >"$TMP/use.out"
diff -u "$HERE/use_cli.out" "$TMP/use.out"
python3 "$PLATFORM" check --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/cli.manifest.json" --generated-dir "$HERE/generated" >/dev/null
python3 "$PLATFORM" generate --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/cli.manifest.json" --generated-dir "$TMP/generated2"
cmp "$TMP/generated/CliGenerated.x" "$TMP/generated2/CliGenerated.x"

case_fail() {
    name="$1"
    expected="$2"
    src="$3"
    printf '%s\n' "$src" >"$TMP/$name.x"
    if python3 "$PLATFORM" generate --entry "$TMP/$name.x" --xdk-root "$ROOT/src/xdk" \
        --manifest "$HERE/cli.manifest.json" --generated-dir "$TMP/out_$name" >"$TMP/$name.log" 2>&1; then
        echo "cli_annotations: $name accepted" >&2; exit 1
    fi
    grep -q "$expected" "$TMP/$name.log"
}

case_fail unknown_parent 'AN1002' 'package app.cli
import xdk.cli
@CliCommand("root","Root")
class Root { }
@CliSubcommand("missing","child","Child")
class Child { }
static Int main() { return 0 }'

case_fail duplicate_command 'AN1003' 'package app.cli
import xdk.cli
@CliCommand("root","Root")
class A { }
@CliCommand("root","Other")
class B { }
static Int main() { return 0 }'

case_fail duplicate_option 'AN1004' 'package app.cli
import xdk.cli
@CliCommand("root","Root")
class A {
    @Option("--x","","")
    Bool a
    @Option("--x","","")
    Bool b
}
static Int main() { return 0 }'

case_fail struct_command 'AN1005' 'package app.cli
import xdk.cli
@CliCommand("root","Root")
struct A { }
static Int main() { return 0 }'

case_fail option_method 'AN1005' 'package app.cli
import xdk.cli
@CliCommand("root","Root")
class A {
    @Option("--x","","")
    Bool x() { return true }
}
static Int main() { return 0 }'

case_fail bool_required 'AN1006' 'package app.cli
import xdk.cli
@CliCommand("root","Root")
class A {
    @Option("--x","","",true)
    Bool x
}
static Int main() { return 0 }'

echo "cli_annotations: PASS"
