// xdk.net 完整实现（源码层过渡单元，仅 XNULL_XDK_SOURCE=1 编入）
//
// 默认构建继续使用 impl/lib/xdk/net.x（S6 §4.7 声明面）。
//
// 依赖矩阵（S6 §2）：net → errors；不反向依赖 sys/collections。
// 运行时服务：handle（socket）、scheduler（*Async 挂起；首版随调度器切片）。
// 跨 FFI 边界：xdkc_net_raw（bindings/xdk/net_raw.xfb 的标量句柄桥）。
// 稳定性：@preview
//
// 合同（S6 §3/§4.7）：
//   - 可失败操作一律返回 Result；不使用 panic 表达可恢复失败。
//   - 资源类型 Socket/Listener 提供 close()；close 幂等。
//   - 首版为文本形态（产品编译器 Bytes 借出面待 B5）；二进制传输随 FFI 修复补齐。
//   - 类静态方法调用当前不可用（B5 编译器），工厂以顶层函数提供：
//     connectSocket / httpGet / httpPost。

import xdk.errors

// ---------- 错误映射 ----------

static Error netError(ErrorKind kind, String message) {
    return new CauseError(kind, message, null)
}

static ErrorKind netKind(Int code) {
    if code == 1 {
        return ErrorKind.InvalidArgument
    }
    if code == 2 {
        return ErrorKind.Io
    }
    if code == 3 {
        return ErrorKind.Cancelled
    }
    if code == 4 {
        return ErrorKind.Timeout
    }
    if code == 5 {
        return ErrorKind.Unavailable
    }
    return ErrorKind.Network
}

static Bool validPort(Int port) {
    return port > 0 && port <= 65535
}

// ---------- 二进制 hex 辅助（避开 Bytes 借出面） ----------

static String netHexChar(Int v) {
    String table = "0123456789abcdef"
    return table.substring(v, 1)
}

static String netHexEncode(Bytes b) {
    String res = ""
    Int i = 0
    while i < b.length() {
        Int v = b.get(i)
        res = $"{res}{netHexChar(v / 16)}{netHexChar(v % 16)}"
        i = i + 1
    }
    return res
}

static Int netHexVal(String ch) {
    if ch == "0" { return 0 }
    if ch == "1" { return 1 }
    if ch == "2" { return 2 }
    if ch == "3" { return 3 }
    if ch == "4" { return 4 }
    if ch == "5" { return 5 }
    if ch == "6" { return 6 }
    if ch == "7" { return 7 }
    if ch == "8" { return 8 }
    if ch == "9" { return 9 }
    if ch == "a" { return 10 }
    if ch == "b" { return 11 }
    if ch == "c" { return 12 }
    if ch == "d" { return 13 }
    if ch == "e" { return 14 }
    if ch == "f" { return 15 }
    return 0
}

static Bytes netHexDecode(String hex) {
    Bytes res = Bytes.fromString("")
    Int i = 0
    while i + 1 < hex.length() {
        Int hi = netHexVal(hex.substring(i, 1))
        Int lo = netHexVal(hex.substring(i + 1, 1))
        res.push(hi * 16 + lo)
        i = i + 2
    }
    return res
}

// ---------- Socket ----------

// Socket：客户端连接句柄。send/recv 为文本形态；close 幂等。
class Socket {
    Int64 handle
    Bool opened

    Socket(Int64 h) {
        self.handle = h
        self.opened = true
    }

    Bool isOpen() {
        return self.opened
    }

    // 发送文本；返回发送字节数。
    Result<Int, Error> send(String data) {
        if !self.opened {
            return Err(netError(ErrorKind.Unavailable, "Socket.send: socket 已关闭"))
        }
        Int64 n = socketSendRaw(self.handle, data)
        if n < 0 {
            return Err(netError(netKind(socketErrorRaw()), "Socket.send: 发送失败"))
        }
        return Ok(n)
    }

    // 发送二进制（首版上限 1 MiB）。
    Result<Int, Error> sendBytes(Bytes data) {
        if !self.opened {
            return Err(netError(ErrorKind.Unavailable, "Socket.sendBytes: socket 已关闭"))
        }
        if data.length() > 1048576 {
            return Err(netError(ErrorKind.Unsupported, "Socket.sendBytes: 首版上限 1 MiB"))
        }
        Int64 n = socketSendHexRaw(self.handle, netHexEncode(data))
        if n < 0 {
            return Err(netError(netKind(socketErrorRaw()), "Socket.sendBytes: 发送失败"))
        }
        return Ok(n)
    }

    // 接收至多 maxBytes 字节并返回二进制；对端关闭 → 空缓冲。
    Result<Bytes, Error> recvBytes(Int maxBytes) {
        if !self.opened {
            return Err(netError(ErrorKind.Unavailable, "Socket.recvBytes: socket 已关闭"))
        }
        String hex = socketRecvHexRaw(self.handle, maxBytes)
        Int code = socketErrorRaw()
        if code != 0 {
            return Err(netError(netKind(code), "Socket.recvBytes: 接收失败"))
        }
        Bytes res = netHexDecode(hex)
        return Ok(res)
    }

    // 接收至多 maxBytes 字节并返回文本；对端关闭 → 空串。
    Result<String, Error> recv(Int maxBytes) {
        if !self.opened {
            return Err(netError(ErrorKind.Unavailable, "Socket.recv: socket 已关闭"))
        }
        String data = socketRecvRaw(self.handle, maxBytes)
        Int code = socketErrorRaw()
        if code != 0 {
            return Err(netError(netKind(code), "Socket.recv: 接收失败"))
        }
        return Ok(data)
    }

    // close 幂等；句柄立即失效。
    Result<void, Error> close() {
        if !self.opened {
            return Ok()
        }
        self.opened = false
        Int rc = socketCloseRaw(self.handle)
        if rc != 0 {
            return Err(netError(ErrorKind.Io, "Socket.close: 关闭失败"))
        }
        return Ok()
    }
}

// connectSocket：建立 TCP 连接（plain 形态，阻塞分类 .unaware）。
Result<Socket, Error> connectSocket(String host, Int port) {
    if host.length() == 0 || !validPort(port) {
        return Err(netError(ErrorKind.InvalidArgument, "connectSocket: 非法 host/port"))
    }
    Int64 h = socketConnectRaw(host, port)
    if h == 0 {
        return Err(netError(netKind(socketErrorRaw()), $"connectSocket: 无法连接 {host}:{port}"))
    }
    return Ok(new Socket(h))
}

// ---------- Listener（运行时 listen/accept 未接入，显式 Unsupported） ----------

class Listener {
    final String host
    final Int port
    Bool opened

    Listener(String h, Int p) {
        self.host = h
        self.port = p
        self.opened = false
    }

    Bool isOpen() {
        return self.opened
    }

    Result<void, Error> close() {
        self.opened = false
        return Ok()
    }

    // 首版运行时未提供 listen/accept；显式 Unsupported，不伪造成功。
    Result<Socket, Error> accept() {
        return Err(netError(ErrorKind.Unsupported, "Listener.accept: 运行时 listen/accept 未接入"))
    }
}

Result<Listener, Error> bindListener(String host, Int port) {
    if host.length() == 0 || !validPort(port) {
        return Err(netError(ErrorKind.InvalidArgument, "bindListener: 非法 host/port"))
    }
    return Err(netError(ErrorKind.Unsupported, "bindListener: 运行时 listen/accept 未接入"))
}

// ---------- HTTP ----------

// Url：解析结果（无效时 valid=false）。
class Url {
    String host
    Int port
    String path
    Bool valid

    Url(String h, Int p, String pa, Bool v) {
        self.host = h
        self.port = p
        self.path = pa
        self.valid = v
    }
}

static Url parseUrl(String url) {
    if url.length() <= 7 {
        return new Url("", 0, "", false)
    }
    if url.substring(0, 7) != "http://" {
        return new Url("", 0, "", false)
    }
    String rest = url.substring(7, url.length() - 7)
    Int slash = rest.indexOf("/")
    String authority = rest
    String path = "/"
    if slash >= 0 {
        authority = rest.substring(0, slash)
        path = rest.substring(slash, rest.length() - slash)
    }
    Int colon = authority.indexOf(":")
    String host = authority
    Int port = 80
    if colon > 0 {
        host = authority.substring(0, colon)
        String ps = authority.substring(colon + 1, authority.length() - colon - 1)
        Result<Int, Error> pr = parseIntLocal(ps)
        if pr.isErr() {
            return new Url("", 0, "", false)
        }
        port = pr.value()
    }
    if host.length() == 0 || !validPort(port) {
        return new Url("", 0, "", false)
    }
    return new Url(host, port, path, true)
}

// 本地十进制解析（避免 net 依赖 xdk.text 的包方向）。
static Result<Int, Error> parseIntLocal(String s) {
    if s.length() == 0 {
        return Err(netError(ErrorKind.InvalidArgument, "parseIntLocal: 空串"))
    }
    Int v = 0
    Int i = 0
    while i < s.length() {
        String ch = s.substring(i, 1)
        Int d = -1
        if ch == "0" { d = 0 }
        if ch == "1" { d = 1 }
        if ch == "2" { d = 2 }
        if ch == "3" { d = 3 }
        if ch == "4" { d = 4 }
        if ch == "5" { d = 5 }
        if ch == "6" { d = 6 }
        if ch == "7" { d = 7 }
        if ch == "8" { d = 8 }
        if ch == "9" { d = 9 }
        if d < 0 {
            return Err(netError(ErrorKind.InvalidArgument, "parseIntLocal: 非法字符"))
        }
        v = v * 10 + d
        i = i + 1
    }
    return Ok(v)
}

// Request：出站请求（方法 + URL + 头 + 文本体）。
class Request {
    String method
    String url
    List<String> headers
    String body

    Request(String m, String u, List<String> h, String b) {
        self.method = m
        self.url = u
        self.headers = h
        self.body = b
    }
}

// Response：入站响应（状态码 + 文本体 + 头）。
class Response {
    Int code
    String payload
    List<String> headers

    Response(Int c, String p, List<String> h) {
        self.code = c
        self.payload = p
        self.headers = h
    }

    Int status() {
        return self.code
    }

    String body() {
        return self.payload
    }

    // 头以 `name: value` 行保存；未命中返回空串。
    String header(String name) {
        String prefix = $"{name}:"
        Int i = 0
        while i < self.headers.length() {
            String line = self.headers.get(i)
            if line.length() >= prefix.length() {
                if line.substring(0, prefix.length()) == prefix {
                    return line.substring(prefix.length(), line.length() - prefix.length())
                }
            }
            i = i + 1
        }
        return ""
    }
}

// httpRequest：发送请求并返回响应；首版忽略自定义头（运行时未接入）。
Result<Response, Error> httpRequest(String method, String url, String body) {
    Url u = parseUrl(url)
    if !u.valid {
        return Err(netError(ErrorKind.InvalidArgument, $"httpRequest: 非法 URL {url}"))
    }
    String payload = httpRequestRaw(method, u.host, u.port, u.path, body)
    Int code = httpErrorRaw()
    if code != 0 {
        return Err(netError(netKind(code), $"httpRequest: {method} {url} 失败"))
    }
    Int status = httpStatusRaw()
    List<String> h = []
    return Ok(new Response(status, payload, h))
}

Result<Response, Error> httpGet(String url) {
    return httpRequest("GET", url, "")
}

Result<Response, Error> httpPost(String url, String body) {
    return httpRequest("POST", url, body)
}
