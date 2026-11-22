#!/bin/sh
# Annotation AST gate: declaration/use/arg nodes are dumped, and @Repeatable
# uses keep source order.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
MINI="$ROOT/src/mini/bin/mini"

dump=$("$MINI" --ast "$HERE/annotations_repeatable.x" --xdk-root "$ROOT/src/xdk")
for needle in "AnnotationDecl: Tag" "AnnotationUse: Tag" "AnnotationArg: 0" \
              "String: \"first\"" "String: \"second\"" "String: \"third\""; do
    printf '%s\n' "$dump" | grep -F "$needle" >/dev/null || {
        echo "annotations ast: missing $needle" >&2
        printf '%s\n' "$dump" >&2
        exit 1
    }
done

first=$(printf '%s\n' "$dump" | grep -n 'String: "first"' | head -1 | cut -d: -f1)
second=$(printf '%s\n' "$dump" | grep -n 'String: "second"' | head -1 | cut -d: -f1)
third=$(printf '%s\n' "$dump" | grep -n 'String: "third"' | head -1 | cut -d: -f1)
[ -n "$first" ] && [ -n "$second" ] && [ -n "$third" ] || {
    echo "annotations ast: repeatable arguments not found" >&2
    exit 1
}
[ "$first" -lt "$second" ] && [ "$second" -lt "$third" ] || {
    echo "annotations ast: @Repeatable order changed" >&2
    exit 1
}

echo "annotations ast: PASS"
