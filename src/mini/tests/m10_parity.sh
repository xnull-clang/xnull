#!/bin/sh
# XDK-W6 T0 conformance matrix: every T0 package in base and full Sys modes.
#
# Differential cases compare mini vs legacy in both modes. Mini-only cases
# (recorded legacy gaps) still assert base/full mode parity. Projects cover
# the resource base/full/cancel surfaces.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT

run_file() {
    file=$1 engine=$2 mode=$3 out=$4
    if [ "$mode" = full ]; then
        XNULL_MINI_XDK_FULL=1 "$XNULL" --bootstrap --engine="$engine" run "$HERE/$file" >"$out" 2>"$out.err" || {
            cat "$out.err" >&2; exit 1
        }
    else
        XNULL_MINI_XDK_FULL=0 "$XNULL" --bootstrap --engine="$engine" run "$HERE/$file" >"$out" 2>"$out.err" || {
            cat "$out.err" >&2; exit 1
        }
    fi
}

check_differential() {
    file=$1
    key=$(printf '%s' "$file" | tr '/.' '__')
    run_file "$file" mini base "$D/$key.mini.base"
    run_file "$file" mini full "$D/$key.mini.full"
    run_file "$file" legacy base "$D/$key.legacy.base"
    run_file "$file" legacy full "$D/$key.legacy.full"
    cmp "$D/$key.mini.base" "$D/$key.mini.full" || { echo "mode mismatch: $file mini" >&2; exit 1; }
    cmp "$D/$key.legacy.base" "$D/$key.legacy.full" || { echo "mode mismatch: $file legacy" >&2; exit 1; }
    cmp "$D/$key.mini.base" "$D/$key.legacy.base" || { echo "engine mismatch: $file base" >&2; exit 1; }
    cmp "$D/$key.mini.full" "$D/$key.legacy.full" || { echo "engine mismatch: $file full" >&2; exit 1; }
    echo "PASS $file [mini+legacy, base+full]"
}

check_mini_only() {
    file=$1
    key=$(printf '%s' "$file" | tr '/.' '__')
    run_file "$file" mini base "$D/$key.mini.base"
    run_file "$file" mini full "$D/$key.mini.full"
    cmp "$D/$key.mini.base" "$D/$key.mini.full" || { echo "mode mismatch: $file mini" >&2; exit 1; }
    echo "PASS $file [mini, base+full]"
}

# Differential T0 file scenarios.
for f in xdk_errors.x xdk_meta.x xdk_runtime.x \
         xdk_bytes.x xdk_bytes_extra.x xdk_text.x xdk_text_full.x \
         xdk_math.x xdk_time.x xdk_io.x xdk_fs.x xdk_sys.x \
         xdk_sync_atomic.x xdk_sync_ref.x xdk_mutex.x \
         xdk_collections.x xdk_integration.x xdk_log.x; do
    check_differential "$f"
done

# Config reads an allowlisted environment variable.
XDK_W5_NAME=from-env
export XDK_W5_NAME
run_file xdk_config.x mini base "$D/cfg.mini.base"
run_file xdk_config.x mini full "$D/cfg.mini.full"
run_file xdk_config.x legacy base "$D/cfg.legacy.base"
run_file xdk_config.x legacy full "$D/cfg.legacy.full"
unset XDK_W5_NAME
cmp "$D/cfg.mini.base" "$D/cfg.mini.full"
cmp "$D/cfg.legacy.base" "$D/cfg.legacy.full"
cmp "$D/cfg.mini.base" "$D/cfg.legacy.base"
cmp "$D/cfg.mini.full" "$D/cfg.legacy.full"
echo "PASS xdk_config.x [mini+legacy, base+full]"

# Mini-only scenarios with recorded legacy gaps.
for f in xdk_tasks.x xdk_cancel.x xdk_channel.x xdk_collections_algo.x; do
    check_mini_only "$f"
done

# CLI takes real argv.
for mode in base full; do
    if [ "$mode" = full ]; then
        XNULL_MINI_XDK_FULL=1 "$XNULL" --bootstrap --engine=mini build "$HERE/xdk_cli.x" -o "$D/cli.$mode" >"$D/cli.$mode.build" 2>&1
    else
        XNULL_MINI_XDK_FULL=0 "$XNULL" --bootstrap --engine=mini build "$HERE/xdk_cli.x" -o "$D/cli.$mode" >"$D/cli.$mode.build" 2>&1
    fi
    "$D/cli.$mode" --name Alpha pos1 -v >"$D/cli.$mode.out" 2>"$D/cli.$mode.err" || {
        cat "$D/cli.$mode.err" >&2; exit 1
    }
done
cmp "$D/cli.base.out" "$D/cli.full.out"
echo "PASS xdk_cli.x [mini, base+full, argv]"

# Resource projects: base surface, full surface (differential), cancel path.
XNULL_MINI_XDK_FULL=0 "$XNULL" --bootstrap --engine=mini run-project "$HERE/resources" >"$D/res.base.mini" 2>"$D/res.base.err"
XNULL_MINI_XDK_FULL=0 "$XNULL" --bootstrap --engine=legacy run-project "$HERE/resources" >"$D/res.base.legacy" 2>"$D/res.base.err"
cmp "$D/res.base.mini" "$D/res.base.legacy"

XNULL_MINI_XDK_FULL=1 "$XNULL" --bootstrap --engine=mini run-project "$HERE/resources_full" >"$D/res.full.mini" 2>"$D/res.full.err"
XNULL_MINI_XDK_FULL=1 "$XNULL" --bootstrap --engine=legacy run-project "$HERE/resources_full" >"$D/res.full.legacy" 2>"$D/res.full.err"
cmp "$D/res.full.mini" "$D/res.full.legacy"

XNULL_MINI_XDK_FULL=1 "$XNULL" --bootstrap --engine=mini run-project "$HERE/resources_cancel" >"$D/res.cancel.mini" 2>"$D/res.cancel.err"
echo "PASS resources [base/full/cancel]"

echo "m10 parity: PASS"
