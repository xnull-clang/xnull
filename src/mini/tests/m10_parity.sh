#!/bin/sh
# T0 conformance matrix: mini only, base and full Sys modes.
#
# mini is the only compiler. Every scenario runs through it in both modes;
# base/full output must match. Package scenarios with a known blocked feature
# are still listed here as mini-only base/full checks, not as differentials.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT

run_file() {
    file=$1 mode=$2 out=$3
    if [ "$mode" = full ]; then
        XNULL_MINI_XDK_FULL=1 "$XNULL" --bootstrap --engine=mini run "$HERE/$file" >"$out" 2>"$out.err" || {
            cat "$out.err" >&2; exit 1
        }
    else
        XNULL_MINI_XDK_FULL=0 "$XNULL" --bootstrap --engine=mini run "$HERE/$file" >"$out" 2>"$out.err" || {
            cat "$out.err" >&2; exit 1
        }
    fi
}

check_file() {
    file=$1
    key=$(printf '%s' "$file" | tr '/.' '__')
    run_file "$file" base "$D/$key.base"
    run_file "$file" full "$D/$key.full"
    cmp "$D/$key.base" "$D/$key.full" || { echo "mode mismatch: $file" >&2; exit 1; }
    echo "PASS $file [mini, base+full]"
}

for f in xdk_errors.x xdk_errors_full.x xdk_meta.x xdk_runtime.x \
         xdk_bytes.x xdk_bytes_extra.x xdk_bytes_strict.x \
         xdk_text.x xdk_text_full.x xdk_math.x xdk_time.x \
         xdk_io.x xdk_fs.x xdk_sys.x \
         xdk_sync_atomic.x xdk_sync_ref.x xdk_mutex.x \
         xdk_collections.x xdk_collections_algo.x xdk_containers.x \
         xdk_integration.x xdk_log.x \
         xdk_tasks.x xdk_cancel.x xdk_channel.x; do
    check_file "$f"
done

XDK_W5_NAME=from-env
export XDK_W5_NAME
run_file xdk_config.x base "$D/cfg.base"
run_file xdk_config.x full "$D/cfg.full"
unset XDK_W5_NAME
cmp "$D/cfg.base" "$D/cfg.full" || { echo "mode mismatch: xdk_config.x" >&2; exit 1; }
echo "PASS xdk_config.x [mini, base+full]"

# CLI takes real argv.
for mode in base full; do
    if [ "$mode" = full ]; then
        XNULL_MINI_XDK_FULL=1 "$XNULL" --bootstrap --engine=mini build "$HERE/xdk_cli.x" -o "$D/cli.$mode" >"$D/cli.build.$mode" 2>"$D/cli.build.$mode.err" || {
            cat "$D/cli.build.$mode.err" >&2; exit 1
        }
    else
        XNULL_MINI_XDK_FULL=0 "$XNULL" --bootstrap --engine=mini build "$HERE/xdk_cli.x" -o "$D/cli.$mode" >"$D/cli.build.$mode" 2>"$D/cli.build.$mode.err" || {
            cat "$D/cli.build.$mode.err" >&2; exit 1
        }
    fi
    "$D/cli.$mode" --name Alpha pos1 -v >"$D/cli.$mode.out" 2>"$D/cli.$mode.err" || {
        cat "$D/cli.$mode.err" >&2; exit 1
    }
done
cmp "$D/cli.base.out" "$D/cli.full.out" || { echo "mode mismatch: xdk_cli.x" >&2; exit 1; }
printf '4\ntrue\nfalse\nAlpha\nfallback\n1\npos1\nusage: demo --name <name> [files]\n2\n' > "$D/cli.exp"
diff -u "$D/cli.exp" "$D/cli.base.out"
echo "PASS xdk_cli.x [mini, base+full, argv]"

echo "m10 parity: PASS"
