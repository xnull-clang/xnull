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

grep -q '^import xdk.cli$' "$TMP/generated/CliGenerated.x"
grep -q '^import xdk.errors$' "$TMP/generated/CliGenerated.x"
grep -q '^import xdk.text$' "$TMP/generated/CliGenerated.x"

python3 - "$HERE/app.x" "$TMP/models.x" <<'PY'
import sys
from pathlib import Path
lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
out = []
for line in lines:
    stripped = line.strip()
    if stripped.startswith(("@CliCommand", "@CliSubcommand", "@Option", "@Arg")):
        continue
    out.append(line)
Path(sys.argv[2]).write_text("\n".join(out) + "\n", encoding="utf-8")
PY

mkdir -p "$TMP/project/generated"
cp "$HERE/run.x" "$TMP/project/run.x"
cp "$TMP/models.x" "$TMP/project/models.x"
cp "$TMP/generated/CliGenerated.x" "$TMP/project/generated/CliGenerated.x"
"$ROOT/src/cli/xnull" --bootstrap --engine=mini build "$TMP/project/run.x" -o "$TMP/run" >"$TMP/build.log" 2>&1
"$TMP/run" >"$TMP/run.out"
diff -u "$HERE/run.out" "$TMP/run.out"

mkdir -p "$TMP/use/generated"
cp "$HERE/use_cli.x" "$TMP/use/use_cli.x"
cp "$TMP/models.x" "$TMP/use/models.x"
cp "$TMP/generated/CliGenerated.x" "$TMP/use/generated/CliGenerated.x"
"$ROOT/src/cli/xnull" --bootstrap --engine=mini build "$TMP/use/use_cli.x" -o "$TMP/use_cli" >"$TMP/use_build.log" 2>&1
"$TMP/use_cli" >"$TMP/use.out"
diff -u "$HERE/use_cli.out" "$TMP/use.out"

python3 "$PLATFORM" check --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/cli.manifest.json" --generated-dir "$HERE/generated" >/dev/null
python3 "$PLATFORM" generate --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/cli.manifest.json" --generated-dir "$TMP/generated2"
cmp "$TMP/generated/CliGenerated.x" "$TMP/generated2/CliGenerated.x"

expect_check_fail() {
    name="$1"
    if python3 "$PLATFORM" check --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
        --manifest "$HERE/cli.manifest.json" --generated-dir "$TMP/$name" >"$TMP/$name.log" 2>&1; then
        echo "cli_annotations: $name unexpectedly passed" >&2
        exit 1
    fi
}

cp -R "$HERE/generated" "$TMP/drift"
printf '\n// drift\n' >>"$TMP/drift/CliGenerated.x"
expect_check_fail drift

cp -R "$HERE/generated" "$TMP/missing"
rm "$TMP/missing/CliGenerated.x"
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
        --manifest "$HERE/cli.manifest.json" --generated-dir "$TMP/out_$name" >"$TMP/$name.log" 2>&1; then
        echo "cli_annotations: $name accepted" >&2; exit 1
    fi
    grep -q "$expected" "$TMP/$name.log"
}

case_warn() {
    name="$1"
    expected="$2"
    src="$3"
    printf '%s\n' "$src" >"$TMP/$name.x"
    python3 "$PLATFORM" generate --entry "$TMP/$name.x" --xdk-root "$ROOT/src/xdk" \
        --manifest "$HERE/cli.manifest.json" --generated-dir "$TMP/warn_$name" >"$TMP/$name.log" 2>&1
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

case_fail duplicate_sibling 'AN1701' 'package app.cli
import xdk.cli
@CliCommand("root","Root")
class Root { }
@CliSubcommand("root","dup","One")
class One { }
@CliSubcommand("root","dup","Two")
class Two { }
static Int main() { return 0 }'

case_fail arg_method 'AN1702' 'package app.cli
import xdk.cli
@CliCommand("root","Root")
class Root { }
@CliSubcommand("root","child","Child")
class Child {
    @Arg("x","X",true)
    String x() { return "" }
}
static Int main() { return 0 }'

case_fail arg_empty_name 'AN1702' 'package app.cli
import xdk.cli
@CliCommand("root","Root")
class Root { }
@CliSubcommand("root","child","Child")
class Child {
    @Arg("","X",true)
    String x
}
static Int main() { return 0 }'

case_warn unsupported_option 'AN1703' 'package app.cli
import xdk.cli
@CliCommand("root","Root")
class Root {
    @Option("--items","","")
    List<String> items
}
static Int main() { return 0 }'

case_warn no_default_ctor 'AN1704' 'package app.cli
import xdk.cli
@CliCommand("root","Root")
class Root {
    Root(String name) { }
}
static Int main() { return 0 }'

if grep -q 'RootBind' "$TMP/warn_no_default_ctor/CliGenerated.x"; then
    echo "cli_annotations: AN1704 still generated a binder" >&2
    exit 1
fi

case_fail duplicate_positional 'AN1705' 'package app.cli
import xdk.cli
@CliCommand("root","Root")
class Root { }
@CliSubcommand("root","child","Child")
class Child {
    @Arg("same","One",true)
    String one
    @Arg("same","Two",false)
    String two
}
static Int main() { return 0 }'

case_fail root_arg 'AN1706' 'package app.cli
import xdk.cli
@CliCommand("root","Root")
class Root {
    @Arg("x","X",true)
    String x
}
static Int main() { return 0 }'

echo "cli_annotations: PASS"
