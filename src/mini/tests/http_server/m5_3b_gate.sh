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

# C-0101: build before starting the network fixture.
"$ROOT/src/cli/xnull" --bootstrap --engine=mini build "$HERE/server.x" -o "$TMP/server" >"$TMP/build.log" 2>&1

PORT=$(python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)

"$TMP/server" "$PORT" 7 "$TMP/ready" >"$TMP/server.out" 2>"$TMP/server.err" &
SERVER=$!
i=0
while [ ! -s "$TMP/ready" ] && [ "$i" -lt 100 ]; do
    i=$((i + 1))
    sleep 0.1
done
if [ ! -s "$TMP/ready" ]; then
    echo "http_server: server did not become ready" >&2
    cat "$TMP/server.out" >&2 || true
    cat "$TMP/server.err" >&2 || true
    exit 1
fi

(sleep 20; kill "$SERVER" 2>/dev/null || true) &
WATCH=$!
python3 "$HERE/client_fixture.py" "$PORT" >"$TMP/client.out" 2>"$TMP/client.err"
set +e
wait "$SERVER"
SERVER_STATUS=$?
set -e
SERVER=""
kill "$WATCH" 2>/dev/null || true
WATCH=""
if [ "$SERVER_STATUS" -ne 0 ]; then
    echo "http_server: server exited $SERVER_STATUS" >&2
    cat "$TMP/server.out" >&2 || true
    cat "$TMP/server.err" >&2 || true
    exit 1
fi
diff -u "$HERE/client_fixture.out" "$TMP/client.out"
diff -u "$HERE/server.out" "$TMP/server.out"
echo "http_server: PASS"
