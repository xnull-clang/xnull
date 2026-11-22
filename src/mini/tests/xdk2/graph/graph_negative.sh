#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/unknown.x" <<'X'
import xdk.graph
static Int main() {
    Graph<String> g = new Graph<String>()
    g.addNode("a")
    g.addEdge(new GraphEdge<String>("a", "b", 1.0))
    return 0
}
X
if "$XNULL" --bootstrap --engine=mini run "$TMP/unknown.x" >"$TMP/out" 2>"$TMP/err"; then
    echo "graph_negative: unknown endpoint accepted" >&2
    exit 1
fi
grep -q 'unknown endpoint' "$TMP/err"
cat > "$TMP/dup.x" <<'X'
import xdk.graph
static Int main() {
    Graph<Int> g = new Graph<Int>()
    g.addNode(1)
    g.addNode(2)
    g.addEdge(new GraphEdge<Int>(1, 2, 1.0))
    g.addEdge(new GraphEdge<Int>(1, 2, 2.0))
    return 0
}
X
if "$XNULL" --bootstrap --engine=mini run "$TMP/dup.x" >"$TMP/out2" 2>"$TMP/err2"; then
    echo "graph_negative: duplicate ordered pair accepted" >&2
    exit 1
fi
grep -q 'duplicate ordered pair' "$TMP/err2"
echo "graph_negative: PASS"
