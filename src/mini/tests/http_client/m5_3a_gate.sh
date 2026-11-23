#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
TMP=$(mktemp -d)
SERVER=""
WATCH=""
cleanup() {
    if [ -n "$WATCH" ]; then kill "$WATCH" 2>/dev/null || true; fi
    if [ -n "$SERVER" ]; then kill "$SERVER" 2>/dev/null || true; wait "$SERVER" 2>/dev/null || true; fi
    rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

# Compile before starting the fixture so the client binary is stable and the
# server lifetime is only used for the request phase.
"$ROOT/src/cli/xnull" --bootstrap --engine=mini build "$HERE/client.x" -o "$TMP/client" >"$TMP/build.log" 2>&1

python3 "$HERE/server_fixture.py" "$TMP/port" 4 >"$TMP/server.log" 2>&1 &
SERVER=$!
i=0
while [ ! -s "$TMP/port" ] && [ "$i" -lt 100 ]; do
    i=$((i + 1))
    sleep 0.1
done
if [ ! -s "$TMP/port" ]; then
    echo "http_client: fixture did not start" >&2
    cat "$TMP/server.log" >&2 || true
    exit 1
fi
PORT=$(cat "$TMP/port")
REFUSED=$((PORT + 1))

(sleep 20; kill "$SERVER" 2>/dev/null || true) &
WATCH=$!
"$TMP/client" "$PORT" "$REFUSED" >"$TMP/client.out" 2>"$TMP/client.err"
set +e
wait "$SERVER"
SERVER_STATUS=$?
set -e
SERVER=""
kill "$WATCH" 2>/dev/null || true
WATCH=""
if [ "$SERVER_STATUS" -ne 0 ]; then
    echo "http_client: fixture exited $SERVER_STATUS" >&2
    cat "$TMP/server.log" >&2 || true
    exit 1
fi
diff -u "$HERE/client.out" "$TMP/client.out"
echo "http_client: PASS"
