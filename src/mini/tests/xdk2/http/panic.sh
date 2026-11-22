#!/bin/sh
# xdk.net.http contract panics: status range, invalid header/cookie, invalid options/body limits.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/panic.x" <<'X'
import xdk.net.http
static Int main(String[] args) {
    String name = args.get(0)
    if name == "statusLow" {
        HttpStatus.of(99)
    } else if name == "statusHigh" {
        HttpStatus.of(600)
    } else if name == "headerName" {
        HttpHeader bad = new HttpHeader("bad name", "v")
    } else if name == "headerLine" {
        HttpHeader bad = new HttpHeader("X", "a\nb")
    } else if name == "cookieName" {
        Cookie bad = new Cookie("bad name", "v")
    } else if name == "options" {
        HttpServerOptions options = new HttpServerOptions()
        options.maxHeaderBytes(0)
    } else if name == "bodyLimit" {
        HttpBody body = HttpBody.empty()
        body.readAll(-1)
    } else if name == "formName" {
        Form form = new Form()
        form.add("", "x")
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || {
    cat "$TMP/build.err" >&2
    echo "http panic: build failed" >&2
    exit 1
}

check_panic() {
    name=$1
    marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && {
        echo "http panic: $name did not fail" >&2
        exit 1
    }
    grep -q "$marker" "$TMP/$name.err" || {
        echo "http panic: $name missing marker '$marker'" >&2
        cat "$TMP/$name.err" >&2
        exit 1
    }
}

check_panic "statusLow" "HttpStatus.of: invalid code"
check_panic "statusHigh" "HttpStatus.of: invalid code"
check_panic "headerName" "HttpHeader: invalid name"
check_panic "headerLine" "HttpHeader: multiline"
check_panic "cookieName" "Cookie: invalid name"
check_panic "options" "HttpServerOptions.maxHeaderBytes: invalid"
check_panic "bodyLimit" "HttpBody.readAll: negative maximum"
check_panic "formName" "FormEntry: empty name"

echo "http_panic: PASS"
