#!/bin/sh
# W6 diagnostic error-code registry: positive gate plus negative fixtures.
# The registry is docs/design/t0/appendices/error-codes.tsv; the checker must
# reject an emitted code that is absent from the registry and a duplicate row.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
CHECK="$ROOT/src/toolchain/check_error_codes.py"
REGISTRY="$ROOT/docs/design/t0/appendices/error-codes.tsv"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT

python3 "$CHECK"

cat > "$D/unregistered.x" <<'X'
static Void emit() {
    self.fail("SEM-999", "unregistered fixture", null)
}
X
if python3 "$CHECK" --source "$D/unregistered.x" >"$D/unregistered.out" 2>&1; then
    echo "expected an unregistered error code to fail" >&2
    cat "$D/unregistered.out" >&2
    exit 1
fi
grep -q 'unregistered error code: SEM-999' "$D/unregistered.out"

cp "$REGISTRY" "$D/duplicate.tsv"
printf 'SEM-001\tSEM\tmini/compiler\terror\tDuplicate fixture\tactive\n' >> "$D/duplicate.tsv"
if python3 "$CHECK" --registry "$D/duplicate.tsv" >"$D/duplicate.out" 2>&1; then
    echo "expected a duplicate error code to fail" >&2
    cat "$D/duplicate.out" >&2
    exit 1
fi
grep -q 'duplicate error code: SEM-001' "$D/duplicate.out"

cp "$REGISTRY" "$D/namespace.tsv"
printf 'CLI-777\tSEM\txnull/cli\terror\tNamespace fixture\tactive\n' >> "$D/namespace.tsv"
if python3 "$CHECK" --registry "$D/namespace.tsv" >"$D/namespace.out" 2>&1; then
    echo "expected a namespace mismatch to fail" >&2
    cat "$D/namespace.out" >&2
    exit 1
fi
grep -q 'does not match namespace' "$D/namespace.out"

echo "mini error codes: PASS"
