#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
package xdk2.net
import xdk.net
import xdk.errors

static Int main(String[] args) {
    String name = args.get(0)
    Context context = Context.background()
    IpAddress loopback = IpAddress.loopback(IpFamily.V4)
    SocketAddress address = new SocketAddress(loopback, 19020)
    if name == "parseNull" {
        Result<IpAddress, Error> value = IpAddress.parse(null)
    } else if name == "fromBytesNull" {
        IpAddress value = IpAddress.fromBytes(null)
    } else if name == "fromBytesLength" {
        IpAddress value = IpAddress.fromBytes(Bytes.alloc(5))
    } else if name == "prefixNull" {
        IpPrefix value = new IpPrefix(null, 8)
    } else if name == "prefixRange" {
        IpPrefix value = new IpPrefix(loopback, 33)
    } else if name == "addressNull" {
        SocketAddress value = new SocketAddress(null, 80)
    } else if name == "addressPort" {
        SocketAddress value = new SocketAddress(loopback, 70000)
    } else if name == "connectNullContext" {
        Result<TcpStream, Error> value = TcpStream.connect(null, address)
    } else if name == "connectNullAddress" {
        Result<TcpStream, Error> value = TcpStream.connect(context, null)
    } else if name == "connectHostNull" {
        Result<TcpStream, Error> value = TcpStream.connectHost(context, null, 80)
    } else if name == "bindNull" {
        Result<TcpListener, Error> value = TcpListener.bind(context, null)
    } else if name == "acceptNull" {
        TcpListener listener = TcpListener.bind(context, address).value()
        Result<TcpStream, Error> value = listener.accept(null)
    } else if name == "optionsBacklog" {
        TcpServerOptions options = new TcpServerOptions()
        options.backlog(0)
    } else if name == "serverBindNull" {
        Result<TcpServer, Error> value = TcpServer.bind(context, null)
    } else if name == "serverOptionsNull" {
        Result<TcpServer, Error> value = TcpServer.bindWithOptions(context, address, null)
    } else if name == "serveNull" {
        TcpServer server = TcpServer.bind(context, address).value()
        Result<Unit, Error> value = server.serve(context, null)
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || { cat "$TMP/build.err" >&2; exit 1; }
check_panic() {
    name=$1
    marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && { echo "net panic: $name did not fail" >&2; exit 1; }
    grep -Fq "$marker" "$TMP/$name.err" || { echo "net panic: $name missing '$marker'" >&2; cat "$TMP/$name.err" >&2; exit 1; }
}
check_panic parseNull "IpAddress.parse: null text"
check_panic fromBytesNull "IpAddress.fromBytes: null bytes"
check_panic fromBytesLength "IpAddress.fromBytes: invalid length"
check_panic prefixNull "IpPrefix: null address"
check_panic prefixRange "IpPrefix: prefix length out of range"
check_panic addressNull "SocketAddress: null address"
check_panic addressPort "SocketAddress: port out of range"
check_panic connectNullContext "TcpStream.connect: null argument"
check_panic connectNullAddress "TcpStream.connect: null argument"
check_panic connectHostNull "TcpStream.connectHost: null argument"
check_panic bindNull "TcpListener.bind: null argument"
check_panic acceptNull "TcpListener.accept: null context"
check_panic optionsBacklog "TcpServerOptions.backlog: must be positive"
check_panic serverBindNull "TcpServer.bind: null argument"
check_panic serverOptionsNull "TcpServer.bind: null argument"
check_panic serveNull "TcpServer.serve: null argument"
echo "net_panic: PASS"
