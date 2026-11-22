#!/bin/sh
# Annotation negative gate: each .xn carries a first-line expectation.
#   // expect: fail AN0001
#   // expect: warn AN0014
# Error cases must make `xnull check` fail; warning cases must succeed and
# still print the stable diagnostic code.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"

pass=0
for src in $(find "$HERE/negative" -name '*.xn' | sort); do
    first=$(sed -n '1p' "$src")
    case "$first" in
        "// expect: fail "*)
            mode=fail
            code=${first#// expect: fail }
            ;;
        "// expect: warn "*)
            mode=warn
            code=${first#// expect: warn }
            ;;
        *)
            echo "annotations negative: missing expectation in $src" >&2
            exit 1
            ;;
    esac

    out=$(mktemp)
    set +e
    "$XNULL" --bootstrap --engine=mini check "$src" >"$out" 2>&1
    rc=$?
    set -e

    if [ "$mode" = fail ] && [ "$rc" -eq 0 ]; then
        echo "annotations negative: expected failure for $src" >&2
        cat "$out" >&2
        rm -f "$out"
        exit 1
    fi
    if [ "$mode" = warn ] && [ "$rc" -ne 0 ]; then
        echo "annotations negative: expected warning-only for $src" >&2
        cat "$out" >&2
        rm -f "$out"
        exit 1
    fi
    if ! grep -F "[$code]" "$out" >/dev/null; then
        echo "annotations negative: missing [$code] for $src" >&2
        cat "$out" >&2
        rm -f "$out"
        exit 1
    fi
    rm -f "$out"
    pass=$((pass + 1))
done

[ "$pass" -gt 0 ] || {
    echo "annotations negative: no cases" >&2
    exit 1
}
echo "annotations negative: PASS ($pass case(s))"
