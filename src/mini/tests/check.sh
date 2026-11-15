#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
"$ROOT/src/cli/xnull" --bootstrap --engine=mini check "$HERE/xdk_errors.x" >/tmp/mini-check.out 2>/tmp/mini-check.err || {
    cat /tmp/mini-check.err >&2
    exit 1
}
grep -q '^sema ok$' /tmp/mini-check.out
printf 'static Int main() { return missing }\n' > /tmp/mini-check-bad.x
if "$ROOT/src/cli/xnull" --bootstrap --engine=mini check /tmp/mini-check-bad.x >/tmp/mini-check.out 2>/tmp/mini-check.err; then
    echo "expected check failure" >&2
    exit 1
fi
grep -q 'SEM-001' /tmp/mini-check.err

"$ROOT/src/cli/xnull" --bootstrap --engine=mini check "$HERE/xdk_errors.x" --json >/tmp/mini-check.out 2>/tmp/mini-check.err
grep -q '"ok":true' /tmp/mini-check.out
if "$ROOT/src/cli/xnull" --bootstrap --engine=mini check /tmp/mini-check-bad.x --json >/tmp/mini-check.out 2>/tmp/mini-check.err; then
    echo "expected json check failure" >&2
    exit 1
fi
grep -q '"ok":false' /tmp/mini-check.out

echo "mini check: PASS"
