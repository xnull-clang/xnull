#!/bin/sh
set -u
BIN=${BIN:-/tmp/xnull-entry-qa}
export XNULL_RUNTIME=${XNULL_RUNTIME:-/private/tmp/qa-m1-main/impl/runtime}
EV=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
: > "$EV/out/matrix.tsv"
while IFS= read -r f; do
  [ -z "$f" ] && continue
  for mode in interp compiled; do
    if [ "$mode" = interp ]; then
      "$BIN" run --interp "$EV/cases/$f.x" > "$EV/out/$f.$mode.out" 2> "$EV/out/$f.$mode.err"
    else
      "$BIN" run "$EV/cases/$f.x" > "$EV/out/$f.$mode.out" 2> "$EV/out/$f.$mode.err"
    fi
    rc=$?
    printf '%s\t%s\t%s\t%s\n' "$f" "$mode" "$rc" "$(tr '\n' '|' < "$EV/out/$f.$mode.err")" >> "$EV/out/matrix.tsv"
    printf '%-24s %-8s rc=%-3s out=%q err=%q\n' "$f" "$mode" "$rc" "$(cat "$EV/out/$f.$mode.out")" "$(tr '\n' '|' < "$EV/out/$f.$mode.err")"
  done
done < "$EV/cases.txt"
