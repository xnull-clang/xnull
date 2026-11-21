#!/bin/sh
# C1 reference programs: real mini programs, built and run end-to-end.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT

"$XNULL" --bootstrap --engine=mini build "$HERE/ref/cli_tool.x" -o "$D/cli" >"$D/cli.build" 2>&1 || {
    cat "$D/cli.build" >&2; exit 1
}
"$XNULL" --bootstrap --engine=mini build "$HERE/ref/concurrent.x" -o "$D/concurrent" >"$D/concurrent.build" 2>&1 || {
    cat "$D/concurrent.build" >&2; exit 1
}
"$XNULL" --bootstrap --engine=mini build "$HERE/ref/ffi_bytes.x" -o "$D/ffi" >"$D/ffi.build" 2>&1 || {
    cat "$D/ffi.build" >&2; exit 1
}
"$XNULL" --bootstrap --engine=mini build "$HERE/ref/project" -o "$D/project" >"$D/project.build" 2>&1 || {
    cat "$D/project.build" >&2; exit 1
}
"$XNULL" --bootstrap --engine=mini build "$HERE/ref/migration_sample.x" -o "$D/migration" >"$D/migration.build" 2>&1 || {
    cat "$D/migration.build" >&2; exit 1
}
"$XNULL" --bootstrap --engine=mini build "$HERE/ref/u2_task_dump.x" -o "$D/u2_task_dump" >"$D/u2_task_dump.build" 2>&1 || {
    cat "$D/u2_task_dump.build" >&2; exit 1
}

printf 'app.name=demo-app\napp.port=8080\n' > "$D/config.txt"

"$D/cli" help > "$D/cli.help" 2>"$D/cli.help.err" || {
    cat "$D/cli.help.err" >&2; exit 1
}
diff -u "$HERE/ref/cli_help.out" "$D/cli.help"

"$D/cli" run --config "$D/config.txt" > "$D/cli.run" 2>"$D/cli.run.err" || {
    cat "$D/cli.run.err" >&2; exit 1
}
diff -u "$HERE/ref/cli_run.out" "$D/cli.run"

"$D/cli" run > "$D/cli.missing" 2>"$D/cli.missing.err" || {
    cat "$D/cli.missing.err" >&2; exit 1
}
diff -u "$HERE/ref/cli_missing.out" "$D/cli.missing"

"$D/concurrent" > "$D/concurrent.out" 2>"$D/concurrent.err" || {
    cat "$D/concurrent.err" >&2; exit 1
}
diff -u "$HERE/ref/concurrent.out" "$D/concurrent.out"

(cd "$ROOT" && "$D/ffi") > "$D/ffi.out" 2>"$D/ffi.err" || {
    cat "$D/ffi.err" >&2; exit 1
}
diff -u "$HERE/ref/ffi_bytes.out" "$D/ffi.out"

"$D/project" > "$D/project.out" 2>"$D/project.err" || {
    cat "$D/project.err" >&2; exit 1
}
diff -u "$HERE/ref/project.out" "$D/project.out"

"$D/migration" > "$D/migration.out" 2>"$D/migration.err" || {
    cat "$D/migration.err" >&2; exit 1
}
diff -u "$HERE/ref/migration_sample.out" "$D/migration.out"

XNULL_CARRIERS=1 "$D/u2_task_dump" > "$D/u2_task_dump.out" 2> "$D/u2_task_dump.err" || {
    cat "$D/u2_task_dump.err" >&2; exit 1
}
diff -u "$HERE/ref/u2_task_dump.out" "$D/u2_task_dump.out"
diff -u "$HERE/ref/u2_task_dump.err" "$D/u2_task_dump.err"

echo "mini ref: PASS"
