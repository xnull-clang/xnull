#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
MAIN="$ROOT/src/mini/main.x"

if grep -q 'expandA8Class' "$MAIN"; then
    echo "a8_registry: hardcoded expandA8Class dispatch still present" >&2
    exit 1
fi
grep -q 'protocol A8Processor' "$MAIN"
grep -q 'List<A8Processor> a8Processors()' "$MAIN"
[ "$(grep -c 'new A8.*Processor()' "$MAIN")" -ge 3 ]
grep -q 'new A8CoreProcessor()' "$MAIN"
grep -q 'new A8BuilderProcessor()' "$MAIN"
grep -q 'new A8DelegateProcessor()' "$MAIN"
grep -q 'p.applies(n)' "$MAIN"
grep -q 'p.process(n, program)' "$MAIN"
echo "a8_registry: PASS (3 processors; no expandA8Class dispatch)"
