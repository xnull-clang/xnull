#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
package xdk2.jsonrpc
import xdk.jsonrpc
import xdk.codec
import xdk.errors

static Int main(String[] args) {
    String name = args.get(0)
    if name == "idText" {
        JsonRpcId value = JsonRpcId.ofText(null)
    } else if name == "idTextValue" {
        JsonRpcId id = JsonRpcId.ofNumber(1 as Long)
        String value = id.textValue()
    } else if name == "idNumberValue" {
        JsonRpcId id = JsonRpcId.ofText("x")
        Long value = id.numberValue()
    } else if name == "idParse" {
        Result<JsonRpcId, Error> value = JsonRpcId.parse(null)
    } else if name == "errorEmpty" {
        JsonRpcError value = new JsonRpcError(-1, "")
    } else if name == "errorMultiline" {
        JsonRpcError value = new JsonRpcError(-1, "a\nb")
    } else if name == "errorData" {
        JsonRpcError value = new JsonRpcError(-1, "x", null)
    } else if name == "errorParse" {
        Result<JsonRpcError, Error> value = JsonRpcError.parse(null)
    } else if name == "requestMethod" {
        JsonRpcRequest value = JsonRpcRequest.notification("")
    } else if name == "requestId" {
        JsonRpcRequest value = JsonRpcRequest.request(null, "m")
    } else if name == "requestParams" {
        JsonRpcRequest request = JsonRpcRequest.notification("m")
        JsonRpcRequest value = request.withParams(null)
    } else if name == "requestWithId" {
        JsonRpcRequest request = JsonRpcRequest.notification("m")
        JsonRpcRequest value = request.withId(null)
    } else if name == "requestParse" {
        Result<JsonRpcRequest, Error> value = JsonRpcRequest.parse(null)
    } else if name == "responseId" {
        JsonRpcResponse value = JsonRpcResponse.success(null, Json.string("x"))
    } else if name == "responseResult" {
        JsonRpcResponse value = JsonRpcResponse.success(JsonRpcId.ofNumber(1 as Long), null)
    } else if name == "responseError" {
        JsonRpcResponse value = JsonRpcResponse.failure(null, null)
    } else if name == "responseParse" {
        Result<JsonRpcResponse, Error> value = JsonRpcResponse.parse(null)
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || { cat "$TMP/build.err" >&2; exit 1; }
check_panic() {
    name=$1
    marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && { echo "jsonrpc panic: $name did not fail" >&2; exit 1; }
    grep -Fq "$marker" "$TMP/$name.err" || { echo "jsonrpc panic: $name missing '$marker'" >&2; cat "$TMP/$name.err" >&2; exit 1; }
}
check_panic idText "JsonRpcId.ofText: null text"
check_panic idTextValue "JsonRpcId.textValue: not text"
check_panic idNumberValue "JsonRpcId.numberValue: not integer"
check_panic idParse "JsonRpcId.parse: null value"
check_panic errorEmpty "JsonRpcError: empty message"
check_panic errorMultiline "JsonRpcError: multiline message"
check_panic errorData "JsonRpcError: null data"
check_panic errorParse "JsonRpcError.parse: null value"
check_panic requestMethod "JsonRpcRequest: empty method"
check_panic requestId "JsonRpcRequest.request: null identifier"
check_panic requestParams "JsonRpcRequest.withParams: null params"
check_panic requestWithId "JsonRpcRequest.withId: null identifier"
check_panic requestParse "JsonRpcRequest.parse: null value"
check_panic responseId "JsonRpcResponse.success: null identifier"
check_panic responseResult "JsonRpcResponse.success: null result"
check_panic responseError "JsonRpcResponse.failure: null error"
check_panic responseParse "JsonRpcResponse.parse: null value"
echo "jsonrpc_panic: PASS"
