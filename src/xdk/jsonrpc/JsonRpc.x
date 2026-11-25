// xdk.jsonrpc —— JSON-RPC 2.0 消息与 peer 协议（M22.2）
//
// 实现 Id/Error/Request/Response/Peer；不做传输、连接、批处理。
package xdk.jsonrpc
import xdk.errors
import xdk.codec

// ---------- JsonRpcId ----------
class JsonRpcId {
    final Bool _textKind
    final String _text
    final Long _number

    private JsonRpcId(Bool textKind, String text, Long number) {
        self._textKind = textKind
        self._text = text
        self._number = number
    }

    static JsonRpcId ofText(String value) {
        if value == null { throw "JsonRpcId.ofText: null text" }
        return new JsonRpcId(true, value, 0 as Long)
    }

    static JsonRpcId ofNumber(Long value) {
        return new JsonRpcId(false, "", value)
    }

    static Result<JsonRpcId, Error> parse(JsonValue value) {
        if value == null { throw "JsonRpcId.parse: null value" }
        if value.isString() {
            String text = value.asString() as String
            return Ok(JsonRpcId.ofText(text))
        }
        if value.isNumber() {
            JsonNumber number = value.asNumber() as JsonNumber
            if !number.isInteger() {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "JsonRpcId: fractional number"))
            }
            Result<Long, Error> parsed = number.asLong()
            if parsed.isErr() { return Err(parsed.error()) }
            return Ok(JsonRpcId.ofNumber(parsed.value()))
        }
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "JsonRpcId: expected string or integer"))
    }

    Bool isText() { return self._textKind }
    Bool isInteger() { return !self._textKind }

    String textValue() {
        if !self._textKind { throw "JsonRpcId.textValue: not text" }
        return self._text
    }

    Long numberValue() {
        if self._textKind { throw "JsonRpcId.numberValue: not integer" }
        return self._number
    }

    String wireText() {
        if self._textKind { return self._text }
        return str(self._number)
    }

    JsonValue toJson() {
        if self._textKind { return Json.string(self._text) }
        return Json.number(str(self._number))
    }

    Bool equals(JsonRpcId other) {
        if other == null { return false }
        if self._textKind != other.isText() { return false }
        if self._textKind { return self._text == other.textValue() }
        return self._number == other.numberValue()
    }

    String describe() {
        if self._textKind { return "id:\"" + self._text + "\"" }
        return "id:" + str(self._number)
    }

    String toString() { return self.describe() }
}

// ---------- JsonRpcError ----------
class JsonRpcError {
    final Int _code
    final String _message
    final JsonValue? _data

    JsonRpcError(Int code, String message) {
        if message == null || message == "" {
            throw "JsonRpcError: empty message"
        }
        if message.indexOf("\n") >= 0 || message.indexOf("\r") >= 0 {
            throw "JsonRpcError: multiline message"
        }
        self._code = code
        self._message = message
        self._data = null
    }

    JsonRpcError(Int code, String message, JsonValue data) {
        if message == null || message == "" {
            throw "JsonRpcError: empty message"
        }
        if message.indexOf("\n") >= 0 || message.indexOf("\r") >= 0 {
            throw "JsonRpcError: multiline message"
        }
        if data == null { throw "JsonRpcError: null data" }
        self._code = code
        self._message = message
        self._data = data
    }

    static JsonRpcError fromCode(Int code, String message) {
        return new JsonRpcError(code, message)
    }

    static JsonRpcError fromCodeWithData(Int code, String message, JsonValue data) {
        return new JsonRpcError(code, message, data)
    }

    static JsonRpcError parseError(String detail) {
        return new JsonRpcError(-32700, JsonRpcError.appendDetail("Parse error", detail))
    }

    static JsonRpcError invalidRequest(String detail) {
        return new JsonRpcError(-32600, JsonRpcError.appendDetail("Invalid Request", detail))
    }

    static JsonRpcError methodNotFound(String method) {
        return new JsonRpcError(-32601, JsonRpcError.appendDetail("Method not found", method))
    }

    static JsonRpcError invalidParams(String detail) {
        return new JsonRpcError(-32602, JsonRpcError.appendDetail("Invalid params", detail))
    }

    static JsonRpcError internalError(String detail) {
        return new JsonRpcError(-32603, JsonRpcError.appendDetail("Internal error", detail))
    }

    static JsonRpcError serverError(Int code, String message) {
        return new JsonRpcError(code, message)
    }

    static String appendDetail(String base, String detail) {
        if detail == null || detail == "" { return base }
        return base + ": " + detail
    }

    Int code() { return self._code }
    String message() { return self._message }
    JsonValue? data() { return self._data }
    Bool hasData() { return self._data != null }

    JsonRpcError withData(JsonValue data) {
        return new JsonRpcError(self._code, self._message, data)
    }

    JsonValue toJson() {
        JsonValue value = Json.object()
        JsonObject object = value.asObject() as JsonObject
        object.set("code", Json.number(str(self._code)))
        object.set("message", Json.string(self._message))
        if self._data != null {
            object.set("data", self._data as JsonValue)
        }
        return value
    }

    static Result<JsonRpcError, Error> parse(JsonValue value) {
        if value == null { throw "JsonRpcError.parse: null value" }
        if !value.isObject() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "JsonRpcError: not an object"))
        }
        JsonObject object = value.asObject() as JsonObject
        JsonValue? codeValue = object.getOrNull("code")
        if codeValue == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "JsonRpcError: invalid code"))
        }
        JsonValue actualCode = codeValue as JsonValue
        if !actualCode.isNumber() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "JsonRpcError: invalid code"))
        }
        JsonNumber number = actualCode.asNumber() as JsonNumber
        if !number.isInteger() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "JsonRpcError: invalid code"))
        }
        Result<Long, Error> codeLong = number.asLong()
        if codeLong.isErr() || codeLong.value() < -2147483648 as Long ||
            codeLong.value() > 2147483647 as Long {
            return Err(new BasicError(ErrorKind.InvalidArgument, "JsonRpcError: code out of range"))
        }
        JsonValue? messageValue = object.getOrNull("message")
        if messageValue == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "JsonRpcError: invalid message"))
        }
        JsonValue actualMessage = messageValue as JsonValue
        if !actualMessage.isString() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "JsonRpcError: invalid message"))
        }
        String message = actualMessage.asString() as String
        if message == "" || message.indexOf("\n") >= 0 || message.indexOf("\r") >= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "JsonRpcError: invalid message"))
        }
        JsonValue? data = object.getOrNull("data")
        if data == null {
            return Ok(new JsonRpcError(codeLong.value() as Int, message))
        }
        return Ok(new JsonRpcError(codeLong.value() as Int, message, data))
    }

    Bool equals(JsonRpcError other) {
        if other == null { return false }
        if self._code != other.code() || self._message != other.message() { return false }
        if self._data == null { return other.data() == null }
        if other.data() == null { return false }
        JsonValue left = self._data as JsonValue
        JsonValue right = other.data() as JsonValue
        return Json.stringify(left) == Json.stringify(right)
    }

    String describe() { return str(self._code) + " " + self._message }
}

// ---------- JsonRpcRequest ----------
class JsonRpcRequest {
    final JsonRpcId? _identifier
    final String _method
    final JsonValue? _parameters

    private JsonRpcRequest(JsonRpcId? identifier, String method, JsonValue? parameters) {
        if method == null || method == "" {
            throw "JsonRpcRequest: empty method"
        }
        if parameters != null {
            JsonValue actualParams = parameters as JsonValue
            if !actualParams.isObject() && !actualParams.isArray() {
                throw "JsonRpcRequest: params must be object or array"
            }
        }
        self._identifier = identifier
        self._method = method
        self._parameters = parameters
    }

    static JsonRpcRequest notification(String method) {
        return new JsonRpcRequest(null, method, null)
    }

    static JsonRpcRequest notificationWithParams(String method, JsonValue params) {
        return new JsonRpcRequest(null, method, params)
    }

    static JsonRpcRequest request(JsonRpcId identifier, String method) {
        if identifier == null { throw "JsonRpcRequest.request: null identifier" }
        return new JsonRpcRequest(identifier, method, null)
    }

    static JsonRpcRequest requestWithParams(JsonRpcId identifier, String method,
                                            JsonValue params) {
        if identifier == null { throw "JsonRpcRequest.request: null identifier" }
        return new JsonRpcRequest(identifier, method, params)
    }

    JsonRpcId? identifier() { return self._identifier }
    Bool hasIdentifier() { return self._identifier != null }
    Bool isNotification() { return self._identifier == null }
    String method() { return self._method }
    JsonValue? params() { return self._parameters }
    JsonValue? parameters() { return self._parameters }
    Bool hasParams() { return self._parameters != null }

    JsonRpcRequest withParams(JsonValue params) {
        if params == null { throw "JsonRpcRequest.withParams: null params" }
        return new JsonRpcRequest(self._identifier, self._method, params)
    }

    JsonRpcRequest withId(JsonRpcId identifier) {
        if identifier == null { throw "JsonRpcRequest.withId: null identifier" }
        return new JsonRpcRequest(identifier, self._method, self._parameters)
    }

    JsonValue toJson() {
        JsonValue value = Json.object()
        JsonObject object = value.asObject() as JsonObject
        object.set("jsonrpc", Json.string("2.0"))
        if self._identifier != null {
            JsonRpcId identifier = self._identifier as JsonRpcId
            object.set("id", identifier.toJson())
        }
        object.set("method", Json.string(self._method))
        if self._parameters != null {
            object.set("params", self._parameters as JsonValue)
        }
        return value
    }

    static Result<JsonRpcRequest, Error> parse(JsonValue value) {
        if value == null { throw "JsonRpcRequest.parse: null value" }
        if !value.isObject() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "JsonRpcRequest: not an object"))
        }
        JsonObject object = value.asObject() as JsonObject
        JsonValue? version = object.getOrNull("jsonrpc")
        if version == null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "JsonRpcRequest: jsonrpc must be 2.0"))
        }
        JsonValue actualVersion = version as JsonValue
        if !actualVersion.isString() || (actualVersion.asString() as String) != "2.0" {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "JsonRpcRequest: jsonrpc must be 2.0"))
        }
        JsonValue? methodValue = object.getOrNull("method")
        if methodValue == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "JsonRpcRequest: invalid method"))
        }
        JsonValue actualMethod = methodValue as JsonValue
        if !actualMethod.isString() || (actualMethod.asString() as String) == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument, "JsonRpcRequest: invalid method"))
        }
        JsonValue? parameters = object.getOrNull("params")
        if parameters != null {
            JsonValue actualParams = parameters as JsonValue
            if !actualParams.isObject() && !actualParams.isArray() {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "JsonRpcRequest: params must be object or array"))
            }
        }
        JsonValue? identifierValue = object.getOrNull("id")
        if identifierValue == null {
            String notificationMethod = actualMethod.asString() as String
            if parameters == null {
                return Ok(JsonRpcRequest.notification(notificationMethod))
            }
            JsonValue actualParams = parameters as JsonValue
            return Ok(JsonRpcRequest.notificationWithParams(notificationMethod, actualParams))
        }
        JsonValue actualIdentifier = identifierValue as JsonValue
        if actualIdentifier.isNull() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "JsonRpcRequest: null id"))
        }
        Result<JsonRpcId, Error> identifier = JsonRpcId.parse(actualIdentifier)
        if identifier.isErr() { return Err(identifier.error()) }
        String method = actualMethod.asString() as String
        if parameters == null {
            return Ok(JsonRpcRequest.request(identifier.value(), method))
        }
        JsonValue actualParams = parameters as JsonValue
        return Ok(JsonRpcRequest.requestWithParams(identifier.value(), method, actualParams))
    }

    Bool equals(JsonRpcRequest other) {
        if other == null { return false }
        if self._method != other.method() { return false }
        if self._identifier == null {
            if other.identifier() != null { return false }
        } else {
            JsonRpcId identifier = self._identifier as JsonRpcId
            JsonRpcId? otherId = other.identifier()
            if otherId == null { return false }
            if !identifier.equals(otherId as JsonRpcId) { return false }
        }
        if self._parameters == null { return other.params() == null }
        if other.params() == null { return false }
        return Json.stringify(self._parameters as JsonValue) ==
            Json.stringify(other.params() as JsonValue)
    }
}

// ---------- JsonRpcResponse ----------
class JsonRpcResponse {
    final JsonRpcId? _identifier
    final Bool _hasResult
    final JsonValue? _result
    final JsonRpcError? _error

    private JsonRpcResponse(JsonRpcId? identifier, Bool hasResult, JsonValue? result,
                            JsonRpcError? error) {
        self._identifier = identifier
        self._hasResult = hasResult
        self._result = result
        self._error = error
    }

    static JsonRpcResponse success(JsonRpcId identifier, JsonValue result) {
        if identifier == null { throw "JsonRpcResponse.success: null identifier" }
        if result == null { throw "JsonRpcResponse.success: null result" }
        return new JsonRpcResponse(identifier, true, result, null)
    }

    static JsonRpcResponse failure(JsonRpcId? identifier, JsonRpcError error) {
        if error == null { throw "JsonRpcResponse.failure: null error" }
        return new JsonRpcResponse(identifier, false, null, error)
    }

    JsonRpcId? identifier() { return self._identifier }
    Bool hasIdentifier() { return self._identifier != null }
    Bool isSuccess() { return self._hasResult }
    Bool hasResult() { return self._hasResult }
    JsonValue? resultOrNull() { return self._result }
    JsonRpcError? errorOrNull() { return self._error }
    JsonValue? result() { return self._result }
    JsonRpcError? error() { return self._error }

    JsonValue toJson() {
        JsonValue value = Json.object()
        JsonObject object = value.asObject() as JsonObject
        object.set("jsonrpc", Json.string("2.0"))
        if self._identifier != null {
            JsonRpcId identifier = self._identifier as JsonRpcId
            object.set("id", identifier.toJson())
        } else {
            object.set("id", Json.nullValue())
        }
        if self._hasResult {
            object.set("result", self._result as JsonValue)
        } else {
            JsonRpcError error = self._error as JsonRpcError
            object.set("error", error.toJson())
        }
        return value
    }

    static Result<JsonRpcResponse, Error> parse(JsonValue value) {
        if value == null { throw "JsonRpcResponse.parse: null value" }
        if !value.isObject() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "JsonRpcResponse: not an object"))
        }
        JsonObject object = value.asObject() as JsonObject
        JsonValue? version = object.getOrNull("jsonrpc")
        if version == null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "JsonRpcResponse: jsonrpc must be 2.0"))
        }
        JsonValue actualVersion = version as JsonValue
        if !actualVersion.isString() || (actualVersion.asString() as String) != "2.0" {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "JsonRpcResponse: jsonrpc must be 2.0"))
        }
        JsonValue? resultValue = object.getOrNull("result")
        JsonValue? errorValue = object.getOrNull("error")
        if resultValue != null && errorValue != null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "JsonRpcResponse: result and error are exclusive"))
        }
        if resultValue == null && errorValue == null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "JsonRpcResponse: missing result and error"))
        }
        JsonRpcId? identifier = null
        JsonValue? identifierValue = object.getOrNull("id")
        if identifierValue != null {
            JsonValue actualId = identifierValue as JsonValue
            if !actualId.isNull() {
                Result<JsonRpcId, Error> parsedId = JsonRpcId.parse(actualId)
                if parsedId.isErr() { return Err(parsedId.error()) }
                identifier = parsedId.value()
            }
        }
        if resultValue != null {
            if identifier == null {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "JsonRpcResponse: success requires id"))
            }
            JsonValue actualResult = resultValue as JsonValue
            return Ok(JsonRpcResponse.success(identifier as JsonRpcId, actualResult))
        }
        Result<JsonRpcError, Error> parsedError = JsonRpcError.parse(errorValue as JsonValue)
        if parsedError.isErr() { return Err(parsedError.error()) }
        return Ok(JsonRpcResponse.failure(identifier, parsedError.value()))
    }

    Bool equals(JsonRpcResponse other) {
        if other == null { return false }
        if self._hasResult != other.isSuccess() { return false }
        if self._identifier == null {
            if other.identifier() != null { return false }
        } else {
            JsonRpcId identifier = self._identifier as JsonRpcId
            JsonRpcId? otherId = other.identifier()
            if otherId == null { return false }
            if !identifier.equals(otherId as JsonRpcId) { return false }
        }
        if self._hasResult {
            if other.resultOrNull() == null { return false }
            return Json.stringify(self._result as JsonValue) ==
                Json.stringify(other.resultOrNull() as JsonValue)
        }
        JsonRpcError error = self._error as JsonRpcError
        JsonRpcError? otherError = other.errorOrNull()
        if otherError == null { return false }
        return error.equals(otherError as JsonRpcError)
    }

    String describe() {
        String idText = "none"
        if self._identifier != null {
            JsonRpcId identifier = self._identifier as JsonRpcId
            idText = identifier.wireText()
        }
        if self._hasResult { return "response id=" + idText + " success" }
        JsonRpcError error = self._error as JsonRpcError
        return "response id=" + idText + " error=" + str(error.code())
    }
}

// ---------- JsonRpcPeer ----------
protocol JsonRpcPeer {
    Result<JsonValue, Error> request(Context context, JsonRpcRequest request);
    Result<Unit, Error> notify(Context context, JsonRpcRequest request);
    Result<Unit, Error> respond(Context context, JsonRpcResponse response);
    Result<Unit, Error> close();
    Bool isOpen();
}
