#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
package xdk2.websocket
import xdk.net.websocket
import xdk.net
import xdk.net.uri
import xdk.errors

static Int main(String[] args) {
    String name = args.get(0)
    Context context = Context.background()
    if name == "optionsFrame" {
        WebSocketOptions value = new WebSocketOptions()
        value.maxFrameBytes(0)
    } else if name == "optionsMessage" {
        WebSocketOptions value = new WebSocketOptions()
        value.maxMessageBytes(0)
    } else if name == "optionsQueue" {
        WebSocketOptions value = new WebSocketOptions()
        value.maxSendQueueBytes(0)
    } else if name == "optionsPing" {
        WebSocketOptions value = new WebSocketOptions()
        value.pingIntervalMillis(-1 as Long)
    } else if name == "optionsPong" {
        WebSocketOptions value = new WebSocketOptions()
        value.pongTimeoutMillis(-1 as Long)
    } else if name == "optionsHeaders" {
        WebSocketOptions value = new WebSocketOptions()
        value.headers(null)
    } else if name == "optionsProtocols" {
        WebSocketOptions value = new WebSocketOptions()
        value.subprotocols(null)
    } else if name == "messageText" {
        WebSocketMessage value = WebSocketMessage.fromText(null)
    } else if name == "messageBinary" {
        WebSocketMessage value = WebSocketMessage.fromBinary(null)
    } else if name == "messageClose" {
        WebSocketMessage value = WebSocketMessage.fromClose(WebSocketCloseCode.Normal, null)
    } else if name == "connectContext" {
        Result<WebSocket, Error> value = WebSocket.connect(null,
            Uri.parse("ws://127.0.0.1:1/").value(), new WebSocketOptions())
    } else if name == "connectUri" {
        Result<WebSocket, Error> value = WebSocket.connect(context, null, new WebSocketOptions())
    } else if name == "connectOptions" {
        Result<WebSocket, Error> value = WebSocket.connect(context,
            Uri.parse("ws://127.0.0.1:1/").value(), null)
    } else if name == "serverBind" {
        Result<WebSocketServer, Error> value = WebSocketServer.bind(context, null, new WebSocketOptions())
    } else if name == "serverOptions" {
        Result<WebSocketServer, Error> value = WebSocketServer.bind(context,
            SocketAddress.parse("127.0.0.1:19999").value(), null)
    } else if name == "serverServe" {
        WebSocketServer server = WebSocketServer.bind(context,
            SocketAddress.parse("127.0.0.1:19999").value(), new WebSocketOptions()).value()
        Result<Unit, Error> value = server.serve(context, null)
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || { cat "$TMP/build.err" >&2; exit 1; }
check_panic() {
    name=$1
    marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && { echo "websocket panic: $name did not fail" >&2; exit 1; }
    grep -Fq "$marker" "$TMP/$name.err" || { echo "websocket panic: $name missing '$marker'" >&2; cat "$TMP/$name.err" >&2; exit 1; }
}
check_panic optionsFrame "WebSocketOptions.maxFrameBytes: must be positive"
check_panic optionsMessage "WebSocketOptions.maxMessageBytes: must be positive"
check_panic optionsQueue "WebSocketOptions.maxSendQueueBytes: must be positive"
check_panic optionsPing "WebSocketOptions.pingIntervalMillis: negative"
check_panic optionsPong "WebSocketOptions.pongTimeoutMillis: negative"
check_panic optionsHeaders "WebSocketOptions.headers: null"
check_panic optionsProtocols "WebSocketOptions.subprotocols: null"
check_panic messageText "WebSocketMessage.text: null"
check_panic messageBinary "WebSocketMessage.binary: null"
check_panic messageClose "WebSocketMessage.close: null reason"
check_panic connectContext "WebSocket.connect: null argument"
check_panic connectUri "WebSocket.connect: null argument"
check_panic connectOptions "WebSocket.connect: null argument"
check_panic serverBind "WebSocketServer.bind: null argument"
check_panic serverOptions "WebSocketServer.bind: null argument"
check_panic serverServe "WebSocketServer.serve: null argument"
echo "websocket_panic: PASS"
