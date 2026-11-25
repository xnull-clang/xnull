// xdk.net.websocket —— WebSocket 核心（M19.2）
//
// 实现 ws:// 握手、帧编解码、文本/二进制/控制帧、分片、关闭、服务端升级。
// wss/TLS、permessage-deflate、HTTP/2、多线程 serve 明确 Unsupported。
// 稳定性：preview。合同见 docs/design/network/net/websocket/。
package xdk.net.websocket
import xdk.errors
import xdk.bytes
import xdk.net
import xdk.net.uri
import xdk.net.http
import xdk.crypto
import xdk.codec
import xdk.time
import xdk.random

// ---------- 枚举 ----------
enum WebSocketState {
    Connecting,
    Open,
    Closing,
    Closed,
}

String webSocketStateName(WebSocketState state) {
    if state == WebSocketState.Connecting { return "connecting" }
    if state == WebSocketState.Open { return "open" }
    if state == WebSocketState.Closing { return "closing" }
    return "closed"
}

enum WebSocketMessageKind {
    Text,
    Binary,
    Ping,
    Pong,
    Close,
}

String webSocketMessageKindName(WebSocketMessageKind kind) {
    if kind == WebSocketMessageKind.Text { return "text" }
    if kind == WebSocketMessageKind.Binary { return "binary" }
    if kind == WebSocketMessageKind.Ping { return "ping" }
    if kind == WebSocketMessageKind.Pong { return "pong" }
    return "close"
}

enum WebSocketCloseCode {
    Normal,
    GoingAway,
    ProtocolError,
    UnsupportedData,
    NoStatus,
    Abnormal,
    InvalidPayload,
    PolicyViolation,
    MessageTooBig,
    MandatoryExtension,
    InternalError,
    TlsHandshake,
}

Int webSocketCloseCodeValue(WebSocketCloseCode code) {
    if code == WebSocketCloseCode.Normal { return 1000 }
    if code == WebSocketCloseCode.GoingAway { return 1001 }
    if code == WebSocketCloseCode.ProtocolError { return 1002 }
    if code == WebSocketCloseCode.UnsupportedData { return 1003 }
    if code == WebSocketCloseCode.NoStatus { return 1005 }
    if code == WebSocketCloseCode.Abnormal { return 1006 }
    if code == WebSocketCloseCode.InvalidPayload { return 1007 }
    if code == WebSocketCloseCode.PolicyViolation { return 1008 }
    if code == WebSocketCloseCode.MessageTooBig { return 1009 }
    if code == WebSocketCloseCode.MandatoryExtension { return 1010 }
    if code == WebSocketCloseCode.InternalError { return 1011 }
    return 1015
}

Result<WebSocketCloseCode, Error> parseWebSocketCloseCode(Int code) {
    if code == 1000 { return Ok(WebSocketCloseCode.Normal) }
    if code == 1001 { return Ok(WebSocketCloseCode.GoingAway) }
    if code == 1002 { return Ok(WebSocketCloseCode.ProtocolError) }
    if code == 1003 { return Ok(WebSocketCloseCode.UnsupportedData) }
    if code == 1005 { return Ok(WebSocketCloseCode.NoStatus) }
    if code == 1006 { return Ok(WebSocketCloseCode.Abnormal) }
    if code == 1007 { return Ok(WebSocketCloseCode.InvalidPayload) }
    if code == 1008 { return Ok(WebSocketCloseCode.PolicyViolation) }
    if code == 1009 { return Ok(WebSocketCloseCode.MessageTooBig) }
    if code == 1010 { return Ok(WebSocketCloseCode.MandatoryExtension) }
    if code == 1011 { return Ok(WebSocketCloseCode.InternalError) }
    if code == 1015 { return Ok(WebSocketCloseCode.TlsHandshake) }
    return Err(new BasicError(ErrorKind.Unsupported, "WebSocket: unsupported close code"))
}

// ---------- Options ----------
class WebSocketOptions {
    HttpHeaders _headers
    List<String> _subprotocols
    Int _maxFrameBytes
    Int _maxMessageBytes
    Int _maxSendQueueBytes
    Long _pingIntervalMillis
    Long _pongTimeoutMillis
    String? _origin

    WebSocketOptions() {
        self._headers = new HttpHeaders()
        self._subprotocols = []
        self._maxFrameBytes = 1048576
        self._maxMessageBytes = 16777216
        self._maxSendQueueBytes = 16777216
        self._pingIntervalMillis = 0 as Long
        self._pongTimeoutMillis = 0 as Long
        self._origin = null
    }

    WebSocketOptions headers(HttpHeaders value) {
        if value == null { throw "WebSocketOptions.headers: null" }
        self._headers = value.copy()
        return self
    }

    WebSocketOptions subprotocols(List<String> values) {
        if values == null { throw "WebSocketOptions.subprotocols: null" }
        self._subprotocols = values.copy()
        return self
    }

    WebSocketOptions maxFrameBytes(Int value) {
        if value <= 0 { throw "WebSocketOptions.maxFrameBytes: must be positive" }
        self._maxFrameBytes = value
        return self
    }

    WebSocketOptions maxMessageBytes(Int value) {
        if value <= 0 { throw "WebSocketOptions.maxMessageBytes: must be positive" }
        self._maxMessageBytes = value
        return self
    }

    WebSocketOptions maxSendQueueBytes(Int value) {
        if value <= 0 { throw "WebSocketOptions.maxSendQueueBytes: must be positive" }
        self._maxSendQueueBytes = value
        return self
    }

    WebSocketOptions pingIntervalMillis(Long value) {
        if value < 0 { throw "WebSocketOptions.pingIntervalMillis: negative" }
        self._pingIntervalMillis = value
        return self
    }

    WebSocketOptions pongTimeoutMillis(Long value) {
        if value < 0 { throw "WebSocketOptions.pongTimeoutMillis: negative" }
        self._pongTimeoutMillis = value
        return self
    }

    WebSocketOptions origin(String? value) {
        self._origin = value
        return self
    }

    HttpHeaders getHeaders() { return self._headers.copy() }
    List<String> getSubprotocols() { return self._subprotocols.copy() }
    Int getMaxFrameBytes() { return self._maxFrameBytes }
    Int getMaxMessageBytes() { return self._maxMessageBytes }
    Int getMaxSendQueueBytes() { return self._maxSendQueueBytes }
    Long getPingIntervalMillis() { return self._pingIntervalMillis }
    Long getPongTimeoutMillis() { return self._pongTimeoutMillis }
    String? getOrigin() { return self._origin }

    WebSocketOptions copy() {
        WebSocketOptions out = new WebSocketOptions()
        out._headers = self._headers.copy()
        out._subprotocols = self._subprotocols.copy()
        out._maxFrameBytes = self._maxFrameBytes
        out._maxMessageBytes = self._maxMessageBytes
        out._maxSendQueueBytes = self._maxSendQueueBytes
        out._pingIntervalMillis = self._pingIntervalMillis
        out._pongTimeoutMillis = self._pongTimeoutMillis
        out._origin = self._origin
        return out
    }
}

// ---------- Message ----------
class WebSocketMessage {
    final WebSocketMessageKind _kind
    final String? _text
    final Bytes? _binary
    final WebSocketCloseCode _closeCode
    final String _closeReason

    private WebSocketMessage(WebSocketMessageKind kind, String? text, Bytes? binary,
                             WebSocketCloseCode closeCode, String reason) {
        self._kind = kind
        self._text = text
        if binary == null { self._binary = null } else { self._binary = copy(binary as Bytes) }
        self._closeCode = closeCode
        self._closeReason = reason
    }

    static WebSocketMessage fromText(String value) {
        if value == null { throw "WebSocketMessage.text: null" }
        return new WebSocketMessage(WebSocketMessageKind.Text, value, null, WebSocketCloseCode.NoStatus, "")
    }

    static WebSocketMessage fromBinary(Bytes value) {
        if value == null { throw "WebSocketMessage.binary: null" }
        return new WebSocketMessage(WebSocketMessageKind.Binary, null, value, WebSocketCloseCode.NoStatus, "")
    }

    static WebSocketMessage fromPing(Bytes value) {
        if value == null { throw "WebSocketMessage.ping: null" }
        return new WebSocketMessage(WebSocketMessageKind.Ping, null, value, WebSocketCloseCode.NoStatus, "")
    }

    static WebSocketMessage fromPong(Bytes value) {
        if value == null { throw "WebSocketMessage.pong: null" }
        return new WebSocketMessage(WebSocketMessageKind.Pong, null, value, WebSocketCloseCode.NoStatus, "")
    }

    static WebSocketMessage fromClose(WebSocketCloseCode code, String reason) {
        if reason == null { throw "WebSocketMessage.close: null reason" }
        return new WebSocketMessage(WebSocketMessageKind.Close, null, null, code, reason)
    }

    WebSocketMessageKind kind() { return self._kind }
    String? text() { return self._text }
    Bytes? binary() {
        if self._binary == null { return null }
        return copy(self._binary as Bytes)
    }
    WebSocketCloseCode closeCode() { return self._closeCode }
    String closeReason() { return self._closeReason }

    Bool isText() { return self._kind == WebSocketMessageKind.Text }
    Bool isBinary() { return self._kind == WebSocketMessageKind.Binary }
    Bool isPing() { return self._kind == WebSocketMessageKind.Ping }
    Bool isPong() { return self._kind == WebSocketMessageKind.Pong }
    Bool isClose() { return self._kind == WebSocketMessageKind.Close }

    String describe() {
        return webSocketMessageKindName(self._kind) + "(reason=" + self._closeReason + ")"
    }
}

// ---------- Stats ----------
class WebSocketStats {
    Long _messagesSent
    Long _messagesReceived
    Long _bytesSent
    Long _bytesReceived
    Long _pingsSent
    Long _pongsReceived
    Long _sendQueueBytes
    Long _lastPongMillis

    WebSocketStats() {
        self._messagesSent = 0 as Long
        self._messagesReceived = 0 as Long
        self._bytesSent = 0 as Long
        self._bytesReceived = 0 as Long
        self._pingsSent = 0 as Long
        self._pongsReceived = 0 as Long
        self._sendQueueBytes = 0 as Long
        self._lastPongMillis = 0 as Long
    }

    Long messagesSent() { return self._messagesSent }
    Long messagesReceived() { return self._messagesReceived }
    Long bytesSent() { return self._bytesSent }
    Long bytesReceived() { return self._bytesReceived }
    Long pingsSent() { return self._pingsSent }
    Long pongsReceived() { return self._pongsReceived }
    Long sendQueueBytes() { return self._sendQueueBytes }
    Long lastPongMillis() { return self._lastPongMillis }

    Void sent(Long bytes) {
        self._messagesSent = self._messagesSent + 1
        self._bytesSent = self._bytesSent + bytes
    }

    Void received(Long bytes) {
        self._messagesReceived = self._messagesReceived + 1
        self._bytesReceived = self._bytesReceived + bytes
    }

    Void pingSent() { self._pingsSent = self._pingsSent + 1 }
    Void pongReceived(Long millis) {
        self._pongsReceived = self._pongsReceived + 1
        self._lastPongMillis = millis
    }

    String describe() {
        return "sent=" + str(self._messagesSent) + ",received=" + str(self._messagesReceived) +
            ",bytesSent=" + str(self._bytesSent) + ",bytesReceived=" + str(self._bytesReceived)
    }
}

// ---------- 帧/HTTP 帮助 ----------
static Void wsPush16(Bytes out, Long value) {
    out.push(((value >> 8) & 255 as Long) as Int)
    out.push((value & 255 as Long) as Int)
}

static Void wsPush64(Bytes out, Long value) {
    Int shift = 56
    while shift >= 0 {
        out.push(((value >> (shift as Long)) & 255 as Long) as Int)
        shift = shift - 8
    }
}

static Bytes wsReadExact(Context context, TcpStream stream, Int count) {
    Bytes result = Bytes.alloc(count)
    Int offset = 0
    while offset < count {
        Bytes sliceBuffer = result.slice(offset, count)
        Result<Int, Error> read = stream.read(context, sliceBuffer)
        if read.isErr() {
            return Bytes.fromString("")
        }
        if read.value() <= 0 { return Bytes.fromString("") }
        Int index = 0
        while index < read.value() {
            result.set(offset + index, sliceBuffer.get(index))
            index = index + 1
        }
        offset = offset + read.value()
    }
    return result
}

static Result<String, Error> wsReadHeaders(Context context, TcpStream stream) {
    String text = ""
    while text.indexOf("\r\n\r\n") < 0 && text.length() < 65536 {
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "WebSocket: handshake cancelled"))
        }
        Bytes buffer = Bytes.alloc(1024)
        Result<Int, Error> read = stream.read(context, buffer)
        if read.isErr() { return Err(read.error()) }
        if read.value() <= 0 {
            return Err(new BasicError(ErrorKind.DataCorrupted, "WebSocket: handshake EOF"))
        }
        String chunk = buffer.slice(0, read.value()).toString()
        text = text + chunk
    }
    if text.indexOf("\r\n\r\n") < 0 {
        return Err(new BasicError(ErrorKind.DataCorrupted, "WebSocket: handshake too large"))
    }
    return Ok(text)
}

static Bool wsListHas(List<String> values, String value) {
    Int index = 0
    while index < values.length() {
        if values.get(index) == value { return true }
        index = index + 1
    }
    return false
}

static String wsHeaderValue(List<String> lines, String name) {
    String wanted = name.toLower()
    Int index = 1
    while index < lines.length() {
        String line = lines.get(index)
        Int colon = line.indexOf(":")
        if colon > 0 {
            String key = line.substring(0, colon).trim().toLower()
            if key == wanted {
                return line.substring(colon + 1, line.length() - colon - 1).trim()
            }
        }
        index = index + 1
    }
    return ""
}

static String wsAcceptKey(String key) {
    String combined = key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    Bytes digest = Hash.digest(HashAlgorithm.Sha1, Bytes.fromString(combined))
    return Base64.encode(digest)
}

static String wsRandomKey() {
    String hex = secureRandomHexRaw(16)
    return Base64.encode(fromHex(hex))
}

// ---------- WebSocket ----------
class WebSocket {
    final TcpStream _stream
    final WebSocketOptions _options
    final WebSocketStats _stats
    final Bool _maskOutgoing
    WebSocketState _state
    String? _subprotocol

    private WebSocket(TcpStream stream, WebSocketOptions options, Bool maskOutgoing, String? subprotocol) {
        self._stream = stream
        self._options = options
        self._maskOutgoing = maskOutgoing
        self._subprotocol = subprotocol
        self._state = WebSocketState.Open
        self._stats = new WebSocketStats()
    }

    static Result<WebSocket, Error> connect(Context context, Uri uri, WebSocketOptions options) {
        if context == null || uri == null || options == null {
            throw "WebSocket.connect: null argument"
        }
        String? scheme = uri.scheme()
        if scheme == null {
            return Err(new BasicError(ErrorKind.Unsupported, "WebSocket: only ws:// is supported"))
        }
        String schemeText = scheme as String
        if schemeText.toLower() != "ws" {
            return Err(new BasicError(ErrorKind.Unsupported, "WebSocket: only ws:// is supported"))
        }
        String? hostValue = uri.host()
        if hostValue == null { return Err(new BasicError(ErrorKind.InvalidArgument, "WebSocket: missing host")) }
        String host = hostValue as String
        Int port = 80
        if uri.port() != null { port = uri.port() as Int }
        Result<TcpStream, Error> connected = TcpStream.connectHost(context, host, port)
        if connected.isErr() { return Err(connected.error()) }
        TcpStream stream = connected.value()
        String key = wsRandomKey()
        String path = uri.path()
        if path == "" { path = "/" }
        if uri.hasQuery() { path = path + "?" + uri.query().encode() }
        String request = "GET " + path + " HTTP/1.1\r\n"
        request = request + "Host: " + host
        if port != 80 { request = request + ":" + str(port) }
        request = request + "\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
        request = request + "Sec-WebSocket-Key: " + key + "\r\n"
        request = request + "Sec-WebSocket-Version: 13\r\n"
        String? origin = options.getOrigin()
        if origin != null { request = request + "Origin: " + (origin as String) + "\r\n" }
        List<String> protocols = options.getSubprotocols()
        if protocols.length() > 0 {
            request = request + "Sec-WebSocket-Protocol: " + protocols.join(", ") + "\r\n"
        }
        List<HttpHeader> extra = options.getHeaders().entries()
        Int index = 0
        while index < extra.length() {
            request = request + extra.get(index).name() + ": " + extra.get(index).value() + "\r\n"
            index = index + 1
        }
        request = request + "\r\n"
        Bytes requestBytes = Bytes.fromString(request)
        Result<Unit, Error> written = stream.writeAll(context, requestBytes)
        if written.isErr() {
            stream.close()
            return Err(written.error())
        }
        Result<String, Error> head = wsReadHeaders(context, stream)
        if head.isErr() {
            stream.close()
            return Err(head.error())
        }
        List<String> lines = head.value().split("\r\n")
        if lines.length() == 0 || lines.get(0).indexOf(" 101 ") < 0 {
            stream.close()
            return Err(new BasicError(ErrorKind.DataCorrupted, "WebSocket: upgrade rejected"))
        }
        String upgrade = wsHeaderValue(lines, "Upgrade").toLower()
        String connection = wsHeaderValue(lines, "Connection").toLower()
        String expected = wsAcceptKey(key)
        String actual = wsHeaderValue(lines, "Sec-WebSocket-Accept")
        if upgrade != "websocket" || connection.indexOf("upgrade") < 0 || actual != expected {
            stream.close()
            return Err(new BasicError(ErrorKind.DataCorrupted, "WebSocket: invalid handshake"))
        }
        String protocolHeader = wsHeaderValue(lines, "Sec-WebSocket-Protocol")
        String? selected = null
        if protocolHeader.length() > 0 { selected = protocolHeader }
        return Ok(new WebSocket(stream, options.copy(), true, selected))
    }

    static WebSocket accept(TcpStream stream, WebSocketOptions options, String? subprotocol) {
        return new WebSocket(stream, options.copy(), false, subprotocol)
    }

    WebSocketState state() { return self._state }
    Bool isOpen() { return self._state == WebSocketState.Open }
    WebSocketOptions options() { return self._options.copy() }
    WebSocketStats stats() { return self._stats }
    String? subprotocol() { return self._subprotocol }

    Result<Unit, Error> sendFrame(Context context, Int opcode, Bytes payload) {
        if context == null || payload == null { throw "WebSocket.sendFrame: null argument" }
        if self._state != WebSocketState.Open {
            return Err(new BasicError(ErrorKind.Unavailable, "WebSocket: not open"))
        }
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "WebSocket: send cancelled"))
        }
        if payload.length() > self._options.getMaxFrameBytes() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "WebSocket: frame too large"))
        }
        if payload.length() > self._options.getMaxSendQueueBytes() {
            return Err(new BasicError(ErrorKind.Busy, "WebSocket: send queue full"))
        }
        Bytes frame = Bytes.fromString("")
        Int first = 128 | opcode
        frame.push(first)
        Bool mask = self._maskOutgoing
        Int maskBit = 0
        if mask { maskBit = 128 }
        Int length = payload.length()
        if length < 126 {
            frame.push(maskBit | length)
        } else if length <= 65535 {
            frame.push(maskBit | 126)
            wsPush16(frame, length as Long)
        } else {
            frame.push(maskBit | 127)
            wsPush64(frame, length as Long)
        }
        Bytes maskKey = Bytes.alloc(4)
        if mask {
            Bytes random = fromHex(secureRandomHexRaw(4))
            Int r = 0
            while r < 4 { maskKey.set(r, random.get(r)); r = r + 1 }
            Int k = 0
            while k < 4 { frame.push(maskKey.get(k)); k = k + 1 }
        }
        Int index = 0
        while index < length {
            Int value = payload.get(index)
            if mask { value = value ^ maskKey.get(index % 4) }
            frame.push(value)
            index = index + 1
        }
        Result<Unit, Error> written = self._stream.writeAll(context, frame)
        if written.isErr() { return Err(written.error()) }
        return Ok()
    }

    Result<Unit, Error> sendText(Context context, String text) {
        if text == null { throw "WebSocket.sendText: null" }
        Result<Unit, Error> sent = self.sendFrame(context, 1, Bytes.fromString(text))
        if sent.isOk() { self._stats.sent(text.length() as Long) }
        return sent
    }

    Result<Unit, Error> sendBinary(Context context, Bytes data) {
        if data == null { throw "WebSocket.sendBinary: null" }
        Result<Unit, Error> sent = self.sendFrame(context, 2, data)
        if sent.isOk() { self._stats.sent(data.length() as Long) }
        return sent
    }

    Result<Unit, Error> sendPing(Context context, Bytes data) {
        if data == null { throw "WebSocket.sendPing: null" }
        Result<Unit, Error> sent = self.sendFrame(context, 9, data)
        if sent.isOk() { self._stats.pingSent() }
        return sent
    }

    Result<Unit, Error> sendPong(Context context, Bytes data) {
        if data == null { throw "WebSocket.sendPong: null" }
        return self.sendFrame(context, 10, data)
    }

    Result<WebSocketMessage?, Error> receive(Context context) {
        if context == null { throw "WebSocket.receive: null context" }
        if self._state == WebSocketState.Closed {
            return Err(new BasicError(ErrorKind.Unavailable, "WebSocket: closed"))
        }
        Bytes fragments = Bytes.fromString("")
        Int messageOpcode = 0
        while true {
            Bytes firstBytes = wsReadExact(context, self._stream, 2)
            if firstBytes.length() != 2 {
                self._state = WebSocketState.Closed
                return Ok(null)
            }
            Int first = firstBytes.get(0)
            Int second = firstBytes.get(1)
            Bool fin = (first & 128) != 0
            Int opcode = first & 15
            Bool masked = (second & 128) != 0
            Long length = (second & 127) as Long
            if length == 126 as Long {
                Bytes ext = wsReadExact(context, self._stream, 2)
                if ext.length() != 2 { return Err(new BasicError(ErrorKind.DataCorrupted, "WebSocket: truncated frame")) }
                length = (ext.get(0) as Long) * 256 + (ext.get(1) as Long)
            } else if length == 127 as Long {
                Bytes ext = wsReadExact(context, self._stream, 8)
                if ext.length() != 8 { return Err(new BasicError(ErrorKind.DataCorrupted, "WebSocket: truncated frame")) }
                length = 0 as Long
                Int e = 0
                while e < 8 { length = length * 256 + (ext.get(e) as Long); e = e + 1 }
            }
            if length > self._options.getMaxFrameBytes() as Long {
                return Err(new BasicError(ErrorKind.InvalidArgument, "WebSocket: frame too large"))
            }
            Bytes maskKey = Bytes.alloc(4)
            if masked {
                maskKey = wsReadExact(context, self._stream, 4)
                if maskKey.length() != 4 { return Err(new BasicError(ErrorKind.DataCorrupted, "WebSocket: truncated mask")) }
            }
            Bytes payload = wsReadExact(context, self._stream, length as Int)
            if payload.length() != length as Int {
                return Err(new BasicError(ErrorKind.DataCorrupted, "WebSocket: truncated payload"))
            }
            if masked {
                Int p = 0
                while p < payload.length() {
                    payload.set(p, payload.get(p) ^ maskKey.get(p % 4))
                    p = p + 1
                }
            }
            if opcode == 8 {
                WebSocketCloseCode code = WebSocketCloseCode.NoStatus
                String reason = ""
                if payload.length() >= 2 {
                    Int closeValue = payload.get(0) * 256 + payload.get(1)
                    if closeValue == 1001 { code = WebSocketCloseCode.GoingAway }
                    else if closeValue == 1002 { code = WebSocketCloseCode.ProtocolError }
                    else if closeValue == 1003 { code = WebSocketCloseCode.UnsupportedData }
                    else if closeValue == 1007 { code = WebSocketCloseCode.InvalidPayload }
                    else if closeValue == 1008 { code = WebSocketCloseCode.PolicyViolation }
                    else if closeValue == 1009 { code = WebSocketCloseCode.MessageTooBig }
                    else if closeValue == 1010 { code = WebSocketCloseCode.MandatoryExtension }
                    else if closeValue == 1011 { code = WebSocketCloseCode.InternalError }
                    else if closeValue == 1015 { code = WebSocketCloseCode.TlsHandshake }
                    else if closeValue != 1000 { code = WebSocketCloseCode.ProtocolError }
                    if payload.length() > 2 { reason = payload.slice(2, payload.length()).toString() }
                }
                if self._state == WebSocketState.Open {
                    self.sendFrame(context, 8, payload)
                }
                self._state = WebSocketState.Closed
                return Ok(WebSocketMessage.fromClose(code, reason))
            }
            if opcode == 9 {
                self.sendPong(context, payload)
                return Ok(WebSocketMessage.fromPing(payload))
            }
            if opcode == 10 {
                self._stats.pongReceived(nowMono())
                return Ok(WebSocketMessage.fromPong(payload))
            }
            if opcode != 0 && opcode != 1 && opcode != 2 {
                return Err(new BasicError(ErrorKind.Unsupported, "WebSocket: unsupported opcode"))
            }
            if opcode == 0 && messageOpcode == 0 {
                return Err(new BasicError(ErrorKind.DataCorrupted, "WebSocket: unexpected continuation"))
            }
            if opcode == 1 || opcode == 2 { messageOpcode = opcode }
            Int f = 0
            while f < payload.length() {
                fragments.push(payload.get(f))
                f = f + 1
            }
            if fragments.length() > self._options.getMaxMessageBytes() {
                self.sendFrame(context, 8, wsClosePayload(WebSocketCloseCode.MessageTooBig, "message too big"))
                self._state = WebSocketState.Closed
                return Ok(WebSocketMessage.fromClose(WebSocketCloseCode.MessageTooBig, "message too big"))
            }
            if fin {
                WebSocketMessage message = WebSocketMessage.fromText("")
                if messageOpcode == 1 {
                    message = WebSocketMessage.fromText(fragments.toString())
                } else {
                    message = WebSocketMessage.fromBinary(fragments)
                }
                self._stats.received(fragments.length() as Long)
                return Ok(message)
            }
            if opcode == 9 || opcode == 10 || opcode == 8 {
                return Err(new BasicError(ErrorKind.DataCorrupted, "WebSocket: control frame fragmentation"))
            }
        }
        return Ok(null)
    }

    Result<Unit, Error> close(Context context, WebSocketCloseCode code, String reason) {
        if context == null || reason == null { throw "WebSocket.close: null argument" }
        if self._state == WebSocketState.Closed { return Ok() }
        WebSocketCloseCode actual = code
        Result<Unit, Error> sent = self.sendFrame(context, 8, wsClosePayload(actual, reason))
        self._state = WebSocketState.Closing
        self._stream.close()
        self._state = WebSocketState.Closed
        return Ok()
    }

    Result<Unit, Error> setReadDeadline(Long deadlineMonoMillis) {
        return Err(new BasicError(ErrorKind.Unsupported, "WebSocket: read deadline is not supported"))
    }

    Result<Unit, Error> setWriteDeadline(Long deadlineMonoMillis) {
        return Err(new BasicError(ErrorKind.Unsupported, "WebSocket: write deadline is not supported"))
    }

    String describe() {
        return "websocket(" + webSocketStateName(self._state) + "," + self._stats.describe() + ")"
    }
}

static Bytes wsClosePayload(WebSocketCloseCode code, String reason) {
    Bytes payload = Bytes.fromString("")
    Int value = webSocketCloseCodeValue(code)
    payload.push((value >> 8) & 255)
    payload.push(value & 255)
    Bytes text = Bytes.fromString(reason)
    Int index = 0
    while index < text.length() { payload.push(text.get(index)); index = index + 1 }
    return payload
}

// ---------- Handler / Server ----------
protocol WebSocketHandler {
    Result<Unit, Error> handle(Context context, WebSocket socket);
}

class WebSocketServer {
    final TcpListener _listener
    final WebSocketOptions _options
    Bool _open

    private WebSocketServer(TcpListener listener, WebSocketOptions options) {
        self._listener = listener
        self._options = options.copy()
        self._open = true
    }

    static Result<WebSocketServer, Error> bind(Context context, SocketAddress address,
                                               WebSocketOptions options) {
        if context == null || address == null || options == null {
            throw "WebSocketServer.bind: null argument"
        }
        Result<TcpListener, Error> listener = TcpListener.bind(context, address)
        if listener.isErr() { return Err(listener.error()) }
        return Ok(new WebSocketServer(listener.value(), options))
    }

    Result<Unit, Error> serve(Context context, WebSocketHandler handler) {
        if context == null || handler == null { throw "WebSocketServer.serve: null argument" }
        while self._open && self._listener.isOpen() {
            if context.isCancelled() {
                self.close()
                return Err(new BasicError(ErrorKind.Cancelled, "WebSocketServer: cancelled"))
            }
            Result<TcpStream, Error> accepted = self._listener.accept(context)
            if accepted.isErr() {
                if !self._listener.isOpen() { return Ok() }
                return Err(accepted.error())
            }
            TcpStream stream = accepted.value()
            Result<WebSocket, Error> upgraded = self.handshake(context, stream)
            if upgraded.isErr() {
                stream.close()
                continue
            }
            WebSocket socket = upgraded.value()
            Result<Unit, Error> handled = handler.handle(context, socket)
            if socket.isOpen() { socket.close(context, WebSocketCloseCode.Normal, "server close") }
            if handled.isErr() { return Err(handled.error()) }
        }
        return Ok()
    }

    Result<WebSocket, Error> handshake(Context context, TcpStream stream) {
        Result<String, Error> head = wsReadHeaders(context, stream)
        if head.isErr() { return Err(head.error()) }
        List<String> lines = head.value().split("\r\n")
        if lines.length() == 0 || lines.get(0).indexOf("GET ") != 0 {
            return Err(new BasicError(ErrorKind.DataCorrupted, "WebSocketServer: invalid request"))
        }
        String upgrade = wsHeaderValue(lines, "Upgrade").toLower()
        String connection = wsHeaderValue(lines, "Connection").toLower()
        String key = wsHeaderValue(lines, "Sec-WebSocket-Key")
        String version = wsHeaderValue(lines, "Sec-WebSocket-Version")
        if upgrade != "websocket" || connection.indexOf("upgrade") < 0 || key == "" || version != "13" {
            self.writeReject(stream)
            return Err(new BasicError(ErrorKind.DataCorrupted, "WebSocketServer: invalid upgrade"))
        }
        String? selected = null
        List<String> offered = self._options.getSubprotocols()
        String requested = wsHeaderValue(lines, "Sec-WebSocket-Protocol")
        if offered.length() > 0 && requested.length() > 0 {
            List<String> requestedList = requested.split(",")
            Int i = 0
            while i < requestedList.length() {
                String candidate = requestedList.get(i).trim()
                if wsListHas(offered, candidate) { selected = candidate }
                i = i + 1
            }
        }
        String response = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n" +
            "Connection: Upgrade\r\nSec-WebSocket-Accept: " + wsAcceptKey(key) + "\r\n"
        if selected != null { response = response + "Sec-WebSocket-Protocol: " + (selected as String) + "\r\n" }
        response = response + "\r\n"
        Result<Unit, Error> written = stream.writeAll(context, Bytes.fromString(response))
        if written.isErr() { return Err(written.error()) }
        return Ok(WebSocket.accept(stream, self._options, selected))
    }

    Void writeReject(TcpStream stream) {
        Result<Unit, Error> ignored = stream.writeAll(Context.background(),
            Bytes.fromString("HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n"))
    }

    SocketAddress localAddress() { return self._listener.localAddress() }
    Bool isOpen() { return self._open && self._listener.isOpen() }

    Void close() {
        self._open = false
        self._listener.close()
    }
}

// ---------- WebSocketClientState ----------
enum WebSocketClientState {
    Idle,
    Connecting,
    Open,
    Reconnecting,
    Closed,
}

String webSocketClientStateName(WebSocketClientState state) {
    if state == WebSocketClientState.Idle { return "idle" }
    if state == WebSocketClientState.Connecting { return "connecting" }
    if state == WebSocketClientState.Open { return "open" }
    if state == WebSocketClientState.Reconnecting { return "reconnecting" }
    return "closed"
}

// ---------- ReconnectPolicy ----------
class ReconnectPolicy {
    Long _initialDelayMillis
    Long _maxDelayMillis
    Double _multiplier
    Int _maxAttempts
    Bool _jitter

    ReconnectPolicy() {
        self._initialDelayMillis = 100 as Long
        self._maxDelayMillis = 30000 as Long
        self._multiplier = 2.0
        self._maxAttempts = 5
        self._jitter = false
    }

    ReconnectPolicy initialDelayMillis(Long value) {
        if value < 0 { throw "ReconnectPolicy.initialDelayMillis: negative" }
        if value > self._maxDelayMillis { throw "ReconnectPolicy.initialDelayMillis: exceeds max" }
        self._initialDelayMillis = value
        return self
    }

    ReconnectPolicy maxDelayMillis(Long value) {
        if value < 0 { throw "ReconnectPolicy.maxDelayMillis: negative" }
        if value < self._initialDelayMillis { throw "ReconnectPolicy.maxDelayMillis: below initial" }
        self._maxDelayMillis = value
        return self
    }

    ReconnectPolicy multiplier(Double value) {
        if value < 1.0 { throw "ReconnectPolicy.multiplier: below 1" }
        self._multiplier = value
        return self
    }

    ReconnectPolicy maxAttempts(Int value) {
        if value < 0 { throw "ReconnectPolicy.maxAttempts: negative" }
        self._maxAttempts = value
        return self
    }

    ReconnectPolicy jitter(Bool value) {
        self._jitter = value
        return self
    }

    Long getInitialDelayMillis() { return self._initialDelayMillis }
    Long getMaxDelayMillis() { return self._maxDelayMillis }
    Double getMultiplier() { return self._multiplier }
    Int getMaxAttempts() { return self._maxAttempts }
    Bool isJitter() { return self._jitter }

    Bool shouldRetry(Int attempt) {
        if attempt < 0 { throw "ReconnectPolicy.shouldRetry: negative attempt" }
        return attempt < self._maxAttempts
    }

    Long delayMillis(Int attempt) {
        if attempt < 0 { throw "ReconnectPolicy.delayMillis: negative attempt" }
        Double value = self._initialDelayMillis as Double
        Int index = 0
        while index < attempt {
            value = value * self._multiplier
            index = index + 1
        }
        if value > self._maxDelayMillis as Double { value = self._maxDelayMillis as Double }
        if self._jitter {
            Long seed = (attempt as Long) + (1000 as Long)
            Random random = new Random(seed)
            Double factor = 0.8 + random.nextDouble() * 0.4
            value = value * factor
        }
        return value as Long
    }

    ReconnectPolicy copy() {
        ReconnectPolicy out = new ReconnectPolicy()
        out._initialDelayMillis = self._initialDelayMillis
        out._maxDelayMillis = self._maxDelayMillis
        out._multiplier = self._multiplier
        out._maxAttempts = self._maxAttempts
        out._jitter = self._jitter
        return out
    }
}

// ---------- WebSocketClient ----------
class WebSocketClient {
    final WebSocketOptions _options
    final ReconnectPolicy _policy
    WebSocket? _socket
    Uri? _uri
    WebSocketClientState _state
    Bool _open
    Int _attempt

    WebSocketClient(WebSocketOptions options, ReconnectPolicy policy) {
        if options == null || policy == null { throw "WebSocketClient: null argument" }
        self._options = options.copy()
        self._policy = policy.copy()
        self._socket = null
        self._uri = null
        self._state = WebSocketClientState.Idle
        self._open = true
        self._attempt = 0
    }

    Result<WebSocket, Error> connect(Context context, Uri uri) {
        if context == null || uri == null { throw "WebSocketClient.connect: null argument" }
        if !self._open {
            return Err(new BasicError(ErrorKind.Unavailable, "WebSocketClient: closed"))
        }
        self._uri = uri
        self._state = WebSocketClientState.Connecting
        Result<WebSocket, Error> connected = WebSocket.connect(context, uri, self._options)
        if connected.isErr() {
            self._state = WebSocketClientState.Idle
            return Err(connected.error())
        }
        self._socket = connected.value()
        self._state = WebSocketClientState.Open
        self._attempt = 0
        return Ok(self._socket as WebSocket)
    }

    WebSocket? socket() { return self._socket }

    WebSocketClientState state() { return self._state }

    Result<WebSocket, Error> reconnect(Context context) {
        if context == null { throw "WebSocketClient.reconnect: null context" }
        if !self._open {
            return Err(new BasicError(ErrorKind.Unavailable, "WebSocketClient: closed"))
        }
        if self._uri == null {
            return Err(new BasicError(ErrorKind.Unavailable, "WebSocketClient: no previous URI"))
        }
        if self._socket != null {
            WebSocket previous = self._socket as WebSocket
            previous.close(Context.background(), WebSocketCloseCode.Normal, "reconnect")
            self._socket = null
        }
        self._state = WebSocketClientState.Reconnecting
        Error? lastError = null
        while self._policy.shouldRetry(self._attempt) {
            Long delay = self._policy.delayMillis(self._attempt)
            self._attempt = self._attempt + 1
            Result<Unit, Error> slept = sleepContext(context, durationOfMillis(delay))
            if slept.isErr() { return Err(slept.error()) }
            Result<WebSocket, Error> connected = WebSocket.connect(context, self._uri as Uri, self._options)
            if connected.isOk() {
                self._socket = connected.value()
                self._state = WebSocketClientState.Open
                self._attempt = 0
                return Ok(self._socket as WebSocket)
            }
            lastError = connected.error()
        }
        self._state = WebSocketClientState.Idle
        if lastError != null { return Err(lastError as Error) }
        return Err(new BasicError(ErrorKind.Unavailable, "WebSocketClient: retry limit reached"))
    }

    WebSocketStats stats() {
        if self._socket == null { return new WebSocketStats() }
        WebSocket current = self._socket as WebSocket
        return current.stats()
    }

    Result<Unit, Error> close() {
        if !self._open { return Ok() }
        self._open = false
        if self._socket != null {
            WebSocket current = self._socket as WebSocket
            current.close(Context.background(), WebSocketCloseCode.Normal, "client close")
        }
        self._socket = null
        self._state = WebSocketClientState.Closed
        return Ok()
    }
}
