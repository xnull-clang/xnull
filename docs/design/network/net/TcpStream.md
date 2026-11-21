# `TcpStream`

| 项 | 值 |
| --- | --- |
| 类型 | `class TcpStream implements ByteStream` |
| 包 | `xdk.net` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Bytes`、`SocketAddress`、`ByteStream`、`Error` |

---

## 1. 定位

TCP 连接流：连接、读、写、写全、半关闭、地址、常用 socket 选项、截止时间、关闭。

不做：TLS、HTTP、连接池、事件驱动、多 reader 并发、裸 socket 选项对象。

---

## 2. 设计逻辑

- 字段 `_handle`、`_local`、`_remote`、`_open`。
- `connect` 支持直接地址与 `host + port`（内部 DNS）。
- `read` 0=EOF；`write` 可短写；`writeAll` 循环写全。
- 所有阻塞操作首参 `Context`；关闭后 `Unavailable`。
- 一个 reader + 一个 writer 可并发；close 可并发。
- `shutdown` 半关闭；`close` 幂等并释放句柄。
- 常用选项用 setter；通用连接选项通过 `SocketOptions` 传入。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_handle` | `TcpHandle` | 运行时句柄 |
| `_local` | `SocketAddress` | 本地地址 |
| `_remote` | `SocketAddress` | 对端地址 |
| `_open` | `Bool` | 是否打开 |
| `_readClosed` | `Bool` | 读方向是否关闭 |
| `_writeClosed` | `Bool` | 写方向是否关闭 |

不变量：handle/地址非 null；close 后 open=false。

---

## 4. 生命周期

`connect`/`accept` 创建；必须 close；close 幂等；关闭后 I/O `Unavailable`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `TcpStream(TcpHandle handle, SocketAddress local, SocketAddress remote)` | 三个非 null | 非 null | null → panic |
| `TcpStream.connect(Context, SocketAddress)` | context/remote | 非 null | `Network`/`Timeout`/`Cancelled` |
| `TcpStream.connect(Context, String, Int)` | host/port | host 非空；port 合法 | 同上 + `NotFound` |

构造器主要供 `TcpListener`/运行时使用。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `connect` | 连接地址 | `Context, SocketAddress` | `Result<TcpStream, Error>` | `Network`/`Timeout`/`Cancelled` |
| `connect` | 带选项连接 | `Context, SocketAddress, SocketOptions` | `Result<TcpStream, Error>` | 同上 |
| `connect` | DNS + 连接 | `Context, String, Int` | `Result<TcpStream, Error>` | 同上 + `NotFound` |
| `connect` | DNS + 选项 | `Context, String, Int, SocketOptions` | `Result<TcpStream, Error>` | 同上 |
| `read` | 读 | `Context, Bytes buffer` | `Result<Int, Error>` | `Unavailable`/`Network`/`Timeout`/`Cancelled` |
| `peek` | 预览读 | `Context, Bytes buffer` | `Result<Int, Error>` | 同上 |
| `write` | 写 | `Context, Bytes data` | `Result<Int, Error>` | 同上 |
| `writeAll` | 写全 | `Context, Bytes data` | `Result<Unit, Error>` | 同上 |
| `shutdown` | 半关闭 | `ShutdownMode mode` | `Result<Unit, Error>` | `Unavailable`/`Network` |
| `localAddress` | 本地地址 | 无 | `SocketAddress` | 无 |
| `remoteAddress` | 对端地址 | 无 | `SocketAddress` | 无 |
| `setNoDelay` | TCP_NODELAY | `Bool enabled` | `Result<Unit, Error>` | `Unavailable`/`Unsupported` |
| `setKeepAlive` | SO_KEEPALIVE | `Bool enabled` | `Result<Unit, Error>` | 同上 |
| `setReadBuffer` | 接收缓冲 | `Int bytes` | `Result<Unit, Error>` | 非法/`Unavailable` |
| `setWriteBuffer` | 发送缓冲 | `Int bytes` | `Result<Unit, Error>` | 同上 |
| `setLinger` | linger | `Int seconds` | `Result<Unit, Error>` | 非法/`Unavailable` |
| `state` | 半关闭状态 | 无 | `SocketState` | 无 |
| `setReadDeadline` | 读截止 | `Long deadlineMonoMillis` | `Result<Unit, Error>` | `Unavailable` |
| `setWriteDeadline` | 写截止 | `Long deadlineMonoMillis` | `Result<Unit, Error>` | 同上 |
| `isOpen` | 是否打开 | 无 | `Bool` | 无 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |

---

## 8. 使用的技术

- OS socket；
- DNS + connect；
- 读写循环；
- 半关闭；
- 单调截止；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、protocol 实现、Bytes、Long、Bool、Result；
- 运行时：`tcpConnectRaw`、`tcpReadRaw`、`tcpPeekRaw`、`tcpWriteRaw`、`tcpShutdownRaw`、`tcpSetBoolOptionRaw`、`tcpSetIntOptionRaw`、`tcpSetDeadlineRaw`、`tcpCloseRaw`、`TcpStreamRaw`；
- 接口：`Context`、`SocketAddress`、`SocketOptions`、`ByteStream`、`Dns`、`ShutdownMode`、`SocketState`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`Context`、`Bytes`、`SocketAddress`、`SocketOptions`、`ByteStream`、`Dns`、`ShutdownMode`、`SocketState`、`Error`、`TcpHandle`、TCP 运行时原语。

---

## 11. 所有权与并发

拥有 socket 句柄；必须 close；一个 reader + 一个 writer；close 可并发；无共享。

---

## 12. 示例与反例

正确：`TcpStream.connect(ctx, addr)` → `read` 循环 → `close`。  
反例：把 0 当“无数据”；忽略短写；close 后写；多 reader 并发；依赖 shutdown 释放句柄。

---

## 13. 测试/场景义务

连接成功/拒绝/超时/取消；DNS；选项连接；读 EOF/peek；短写；writeAll；半关闭/state；地址；选项/linger；截止；close 幂等；关闭后。

---

## 14. XNull 伪代码

```xnull
class TcpStream implements ByteStream {
    final TcpHandle _handle
    final SocketAddress _local
    final SocketAddress _remote
    Bool _open
    Bool _readClosed
    Bool _writeClosed

    TcpStream(TcpHandle handle, SocketAddress local, SocketAddress remote) {
        if handle == null || local == null || remote == null {
            throw "TcpStream: null argument"
        }
        _handle = handle
        _local = local
        _remote = remote
        _open = true
        _readClosed = false
        _writeClosed = false
    }

    static Result<TcpStream, Error> connect(Context context, SocketAddress remote) {
        return TcpStream.connect(context, remote, new SocketOptions())
    }

    static Result<TcpStream, Error> connect(Context context, SocketAddress remote, SocketOptions options) {
        if context == null || remote == null || options == null {
            throw "TcpStream.connect: null argument"
        }
        Result<TcpStreamRaw, Error> raw = tcpConnectRaw(context, remote, options.copy())
        if raw.isErr() { return Err(raw.error()) }
        TcpStreamRaw value = raw.value()
        return Ok(new TcpStream(value.handle(), value.local(), value.remote()))
    }

    static Result<TcpStream, Error> connect(Context context, String host, Int port) {
        return TcpStream.connect(context, host, port, new SocketOptions())
    }

    static Result<TcpStream, Error> connect(Context context, String host, Int port, SocketOptions options) {
        if context == null || options == null {
            throw "TcpStream.connect: null argument"
        }
        if host == null || host == "" { throw "TcpStream.connect: empty host" }
        Result<IpAddress, Error> resolved = Dns.resolveOne(context, host, IpFamily.Unspecified)
        if resolved.isErr() { return Err(resolved.error()) }
        SocketAddress remote = new SocketAddress(resolved.value(), port)
        return TcpStream.connect(context, remote, options)
    }

    Result<Int, Error> read(Context context, Bytes buffer) {
        if context == null || buffer == null {
            throw "TcpStream.read: null argument"
        }
        if !_open || _readClosed { return Err(unavailableError("tcp stream")) }
        return tcpReadRaw(_handle, context, buffer)
    }

    Result<Int, Error> peek(Context context, Bytes buffer) {
        if context == null || buffer == null {
            throw "TcpStream.peek: null argument"
        }
        if !_open || _readClosed { return Err(unavailableError("tcp stream")) }
        return tcpPeekRaw(_handle, context, buffer)
    }

    Result<Int, Error> write(Context context, Bytes data) {
        if context == null || data == null {
            throw "TcpStream.write: null argument"
        }
        if !_open || _writeClosed { return Err(unavailableError("tcp stream")) }
        return tcpWriteRaw(_handle, context, data)
    }

    Result<Unit, Error> writeAll(Context context, Bytes data) {
        if context == null || data == null {
            throw "TcpStream.writeAll: null argument"
        }
        Int total = 0
        while total < data.length() {
            Bytes part = slice(data, total, data.length())
            Result<Int, Error> written = self.write(context, part)
            if written.isErr() { return Err(written.error()) }
            if written.value() == 0 {
                return Err(unavailableError("tcp write"))
            }
            total = total + written.value()
        }
        return Ok(unit)
    }

    Result<Unit, Error> shutdown(ShutdownMode mode) {
        if !_open { return Err(unavailableError("tcp stream")) }
        Result<Unit, Error> result = tcpShutdownRaw(_handle, mode)
        if result.isErr() { return result }
        if mode == ShutdownMode.Read || mode == ShutdownMode.Both {
            _readClosed = true
        }
        if mode == ShutdownMode.Write || mode == ShutdownMode.Both {
            _writeClosed = true
        }
        return result
    }

    SocketAddress localAddress() { return _local }
    SocketAddress remoteAddress() { return _remote }

    Result<Unit, Error> setNoDelay(Bool enabled) {
        if !_open { return Err(unavailableError("tcp stream")) }
        return tcpSetBoolOptionRaw(_handle, "nodelay", enabled)
    }

    Result<Unit, Error> setKeepAlive(Bool enabled) {
        if !_open { return Err(unavailableError("tcp stream")) }
        return tcpSetBoolOptionRaw(_handle, "keepalive", enabled)
    }

    Result<Unit, Error> setReadBuffer(Int bytes) {
        if bytes <= 0 { throw "TcpStream.setReadBuffer: invalid size" }
        if !_open { return Err(unavailableError("tcp stream")) }
        return tcpSetIntOptionRaw(_handle, "readBuffer", bytes)
    }

    Result<Unit, Error> setWriteBuffer(Int bytes) {
        if bytes <= 0 { throw "TcpStream.setWriteBuffer: invalid size" }
        if !_open { return Err(unavailableError("tcp stream")) }
        return tcpSetIntOptionRaw(_handle, "writeBuffer", bytes)
    }

    Result<Unit, Error> setLinger(Int seconds) {
        if seconds < 0 { throw "TcpStream.setLinger: negative" }
        if !_open { return Err(unavailableError("tcp stream")) }
        return tcpSetIntOptionRaw(_handle, "linger", seconds)
    }

    SocketState state() {
        if !_open { return SocketState.Closed }
        if _readClosed && _writeClosed { return SocketState.Closed }
        if _readClosed { return SocketState.ReadClosed }
        if _writeClosed { return SocketState.WriteClosed }
        return SocketState.Open
    }

    Result<Unit, Error> setReadDeadline(Long deadlineMonoMillis) {
        if !_open { return Err(unavailableError("tcp stream")) }
        return tcpSetDeadlineRaw(_handle, true, deadlineMonoMillis)
    }

    Result<Unit, Error> setWriteDeadline(Long deadlineMonoMillis) {
        if !_open { return Err(unavailableError("tcp stream")) }
        return tcpSetDeadlineRaw(_handle, false, deadlineMonoMillis)
    }

    Bool isOpen() { return _open }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        return tcpCloseRaw(_handle)
    }
}
```

> `TcpHandle`、`TcpStreamRaw` 和 `tcp*Raw` 是运行时 TCP 原语；不是 XDK 公共类型。
