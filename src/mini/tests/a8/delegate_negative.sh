#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
XNULL="$ROOT/src/cli/xnull"

case_fail() {
    file="$1"
    expected="$2"
    if "$XNULL" --bootstrap --engine=mini run "$HERE/$file" >/tmp/a8_delegate.out 2>/tmp/a8_delegate.err; then
        echo "delegate_negative: $file compiled" >&2
        exit 1
    fi
    grep -q "$expected" /tmp/a8_delegate.err
}
case_fail delegate_missing.x 'AN0027'
case_fail delegate_generic.x 'AN0028'
case_fail delegate_conflict.x 'AN0026'
case_fail delegate_two.x 'AN0026'
echo "delegate_negative: PASS"
