#!/bin/sh
# Regression gate for the B4 generic-instantiation hang.
# The compiler must finish the minimal xdk.functional import under a hard
# timeout and exit 0; the full B4 scenario must at least stop (it may still
# fail on package-level gaps such as a missing Lazy<T>).
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
MINI="$ROOT/src/mini/bin/mini"

python3 - "$MINI" "$HERE/functional_min.x" "$ROOT/src/xdk" \
    "$ROOT/src/mini/tests/xdk2/functional/functional.x" <<'PY'
import subprocess
import sys

mini, minimal, xdk_root, full = sys.argv[1:5]
limit = 30

def run(path):
    return subprocess.run(
        [mini, "--emit-c", path, "--xdk-root", xdk_root],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=limit,
    )

try:
    minimal_run = run(minimal)
except subprocess.TimeoutExpired:
    print(f"compiler hang: minimal scenario exceeded {limit}s", file=sys.stderr)
    sys.exit(1)
if minimal_run.returncode != 0:
    print("compiler hang: minimal scenario failed", file=sys.stderr)
    print(minimal_run.stdout[-2000:], file=sys.stderr)
    print(minimal_run.stderr[-2000:], file=sys.stderr)
    sys.exit(1)
if "int main" not in minimal_run.stdout:
    print("compiler hang: minimal scenario produced no C output", file=sys.stderr)
    sys.exit(1)

try:
    full_run = run(full)
except subprocess.TimeoutExpired:
    print(f"compiler hang: full functional scenario exceeded {limit}s", file=sys.stderr)
    sys.exit(1)
print(f"compiler hang: minimal OK; full functional stopped with rc={full_run.returncode}")
PY

echo "compiler hang: PASS"
