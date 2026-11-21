# `Connection`

| 项 | 值 |
| --- | --- |
| 类型 | `class Connection implements ByteStream` |
| 包 | `xdk.net.service` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Bytes`、`ByteStream`、`SocketAddress`、`Session`、`ConnectionHandler`、`HeartbeatPolicy`、`Error` |

---

## 1. 定位

服务层连接：包装一个 `ByteStream`（`TcpStream`、`TlsStream` 或调用方提供的流）、本地/对端地址、连接 ID、活动时间、累计读写字节；提供原始读写、排空标记、会话创建与原始处理循环。

不做：accept、DNS、TLS 握手、连接池、帧解析、应用层写队列、重连、会话持久化、裸 socket 选项。

`Connection` 不复制 `TcpStream`/`TlsStream`，只持有 `ByteStream` 引用并委托读写。

---

## 2. 设计逻辑

- 字段：底层流、地址、ID、打开时间、最后活动时间、累计读写、读缓冲、打开/排空标志、唯一会话。
- 实现 `ByteStream` 的 `read`/`write`/`writeAll`/截止时间/`isOpen`/`close`；语义与  一致：0=EOF、短写正常、`writeAll` 循环、`close` 幂等。
- `read` 成功后更新 `_readBytes` 与 `_lastActivityMonoMillis`；`write`/`writeAll` 成功写入后更新 `_writtenBytes` 与活动时间。
- `beginDrain` 置排空标志：允许继续读，拒绝新的写；用于服务端优雅停机。
- 每个连接至多一个 `Session`；`openSession` 幂等，返回同一会话；连接关闭后不能新建会话。
- `process` 是原始字节模式的终止操作：驱动 `ConnectionHandler` 生命周期并最终关闭连接。
- `onOpen` 失败时仍调用 `onError` 与 `onClose`，保留原始 `onOpen` 错误；若关闭资源失败，返回关闭错误。`onError`/`onClose` 的返回值仅用于诊断。
- 一个 reader 与一个 writer 可并发；多个 reader/多个 writer 不承诺安全。
- 无全局；不持有服务/服务器引用。
- 不建立应用层写队列；写背压由底层流与 `writeTimeout` 提供。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_stream` | `ByteStream` | final | 底层流；非 null |
| `_local` | `SocketAddress` | final | 本地地址；非 null |
| `_remote` | `SocketAddress` | final | 对端地址；非 null |
| `_connectionId` | `Long` | final | 连接 ID，≥0 |
| `_openedAtMonoMillis` | `Long` | final | 打开时间，≥0 |
| `_readBufferBytes` | `Int` | final | `process` 读缓冲，>0 |
| `_lastActivityMonoMillis` | `Long` | 可变 | 最后成功读写时间，≥打开时间 |
| `_readBytes` | `Long` | 可变 | 累计读字节，≥0 |
| `_writtenBytes` | `Long` | 可变 | 累计写字节，≥0 |
| `_open` | `Bool` | 可变 | 是否可 I/O |
| `_draining` | `Bool` | 可变 | 是否拒绝新写 |
| `_session` | `Session?` | 可变 | 唯一会话；至多一个 |

不变量：流/地址非 null；ID/时间/计数非负；`_session` 只赋值一次；`close` 后 `_open=false`；`_draining` 只在打开时置位；连接关闭使会话失效。

---

## 4. 生命周期

由服务端 accept 或客户端 connect 创建；也可由调用方包装已有 `ByteStream`。必须 `close()`；`close()` 幂等；关闭后 I/O 返回 `Unavailable`。排空不是关闭。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Connection(Long connectionId, ByteStream stream, SocketAddress local, SocketAddress remote, Int readBufferBytes)` | 全部非 null；ID≥0；缓冲>0 | 同上 | null/负值/零缓冲 → panic |

构造器公开供服务实现/测试使用；业务代码通常从 `Server`/`Client` 获取连接。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `connectionId` | 连接 ID | 无 | `Long` | 无 |
| `localAddress` | 本地地址 | 无 | `SocketAddress` | 无 |
| `remoteAddress` | 对端地址 | 无 | `SocketAddress` | 无 |
| `openedAtMonoMillis` | 打开时间 | 无 | `Long` | 无 |
| `lastActivityMonoMillis` | 最后活动 | 无 | `Long` | 无 |
| `readBytes` | 累计读 | 无 | `Long` | 无 |
| `writtenBytes` | 累计写 | 无 | `Long` | 无 |
| `readBufferBytes` | 读缓冲 | 无 | `Int` | 无 |
| `read` | 读字节 | `Context context, Bytes buffer` | `Result<Int, Error>` | `Unavailable`/`Network`/`Timeout`/`Cancelled` |
| `write` | 写字节 | `Context context, Bytes data` | `Result<Int, Error>` | 同上 + `Busy`（排空） |
| `writeAll` | 写全 | `Context context, Bytes data` | `Result<Unit, Error>` | 同上 |
| `setReadDeadline` | 读截止 | `Long deadlineMonoMillis` | `Result<Unit, Error>` | `Unavailable` |
| `setWriteDeadline` | 写截止 | `Long deadlineMonoMillis` | `Result<Unit, Error>` | `Unavailable` |
| `isOpen` | 是否可 I/O | 无 | `Bool` | 无 |
| `beginDrain` | 进入排空 | 无 | `Result<Unit, Error>` | `Unavailable` |
| `isDraining` | 是否排空 | 无 | `Bool` | 无 |
| `hasSession` | 是否已有会话 | 无 | `Bool` | 无 |
| `session` | 当前会话/无 | 无 | `Session?` | 无 |
| `openSession` | 创建默认会话 | 无 | `Result<Session, Error>` | `Unavailable` |
| `openSession` | 创建会话 | `Int readBufferBytes, HeartbeatPolicy heartbeatPolicy` | `Result<Session, Error>` | `Unavailable`/参数非法 |
| `process` | 原始处理循环 | `Context context, ConnectionHandler handler` | `Result<Unit, Error>` | 业务/IO/`Cancelled` |
| `describe` | 单行摘要 | 无 | `String` | 无 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |

说明：

- `read` 返回 0 表示 EOF；不把 0 当“暂时无数据”。
- `write` 可短写；调用方用 `writeAll` 写全。
- 排空期间 `read` 仍可用；`write`/`writeAll` 返回 `Busy`，避免停机时接受新输出。
- `beginDrain` 幂等；关闭后调用返回 `Unavailable`。
- `openSession` 返回已有会话；已关闭连接无会话时返回 `Unavailable`。
- `process` 只能调用一次；它拥有读取循环并在返回前关闭连接。
- `describe` 不含载荷、会话属性或密钥。

---

## 8. 使用的技术

- `ByteStream` 组合；
- 0=EOF / 短写 / `writeAll`；
- 单调活动时间；
- 排空标记；
- 单会话缓存；
- 生命周期回调驱动；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、protocol 实现、泛型引用、Long、Int、Bool、Result；
- 运行时：`monotonicMillis`、`nextSessionIdRaw`、`toLong`、`slice`、`str`；
- 接口：`Context`、`Bytes`、`ByteStream`、`SocketAddress`、`Session`、`ConnectionHandler`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`Context`、`Bytes`、`ByteStream`、`SocketAddress`、`Session`、`ConnectionHandler`、`HeartbeatPolicy`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`、`monotonicMillis`、`nextSessionIdRaw`、`toLong`、`slice`、`str`。

---

## 11. 所有权与并发

拥有 `ByteStream`；`Session` 借用连接；一个 reader + 一个 writer；`close` 可并发；`process` 单消费者且终止性；`session`/`openSession` 非线程安全，应在连接分派前完成。
相等：引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：`Connection connection = acceptedConnection`；`connection.writeAll(context, request)`；`Session session = connection.openSession(32768, new HeartbeatPolicy()).value()`；`session.run(context, handler)`。  
反例：把 0 当“暂时无数据”；排空后继续写；为同一连接创建第二个会话；`process` 与手写 reader 并行；关闭后继续读；忽略短写；保存 `message` 引用。

---

## 13. 测试/场景义务

构造/非法参数；ID/地址/时间；read EOF/短读/计数；write 短写/排空拒绝/计数；`writeAll`；截止；`isOpen`/`close` 幂等；`beginDrain`；单会话/重复 `openSession`；`process` 正常/EOF/错误/取消/`onOpen` 失败；`onError` 在 `onClose` 前；关闭后 I/O；`describe` 脱敏。

---

## 14. XNull 伪代码

```xnull
class Connection implements ByteStream {
    final ByteStream _stream
    final SocketAddress _local
    final SocketAddress _remote
    final Long _connectionId
    final Long _openedAtMonoMillis
    final Int _readBufferBytes
    Long _lastActivityMonoMillis
    Long _readBytes
    Long _writtenBytes
    Bool _open
    Bool _draining
    Session? _session

    Connection(Long connectionId, ByteStream stream, SocketAddress local,
               SocketAddress remote, Int readBufferBytes) {
        if stream == null || local == null || remote == null {
            throw "Connection: null argument"
        }
        if connectionId < 0 { throw "Connection: negative id" }
        if readBufferBytes <= 0 { throw "Connection: invalid buffer" }
        _stream = stream
        _local = local
        _remote = remote
        _connectionId = connectionId
        _openedAtMonoMillis = monotonicMillis()
        _readBufferBytes = readBufferBytes
        _lastActivityMonoMillis = _openedAtMonoMillis
        _readBytes = 0
        _writtenBytes = 0
        _open = true
        _draining = false
        _session = null
    }

    Long connectionId() { return _connectionId }
    SocketAddress localAddress() { return _local }
    SocketAddress remoteAddress() { return _remote }
    Long openedAtMonoMillis() { return _openedAtMonoMillis }
    Long lastActivityMonoMillis() { return _lastActivityMonoMillis }
    Long readBytes() { return _readBytes }
    Long writtenBytes() { return _writtenBytes }
    Int readBufferBytes() { return _readBufferBytes }

    Result<Int, Error> read(Context context, Bytes buffer) {
        if context == null || buffer == null {
            throw "Connection.read: null argument"
        }
        if !self.isOpen() { return Err(unavailableError("connection")) }
        Result<Int, Error> result = _stream.read(context, buffer)
        if result.isErr() { return result }
        if result.value() > 0 {
            _readBytes = _readBytes + toLong(result.value())
            _lastActivityMonoMillis = monotonicMillis()
        }
        return result
    }

    Result<Int, Error> write(Context context, Bytes data) {
        if context == null || data == null {
            throw "Connection.write: null argument"
        }
        if !self.isOpen() { return Err(unavailableError("connection")) }
        if _draining {
            return Err(new BasicError(ErrorKind.Busy, "connection draining"))
        }
        Result<Int, Error> result = _stream.write(context, data)
        if result.isErr() { return result }
        if result.value() > 0 {
            _writtenBytes = _writtenBytes + toLong(result.value())
            _lastActivityMonoMillis = monotonicMillis()
        }
        return result
    }

    Result<Unit, Error> writeAll(Context context, Bytes data) {
        if context == null || data == null {
            throw "Connection.writeAll: null argument"
        }
        Int total = 0
        while total < data.length() {
            Bytes part = slice(data, total, data.length())
            Result<Int, Error> written = self.write(context, part)
            if written.isErr() { return Err(written.error()) }
            if written.value() == 0 {
                return Err(unavailableError("connection write"))
            }
            total = total + written.value()
        }
        return Ok(unit)
    }

    Result<Unit, Error> setReadDeadline(Long deadlineMonoMillis) {
        if !self.isOpen() { return Err(unavailableError("connection")) }
        return _stream.setReadDeadline(deadlineMonoMillis)
    }

    Result<Unit, Error> setWriteDeadline(Long deadlineMonoMillis) {
        if !self.isOpen() { return Err(unavailableError("connection")) }
        return _stream.setWriteDeadline(deadlineMonoMillis)
    }

    Bool isOpen() {
        if !_open { return false }
        return _stream.isOpen()
    }

    Result<Unit, Error> beginDrain() {
        if !self.isOpen() { return Err(unavailableError("connection")) }
        _draining = true
        return Ok(unit)
    }

    Bool isDraining() { return _draining }
    Bool hasSession() { return _session != null }
    Session? session() { return _session }

    Result<Session, Error> openSession() {
        return self.openSession(_readBufferBytes, new HeartbeatPolicy())
    }

    Result<Session, Error> openSession(Int readBufferBytes,
                                       HeartbeatPolicy heartbeatPolicy) {
        if heartbeatPolicy == null {
            throw "Connection.openSession: null heartbeat policy"
        }
        if readBufferBytes <= 0 {
            throw "Connection.openSession: invalid buffer"
        }
        if !self.isOpen() { return Err(unavailableError("connection")) }
        if _session != null { return Ok(_session as Session) }
        Session created = new Session(nextSessionIdRaw(), self,
            readBufferBytes, heartbeatPolicy.copy())
        _session = created
        return Ok(created)
    }

    Result<Unit, Error> process(Context context, ConnectionHandler handler) {
        if context == null || handler == null {
            throw "Connection.process: null argument"
        }
        if !self.isOpen() { return Err(unavailableError("connection")) }
        Result<Unit, Error> opened = handler.onOpen(context, self)
        if opened.isErr() {
            Error openError = opened.error()
            handler.onError(context, self, openError)
            Result<Unit, Error> connectionClosed = self.close()
            handler.onClose(context, self, openError)
            if connectionClosed.isErr() { return Err(connectionClosed.error()) }
            return Err(openError)
        }
        Bytes buffer = Bytes.alloc(_readBufferBytes)
        Error? cause = null
        Result<Unit, Error> result = Ok(unit)
        while self.isOpen() && !context.isCancelled() {
            Result<Int, Error> read = self.read(context, buffer)
            if read.isErr() {
                Error readError = read.error()
                cause = readError
                result = Err(readError)
                break
            }
            if read.value() == 0 { break }
            Bytes message = slice(buffer, 0, read.value())
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
                ErrorKind.Cancelled, "connection cancelled")
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
        Result<Unit, Error> connectionClosed = self.close()
        handler.onClose(context, self, cause)
        if result.isOk() && connectionClosed.isErr() {
            result = Err(connectionClosed.error())
        }
        return result
    }

    String describe() {
        return "connection id=" + str(_connectionId)
            + " local=" + _local.text()
            + " remote=" + _remote.text()
            + " open=" + str(self.isOpen())
            + " draining=" + str(_draining)
            + " readBytes=" + str(_readBytes)
            + " writtenBytes=" + str(_writtenBytes)
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        _draining = false
        return _stream.close()
    }
}
```
