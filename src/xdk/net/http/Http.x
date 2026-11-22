// xdk.net.http — HTTP/1.x route-closure subset (M5.1).
//
// Deliberate cuts for this milestone:
// - no Context parameter (core Context is not implemented yet);
// - HttpBody is buffered bytes only (no ByteStream/SocketAddress);
// - no socket client/server, HTTP/2, TLS, proxy, multipart, streaming.
package xdk.net.http
import xdk.bytes
import xdk.errors
import xdk.net.mime
import xdk.net.uri
import xdk.text

static Error httpError(ErrorKind kind, String message) {
    BasicError error = new BasicError(kind, message)
    return error
}

static Bool httpIsToken(String text) {
    if text == null || text == "" { return false }
    String allowed = "!#$%&'*+-.^_`|~0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    Int index = 0
    while index < text.length() {
        if allowed.indexOf(text.substring(index, 1)) < 0 { return false }
        index = index + 1
    }
    return true
}

static Bool httpHasLineBreak(String text) {
    return text.indexOf("\n") >= 0 || text.indexOf("\r") >= 0
}

static Int httpDigit(String c) {
    return "0123456789".indexOf(c)
}

static Result<Long, Error> httpParseLong(String text) {
    if text == null || text == "" { return Err(httpError(ErrorKind.InvalidArgument, "invalid number")) }
    Int index = 0
    Bool negative = false
    if text.substring(0, 1) == "-" {
        negative = true
        index = 1
    }
    if index >= text.length() { return Err(httpError(ErrorKind.InvalidArgument, "invalid number")) }
    Long value = 0
    while index < text.length() {
        Int digit = httpDigit(text.substring(index, 1))
        if digit < 0 { return Err(httpError(ErrorKind.InvalidArgument, "invalid number")) }
        value = value * 10 + digit
        index = index + 1
    }
    if negative { value = -value }
    return Ok(value)
}

enum HttpMethod {
    Get,
    Post,
    Put,
    Delete,
    Patch,
    Head,
    Options,
    Trace,
    Connect,
}

String httpMethodName(HttpMethod method) {
    if method == HttpMethod.Get { return "GET" }
    if method == HttpMethod.Post { return "POST" }
    if method == HttpMethod.Put { return "PUT" }
    if method == HttpMethod.Delete { return "DELETE" }
    if method == HttpMethod.Patch { return "PATCH" }
    if method == HttpMethod.Head { return "HEAD" }
    if method == HttpMethod.Options { return "OPTIONS" }
    if method == HttpMethod.Trace { return "TRACE" }
    return "CONNECT"
}

Result<HttpMethod, Error> parseHttpMethod(String text) {
    if text == null { throw "parseHttpMethod: null" }
    String value = text.toUpper()
    if value == "GET" { return Ok(HttpMethod.Get) }
    if value == "POST" { return Ok(HttpMethod.Post) }
    if value == "PUT" { return Ok(HttpMethod.Put) }
    if value == "DELETE" { return Ok(HttpMethod.Delete) }
    if value == "PATCH" { return Ok(HttpMethod.Patch) }
    if value == "HEAD" { return Ok(HttpMethod.Head) }
    if value == "OPTIONS" { return Ok(HttpMethod.Options) }
    if value == "TRACE" { return Ok(HttpMethod.Trace) }
    if value == "CONNECT" { return Ok(HttpMethod.Connect) }
    return Err(httpError(ErrorKind.InvalidArgument, "unknown method: " + text))
}

enum HttpVersion {
    Http10,
    Http11,
    Http2,
}

String httpVersionName(HttpVersion version) {
    if version == HttpVersion.Http10 { return "HTTP/1.0" }
    if version == HttpVersion.Http11 { return "HTTP/1.1" }
    return "HTTP/2"
}

Result<HttpVersion, Error> parseHttpVersion(String text) {
    if text == null { throw "parseHttpVersion: null" }
    String value = text.toUpper()
    if value == "HTTP/1.0" { return Ok(HttpVersion.Http10) }
    if value == "HTTP/1.1" { return Ok(HttpVersion.Http11) }
    if value == "HTTP/2" || value == "HTTP/2.0" { return Ok(HttpVersion.Http2) }
    return Err(httpError(ErrorKind.InvalidArgument, "unsupported version: " + text))
}

String httpStatusReason(Int code) {
    if code == 100 { return "Continue" }
    if code == 101 { return "Switching Protocols" }
    if code == 102 { return "Processing" }
    if code == 103 { return "Early Hints" }
    if code == 200 { return "OK" }
    if code == 201 { return "Created" }
    if code == 202 { return "Accepted" }
    if code == 203 { return "Non-Authoritative Information" }
    if code == 204 { return "No Content" }
    if code == 205 { return "Reset Content" }
    if code == 206 { return "Partial Content" }
    if code == 207 { return "Multi-Status" }
    if code == 208 { return "Already Reported" }
    if code == 226 { return "IM Used" }
    if code == 300 { return "Multiple Choices" }
    if code == 301 { return "Moved Permanently" }
    if code == 302 { return "Found" }
    if code == 303 { return "See Other" }
    if code == 304 { return "Not Modified" }
    if code == 305 { return "Use Proxy" }
    if code == 307 { return "Temporary Redirect" }
    if code == 308 { return "Permanent Redirect" }
    if code == 400 { return "Bad Request" }
    if code == 401 { return "Unauthorized" }
    if code == 402 { return "Payment Required" }
    if code == 403 { return "Forbidden" }
    if code == 404 { return "Not Found" }
    if code == 405 { return "Method Not Allowed" }
    if code == 406 { return "Not Acceptable" }
    if code == 407 { return "Proxy Authentication Required" }
    if code == 408 { return "Request Timeout" }
    if code == 409 { return "Conflict" }
    if code == 410 { return "Gone" }
    if code == 411 { return "Length Required" }
    if code == 412 { return "Precondition Failed" }
    if code == 413 { return "Payload Too Large" }
    if code == 414 { return "URI Too Long" }
    if code == 415 { return "Unsupported Media Type" }
    if code == 416 { return "Range Not Satisfiable" }
    if code == 417 { return "Expectation Failed" }
    if code == 418 { return "I'm a teapot" }
    if code == 421 { return "Misdirected Request" }
    if code == 422 { return "Unprocessable Entity" }
    if code == 423 { return "Locked" }
    if code == 424 { return "Failed Dependency" }
    if code == 425 { return "Too Early" }
    if code == 426 { return "Upgrade Required" }
    if code == 428 { return "Precondition Required" }
    if code == 429 { return "Too Many Requests" }
    if code == 431 { return "Request Header Fields Too Large" }
    if code == 451 { return "Unavailable For Legal Reasons" }
    if code == 500 { return "Internal Server Error" }
    if code == 501 { return "Not Implemented" }
    if code == 502 { return "Bad Gateway" }
    if code == 503 { return "Service Unavailable" }
    if code == 504 { return "Gateway Timeout" }
    if code == 505 { return "HTTP Version Not Supported" }
    if code == 506 { return "Variant Also Negotiates" }
    if code == 507 { return "Insufficient Storage" }
    if code == 508 { return "Loop Detected" }
    if code == 510 { return "Not Extended" }
    if code == 511 { return "Network Authentication Required" }
    return ""
}

class HttpStatus {
    final Int _code
    final String _reason

    HttpStatus(Int code) {
        if code < 100 || code > 599 { throw "HttpStatus.of: invalid code" }
        self._code = code
        self._reason = httpStatusReason(code)
    }

    static HttpStatus of(Int code) {
        return new HttpStatus(code)
    }

    Int code() { return self._code }
    String reason() { return self._reason }
    Bool isInformational() { return self._code >= 100 && self._code <= 199 }
    Bool isSuccess() { return self._code >= 200 && self._code <= 299 }
    Bool isRedirect() { return self._code >= 300 && self._code <= 399 }
    Bool isClientError() { return self._code >= 400 && self._code <= 499 }
    Bool isServerError() { return self._code >= 500 && self._code <= 599 }

    Bool equals(HttpStatus other) {
        if other == null { return false }
        return self._code == other.code()
    }

    String toString() {
        if self._reason == "" { return str(self._code) }
        return str(self._code) + " " + self._reason
    }
}

class HttpHeader {
    final String _name
    final String _value

    HttpHeader(String name, String value) {
        if name == null || name == "" { throw "HttpHeader: empty name" }
        if value == null { throw "HttpHeader: null value" }
        if !httpIsToken(name) { throw "HttpHeader: invalid name" }
        if httpHasLineBreak(value) { throw "HttpHeader: multiline" }
        self._name = name
        self._value = value
    }

    String name() { return self._name }
    String value() { return self._value }

    Bool equals(HttpHeader other) {
        if other == null { return false }
        return self._name == other.name() && self._value == other.value()
    }

    String toString() { return self._name + ": " + self._value }
}

class HttpHeaders {
    List<String> _names
    List<List<String>> _values

    HttpHeaders() {
        self._names = []
        self._values = []
    }

    Int indexOfName(String key) {
        Int index = 0
        while index < self._names.length() {
            if self._names.get(index) == key { return index }
            index = index + 1
        }
        return -1
    }

    void add(String name, String value) {
        HttpHeader header = new HttpHeader(name, value)
        String key = header.name().toLower()
        Int index = self.indexOfName(key)
        if index < 0 {
            List<String> values = []
            values.push(header.value())
            self._names.push(key)
            self._values.push(values)
        } else {
            self._values.get(index).push(header.value())
        }
    }

    void set(String name, String value) {
        HttpHeader header = new HttpHeader(name, value)
        String key = header.name().toLower()
        Int index = self.indexOfName(key)
        if index < 0 {
            List<String> values = []
            values.push(header.value())
            self._names.push(key)
            self._values.push(values)
        } else {
            List<String> values = []
            values.push(header.value())
            self._values.set(index, values)
        }
    }

    String? getOrNull(String name) {
        if name == null { return null }
        Int index = self.indexOfName(name.toLower())
        if index < 0 { return null }
        List<String> values = self._values.get(index)
        if values.length() == 0 { return null }
        return values.get(0)
    }

    String getOr(String name, String fallback) {
        if fallback == null { throw "HttpHeaders.getOr: null fallback" }
        String? value = self.getOrNull(name)
        if value == null { return fallback }
        return value as String
    }

    List<String> getAll(String name) {
        List<String> result = []
        if name == null { return result }
        Int index = self.indexOfName(name.toLower())
        if index < 0 { return result }
        List<String> values = self._values.get(index)
        Int cursor = 0
        while cursor < values.length() {
            result.push(values.get(cursor))
            cursor = cursor + 1
        }
        return result
    }

    Bool has(String name) {
        if name == null { return false }
        return self.indexOfName(name.toLower()) >= 0
    }

    void remove(String name) {
        if name == null { return }
        Int index = self.indexOfName(name.toLower())
        if index >= 0 {
            self._names.remove(index)
            self._values.remove(index)
        }
    }

    List<HttpHeader> entries() {
        List<HttpHeader> result = []
        Int index = 0
        while index < self._names.length() {
            String key = self._names.get(index)
            List<String> values = self._values.get(index)
            Int cursor = 0
            while cursor < values.length() {
                result.push(new HttpHeader(key, values.get(cursor)))
                cursor = cursor + 1
            }
            index = index + 1
        }
        return result
    }

    Int length() { return self._names.length() }

    void clear() {
        self._names.clear()
        self._values.clear()
    }

    HttpHeaders copy() {
        HttpHeaders result = new HttpHeaders()
        List<HttpHeader> all = self.entries()
        Int index = 0
        while index < all.length() {
            result.add(all.get(index).name(), all.get(index).value())
            index = index + 1
        }
        return result
    }

    MediaType? contentType() {
        String? value = self.getOrNull("content-type")
        if value == null { return null }
        Result<MediaType, Error> parsed = MediaType.parse(value as String)
        if parsed.isErr() { return null }
        return parsed.value()
    }

    Long? contentLength() {
        String? value = self.getOrNull("content-length")
        if value == null { return null }
        Result<Long, Error> parsed = httpParseLong(value as String)
        if parsed.isErr() { return null }
        return parsed.value()
    }

    String? userAgent() { return self.getOrNull("user-agent") }
}

class HttpBody {
    final Bytes _bytes
    final Long _contentLength
    Bool _closed

    HttpBody(Bytes bytes, Long contentLength) {
        if bytes == null { throw "HttpBody: null bytes" }
        self._bytes = bytes
        self._contentLength = contentLength
        self._closed = false
    }

    static HttpBody empty() {
        Bytes data = Bytes.fromString("")
        return new HttpBody(data, 0)
    }

    static HttpBody fromBytes(Bytes data) {
        if data == null { throw "HttpBody.fromBytes: null" }
        return new HttpBody(copy(data), data.length() as Long)
    }

    static HttpBody fromText(String text) {
        if text == null { throw "HttpBody.fromText: null" }
        return HttpBody.fromBytes(Bytes.fromString(text))
    }

    Bool isEmpty() { return self._bytes.length() == 0 }
    Long? contentLength() { return self._contentLength }
    Bytes? bytes() { return copy(self._bytes) }

    Result<Bytes, Error> readAll(Long maximumBytes) {
        if maximumBytes < 0 { throw "HttpBody.readAll: negative maximum" }
        if self._closed { return Err(httpError(ErrorKind.Unavailable, "http body is closed")) }
        if self._contentLength > maximumBytes {
            return Err(httpError(ErrorKind.InvalidArgument, "body exceeds maximum"))
        }
        return Ok(copy(self._bytes))
    }

    Result<String, Error> readText(Long maximumBytes) {
        Result<Bytes, Error> data = self.readAll(maximumBytes)
        if data.isErr() { return Err(data.error()) }
        return Ok(data.value().toString())
    }

    Result<Unit, Error> close() {
        self._closed = true
        return Ok()
    }
}

class HttpRequest {
    final HttpMethod _method
    final Uri _uri
    HttpVersion _version
    HttpHeaders _headers
    HttpBody _body

    HttpRequest(HttpMethod method, Uri uri) {
        if method == null || uri == null { throw "HttpRequest: null argument" }
        self._method = method
        self._uri = uri
        self._version = HttpVersion.Http11
        self._headers = new HttpHeaders()
        self._body = HttpBody.empty()
    }

    HttpMethod method() { return self._method }
    Uri uri() { return self._uri }
    HttpVersion version() { return self._version }
    HttpHeaders headers() { return self._headers.copy() }
    HttpBody body() { return self._body }

    HttpRequest withHeader(String name, String value) {
        HttpRequest next = new HttpRequest(self._method, self._uri)
        next._version = self._version
        next._headers = self._headers.copy()
        next._headers.add(name, value)
        next._body = self._body
        return next
    }

    HttpRequest withHeaders(HttpHeaders headers) {
        if headers == null { throw "HttpRequest.withHeaders: null" }
        HttpRequest next = new HttpRequest(self._method, self._uri)
        next._version = self._version
        next._headers = headers.copy()
        next._body = self._body
        return next
    }

    HttpRequest withBody(HttpBody body) {
        if body == null { throw "HttpRequest.withBody: null" }
        HttpRequest next = new HttpRequest(self._method, self._uri)
        next._version = self._version
        next._headers = self._headers.copy()
        next._body = body
        return next
    }

    HttpRequest withVersion(HttpVersion version) {
        if version == null { throw "HttpRequest.withVersion: null" }
        HttpRequest next = new HttpRequest(self._method, self._uri)
        next._version = version
        next._headers = self._headers.copy()
        next._body = self._body
        return next
    }

    HttpRequest withUri(Uri uri) {
        if uri == null { throw "HttpRequest.withUri: null" }
        HttpRequest next = new HttpRequest(self._method, uri)
        next._version = self._version
        next._headers = self._headers.copy()
        next._body = self._body
        return next
    }
}

class HttpResponse {
    final HttpStatus _status
    HttpVersion _version
    HttpHeaders _headers
    HttpBody _body

    HttpResponse(HttpStatus status) {
        if status == null { throw "HttpResponse: null status" }
        self._status = status
        self._version = HttpVersion.Http11
        self._headers = new HttpHeaders()
        self._body = HttpBody.empty()
    }

    static HttpResponse of(Int status) {
        return new HttpResponse(HttpStatus.of(status))
    }

    HttpStatus status() { return self._status }
    HttpVersion version() { return self._version }
    HttpHeaders headers() { return self._headers.copy() }
    HttpBody body() { return self._body }

    HttpResponse withHeader(String name, String value) {
        HttpResponse next = new HttpResponse(self._status)
        next._version = self._version
        next._headers = self._headers.copy()
        next._headers.add(name, value)
        next._body = self._body
        return next
    }

    HttpResponse withHeaders(HttpHeaders headers) {
        if headers == null { throw "HttpResponse.withHeaders: null" }
        HttpResponse next = new HttpResponse(self._status)
        next._version = self._version
        next._headers = headers.copy()
        next._body = self._body
        return next
    }

    HttpResponse withBody(HttpBody body) {
        if body == null { throw "HttpResponse.withBody: null" }
        HttpResponse next = new HttpResponse(self._status)
        next._version = self._version
        next._headers = self._headers.copy()
        next._body = body
        return next
    }

    HttpResponse withStatus(Int status) {
        HttpResponse next = new HttpResponse(HttpStatus.of(status))
        next._version = self._version
        next._headers = self._headers.copy()
        next._body = self._body
        return next
    }

    Bool isSuccess() { return self._status.isSuccess() }
    Bool isRedirect() { return self._status.isRedirect() }
    Bool isClientError() { return self._status.isClientError() }
    Bool isServerError() { return self._status.isServerError() }
}

class HttpServerOptions {
    Int _maxHeaderBytes
    Long _maxBodyBytes
    Long _readTimeoutMillis
    Long _writeTimeoutMillis
    Bool _keepAlive
    Int _maxConnections
    Bool _http2

    HttpServerOptions() {
        self._maxHeaderBytes = 65536
        self._maxBodyBytes = 16777216
        self._readTimeoutMillis = 30000
        self._writeTimeoutMillis = 30000
        self._keepAlive = true
        self._maxConnections = 128
        self._http2 = false
    }

    HttpServerOptions maxHeaderBytes(Int value) {
        if value <= 0 { throw "HttpServerOptions.maxHeaderBytes: invalid" }
        self._maxHeaderBytes = value
        return self
    }

    HttpServerOptions maxBodyBytes(Long value) {
        if value <= 0 { throw "HttpServerOptions.maxBodyBytes: invalid" }
        self._maxBodyBytes = value
        return self
    }

    HttpServerOptions readTimeoutMillis(Long value) {
        if value <= 0 { throw "HttpServerOptions.readTimeoutMillis: invalid" }
        self._readTimeoutMillis = value
        return self
    }

    HttpServerOptions writeTimeoutMillis(Long value) {
        if value <= 0 { throw "HttpServerOptions.writeTimeoutMillis: invalid" }
        self._writeTimeoutMillis = value
        return self
    }

    HttpServerOptions keepAlive(Bool value) {
        self._keepAlive = value
        return self
    }

    HttpServerOptions maxConnections(Int value) {
        if value <= 0 { throw "HttpServerOptions.maxConnections: invalid" }
        self._maxConnections = value
        return self
    }

    HttpServerOptions http2(Bool value) {
        self._http2 = value
        return self
    }

    Int getMaxHeaderBytes() { return self._maxHeaderBytes }
    Long getMaxBodyBytes() { return self._maxBodyBytes }
    Long getReadTimeoutMillis() { return self._readTimeoutMillis }
    Long getWriteTimeoutMillis() { return self._writeTimeoutMillis }
    Bool isKeepAlive() { return self._keepAlive }
    Int getMaxConnections() { return self._maxConnections }
    Bool isHttp2() { return self._http2 }

    HttpServerOptions copy() {
        HttpServerOptions result = new HttpServerOptions()
        result._maxHeaderBytes = self._maxHeaderBytes
        result._maxBodyBytes = self._maxBodyBytes
        result._readTimeoutMillis = self._readTimeoutMillis
        result._writeTimeoutMillis = self._writeTimeoutMillis
        result._keepAlive = self._keepAlive
        result._maxConnections = self._maxConnections
        result._http2 = self._http2
        return result
    }
}

class FormEntry {
    final String _name
    final String _value

    FormEntry(String name, String value) {
        if name == null || name == "" { throw "FormEntry: empty name" }
        if value == null { throw "FormEntry: null value" }
        self._name = name
        self._value = value
    }

    String name() { return self._name }
    String value() { return self._value }
    String toString() { return self._name + "=" + self._value }
}

class Form {
    List<FormEntry> _entries

    Form() {
        self._entries = []
    }

    static Result<Form, Error> parse(String text) {
        if text == null { throw "Form.parse: null" }
        Form result = new Form()
        if text == "" { return Ok(result) }
        List<String> parts = text.split("&")
        Int index = 0
        while index < parts.length() {
            String part = parts.get(index)
            if part != "" {
                Int separator = part.indexOf("=")
                String rawName = part
                String rawValue = ""
                if separator >= 0 {
                    rawName = part.substring(0, separator)
                    rawValue = part.substring(separator + 1, part.length() - separator - 1)
                }
                Result<String, Error> name = queryDecode(rawName)
                if name.isErr() { return Err(name.error()) }
                Result<String, Error> value = queryDecode(rawValue)
                if value.isErr() { return Err(value.error()) }
                result.add(name.value(), value.value())
            }
            index = index + 1
        }
        return Ok(result)
    }

    void add(String name, String value) {
        self._entries.push(new FormEntry(name, value))
    }

    void set(String name, String value) {
        self.remove(name)
        self.add(name, value)
    }

    String? getOrNull(String name) {
        if name == null { return null }
        Int index = 0
        while index < self._entries.length() {
            if self._entries.get(index).name() == name {
                return self._entries.get(index).value()
            }
            index = index + 1
        }
        return null
    }

    String getOr(String name, String fallback) {
        if fallback == null { throw "Form.getOr: null fallback" }
        String? value = self.getOrNull(name)
        if value == null { return fallback }
        return value as String
    }

    List<String> getAll(String name) {
        List<String> result = []
        Int index = 0
        while index < self._entries.length() {
            if self._entries.get(index).name() == name {
                result.push(self._entries.get(index).value())
            }
            index = index + 1
        }
        return result
    }

    Bool remove(String name) {
        Bool removed = false
        Int index = self._entries.length() - 1
        while index >= 0 {
            if self._entries.get(index).name() == name {
                self._entries.remove(index)
                removed = true
            }
            index = index - 1
        }
        return removed
    }

    List<FormEntry> entries() { return self._entries.copy() }
    Int length() { return self._entries.length() }

    String encode() {
        String result = ""
        Int index = 0
        while index < self._entries.length() {
            if index > 0 { result = result + "&" }
            FormEntry entry = self._entries.get(index)
            result = result + queryEncode(entry.name()) + "=" + queryEncode(entry.value())
            index = index + 1
        }
        return result
    }

    HttpBody toBody() { return HttpBody.fromText(self.encode()) }

    void clear() { self._entries.clear() }

    Form copy() {
        Form result = new Form()
        Int index = 0
        while index < self._entries.length() {
            result.add(self._entries.get(index).name(), self._entries.get(index).value())
            index = index + 1
        }
        return result
    }
}

enum SameSite {
    Strict,
    Lax,
    None,
}

String sameSiteName(SameSite value) {
    if value == SameSite.Strict { return "Strict" }
    if value == SameSite.Lax { return "Lax" }
    return "None"
}

Result<SameSite, Error> parseSameSite(String text) {
    if text == null { throw "parseSameSite: null" }
    String value = text.toLower()
    if value == "strict" { return Ok(SameSite.Strict) }
    if value == "lax" { return Ok(SameSite.Lax) }
    if value == "none" { return Ok(SameSite.None) }
    return Err(httpError(ErrorKind.InvalidArgument, "invalid SameSite: " + text))
}

class Cookie {
    final String _name
    final String _value
    String _domain
    String _path
    Bool _hasExpires
    Long _expiresValue
    Bool _isSecure
    Bool _isHttpOnly
    Bool _hasSameSite
    SameSite _sameSiteValue

    Cookie(String name, String value) {
        if name == null || name == "" { throw "Cookie: empty name" }
        if value == null { throw "Cookie: null value" }
        if !httpIsToken(name) { throw "Cookie: invalid name" }
        if httpHasLineBreak(value) { throw "Cookie: multiline" }
        self._name = name
        self._value = value
        self._domain = ""
        self._path = ""
        self._hasExpires = false
        self._expiresValue = 0
        self._isSecure = false
        self._isHttpOnly = false
        self._hasSameSite = false
        self._sameSiteValue = SameSite.Strict
    }

    static Result<Cookie, Error> parseSetCookie(String header) {
        if header == null { throw "Cookie.parseSetCookie: null" }
        List<String> parts = header.split(";")
        if parts.length() == 0 { return Err(httpError(ErrorKind.InvalidArgument, "empty cookie")) }
        String first = parts.get(0).trim()
        Int separator = first.indexOf("=")
        if separator <= 0 { return Err(httpError(ErrorKind.InvalidArgument, "invalid cookie")) }
        String name = first.substring(0, separator).trim()
        String value = first.substring(separator + 1, first.length() - separator - 1)
        if name == "" { return Err(httpError(ErrorKind.InvalidArgument, "empty cookie name")) }
        if httpHasLineBreak(name) || httpHasLineBreak(value) {
            return Err(httpError(ErrorKind.InvalidArgument, "cookie contains line break"))
        }
        Cookie cookie = new Cookie(name, value)
        Int index = 1
        while index < parts.length() {
            String part = parts.get(index).trim()
            if part != "" {
                Int equals = part.indexOf("=")
                String key = part
                String attrValue = ""
                if equals >= 0 {
                    key = part.substring(0, equals).trim()
                    attrValue = part.substring(equals + 1, part.length() - equals - 1).trim()
                }
                String lower = key.toLower()
                if lower == "domain" { cookie._domain = attrValue }
                else if lower == "path" { cookie._path = attrValue }
                else if lower == "secure" { cookie._isSecure = true }
                else if lower == "httponly" { cookie._isHttpOnly = true }
                else if lower == "samesite" {
                    Result<SameSite, Error> parsed = parseSameSite(attrValue)
                    if parsed.isErr() { return Err(parsed.error()) }
                    cookie._hasSameSite = true
                    cookie._sameSiteValue = parsed.value() as SameSite
                } else if lower == "max-age" {
                    Result<Long, Error> parsed = httpParseLong(attrValue)
                    if parsed.isErr() { return Err(parsed.error()) }
                    if parsed.value() <= 0 {
                        cookie._hasExpires = true
                        cookie._expiresValue = 0
                    }
                } else if lower == "expires" {
                    Result<Long, Error> parsed = httpParseLong(attrValue)
                    if parsed.isOk() {
                        cookie._hasExpires = true
                        cookie._expiresValue = parsed.value()
                    }
                }
            }
            index = index + 1
        }
        return Ok(cookie)
    }

    static Result<List<Cookie>, Error> parseCookieHeader(String header) {
        if header == null { throw "Cookie.parseCookieHeader: null" }
        List<Cookie> result = []
        List<String> parts = header.split(";")
        Int index = 0
        while index < parts.length() {
            String part = parts.get(index).trim()
            if part != "" {
                Int separator = part.indexOf("=")
                if separator <= 0 { return Err(httpError(ErrorKind.InvalidArgument, "invalid cookie header")) }
                String name = part.substring(0, separator).trim()
                String value = part.substring(separator + 1, part.length() - separator - 1).trim()
                if name == "" { return Err(httpError(ErrorKind.InvalidArgument, "empty cookie name")) }
                result.push(new Cookie(name, value))
            }
            index = index + 1
        }
        return Ok(result)
    }

    String name() { return self._name }
    String value() { return self._value }
    String domain() { return self._domain }
    String path() { return self._path }
    Long? expiresMillis() {
        if !self._hasExpires { return null }
        return self._expiresValue
    }
    Bool hasExpires() { return self._hasExpires }
    Long expiresValue() { return self._expiresValue }
    Bool isSecure() { return self._isSecure }
    Bool isHttpOnly() { return self._isHttpOnly }
    SameSite? sameSite() {
        if !self._hasSameSite { return null }
        return self._sameSiteValue
    }
    Bool hasSameSite() { return self._hasSameSite }
    SameSite sameSiteValue() { return self._sameSiteValue }

    String headerValue() {
        String result = self._name + "=" + self._value
        if self._domain != "" { result = result + "; Domain=" + self._domain }
        if self._path != "" { result = result + "; Path=" + self._path }
        if self._hasExpires {
            result = result + "; Expires=" + str(self._expiresValue)
        }
        if self._isSecure { result = result + "; Secure" }
        if self._isHttpOnly { result = result + "; HttpOnly" }
        if self._hasSameSite {
            result = result + "; SameSite=" + sameSiteName(self._sameSiteValue)
        }
        return result
    }

    Bool matches(Uri requestUri) {
        if requestUri == null { return false }
        if self._isSecure {
            String? scheme = requestUri.scheme()
            if scheme == null { return false }
            String schemeText = scheme as String
            if schemeText.toLower() != "https" { return false }
        }
        if self._domain != "" {
            String? host = requestUri.host()
            if host == null { return false }
            String hostText = host as String
            if hostText.toLower() != self._domain.toLower() { return false }
        }
        if self._path != "" {
            if !requestUri.path().startsWith(self._path) { return false }
        }
        return true
    }
}

class CookieJar {
    List<Cookie> _cookies

    CookieJar() {
        self._cookies = []
    }

    void store(Cookie cookie) {
        if cookie == null { throw "CookieJar.store: null" }
        Int index = 0
        while index < self._cookies.length() {
            Cookie current = self._cookies.get(index)
            if current.name() == cookie.name() && current.domain() == cookie.domain() && current.path() == cookie.path() {
                self._cookies.set(index, cookie)
                return
            }
            index = index + 1
        }
        self._cookies.push(cookie)
    }

    List<Cookie> cookies() { return self._cookies.copy() }

    String? headerForRequest(Uri requestUri) {
        if requestUri == null { return null }
        String result = ""
        Bool has = false
        Int index = 0
        while index < self._cookies.length() {
            Cookie cookie = self._cookies.get(index)
            if cookie.matches(requestUri) {
                if has { result = result + "; " }
                result = result + cookie.name() + "=" + cookie.value()
                has = true
            }
            index = index + 1
        }
        if !has { return null }
        return result
    }

    Int removeExpired(Long nowMillis) {
        Int removed = 0
        Int index = self._cookies.length() - 1
        while index >= 0 {
            Cookie cookie = self._cookies.get(index)
            if cookie.hasExpires() {
                if cookie.expiresValue() <= nowMillis {
                    self._cookies.remove(index)
                    removed = removed + 1
                }
            }
            index = index - 1
        }
        return removed
    }

    void clear() { self._cookies.clear() }
    Int length() { return self._cookies.length() }
}
