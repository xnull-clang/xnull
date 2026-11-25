package xdk2.jsonrpc
import xdk.jsonrpc
import xdk.codec
import xdk.errors

class FakePeer implements JsonRpcPeer {
    Bool open
    Int requests
    Int notifications
    Int responses

    FakePeer() {
        self.open = true
        self.requests = 0
        self.notifications = 0
        self.responses = 0
    }

    Result<JsonValue, Error> request(Context context, JsonRpcRequest request) {
        self.requests = self.requests + 1
        return Ok(Json.string("result"))
    }

    Result<Unit, Error> notify(Context context, JsonRpcRequest request) {
        self.notifications = self.notifications + 1
        return Ok()
    }

    Result<Unit, Error> respond(Context context, JsonRpcResponse response) {
        self.responses = self.responses + 1
        return Ok()
    }

    Result<Unit, Error> close() {
        self.open = false
        return Ok()
    }

    Bool isOpen() { return self.open }
}

static Int main() {
    JsonRpcId textId = JsonRpcId.ofText("req-1")
    JsonRpcId numberId = JsonRpcId.ofNumber(42 as Long)
    JsonRpcId parsedText = JsonRpcId.parse(textId.toJson()).value()
    JsonRpcId parsedNumber = JsonRpcId.parse(numberId.toJson()).value()
    print("id=" + str(textId.isText()) + "," + str(numberId.isInteger()) + "," +
        textId.textValue() + "," + str(numberId.numberValue()) + "," +
        textId.wireText() + "," + numberId.wireText() + "," +
        str(parsedText.equals(textId)) + "," + str(parsedNumber.equals(numberId)) + "," +
        str(textId.equals(numberId)) + "," + textId.describe())
    print("id-parse-invalid=" +
        errorKindName(JsonRpcId.parse(Json.number("1.5")).error().kind()) + "," +
        errorKindName(JsonRpcId.parse(Json.bool(true)).error().kind()) + "," +
        errorKindName(JsonRpcId.parse(Json.nullValue()).error().kind()))

    JsonRpcError parseError = JsonRpcError.parseError("bad")
    JsonRpcError invalidParams = JsonRpcError.invalidParams("name")
    JsonRpcError internal = JsonRpcError.internalError("boom")
    JsonRpcError withData = new JsonRpcError(-32020, "Header mismatch", Json.string("x"))
    JsonRpcError parsedError = JsonRpcError.parse(parseError.toJson()).value()
    print("error=" + str(parseError.code()) + "," + parseError.message() + "," +
        str(invalidParams.code()) + "," + str(internal.code()) + "," +
        str(withData.hasData()) + "," + str(parsedError.equals(parseError)) + "," +
        parseError.describe() + "," + str(withData.data() != null))
    print("error-invalid=" +
        errorKindName(JsonRpcError.parse(Json.object()).error().kind()) + "," +
        errorKindName(JsonRpcError.parse(Json.string("x")).error().kind()))

    JsonRpcRequest notification = JsonRpcRequest.notification("ping")
    JsonRpcRequest request = JsonRpcRequest.request(numberId, "add")
    JsonValue params = Json.object()
    JsonRpcRequest withParams = JsonRpcRequest.requestWithParams(textId, "echo", params)
    JsonRpcRequest converted = notification.withId(textId)
    JsonRpcRequest parsedRequest = JsonRpcRequest.parse(request.toJson()).value()
    JsonRpcRequest parsedParams = JsonRpcRequest.parse(withParams.toJson()).value()
    print("request=" + str(notification.isNotification()) + "," +
        str(notification.hasIdentifier()) + "," + str(request.hasIdentifier()) + "," +
        request.method() + "," + str(notification.hasParams()) + "," +
        str(withParams.hasParams()) + "," + str(parsedRequest.equals(request)) + "," +
        str(parsedParams.equals(withParams)) + "," +
        str(converted.hasIdentifier()) + "," + str(converted.identifier() != null))
    JsonValue badParamsRequest = Json.object()
    JsonObject badParamsObject = badParamsRequest.asObject() as JsonObject
    badParamsObject.set("jsonrpc", Json.string("2.0"))
    badParamsObject.set("method", Json.string("echo"))
    badParamsObject.set("params", Json.string("bad"))
    print("request-invalid=" +
        errorKindName(JsonRpcRequest.parse(badParamsRequest).error().kind()) + "," +
        errorKindName(JsonRpcRequest.parse(Json.object()).error().kind()) + "," +
        errorKindName(JsonRpcRequest.parse(Json.string("x")).error().kind()))

    JsonRpcResponse success = JsonRpcResponse.success(numberId, Json.string("ok"))
    JsonRpcResponse failure = JsonRpcResponse.failure(null, JsonRpcError.methodNotFound("x"))
    JsonRpcResponse parsedSuccess = JsonRpcResponse.parse(success.toJson()).value()
    JsonRpcResponse parsedFailure = JsonRpcResponse.parse(failure.toJson()).value()
    print("response=" + str(success.isSuccess()) + "," + str(failure.isSuccess()) + "," +
        str(success.hasResult()) + "," + str(success.hasIdentifier()) + "," +
        str(failure.hasIdentifier()) + "," + str(success.errorOrNull() == null) + "," +
        str(failure.resultOrNull() == null) + "," + str(parsedSuccess.equals(success)) +
        "," + str(parsedFailure.equals(failure)) + "," + success.describe() + "," +
        failure.describe())

    JsonValue both = Json.object()
    JsonObject bothObject = both.asObject() as JsonObject
    bothObject.set("jsonrpc", Json.string("2.0"))
    bothObject.set("id", Json.number("1"))
    bothObject.set("result", Json.string("ok"))
    bothObject.set("error", JsonRpcError.internalError("x").toJson())
    JsonValue neither = Json.object()
    JsonObject neitherObject = neither.asObject() as JsonObject
    neitherObject.set("jsonrpc", Json.string("2.0"))
    neitherObject.set("id", Json.number("1"))
    print("response-invalid=" +
        errorKindName(JsonRpcResponse.parse(both).error().kind()) + "," +
        errorKindName(JsonRpcResponse.parse(neither).error().kind()) + "," +
        errorKindName(JsonRpcResponse.parse(Json.string("x")).error().kind()))

    String requestJson = Json.stringify(withParams.toJson())
    JsonValue reparsed = Json.parse(requestJson).value()
    JsonRpcRequest roundTrip = JsonRpcRequest.parse(reparsed).value()
    print("roundtrip=" + requestJson + "," + str(roundTrip.equals(withParams)) + "," +
        str(Json.stringify(success.toJson()).length() > 0))

    FakePeer peer = new FakePeer()
    Context context = Context.background()
    Result<JsonValue, Error> peerRequest = peer.request(context, request)
    Result<Unit, Error> peerNotify = peer.notify(context, notification)
    Result<Unit, Error> peerRespond = peer.respond(context, success)
    print("peer=" + str(peerRequest.isOk()) + "," +
        (peerRequest.value().asString() as String) + "," + str(peerNotify.isOk()) + "," +
        str(peerRespond.isOk()) + "," + str(peer.isOpen()) + "," +
        str(peer.requests) + "," + str(peer.notifications) + "," + str(peer.responses))
    Result<Unit, Error> peerClose = peer.close()
    print("peer-close=" + str(peerClose.isOk()) + "," + str(peer.isOpen()))
    return 0
}
