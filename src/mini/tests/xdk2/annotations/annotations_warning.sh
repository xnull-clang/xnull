#!/bin/sh
# Warning path gate:
#   - the build/run codegen path (mini --emit-c) reports warnings on stderr;
#   - xnull run reports them without changing stdout or the exit code;
#   - each warning is emitted once, not duplicated by the two passes.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
MINI="$ROOT/src/mini/bin/mini"
XNULL="$ROOT/src/cli/xnull"
SRC="$HERE/annotations_warning.x"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

set +e
"$MINI" --emit-c "$SRC" --xdk-root "$ROOT/src/xdk" >"$TMP/emit.c" 2>"$TMP/emit.err"
emit_rc=$?
set -e
[ "$emit_rc" -eq 0 ] || {
    echo "annotations warning: --emit-c failed" >&2
    cat "$TMP/emit.err" >&2
    exit 1
}
grep -F "[AN0014]" "$TMP/emit.err" >/dev/null || {
    echo "annotations warning: missing AN0014 on --emit-c stderr" >&2
    cat "$TMP/emit.err" >&2
    exit 1
}
grep -F "[AN0015]" "$TMP/emit.err" >/dev/null || {
    echo "annotations warning: missing AN0015 on --emit-c stderr" >&2
    cat "$TMP/emit.err" >&2
    exit 1
}
[ "$(grep -Fc 'warning [AN0014]' "$TMP/emit.err" || true)" -eq 1 ] || {
    echo "annotations warning: AN0014 not emitted exactly once by --emit-c" >&2
    cat "$TMP/emit.err" >&2
    exit 1
}
[ "$(grep -Fc 'warning [AN0015]' "$TMP/emit.err" || true)" -eq 1 ] || {
    echo "annotations warning: AN0015 not emitted exactly once by --emit-c" >&2
    cat "$TMP/emit.err" >&2
    exit 1
}

set +e
"$XNULL" --bootstrap --engine=mini run "$SRC" >"$TMP/run.out" 2>"$TMP/run.err"
run_rc=$?
set -e
[ "$run_rc" -eq 0 ] || {
    echo "annotations warning: run exit code changed: $run_rc" >&2
    cat "$TMP/run.err" >&2
    exit 1
}
printf 'business\n' >"$TMP/expected.out"
diff -u "$TMP/expected.out" "$TMP/run.out" || {
    echo "annotations warning: run stdout changed" >&2
    exit 1
}
grep -F "[AN0014]" "$TMP/run.err" >/dev/null || {
    echo "annotations warning: missing AN0014 on run stderr" >&2
    cat "$TMP/run.err" >&2
    exit 1
}
grep -F "[AN0015]" "$TMP/run.err" >/dev/null || {
    echo "annotations warning: missing AN0015 on run stderr" >&2
    cat "$TMP/run.err" >&2
    exit 1
}

echo "annotations warning: PASS (stderr warnings; stdout/exit unchanged)"
