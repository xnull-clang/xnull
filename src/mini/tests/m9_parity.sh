#!/bin/sh
# Full M9-PAR matrix: run every supported positive scenario through both
# engines and compare program stdout, stderr, and exit status.
#
# `base` explicitly selects the io/base compatibility surface; `full`
# enables the complete io/system/Sys.x unit and is required by the
# m7_sys/XDK full-mode cases.  An unset variable keeps legacy's historical
# full-Sys default so build tools that use pathExists/writeFileText still work.
# Compile diagnostics are intentionally not compared: M8-P5 owns the
# diagnostic-code matrix, while M9-PAR is about executable behaviour.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT

files='
base src/examples/hello.x
base src/examples/ast-seed.x
base src/examples/classes.x
base src/examples/containers.x
base src/examples/lexer-seed.x
base src/examples/parser-seed.x
base src/examples/defer-cleanup.x
base src/examples/objlist.x
base src/examples/result-try.x
base src/examples/multi/main.x
base src/mini/tests/array.x
base src/mini/tests/ast_local.x
base src/mini/tests/class_basic.x
base src/mini/tests/codegen_hello.x
base src/mini/tests/features.x
base src/mini/tests/ffi_demo.x
base src/mini/tests/flow.x
base src/mini/tests/generics.x
base src/mini/tests/lex_hello.x
base src/mini/tests/m6_4.x
base src/mini/tests/object_list.x
base src/mini/tests/sema_good.x
base src/mini/tests/throw.x
base src/mini/tests/xdk_errors.x
base src/mini/tests/xdk_integration.x
base src/mini/tests/xdk_math.x
base src/mini/tests/xdk_meta.x
base src/mini/tests/xdk_runtime.x
base src/mini/tests/xdk_sys.x
base src/mini/tests/xdk_text.x
base src/mini/tests/xdk_text_full.x
base src/mini/tests/xdk_time.x
full src/mini/tests/m7_sys.x
full src/mini/tests/xdk_errors.x
full src/mini/tests/xdk_math.x
full src/mini/tests/xdk_meta.x
full src/mini/tests/xdk_runtime.x
full src/mini/tests/xdk_sys.x
full src/mini/tests/xdk_text.x
full src/mini/tests/xdk_text_full.x
full src/mini/tests/xdk_time.x
'

projects='
base src/mini/tests/project
base src/mini/tests/resources
base src/mini/tests/modules
base ide/web/workspace/ide-demo
base ide/web/workspace/imported-probe
base ide/web/workspace/wizard-test
'

fail=0
n=0
# Run a program without letting the outer shell print a job-control
# "Abort trap" line into the captured stderr.  Python returns the child's
# exit status as data; the program's own stdout/stderr are preserved.
run_program() {
    bin=$1
    base=$2
    python3 - "$bin" "$base.stdout" "$base.stderr" "$base.exit" "$ROOT" <<'PY'
import subprocess
import sys

binary, out_path, err_path, exit_path, cwd = sys.argv[1:6]
with open(out_path, "wb") as out, open(err_path, "wb") as err:
    proc = subprocess.run([binary], cwd=cwd, stdout=out, stderr=err)
code = proc.returncode
if code < 0:
    code = 128 + (-code)
with open(exit_path, "w", encoding="ascii") as f:
    f.write(str(code) + "\n")
PY
}

run_file() {
    rel=$1
    mode=$2
    name=$(printf '%s' "$rel" | tr '/.' '__')_$mode
    n=$((n + 1))
    if [ "$mode" = full ]; then export XNULL_MINI_XDK_FULL=1; else export XNULL_MINI_XDK_FULL=0; fi
    for engine in legacy mini; do
        out="$D/$name.$engine"
        if ! "$XNULL" --bootstrap --engine="$engine" build "$ROOT/$rel" -o "$out.bin" \
            >"$out.build.out" 2>"$out.build.err"; then
            echo "m9-parity: $rel [$engine/$mode] build failed" >&2
            cat "$out.build.err" >&2
            fail=1
            return
        fi
        run_program "$out.bin" "$out"
    done
    for part in stdout stderr exit; do
        if ! cmp -s "$D/$name.legacy.$part" "$D/$name.mini.$part"; then
            echo "m9-parity: $rel [$mode] $part differs" >&2
            diff -u "$D/$name.legacy.$part" "$D/$name.mini.$part" >&2 || true
            fail=1
        fi
    done
}

run_project() {
    rel=$1
    name=$(printf '%s' "$rel" | tr '/.' '__')_project
    n=$((n + 1))
    export XNULL_MINI_XDK_FULL=0
    for engine in legacy mini; do
        out="$D/$name.$engine"
        if ! "$XNULL" --bootstrap --engine="$engine" build-project "$ROOT/$rel" -o "$out.dir" \
            >"$out.build.out" 2>"$out.build.err"; then
            echo "m9-parity: $rel [$engine] build failed" >&2
            cat "$out.build.err" >&2
            fail=1
            return
        fi
        if [ ! -x "$out.dir/app" ]; then
            echo "m9-parity: $rel [$engine] no app binary" >&2
            fail=1
            return
        fi
        run_program "$out.dir/app" "$out"
    done
    for part in stdout stderr exit; do
        if ! cmp -s "$D/$name.legacy.$part" "$D/$name.mini.$part"; then
            echo "m9-parity: $rel project $part differs" >&2
            diff -u "$D/$name.legacy.$part" "$D/$name.mini.$part" >&2 || true
            fail=1
        fi
    done
}

while read -r mode rel; do
    [ -n "$rel" ] || continue
    run_file "$rel" "$mode"
done <<EOF
$files
EOF

while read -r mode rel; do
    [ -n "$rel" ] || continue
    run_project "$rel"
done <<EOF
$projects
EOF

echo "mini m9 parity: files+projects=$n diff=$fail"
[ "$fail" -eq 0 ]
