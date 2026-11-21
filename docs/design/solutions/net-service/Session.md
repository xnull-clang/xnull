# `Session`

| 项 | 值 |
| --- | --- |
| 类型 | `class Session` |
| 包 | `xdk.net.service` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Bytes`、`Connection`、`SessionHandler`、`HeartbeatPolicy`、`Map`、`Error` |

---

## 1. 定位

每连接一个的会话对象：持有连接引用、会话 ID、打开/活动时间、消息/字节计数、字符串属性；提供发送、空闲判断、会话处理循环与关闭。

不做：连接创建、accept、TLS、协议编解码、会话持久化、跨连接共享、认证、路由。

`Session` 借用 `Connection`；关闭会话会关闭连接。一个连接至多一个会话，由 `Connection.openSession` 保证。

---

## 2. 设计逻辑

- 字段：会话 ID、连接、读缓冲、心跳策略、打开时间、最后活动、收/发消息数、收/发字节数、属性、会话打开标志。
- `run` 是会话模式的终止操作：驱动 `SessionHandler` 生命周期；读取块作为 `onMessage` 消息。
- `onOpen` 失败时仍调用 `onError` 与 `onClose`，保留原始 `onOpen` 错误；若关闭资源失败，返回关闭错误。`onError`/`onClose` 的返回值仅用于诊断。
- 心跳启用时，`run` 在每次读取前把读截止设为 `now + timeout`；读返回 `Timeout` 即空闲超时，进入 `onError`/`onClose`。
- `send` 委托 `Connection.writeAll`；成功后更新发送计数与活动时间；不建立应用层队列。
- `close` 只置会话关闭标志并关闭连接；连接关闭也会使 `isOpen` 为 false。
- 属性是进程内字符串映射；非线程安全；会话通常由单任务驱动。
- 无全局；不持有服务/服务器引用。
- 读缓冲由 `ServiceOptions.readBufferBytes` 决定；消息是读取块，分帧由 handler 负责。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_sessionId` | `Long` | final | 会话 ID，≥0 |
| `_connection` | `Connection` | final | 借用的连接；非 null |
| `_readBufferBytes` | `Int` | final | 读缓冲，>0 |
| `_heartbeatPolicy` | `HeartbeatPolicy` | final | 心跳策略副本 |
| `_openedAtMonoMillis` | `Long` | final | 打开时间，≥0 |
| `_lastActivityMonoMillis` | `Long` | 可变 | 最后活动，≥打开时间 |
| `_messagesReceived` | `Long` | 可变 | 累计收消息，≥0 |
| `_messagesSent` | `Long` | 可变 | 累计发消息，≥0 |
| `_bytesReceived` | `Long` | 可变 | 累计收字节，≥0 |
| `_bytesSent` | `Long` | 可变 | 累计发字节，≥0 |
| `_attributes` | `Map<String,String>` | 可变 | 会话属性；键非空 |
| `_sessionOpen` | `Bool` | 可变 | 会话逻辑打开标志 |

不变量：ID/时间/计数非负；连接/策略非 null；属性键非空、值非 null；`close` 后 `_sessionOpen=false`；`isOpen` 同时要求连接打开。

---

## 4. 生命周期

由 `Connection.openSession` 创建；每个连接至多一个。必须 `close()`；`close()` 幂等；关闭后 `send`/`run` 返回 `Unavailable`。连接关闭后会话不可重新打开。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Session(Long sessionId, Connection connection, Int readBufferBytes, HeartbeatPolicy heartbeatPolicy)` | ID≥0；其余非 null；缓冲>0 | 同上 | 非法 → panic |

构造器公开供 `Connection`/测试使用；业务代码通过 `Connection.openSession` 获取。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `sessionId` | 会话 ID | 无 | `Long` | 无 |
| `connection` | 借用连接 | 无 | `Connection` | 无 |
| `openedAtMonoMillis` | 打开时间 | 无 | `Long` | 无 |
| `lastActivityMonoMillis` | 最后活动 | 无 | `Long` | 无 |
| `messageCount` | 累计收消息 | 无 | `Long` | 无 |
| `sentMessageCount` | 累计发消息 | 无 | `Long` | 无 |
| `bytesReceived` | 累计收字节 | 无 | `Long` | 无 |
| `bytesSent` | 累计发字节 | 无 | `Long` | 无 |
| `readBufferBytes` | 读缓冲 | 无 | `Int` | 无 |
| `heartbeatPolicy` | 心跳策略副本 | 无 | `HeartbeatPolicy` | 无 |
| `attribute` | 读属性/无 | `String name` | `String?` | 空名 → panic |
| `setAttribute` | 写属性 | `String name, String value` | `void` | 空名/null 值 → panic |
| `removeAttribute` | 删除属性/旧值 | `String name` | `String?` | 空名 → panic |
| `attributes` | 属性快照 | 无 | `Map<String,String>` | 无 |
| `send` | 发送消息 | `Context context, Bytes data` | `Result<Unit, Error>` | `Unavailable`/`Network`/`Timeout`/`Cancelled`/`Busy` |
| `isIdle` | 是否空闲超时 | `Long nowMonoMillis` | `Bool` | <0 → panic |
| `isOpen` | 是否打开 | 无 | `Bool` | 无 |
| `run` | 会话处理循环 | `Context context, SessionHandler handler` | `Result<Unit, Error>` | 业务/IO/`Cancelled` |
| `describe` | 单行摘要 | 无 | `String` | 无 |
| `close` | 关闭会话/连接 | 无 | `Result<Unit, Error>` | `Io`（诊断） |

说明：

- `send` 在连接排空时返回 `Busy`；在关闭后返回 `Unavailable`。
- `isIdle` 只使用 `HeartbeatPolicy`；策略禁用时恒为 false。
- `run` 只能调用一次；它是终止操作，返回前关闭会话与连接。
- `run` 的 `onMessage` 消息是读取块；长度不超过读缓冲，不保证是完整协议帧。
- 启用心跳时 `run` 在每次读取前设置读截止；禁用时沿用调用方已设置的截止（若有）。
- 属性不参与协议；不记录敏感值到日志。
- `describe` 不含属性值、载荷或密钥。

---

## 8. 使用的技术

- 会话包装；
- 心跳读截止；
- 生命周期回调；
- 借用消息；
- 属性快照；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、Long、Int、Bool、Map、Result；
- 运行时：`monotonicMillis`、`toLong`、`slice`、`str`；
- 接口：`Context`、`Bytes`、`Connection`、`SessionHandler`、`HeartbeatPolicy`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`Context`、`Bytes`、`Connection`、`SessionHandler`、`HeartbeatPolicy`、`Error`、`BasicError`、`ErrorKind`、`Map`、`monotonicMillis`、`toLong`、`slice`、`str`、`unavailableError`。

---

## 11. 所有权与并发

借用 `Connection`；关闭会话会关闭连接；连接关闭使会话失效。会话通常单任务驱动；`run` 单消费者；`send` 可与读循环并发（一个 writer），但属性/计数非线程安全。
相等：引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：`Session session = connection.openSession(32768, policy).value()`；`session.setAttribute("tenant", "a")`；`session.run(context, handler)`；handler 中 `session.send(context, reply)`。  
反例：同一连接创建两个会话；关闭后 `send`；把 `send` 当可靠入队（无应用层队列）；保存 `onMessage` 的 `message` 引用；在 `run` 外并发读；把属性当持久化存储；把 `isIdle` 当协议心跳。

---

## 13. 测试/场景义务

构造/非法参数；ID/连接/时间；属性增删查/快照/空名/null；`send` 成功/排空/关闭/短写；计数；`isIdle` 禁用/边界/超时；`isOpen` 与连接联动；`run` 正常/EOF/错误/取消/心跳超时/`onOpen` 失败；`onError` 在 `onClose` 前；重复 `close`；`describe` 脱敏。

---

## 14. XNull 伪代码

```xnull
class Session {
    final Long _sessionId
    final Connection _connection
    final Int _readBufferBytes
    final HeartbeatPolicy _heartbeatPolicy
    final Long _openedAtMonoMillis
    Long _lastActivityMonoMillis
    Long _messagesReceived
    Long _messagesSent
    Long _bytesReceived
    Long _bytesSent
    Map<String, String> _attributes
    Bool _sessionOpen

    Session(Long sessionId, Connection connection, Int readBufferBytes,
            HeartbeatPolicy heartbeatPolicy) {
        if connection == null || heartbeatPolicy == null {
            throw "Session: null argument"
        }
        if sessionId < 0 { throw "Session: negative id" }
        if readBufferBytes <= 0 { throw "Session: invalid buffer" }
        _sessionId = sessionId
        _connection = connection
        _readBufferBytes = readBufferBytes
        _heartbeatPolicy = heartbeatPolicy.copy()
        _openedAtMonoMillis = monotonicMillis()
        _lastActivityMonoMillis = _openedAtMonoMillis
        _messagesReceived = 0
        _messagesSent = 0
        _bytesReceived = 0
        _bytesSent = 0
        _attributes = [:]
        _sessionOpen = true
    }

    Long sessionId() { return _sessionId }
    Connection connection() { return _connection }
    Long openedAtMonoMillis() { return _openedAtMonoMillis }
    Long lastActivityMonoMillis() { return _lastActivityMonoMillis }
    Long messageCount() { return _messagesReceived }
    Long sentMessageCount() { return _messagesSent }
    Long bytesReceived() { return _bytesReceived }
    Long bytesSent() { return _bytesSent }
    Int readBufferBytes() { return _readBufferBytes }
    HeartbeatPolicy heartbeatPolicy() { return _heartbeatPolicy.copy() }

    String? attribute(String name) {
        if name == null || name == "" {
            throw "Session.attribute: empty name"
        }
        if !_attributes.has(name) { return null }
        return _attributes.get(name)
    }

    void setAttribute(String name, String value) {
        if name == null || name == "" {
            throw "Session.setAttribute: empty name"
        }
        if value == null {
            throw "Session.setAttribute: null value"
        }
        _attributes.put(name, value)
    }

    String? removeAttribute(String name) {
        if name == null || name == "" {
            throw "Session.removeAttribute: empty name"
        }
        if !_attributes.has(name) { return null }
        String value = _attributes.get(name)
        _attributes.remove(name)
        return value
    }

    Map<String, String> attributes() { return _attributes.copy() }

    Result<Unit, Error> send(Context context, Bytes data) {
        if context == null || data == null {
            throw "Session.send: null argument"
        }
        if !self.isOpen() { return Err(unavailableError("session")) }
        Result<Unit, Error> result = _connection.writeAll(context, data)
        if result.isErr() { return result }
        _messagesSent = _messagesSent + 1
        _bytesSent = _bytesSent + toLong(data.length())
        _lastActivityMonoMillis = _connection.lastActivityMonoMillis()
        return Ok(unit)
    }

    Bool isIdle(Long nowMonoMillis) {
        if nowMonoMillis < 0 { throw "Session.isIdle: negative" }
        return _heartbeatPolicy.isExpired(nowMonoMillis, _lastActivityMonoMillis)
    }

    Bool isOpen() {
        if !_sessionOpen { return false }
        return _connection.isOpen()
    }

    Result<Unit, Error> run(Context context, SessionHandler handler) {
        if context == null || handler == null {
            throw "Session.run: null argument"
        }
        if !self.isOpen() { return Err(unavailableError("session")) }
        Result<Unit, Error> opened = handler.onOpen(context, self)
        if opened.isErr() {
            Error openError = opened.error()
            handler.onError(context, self, openError)
            Result<Unit, Error> sessionClosed = self.close()
            handler.onClose(context, self, openError)
            if sessionClosed.isErr() { return Err(sessionClosed.error()) }
            return Err(openError)
        }
        Bytes buffer = Bytes.alloc(_readBufferBytes)
        Error? cause = null
        Result<Unit, Error> result = Ok(unit)
        while self.isOpen() && !context.isCancelled() {
            if _heartbeatPolicy.isEnabled() {
                Long deadline = monotonicMillis()
                    + _heartbeatPolicy.getTimeoutMillis()
                Result<Unit, Error> deadlineResult =
                    _connection.setReadDeadline(deadline)
                if deadlineResult.isErr() {
                    Error deadlineError = deadlineResult.error()
                    cause = deadlineError
                    result = Err(deadlineError)
                    break
                }
            }
            Result<Int, Error> read = _connection.read(context, buffer)
            if read.isErr() {
                Error readError = read.error()
                cause = readError
                result = Err(readError)
                break
            }
            if read.value() == 0 { break }
            Bytes message = slice(buffer, 0, read.value())
            _messagesReceived = _messagesReceived + 1
            _bytesReceived = _bytesReceived + toLong(read.value())
            _lastActivityMonoMillis = _connection.lastActivityMonoMillis()
            Result<Unit, Error> handled = handler.onMessage(
                context, self, message)
            if handled.isErr() {
                Error handledError = handled.error()
                cause = handledError
                result = Err(handledError)
                break
            }
        }
        if context.isCancelled() && cause == null {
            Error cancelled = new BasicError(
                ErrorKind.Cancelled, "session cancelled")
            cause = cancelled
            result = Err(cancelled)
        }
        if cause != null {
            Error finalCause = cause as Error
            Result<Unit, Error> reported = handler.onError(
                context, self, finalCause)
            if reported.isErr() && result.isOk() {
                result = Err(reported.error())
            }
        }
        Result<Unit, Error> sessionClosed = self.close()
        handler.onClose(context, self, cause)
        if result.isOk() && sessionClosed.isErr() {
            result = Err(sessionClosed.error())
        }
        return result
    }

    String describe() {
        return "session id=" + str(_sessionId)
            + " connection=" + str(_connection.connectionId())
            + " open=" + str(self.isOpen())
            + " messagesIn=" + str(_messagesReceived)
            + " messagesOut=" + str(_messagesSent)
            + " bytesIn=" + str(_bytesReceived)
            + " bytesOut=" + str(_bytesSent)
    }

    Result<Unit, Error> close() {
        if !_sessionOpen { return Ok(unit) }
        _sessionOpen = false
        return _connection.close()
    }
}
```
