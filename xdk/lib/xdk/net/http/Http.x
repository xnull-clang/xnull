// xdk.net.http — HTTP/1.x route-closure subset (M5.1).
//
// Deliberate cuts for this milestone:
// - route closure has no Context parameter;
// - HttpBody is buffered bytes only (no ByteStream/SocketAddress);
// - M5.3a client and M5.3b server are buffered text only: no TLS/redirect/
//   keep-alive/streaming/proxy, no HTTP/2, and server responses expose only
//   Content-Length plus caller headers.
package xdk.net.http
import xdk.bytes
import xdk.errors
import xdk.math
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
        if uri == null { throw "HttpRequest: null argument" }
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

// ---------- M5.3a：最小真实 HTTP client ----------
// FFI 只暴露 body 文本与状态码；响应头仅补 Content-Length，不伪造真实头。

class HttpClientOptions {
    Uri? _baseUri

    Uri? baseUriOrNull() { return self._baseUri }

    Void baseUri(Uri uri) {
        if uri == null { throw "HttpClientOptions.baseUri: null uri" }
        self._baseUri = uri
    }
}

static Uri httpClientResolve(HttpClientOptions options, Uri request) {
    Uri? baseValue = options.baseUriOrNull()
    if baseValue == null { return request }
    Uri base = baseValue as Uri
    if request.scheme() != null && request.host() != null { return request }
    String? scheme = request.scheme()
    if scheme == null { scheme = base.scheme() }
    String? host = request.host()
    if host == null { host = base.host() }
    Int? port = request.port()
    if port == null { port = base.port() }
    String? userInfo = request.userInfo()
    if userInfo == null { userInfo = base.userInfo() }
    return new Uri(scheme, userInfo, host, port, request.path(), request.query(),
        request.hasQuery(), request.fragment())
}

static Error httpClientRawError(Int code) {
    if code == 1 { return httpError(ErrorKind.InvalidArgument, "http request rejected") }
    if code == 2 { return httpError(ErrorKind.Io, "http request io failure") }
    if code == 3 { return httpError(ErrorKind.Cancelled, "http request cancelled") }
    if code == 4 { return httpError(ErrorKind.Timeout, "http request timed out") }
    if code == 5 { return httpError(ErrorKind.Unavailable, "http request unavailable") }
    return httpError(ErrorKind.Network, "http request failed")
}

class HttpClient {
    final HttpClientOptions _options
    Bool _open

    HttpClient() {
        self._options = new HttpClientOptions()
        self._open = true
    }

    HttpClient(HttpClientOptions options) {
        if options == null { throw "HttpClient: null options" }
        self._options = options
        self._open = true
    }

    HttpClientOptions options() { return self._options }
    Bool isOpen() { return self._open }

    Result<Unit, Error> close() {
        self._open = false
        return Ok()
    }

    Result<HttpResponse, Error> request(Context context, HttpRequest request) {
        if request == null || context == null {
            throw "HttpClient.request: null argument"
        }
        if !self._open {
            return Err(httpError(ErrorKind.Unavailable, "http client is closed"))
        }
        if context.isCancelled() {
            return Err(httpError(ErrorKind.Cancelled, "http request cancelled"))
        }
        Uri uri = httpClientResolve(self._options, request.uri())
        String? schemeValue = uri.scheme()
        if schemeValue == null || (schemeValue as String) == "" {
            return Err(httpError(ErrorKind.InvalidArgument, "http request requires a scheme"))
        }
        String scheme = schemeValue as String
        if scheme.toLower() != "http" {
            return Err(httpError(ErrorKind.Unsupported, "only http scheme is supported"))
        }
        String? hostValue = uri.host()
        if hostValue == null || (hostValue as String) == "" {
            return Err(httpError(ErrorKind.InvalidArgument, "http request requires a host"))
        }
        String host = hostValue as String
        Int port = 80
        Int? portValue = uri.port()
        if portValue != null { port = portValue as Int }
        String path = uri.path()
        if path == "" { path = "/" }
        if uri.hasQuery() {
            path = path + "?" + uri.query().toString()
        }
        Result<String, Error> bodyRead = request.body().readText(maxLongValue())
        if bodyRead.isErr() {
            return Err(httpError(ErrorKind.DataCorrupted, "request body cannot be read"))
        }
        String bodyText = bodyRead.value()
        String responseText = httpRequestRaw(httpMethodName(request.method()), host,
            port as Int32, path, bodyText)
        Int status = httpStatusRaw()
        if context.isCancelled() {
            return Err(httpError(ErrorKind.Cancelled, "http request cancelled"))
        }
        if status == 0 {
            return Err(httpClientRawError(httpErrorRaw()))
        }
        HttpBody responseBody = HttpBody.fromText(responseText)
        Long length = responseBody.contentLength() as Long
        HttpResponse response = HttpResponse.of(status).withBody(responseBody)
        response = response.withHeader("Content-Length", str(length))
        return Ok(response)
    }

    Result<HttpResponse, Error> get(Context context, Uri uri) {
        return self.request(context, new HttpRequest(HttpMethod.Get, uri))
    }

    Result<HttpResponse, Error> post(Context context, Uri uri, HttpBody body) {
        HttpRequest request = new HttpRequest(HttpMethod.Post, uri)
        return self.request(context, request.withBody(body))
    }

    Result<HttpResponse, Error> put(Context context, Uri uri, HttpBody body) {
        HttpRequest request = new HttpRequest(HttpMethod.Put, uri)
        return self.request(context, request.withBody(body))
    }

    Result<HttpResponse, Error> delete(Context context, Uri uri) {
        return self.request(context, new HttpRequest(HttpMethod.Delete, uri))
    }
}

// ---------- M5.3b：最小真实 HTTP server ----------
// wire 面：HTTP/1.0/1.1 文本、单请求单连接；无 chunked/keep-alive/TLS/HTTP2/upgrade。

protocol HttpHandler {
    Result<Unit, Error> handle(Context context, HttpExchange exchange);
}

static Error httpServerRawError(Int code) {
    if code == 1 { return httpError(ErrorKind.InvalidArgument, "http server argument rejected") }
    if code == 2 { return httpError(ErrorKind.Io, "http server io failure") }
    if code == 3 { return httpError(ErrorKind.Cancelled, "http server cancelled") }
    if code == 4 { return httpError(ErrorKind.Timeout, "http server timed out") }
    if code == 5 { return httpError(ErrorKind.Unavailable, "http server unavailable") }
    return httpError(ErrorKind.Network, "http server failed")
}

static Result<Unit, Error> httpWriteAll(Int64 socket, String text) {
    Int64 sent = socketSendRaw(socket, text)
    if sent < 0 {
        return Err(httpError(ErrorKind.Io, "http response write failed"))
    }
    return Ok()
}

static Result<Unit, Error> httpWriteResponse(Int64 socket, HttpResponse response) {
    Result<String, Error> bodyResult = response.body().readText(maxLongValue())
    if bodyResult.isErr() {
        return Err(httpError(ErrorKind.DataCorrupted, "http response body cannot be read"))
    }
    String body = bodyResult.value()
    Int code = response.status().code()
    String reason = response.status().reason()
    if reason == "" { reason = str(code) }
    Long length = response.body().contentLength() as Long
    String wire = "HTTP/1.1 " + str(code) + " " + reason + "\r\n" +
        "Content-Length: " + str(length) + "\r\n" +
        "Connection: close\r\n"
    List<HttpHeader> entries = response.headers().entries()
    Int index = 0
    while index < entries.length() {
        HttpHeader header = entries.get(index)
        String name = header.name().toLower()
        if name != "content-length" && name != "connection" {
            wire = wire + header.name() + ": " + header.value() + "\r\n"
        }
        index = index + 1
    }
    wire = wire + "\r\n" + body
    return httpWriteAll(socket, wire)
}

static Result<Unit, Error> httpWriteStatus(Int64 socket, Int status) {
    return httpWriteResponse(socket, HttpResponse.of(status))
}

static Result<HttpRequest, Error> httpReadRequest(Int64 socket, String host, Int port) {
    String headerText = ""
    Int headerEnd = -1
    while headerEnd < 0 {
        String chunk = socketRecvRaw(socket, 65536)
        if chunk == "" {
            return Err(httpError(ErrorKind.DataCorrupted, "empty or failed request read"))
        }
        headerText = headerText + chunk
        headerEnd = headerText.indexOf("\r\n\r\n")
        if headerEnd < 0 && headerText.length() > 65536 {
            return Err(httpError(ErrorKind.DataCorrupted, "request headers exceed 64KiB"))
        }
    }
    if headerEnd > 65536 {
        return Err(httpError(ErrorKind.DataCorrupted, "request headers exceed 64KiB"))
    }
    String bodyText = headerText.substring(headerEnd + 4, headerText.length() - headerEnd - 4)
    List<String> lines = headerText.substring(0, headerEnd).split("\r\n")
    if lines.length() == 0 {
        return Err(httpError(ErrorKind.InvalidArgument, "invalid request line"))
    }
    List<String> requestLine = lines.get(0).split(" ")
    if requestLine.length() != 3 {
        return Err(httpError(ErrorKind.InvalidArgument, "invalid request line"))
    }
    Result<HttpMethod, Error> methodResult = parseHttpMethod(requestLine.get(0))
    if methodResult.isErr() {
        return Err(httpError(ErrorKind.InvalidArgument, "invalid request method"))
    }
    HttpMethod method = methodResult.value() as HttpMethod
    Result<HttpVersion, Error> versionResult = parseHttpVersion(requestLine.get(2))
    if versionResult.isErr() {
        return Err(httpError(ErrorKind.InvalidArgument, "invalid request version"))
    }
    HttpVersion version = versionResult.value() as HttpVersion
    if version != HttpVersion.Http10 && version != HttpVersion.Http11 {
        return Err(httpError(ErrorKind.InvalidArgument, "only HTTP/1.0 and HTTP/1.1 are supported"))
    }
    HttpHeaders headers = new HttpHeaders()
    Int lineIndex = 1
    while lineIndex < lines.length() {
        String line = lines.get(lineIndex)
        if line == "" {
            lineIndex = lineIndex + 1
            continue
        }
        Int colon = line.indexOf(":")
        if colon <= 0 {
            return Err(httpError(ErrorKind.InvalidArgument, "invalid request header"))
        }
        String name = line.substring(0, colon).trim()
        String value = line.substring(colon + 1, line.length() - colon - 1).trim()
        headers.add(name, value)
        lineIndex = lineIndex + 1
    }
    if headers.has("transfer-encoding") {
        return Err(httpError(ErrorKind.Unsupported, "transfer-encoding is not supported"))
    }
    Long contentLength = 0
    String? lengthText = headers.getOrNull("content-length")
    if lengthText != null {
        Result<Long, Error> parsedLength = httpParseLong(lengthText as String)
        if parsedLength.isErr() || parsedLength.value() < 0 {
            return Err(httpError(ErrorKind.InvalidArgument, "invalid content-length"))
        }
        contentLength = parsedLength.value()
        if contentLength > 1048576 {
            return Err(httpError(ErrorKind.InvalidArgument, "request body exceeds 1MiB"))
        }
    }
    Int expected = contentLength as Int
    while bodyText.length() < expected {
        Int remaining = expected - bodyText.length()
        Int ask = remaining
        if ask > 65536 { ask = 65536 }
        String chunk = socketRecvRaw(socket, ask as Int32)
        if chunk == "" {
            return Err(httpError(ErrorKind.DataCorrupted, "request body is truncated"))
        }
        bodyText = bodyText + chunk
    }
    if bodyText.length() > expected {
        bodyText = bodyText.substring(0, expected)
    }
    String target = requestLine.get(1)
    String uriText = target
    if !target.startsWith("http://") && !target.startsWith("https://") {
        uriText = "http://" + host + ":" + str(port) + target
    }
    Result<Uri, Error> uriResult = Uri.parse(uriText)
    if uriResult.isErr() {
        return Err(httpError(ErrorKind.InvalidArgument, "invalid request target"))
    }
    HttpRequest request = new HttpRequest(method, uriResult.value())
    request = request.withVersion(version).withHeaders(headers)
    if expected > 0 {
        request = request.withBody(HttpBody.fromText(bodyText))
    }
    return Ok(request)
}

class HttpExchange {
    final HttpRequest _request
    final Int64 _socket
    Bool _responded
    Bool _closed

    HttpExchange(HttpRequest request, Int64 socket) {
        if request == null { throw "HttpExchange: null request" }
        self._request = request
        self._socket = socket
        self._responded = false
        self._closed = false
    }

    HttpRequest request() { return self._request }
    Bool isResponded() { return self._responded }
    Bool isUpgraded() { return false }

    Result<Unit, Error> respond(HttpResponse response) {
        if response == null { throw "HttpExchange.respond: null response" }
        if self._closed {
            return Err(httpError(ErrorKind.Unavailable, "http exchange is closed"))
        }
        if self._responded {
            return Err(httpError(ErrorKind.InvalidArgument, "http response already sent"))
        }
        if self._socket == 0 as Int64 {
            return Err(httpError(ErrorKind.Unavailable, "http exchange has no socket"))
        }
        Result<Unit, Error> written = httpWriteResponse(self._socket, response)
        if written.isErr() { return written }
        self._responded = true
        return Ok()
    }

    Result<Unit, Error> respondStatus(Int status) {
        return self.respond(HttpResponse.of(status))
    }

    Result<Unit, Error> close() {
        if self._closed { return Ok() }
        self._closed = true
        if self._socket == 0 as Int64 { return Ok() }
        Int rc = socketCloseRaw(self._socket)
        if rc != 0 {
            return Err(httpError(ErrorKind.Io, "socket close failed"))
        }
        return Ok()
    }
}

class HttpServer {
    final Int64 _listener
    final String _host
    final Int _port
    Bool _open

    HttpServer(Int64 listener, String host, Int port) {
        self._listener = listener
        self._host = host
        self._port = port
        self._open = true
    }

    static Result<HttpServer, Error> bind(Context context, String host, Int port) {
        if context == null || host == null { throw "HttpServer.bind: null argument" }
        if context.isCancelled() {
            return Err(httpError(ErrorKind.Cancelled, "http server bind cancelled"))
        }
        if host == "" || port <= 0 || port > 65535 {
            return Err(httpError(ErrorKind.InvalidArgument, "http server requires explicit 1..65535 port"))
        }
        Int64 listener = listenerBindRaw(host, port as Int32)
        if listener == 0 {
            return Err(httpServerRawError(socketErrorRaw()))
        }
        return Ok(new HttpServer(listener, host, port))
    }

    String host() { return self._host }
    Int localPort() { return self._port }
    Bool isOpen() { return self._open }

    Result<Unit, Error> serve(Context context, HttpHandler handler, Int maxRequests) {
        if context == null || handler == null { throw "HttpServer.serve: null argument" }
        if maxRequests <= 0 { throw "HttpServer.serve: maxRequests must be positive" }
        if !self._open {
            return Err(httpError(ErrorKind.Unavailable, "http server is closed"))
        }
        Int served = 0
        while served < maxRequests {
            if context.isCancelled() {
                return Err(httpError(ErrorKind.Cancelled, "http server request cancelled"))
            }
            if !self._open {
                return Err(httpError(ErrorKind.Unavailable, "http server is closed"))
            }
            Int64 socket = listenerAcceptRaw(self._listener)
            if socket == 0 {
                if context.isCancelled() {
                    return Err(httpError(ErrorKind.Cancelled, "http server request cancelled"))
                }
                return Err(httpServerRawError(socketErrorRaw()))
            }
            served = served + 1
            Result<HttpRequest, Error> parsed = httpReadRequest(socket, self._host, self._port)
            if parsed.isErr() {
                Error parseError = parsed.error()
                Int status = 400
                if parseError.kind() == ErrorKind.Unsupported {
                    status = 501
                }
                Result<Unit, Error> sent = httpWriteStatus(socket, status)
                socketCloseRaw(socket)
                if sent.isErr() { return sent }
                continue
            }
            HttpExchange exchange = new HttpExchange(parsed.value(), socket)
            Result<Unit, Error> handled = handler.handle(context, exchange)
            if !exchange.isResponded() {
                Result<Unit, Error> fallback = exchange.respondStatus(500)
                if fallback.isErr() {
                    exchange.close()
                    return fallback
                }
            }
            exchange.close()
            if handled.isErr() {
                return Err(handled.error())
            }
        }
        return Ok()
    }

    Result<Unit, Error> serveOnce(Context context, HttpHandler handler) {
        return self.serve(context, handler, 1)
    }

    Result<Unit, Error> close() {
        if !self._open { return Ok() }
        self._open = false
        socketCloseRaw(self._listener)
        return Ok()
    }
}
