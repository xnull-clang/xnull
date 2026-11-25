// xdk.net —— L5 TCP / IP 核心子集（M19.1）
//
// 实现 IpFamily/IpAddress/IpPrefix/SocketAddress/SocketState/ByteStream/
// TcpStream/TcpListener/TcpClient/TcpHandler/TcpServer/TcpServerOptions。
// Dns/Udp/ConnectionPool/TLS/HTTP2 仍 planned。
// 稳定性：preview。合同见 docs/design/network/net/。
package xdk.net
import xdk.errors
import xdk.bytes

// ---------- IpFamily ----------
enum IpFamily {
    V4,
    V6,
}

String ipFamilyName(IpFamily family) {
    if family == IpFamily.V4 { return "v4" }
    return "v6"
}

static String netToHex(Bytes data) {
    String digits = "0123456789abcdef"
    List<String> parts = []
    Int index = 0
    while index < data.length() {
        Int value = data.get(index)
        parts.push(digits.substring(value / 16, 1) + digits.substring(value % 16, 1))
        index = index + 1
    }
    return parts.join("")
}

static Error netError(Int code, String message) {
    if code == 3 { return new BasicError(ErrorKind.Cancelled, message) }
    if code == 4 { return new BasicError(ErrorKind.Timeout, message) }
    if code == 5 { return new BasicError(ErrorKind.Unavailable, message) }
    if code == 1 { return new BasicError(ErrorKind.InvalidArgument, message) }
    return new BasicError(ErrorKind.Io, message)
}

// ---------- IpAddress ----------
class IpAddress {
    final IpFamily _family
    final Bytes _bytes

    private IpAddress(IpFamily family, Bytes bytes) {
        if bytes == null { throw "IpAddress: null argument" }
        self._family = family
        self._bytes = copy(bytes)
    }

    static Result<IpAddress, Error> parse(String text) {
        if text == null { throw "IpAddress.parse: null text" }
        String hex = ipParseRaw(text)
        if hex.length() == 8 {
            return Ok(new IpAddress(IpFamily.V4, fromHex(hex)))
        }
        if hex.length() == 32 {
            return Ok(new IpAddress(IpFamily.V6, fromHex(hex)))
        }
        return Err(new BasicError(ErrorKind.InvalidArgument, "IpAddress.parse: invalid address"))
    }

    static IpAddress fromBytes(Bytes bytes) {
        if bytes == null { throw "IpAddress.fromBytes: null bytes" }
        if bytes.length() == 4 { return new IpAddress(IpFamily.V4, bytes) }
        if bytes.length() == 16 { return new IpAddress(IpFamily.V6, bytes) }
        throw "IpAddress.fromBytes: invalid length"
    }

    static IpAddress loopback(IpFamily family) {
        if family == IpFamily.V6 { return IpAddress.fromBytes(fromHex("00000000000000000000000000000001")) }
        return IpAddress.fromBytes(fromHex("7f000001"))
    }

    static IpAddress any(IpFamily family) {
        if family == IpFamily.V6 { return IpAddress.fromBytes(Bytes.alloc(16)) }
        return IpAddress.fromBytes(Bytes.alloc(4))
    }

    IpFamily family() { return self._family }
    Bytes bytes() { return copy(self._bytes) }

    String text() {
        Int family = 4
        if self._family == IpFamily.V6 { family = 6 }
        String text = ipFormatRaw(toHex(self._bytes), family)
        return text
    }

    Bool isLoopback() {
        return self.equals(IpAddress.loopback(self._family))
    }

    Bool isAny() {
        return self.equals(IpAddress.any(self._family))
    }

    Bool equals(IpAddress other) {
        if other == null { return false }
        if self._family != other._family { return false }
        return ipCompareBytes(self._bytes, other._bytes) == 0
    }

    Int compare(IpAddress other) {
        if other == null { throw "IpAddress.compare: null" }
        if self._family != other._family {
            if self._family == IpFamily.V4 { return -1 }
            return 1
        }
        return ipCompareBytes(self._bytes, other._bytes)
    }

    String describe() {
        return self.text() + "(" + ipFamilyName(self._family) + ")"
    }
}

static Int ipCompareBytes(Bytes left, Bytes right) {
    Int index = 0
    while index < left.length() {
        Int a = left.get(index)
        Int b = right.get(index)
        if a < b { return -1 }
        if a > b { return 1 }
        index = index + 1
    }
    return 0
}

// ---------- IpPrefix ----------
class IpPrefix {
    final IpAddress _address
    final Int _prefixLength

    IpPrefix(IpAddress address, Int prefixLength) {
        if address == null { throw "IpPrefix: null address" }
        Int maximum = 32
        if address.family() == IpFamily.V6 { maximum = 128 }
        if prefixLength < 0 || prefixLength > maximum {
            throw "IpPrefix: prefix length out of range"
        }
        self._address = address
        self._prefixLength = prefixLength
    }

    static Result<IpPrefix, Error> parse(String text) {
        if text == null { throw "IpPrefix.parse: null text" }
        Int slash = -1
        Int probe = 0
        while probe < text.length() {
            if text.substring(probe, 1) == "/" { slash = probe }
            probe = probe + 1
        }
        if slash <= 0 || slash == text.length() - 1 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "IpPrefix.parse: invalid prefix"))
        }
        Result<IpAddress, Error> parsed = IpAddress.parse(text.substring(0, slash))
        if parsed.isErr() { return Err(parsed.error()) }
        String lengthText = text.substring(slash + 1, text.length() - slash - 1)
        Int index = 0
        Int length = 0
        while index < lengthText.length() {
            Int code = lengthText.get(index)
            if code < 48 || code > 57 {
                return Err(new BasicError(ErrorKind.InvalidArgument, "IpPrefix.parse: invalid length"))
            }
            length = length * 10 + (code - 48)
            index = index + 1
        }
        Int maximum = 32
        if parsed.value().family() == IpFamily.V6 { maximum = 128 }
        if length < 0 || length > maximum {
            return Err(new BasicError(ErrorKind.InvalidArgument, "IpPrefix.parse: length out of range"))
        }
        return Ok(new IpPrefix(parsed.value(), length))
    }

    IpAddress address() { return self._address }
    Int prefixLength() { return self._prefixLength }

    IpAddress network() {
        Bytes bytes = self._address.bytes()
        IpPrefix.mask(bytes, self._prefixLength, false)
        return IpAddress.fromBytes(bytes)
    }

    IpAddress? broadcast() {
        if self._address.family() == IpFamily.V6 { return null }
        Bytes bytes = self._address.bytes()
        IpPrefix.mask(bytes, self._prefixLength, true)
        return IpAddress.fromBytes(bytes)
    }

    Bool contains(IpAddress address) {
        if address == null { throw "IpPrefix.contains: null address" }
        if address.family() != self._address.family() { return false }
        Bytes left = self._address.bytes()
        Bytes right = address.bytes()
        IpPrefix.mask(left, self._prefixLength, false)
        IpPrefix.mask(right, self._prefixLength, false)
        return ipCompareBytes(left, right) == 0
    }

    Bool containsPrefix(IpPrefix other) {
        if other == null { throw "IpPrefix.containsPrefix: null" }
        if other.address().family() != self._address.family() { return false }
        if other.prefixLength() < self._prefixLength { return false }
        Bytes left = self._address.bytes()
        Bytes right = other.address().bytes()
        IpPrefix.mask(left, self._prefixLength, false)
        IpPrefix.mask(right, self._prefixLength, false)
        return ipCompareBytes(left, right) == 0
    }

    String text() {
        return self._address.text() + "/" + str(self._prefixLength)
    }

    Bool equals(IpPrefix other) {
        if other == null { return false }
        return self._address.equals(other.address()) && self._prefixLength == other.prefixLength()
    }

    Int compare(IpPrefix other) {
        if other == null { throw "IpPrefix.compare: null" }
        Int result = self._address.compare(other.address())
        if result != 0 { return result }
        if self._prefixLength < other.prefixLength() { return -1 }
        if self._prefixLength > other.prefixLength() { return 1 }
        return 0
    }

    static Void mask(Bytes bytes, Int prefixLength, Bool broadcast) {
        Int total = bytes.length() * 8
        Int index = 0
        while index < bytes.length() {
            Int bitStart = index * 8
            Int bits = prefixLength - bitStart
            if bits >= 8 {
                index = index + 1
                continue
            }
            if bits <= 0 {
                if broadcast { bytes.set(index, 255) } else { bytes.set(index, 0) }
            } else {
                Int maskValue = 255 - ((1 << (8 - bits)) - 1)
                Int value = bytes.get(index) & maskValue
                if broadcast {
                    value = value | (255 - maskValue)
                }
                bytes.set(index, value)
            }
            index = index + 1
        }
    }
}

// ---------- SocketAddress ----------
class SocketAddress {
    final IpAddress _address
    final Int _port

    SocketAddress(IpAddress address, Int port) {
        if address == null { throw "SocketAddress: null address" }
        if port < 0 || port > 65535 { throw "SocketAddress: port out of range" }
        self._address = address
        self._port = port
    }

    static Result<SocketAddress, Error> parse(String text) {
        if text == null { throw "SocketAddress.parse: null text" }
        if text.length() > 0 && text.substring(0, 1) == "[" {
            Int close = text.indexOf("]")
            if close < 0 || close + 1 >= text.length() || text.substring(close + 1, 1) != ":" {
                return Err(new BasicError(ErrorKind.InvalidArgument, "SocketAddress.parse: invalid IPv6 address"))
            }
            Result<IpAddress, Error> parsed = IpAddress.parse(text.substring(1, close - 1))
            if parsed.isErr() { return Err(parsed.error()) }
            return SocketAddress.withPort(parsed.value(), text.substring(close + 2, text.length() - close - 2))
        }
        Int colon = -1
        Int index = 0
        while index < text.length() {
            if text.substring(index, 1) == ":" { colon = index }
            index = index + 1
        }
        if colon <= 0 || colon == text.length() - 1 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "SocketAddress.parse: missing port"))
        }
        Result<IpAddress, Error> parsed = IpAddress.parse(text.substring(0, colon))
        if parsed.isErr() { return Err(parsed.error()) }
        return SocketAddress.withPort(parsed.value(), text.substring(colon + 1, text.length() - colon - 1))
    }

    static Result<SocketAddress, Error> withPort(IpAddress address, String portText) {
        if portText.length() == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "SocketAddress: empty port"))
        }
        Int port = 0
        Int index = 0
        while index < portText.length() {
            Int code = portText.get(index)
            if code < 48 || code > 57 {
                return Err(new BasicError(ErrorKind.InvalidArgument, "SocketAddress: invalid port"))
            }
            port = port * 10 + (code - 48)
            index = index + 1
        }
        if port > 65535 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "SocketAddress: port out of range"))
        }
        return Ok(new SocketAddress(address, port))
    }

    IpAddress address() { return self._address }
    Int port() { return self._port }

    String text() {
        String host = self._address.text()
        if self._address.family() == IpFamily.V6 {
            return "[" + host + "]:" + str(self._port)
        }
        return host + ":" + str(self._port)
    }

    Bool equals(SocketAddress other) {
        if other == null { return false }
        return self._address.equals(other.address()) && self._port == other.port()
    }

    String describe() {
        return self.text()
    }
}

// ---------- SocketState ----------
enum SocketState {
    Open,
    ReadClosed,
    WriteClosed,
    Closed,
}

String socketStateName(SocketState state) {
    if state == SocketState.Open { return "open" }
    if state == SocketState.ReadClosed { return "read_closed" }
    if state == SocketState.WriteClosed { return "write_closed" }
    return "closed"
}

// ---------- ByteStream ----------
protocol ByteStream {
    Result<Int, Error> read(Context context, Bytes buffer);
    Result<Int, Error> write(Context context, Bytes data);
    Result<Unit, Error> writeAll(Context context, Bytes data);
    Result<Unit, Error> setReadDeadline(Long deadlineMonoMillis);
    Result<Unit, Error> setWriteDeadline(Long deadlineMonoMillis);
    Bool isOpen();
    Void close();
}

// ---------- TcpStream ----------
class TcpStream implements ByteStream {
    final Int64 _handle
    SocketAddress _local
    SocketAddress _remote
    Bool _open
    Bool _readClosed
    Bool _writeClosed

    private TcpStream(Int64 handle) {
        self._handle = handle
        self._open = true
        self._readClosed = false
        self._writeClosed = false
        self._local = TcpStream.addressFromText(socketLocalTextRaw(handle))
        self._remote = TcpStream.addressFromText(socketRemoteTextRaw(handle))
    }

    static TcpStream wrap(Int64 handle) {
        return new TcpStream(handle)
    }

    static SocketAddress addressFromText(String text) {
        Result<SocketAddress, Error> parsed = SocketAddress.parse(text)
        if parsed.isOk() { return parsed.value() }
        return new SocketAddress(IpAddress.any(IpFamily.V4), 0)
    }

    static Result<TcpStream, Error> connect(Context context, SocketAddress address) {
        if context == null || address == null { throw "TcpStream.connect: null argument" }
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "TcpStream.connect: cancelled"))
        }
        return TcpStream.connectHost(context, address.address().text(), address.port())
    }

    static Result<TcpStream, Error> connectHost(Context context, String host, Int port) {
        if context == null || host == null { throw "TcpStream.connectHost: null argument" }
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "TcpStream.connectHost: cancelled"))
        }
        Int64 handle = socketConnectRaw(host, port)
        if handle == 0 {
            return Err(netError(socketErrorRaw(), "TcpStream: connect failed"))
        }
        return Ok(TcpStream.wrap(handle))
    }

    Result<Int, Error> read(Context context, Bytes buffer) {
        if context == null || buffer == null { throw "TcpStream.read: null argument" }
        if !self._open || self._readClosed {
            return Err(new BasicError(ErrorKind.Unavailable, "TcpStream.read: closed"))
        }
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "TcpStream.read: cancelled"))
        }
        if buffer.length() == 0 { return Ok(0) }
        String hex = socketRecvHexRaw(self._handle, buffer.length())
        Int code = socketErrorRaw()
        if code != 0 { return Err(netError(code, "TcpStream: read failed")) }
        if hex.length() == 0 { return Ok(0) }
        Bytes received = fromHex(hex)
        Int count = received.length()
        if count > buffer.length() { count = buffer.length() }
        Int index = 0
        while index < count {
            buffer.set(index, received.get(index))
            index = index + 1
        }
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "TcpStream.read: cancelled"))
        }
        return Ok(count)
    }

    Result<Int, Error> write(Context context, Bytes data) {
        if context == null || data == null { throw "TcpStream.write: null argument" }
        if !self._open || self._writeClosed {
            return Err(new BasicError(ErrorKind.Unavailable, "TcpStream.write: closed"))
        }
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "TcpStream.write: cancelled"))
        }
        Int64 sent = socketSendHexRaw(self._handle, netToHex(data))
        if sent < 0 {
            return Err(netError(socketErrorRaw(), "TcpStream: write failed"))
        }
        return Ok(sent as Int)
    }

    Result<Unit, Error> writeAll(Context context, Bytes data) {
        if context == null || data == null { throw "TcpStream.writeAll: null argument" }
        Int offset = 0
        while offset < data.length() {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled, "TcpStream.writeAll: cancelled"))
            }
            Bytes sliceData = data.slice(offset, data.length())
            Result<Int, Error> written = self.write(context, sliceData)
            if written.isErr() { return Err(written.error()) }
            if written.value() <= 0 {
                return Err(new BasicError(ErrorKind.Io, "TcpStream.writeAll: no progress"))
            }
            offset = offset + written.value()
        }
        return Ok()
    }

    Result<Unit, Error> setReadDeadline(Long deadlineMonoMillis) {
        return Err(new BasicError(ErrorKind.Unsupported, "TcpStream: read deadline is not supported"))
    }

    Result<Unit, Error> setWriteDeadline(Long deadlineMonoMillis) {
        return Err(new BasicError(ErrorKind.Unsupported, "TcpStream: write deadline is not supported"))
    }

    SocketAddress localAddress() { return self._local }
    SocketAddress remoteAddress() { return self._remote }

    SocketState state() {
        if !self._open || (self._readClosed && self._writeClosed) { return SocketState.Closed }
        if self._readClosed { return SocketState.ReadClosed }
        if self._writeClosed { return SocketState.WriteClosed }
        return SocketState.Open
    }

    Bool isOpen() { return self._open }

    Void close() {
        if self._open {
            socketCloseRaw(self._handle)
            self._open = false
            self._readClosed = true
            self._writeClosed = true
        }
    }
}

// ---------- TcpListener ----------
class TcpListener {
    final Int64 _handle
    SocketAddress _local
    Bool _open

    private TcpListener(Int64 handle) {
        self._handle = handle
        self._open = true
        self._local = TcpStream.addressFromText(listenerLocalTextRaw(handle))
    }

    static TcpListener wrap(Int64 handle) {
        return new TcpListener(handle)
    }

    static Result<TcpListener, Error> bind(Context context, SocketAddress local) {
        if context == null || local == null { throw "TcpListener.bind: null argument" }
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "TcpListener.bind: cancelled"))
        }
        Int64 handle = listenerBindBacklogRaw(local.address().text(), local.port(), 128)
        if handle == 0 {
            return Err(netError(socketErrorRaw(), "TcpListener: bind failed"))
        }
        return Ok(new TcpListener(handle))
    }

    Result<TcpStream, Error> accept(Context context) {
        if context == null { throw "TcpListener.accept: null context" }
        if !self._open {
            return Err(new BasicError(ErrorKind.Unavailable, "TcpListener.accept: closed"))
        }
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "TcpListener.accept: cancelled"))
        }
        Int64 handle = listenerAcceptRaw(self._handle)
        if handle == 0 {
            Int code = socketErrorRaw()
            if !self._open { return Err(new BasicError(ErrorKind.Unavailable, "TcpListener.accept: closed")) }
            return Err(netError(code, "TcpListener: accept failed"))
        }
        if context.isCancelled() {
            socketCloseRaw(handle)
            return Err(new BasicError(ErrorKind.Cancelled, "TcpListener.accept: cancelled"))
        }
        return Ok(TcpStream.wrap(handle))
    }

    SocketAddress localAddress() {
        if self._open {
            self._local = TcpStream.addressFromText(listenerLocalTextRaw(self._handle))
        }
        return self._local
    }

    Bool isOpen() { return self._open }

    Void close() {
        if self._open {
            socketCloseRaw(self._handle)
            self._open = false
        }
    }
}

// ---------- TcpClient ----------
class TcpClient {
    TcpClient() { }

    Result<TcpStream, Error> connect(Context context, SocketAddress address) {
        return TcpStream.connect(context, address)
    }

    Result<TcpStream, Error> connectHost(Context context, String host, Int port) {
        return TcpStream.connectHost(context, host, port)
    }
}

// ---------- TcpHandler ----------
protocol TcpHandler {
    Result<Unit, Error> handle(Context context, TcpStream stream);
}

// ---------- TcpServerOptions ----------
class TcpServerOptions {
    Int _backlog
    Bool _closeOnHandlerError

    TcpServerOptions() {
        self._backlog = 128
        self._closeOnHandlerError = true
    }

    TcpServerOptions backlog(Int value) {
        if value <= 0 { throw "TcpServerOptions.backlog: must be positive" }
        self._backlog = value
        return self
    }

    TcpServerOptions closeOnHandlerError(Bool value) {
        self._closeOnHandlerError = value
        return self
    }

    Int getBacklog() { return self._backlog }
    Bool isCloseOnHandlerError() { return self._closeOnHandlerError }

    TcpServerOptions copy() {
        TcpServerOptions out = new TcpServerOptions()
        out._backlog = self._backlog
        out._closeOnHandlerError = self._closeOnHandlerError
        return out
    }
}

// ---------- TcpServer ----------
class TcpServer {
    final TcpListener _listener
    final TcpServerOptions _options

    private TcpServer(TcpListener listener, TcpServerOptions options) {
        self._listener = listener
        self._options = options
    }

    static Result<TcpServer, Error> bind(Context context, SocketAddress address) {
        return TcpServer.bindWithOptions(context, address, new TcpServerOptions())
    }

    static Result<TcpServer, Error> bindWithOptions(Context context, SocketAddress address,
                                                    TcpServerOptions options) {
        if context == null || address == null || options == null {
            throw "TcpServer.bind: null argument"
        }
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "TcpServer.bind: cancelled"))
        }
        Int64 handle = listenerBindBacklogRaw(address.address().text(), address.port(),
            options.getBacklog())
        if handle == 0 {
            return Err(netError(socketErrorRaw(), "TcpServer: bind failed"))
        }
        return Ok(new TcpServer(TcpListener.wrap(handle), options.copy()))
    }

    Result<Unit, Error> serve(Context context, TcpHandler handler) {
        if context == null || handler == null { throw "TcpServer.serve: null argument" }
        while self._listener.isOpen() {
            if context.isCancelled() {
                self._listener.close()
                return Err(new BasicError(ErrorKind.Cancelled, "TcpServer.serve: cancelled"))
            }
            Result<TcpStream, Error> accepted = self._listener.accept(context)
            if accepted.isErr() {
                if context.isCancelled() {
                    self._listener.close()
                    return Err(new BasicError(ErrorKind.Cancelled, "TcpServer.serve: cancelled"))
                }
                if !self._listener.isOpen() { return Ok() }
                return Err(accepted.error())
            }
            TcpStream stream = accepted.value()
            Result<Unit, Error> handled = handler.handle(context, stream)
            stream.close()
            if handled.isErr() {
                if self._options.isCloseOnHandlerError() {
                    self._listener.close()
                    return Err(handled.error())
                }
            }
        }
        return Ok()
    }

    SocketAddress localAddress() { return self._listener.localAddress() }
    Bool isOpen() { return self._listener.isOpen() }

    Void close() { self._listener.close() }
}
