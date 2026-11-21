# `Client`

| 项 | 值 |
| --- | --- |
| 类型 | `class Client` |
| 包 | `xdk.net.service` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`SocketAddress`、`TcpClient`、`TcpStream`、`TlsStream`、`TlsConfig`、`ByteStream`、`Connection`、`Session`、`ServiceOptions`、`ReconnectPolicy`、`HeartbeatPolicy`、`ServiceStats`、`ServiceState`、`Error` |

---

## 1. 定位

通用流式客户端：连接地址或主机名、按策略重连、保存当前连接、创建会话、关闭、提供统计。

不做：服务端 accept、消息重放、连接池、DNS 缓存、服务发现、多活动连接、HTTP/WS 协议、会话持久化。

TLS 由 `ServiceOptions.tlsConfig` 开启：客户端用 `TlsStream.connect` 包装 TCP 流；本类型不重复 TLS 握手。

---

## 2. 设计逻辑

- 字段：TCP 客户端、选项快照、重连策略、当前连接、最近对端地址、最近错误、状态、打开标志、重连次数/尝试、累计连接/会话、累计错误、启动时间。
- `connect` 先关闭/丢弃已关闭的旧连接，再建立 TCP；TLS 配置存在时执行 `TlsStream.connect`；成功后包装 `Connection`。
- 同一时刻最多一个活动连接；已有活动连接时 `connect`/`reconnect` 返回 `Busy`。
- `reconnect` 只执行一次尝试：检查策略、按 100ms 分片等待、递增 attempt、调用 `connect`；失败保留错误，成功由 `connect` 归零 attempt。
- `close` 关闭当前连接并置 `Closed`；幂等。
- `openSession` 在当前连接上创建/复用唯一会话；计数只在首次创建时增加。
- `stats` 从当前连接/会话与累计计数器生成快照；关闭后仍可读。
- 无全局；无裸 socket；无应用层队列。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_tcpClient` | `TcpClient` | final |  TCP 客户端；使用选项副本 |
| `_options` | `ServiceOptions` | final | 配置快照 |
| `_policy` | `ReconnectPolicy` | final | 重连策略快照 |
| `_startedAtMonoMillis` | `Long` | final | 启动时间，≥0 |
| `_connection` | `Connection?` | 可变 | 当前连接；至多一个 |
| `_lastRemote` | `SocketAddress?` | 可变 | 最近成功对端 |
| `_lastError` | `Error?` | 可变 | 最近失败 |
| `_state` | `ServiceState` | 可变 | 生命周期 |
| `_open` | `Bool` | 可变 | 客户端可用 |
| `_attempt` | `Int` | 可变 | 连续重连尝试，≥0 |
| `_totalConnections` | `Long` | 可变 | 累计成功连接，≥0 |
| `_totalSessions` | `Long` | 可变 | 累计创建会话，≥0 |
| `_reconnectAttempts` | `Long` | 可变 | 累计重连尝试，≥0 |
| `_errors` | `Long` | 可变 | 累计失败，≥0 |

不变量：final 字段只赋值一次；当前连接至多一个；`_state=Running` 时连接非 null 且打开；`close` 后 `_open=false`；累计计数非负；`_attempt` 在成功连接后归零。

---

## 4. 生命周期

构造 → `connect` →（可选 `openSession`/`reconnect`）→ `close`。构造后可用；`close` 后 `connect`/`reconnect` 返回 `Unavailable`；`close` 幂等。连接失败不关闭客户端，允许再次 `connect`/`reconnect`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Client(ServiceOptions options)` | 非 null | 非 null；TLS 客户端配置在 connect 时校验 | null → panic |

构造时复制 options 与 reconnect policy；`TcpClient` 使用 socket 选项副本。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `connect` | 连接地址 | `Context context, SocketAddress remote` | `Result<Connection, Error>` | `Busy`/`Network`/`Timeout`/`Cancelled`/TLS |
| `connect` | DNS + 连接 | `Context context, String host, Int port` | `Result<Connection, Error>` | 同上 + `NotFound` |
| `connection` | 当前连接/无 | 无 | `Connection?` | 无 |
| `state` | 生命周期 | 无 | `ServiceState` | 无 |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 |
| `attempt` | 当前重连尝试 | 无 | `Int` | 无 |
| `lastError` | 最近错误/无 | 无 | `Error?` | 无 |
| `reconnectPolicy` | 策略副本 | 无 | `ReconnectPolicy` | 无 |
| `openSession` | 当前连接建会话 | 无 | `Result<Session, Error>` | `Unavailable` |
| `openSession` | 指定缓冲/心跳 | `Int readBufferBytes, HeartbeatPolicy heartbeatPolicy` | `Result<Session, Error>` | `Unavailable`/参数非法 |
| `reconnect` | 单次重连尝试 | `Context context` | `Result<Connection, Error>` | 策略拒绝/`Busy`/`Unavailable`/连接失败 |
| `stats` | 统计快照 | 无 | `ServiceStats` | 无 |
| `options` | 配置副本 | 无 | `ServiceOptions` | 无 |
| `close` | 关闭客户端/连接 | 无 | `Result<Unit, Error>` | `Io`（诊断） |

说明：

- `connect` 成功后 `_attempt=0`、`_lastError=null`、`_state=Running`。
- `connect` 失败后 `_state=Stopped`、`_lastError` 更新、`_errors++`；客户端仍可再次连接。
- `reconnect` 在已有活动连接时返回 `Busy`；不自动关闭活动连接。
- `reconnect` 等待按 100ms 分片，期间响应 `Context` 取消；取消返回 `Cancelled`。错误分类来自最近一次 `connect` 失败；若上层有协议错误，先用 `reconnectPolicy().shouldRetry(attempt, error)` 判断再调用。
- `openSession` 返回已有会话；不重复计 `totalSessions`。
- `state` 若观察到连接已被外部关闭，返回 `Stopped`，不修改内部状态。
- `isOpen` 只表示客户端对象仍可调用 `connect`/`reconnect`；当前连接是否可 I/O 看 `connection().isOpen()`。
- `stats` 的 `rejectedConnections` 与 `backpressureEvents` 恒为 0；客户端不做接受背压。

---

## 8. 使用的技术

- 单连接状态机；
-  TCP/TLS 组合；
- 退避等待分片；
- 连接/会话计数；
- 幂等关闭；
- 统计快照。

---

## 9. 需要的支撑

- 语言：class、Long、Int、Bool、Result、可空引用；
- 运行时：`monotonicMillis`、`nextConnectionIdRaw`、`nextSessionIdRaw`、`sleepMillis`；
- 接口：`Context`、`SocketAddress`、`TcpClient`、`TcpStream`、`TlsStream`、`TlsConfig`、`Connection`、`Session`、`ServiceOptions`、`ReconnectPolicy`、`ServiceStats`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`Context`、`SocketAddress`、`TcpClient`、`TcpStream`、`TlsStream`、`TlsConfig`、`ByteStream`、`Connection`、`Session`、`ServiceOptions`、`ReconnectPolicy`、`HeartbeatPolicy`、`ServiceStats`、`ServiceState`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`、`monotonicMillis`、`nextConnectionIdRaw`、`sleepMillis`。

---

## 11. 所有权与并发

引用语义；拥有当前 `Connection`；`connect`/`reconnect`/`openSession` 不可并发；`close` 可与其他操作并发（幂等）；`connection` 返回借用引用；`stats` 可并发读取（快照可能不原子）。
相等：引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：`Client client = new Client(options)`；`Connection connection = client.connect(context, remote).value()`；失败后 `client.reconnect(context)`；结束时 `client.close()`。  
反例：同时 `connect` 两个地址；`reconnect` 时保留活动连接；`close` 后继续 `connect`；把 `reconnect` 当无限循环；忽略 `lastError` 的重试分类；期望客户端自动重放消息。

---

## 13. 测试/场景义务

连接成功/拒绝/超时/取消/DNS 失败；TLS 成功/证书失败/缺 serverName；已有连接 `Busy`；`connect` 失败后可重试；`reconnect` 次数/延迟/分类/取消；成功后 attempt 归零；`openSession` 复用/计数；`close` 幂等/关闭后行为；`stats` 计数/关闭后快照；外部关闭连接后的 `state`；`options` 副本独立性。

---

## 14. XNull 伪代码

```xnull
class Client {
    final TcpClient _tcpClient
    final ServiceOptions _options
    final ReconnectPolicy _policy
    final Long _startedAtMonoMillis
    Connection? _connection
    SocketAddress? _lastRemote
    Error? _lastError
    ServiceState _state
    Bool _open
    Int _attempt
    Long _totalConnections
    Long _totalSessions
    Long _reconnectAttempts
    Long _errors

    Client(ServiceOptions options) {
        if options == null { throw "Client: null options" }
        _options = options.copy()
        _policy = _options.getReconnectPolicy()
        _tcpClient = new TcpClient(_options.getSocketOptions())
        _startedAtMonoMillis = monotonicMillis()
        _connection = null
        _lastRemote = null
        _lastError = null
        _state = ServiceState.Created
        _open = true
        _attempt = 0
        _totalConnections = 0
        _totalSessions = 0
        _reconnectAttempts = 0
        _errors = 0
    }

    Result<Connection, Error> connect(Context context, SocketAddress remote) {
        if context == null || remote == null {
            throw "Client.connect: null argument"
        }
        if !_open { return Err(unavailableError("client")) }
        if _connection != null && _connection.isOpen() {
            return Err(new BasicError(ErrorKind.Busy, "client already connected"))
        }
        _connection = null
        _state = ServiceState.Starting
        Result<TcpStream, Error> tcpResult = _tcpClient.connect(context, remote)
        if tcpResult.isErr() {
            self.recordFailure(tcpResult.error())
            return Err(tcpResult.error())
        }
        return self.finishConnect(context, tcpResult.value())
    }

    Result<Connection, Error> connect(Context context, String host, Int port) {
        if context == null { throw "Client.connect: null context" }
        if host == null || host == "" { throw "Client.connect: empty host" }
        if !_open { return Err(unavailableError("client")) }
        if _connection != null && _connection.isOpen() {
            return Err(new BasicError(ErrorKind.Busy, "client already connected"))
        }
        _connection = null
        _state = ServiceState.Starting
        Result<TcpStream, Error> tcpResult = _tcpClient.connect(context, host, port)
        if tcpResult.isErr() {
            self.recordFailure(tcpResult.error())
            return Err(tcpResult.error())
        }
        return self.finishConnect(context, tcpResult.value())
    }

    private Result<Connection, Error> finishConnect(Context context, TcpStream tcp) {
        ByteStream stream = tcp
        TlsConfig? tlsConfig = _options.getTlsConfig()
        if tlsConfig != null {
            Result<TlsStream, Error> tlsResult = TlsStream.connect(
                context, tcp, tlsConfig as TlsConfig)
            if tlsResult.isErr() {
                tcp.close()
                self.recordFailure(tlsResult.error())
                return Err(tlsResult.error())
            }
            stream = tlsResult.value()
        }
        Connection created = new Connection(nextConnectionIdRaw(), stream,
            tcp.localAddress(), tcp.remoteAddress(), _options.getReadBufferBytes())
        _connection = created
        _lastRemote = tcp.remoteAddress()
        _lastError = null
        _state = ServiceState.Running
        _attempt = 0
        _totalConnections = _totalConnections + 1
        return Ok(created)
    }

    private void recordFailure(Error error) {
        _lastError = error
        _state = ServiceState.Stopped
        _errors = _errors + 1
    }

    Connection? connection() { return _connection }

    ServiceState state() {
        if _state == ServiceState.Running && _connection != null
            && !_connection.isOpen() {
            return ServiceState.Stopped
        }
        return _state
    }

    Bool isOpen() { return _open }

    Int attempt() { return _attempt }
    Error? lastError() { return _lastError }
    ReconnectPolicy reconnectPolicy() { return _policy.copy() }

    Result<Session, Error> openSession() {
        if _connection == null || !_connection.isOpen() {
            return Err(unavailableError("client connection"))
        }
        Bool hadSession = _connection.hasSession()
        Result<Session, Error> result = _connection.openSession(
            _options.getReadBufferBytes(), _options.getHeartbeatPolicy())
        if result.isOk() && !hadSession {
            _totalSessions = _totalSessions + 1
        }
        return result
    }

    Result<Session, Error> openSession(Int readBufferBytes,
                                       HeartbeatPolicy heartbeatPolicy) {
        if heartbeatPolicy == null {
            throw "Client.openSession: null heartbeat policy"
        }
        if _connection == null || !_connection.isOpen() {
            return Err(unavailableError("client connection"))
        }
        Bool hadSession = _connection.hasSession()
        Result<Session, Error> result = _connection.openSession(
            readBufferBytes, heartbeatPolicy)
        if result.isOk() && !hadSession {
            _totalSessions = _totalSessions + 1
        }
        return result
    }

    Result<Connection, Error> reconnect(Context context) {
        if context == null { throw "Client.reconnect: null context" }
        if !_open { return Err(unavailableError("client")) }
        if _lastRemote == null {
            return Err(unavailableError("no previous remote"))
        }
        if _connection != null && _connection.isOpen() {
            return Err(new BasicError(ErrorKind.Busy, "client already connected"))
        }
        if _lastError == null {
            if !_policy.shouldRetry(_attempt) {
                return Err(unavailableError("reconnect attempts exhausted"))
            }
        } else {
            if !_policy.shouldRetry(_attempt, _lastError as Error) {
                return Err(unavailableError("reconnect attempts exhausted"))
            }
        }
        Long remaining = _policy.delayMillis(_attempt)
        while remaining > 0 && !context.isCancelled() {
            Long sliceMillis = remaining
            if sliceMillis > 100 { sliceMillis = 100 }
            sleepMillis(sliceMillis)
            remaining = remaining - sliceMillis
        }
        if context.isCancelled() {
            Error cancelled = new BasicError(
                ErrorKind.Cancelled, "reconnect cancelled")
            self.recordFailure(cancelled)
            return Err(cancelled)
        }
        _reconnectAttempts = _reconnectAttempts + 1
        _attempt = _attempt + 1
        return self.connect(context, _lastRemote as SocketAddress)
    }

    ServiceStats stats() {
        Int activeConnections = 0
        Int activeSessions = 0
        Long bytesRead = 0
        Long bytesWritten = 0
        Long messagesReceived = 0
        Long messagesSent = 0
        if _connection != null {
            if _connection.isOpen() { activeConnections = 1 }
            bytesRead = _connection.readBytes()
            bytesWritten = _connection.writtenBytes()
            Session? session = _connection.session()
            if session != null {
                if session.isOpen() { activeSessions = 1 }
                messagesReceived = session.messageCount()
                messagesSent = session.sentMessageCount()
            }
        }
        Long uptimeMillis = monotonicMillis() - _startedAtMonoMillis
        return new ServiceStats(activeConnections, _totalConnections,
            0, activeSessions, _totalSessions, bytesRead, bytesWritten,
            messagesReceived, messagesSent, _reconnectAttempts, 0,
            _errors, uptimeMillis)
    }

    ServiceOptions options() { return _options.copy() }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        _state = ServiceState.Closed
        if _connection == null { return Ok(unit) }
        return _connection.close()
    }
}
```
