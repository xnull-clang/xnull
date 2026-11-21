# `TcpListener`

| 项 | 值 |
| --- | --- |
| 类型 | `class TcpListener` |
| 包 | `xdk.net` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`SocketAddress`、`TcpStream`、`Error` |

---

## 1. 定位

TCP 监听器：绑定本地地址、接受连接、查询实际地址、关闭。

不做：TLS、HTTP、连接池、多个 accept 循环、平台特有选项。

---

## 2. 设计逻辑

- 字段 `_handle`、`_local`、`_open`。
- `bind` 调用运行时监听原语；端口 0 由内核分配，`localAddress` 返回实际地址。
- `accept` 阻塞等待；Context 取消返回 `Cancelled`；关闭后 `Unavailable`。
- 返回的 `TcpStream` 归调用方所有，必须 close。
- `close` 幂等；停止监听；已接受连接不受影响。
- 一个 accept 循环；`close` 可与 `accept` 并发。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_handle` | `TcpHandle` | 运行时监听句柄 |
| `_local` | `SocketAddress` | 实际本地地址 |
| `_open` | `Bool` | 是否监听 |

不变量：handle/local 非 null；close 后 open=false。

---

## 4. 生命周期

`bind` 创建；必须 close；close 幂等；关闭后 accept `Unavailable`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `TcpListener.bind(Context context, SocketAddress local)` | context/local | 非 null | `InvalidArgument`/`PermissionDenied`/`Network`/`Unavailable` |

构造器私有。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `bind` | 绑定/监听 | `Context context, SocketAddress local` | `Result<TcpListener, Error>` | 绑定失败 |
| `bind` | 带选项绑定 | `Context context, SocketAddress local, SocketOptions options` | `Result<TcpListener, Error>` | 绑定失败 |
| `accept` | 接受连接 | `Context context` | `Result<TcpStream, Error>` | `Cancelled`/`Timeout`/`Unavailable`/`Network` |
| `acceptDeadline` | 截止接受 | `Context context, Long deadlineMonoMillis` | `Result<TcpStream, Error>` | `Timeout`/`Cancelled`/`Unavailable`/`Network` |
| `localAddress` | 实际地址 | 无 | `SocketAddress` | 无 |
| `isOpen` | 是否监听 | 无 | `Bool` | 无 |
| `close` | 停止监听 | 无 | `Result<Unit, Error>` | `Io`（诊断） |

---

## 8. 使用的技术

- OS listen/accept；
- Context 取消；
- 幂等关闭；
- 实际地址查询。

---

## 9. 需要的支撑

- 语言：class、Bool、Result；
- 运行时：`tcpListenRaw`、`tcpAcceptRaw`、`tcpAcceptDeadlineRaw`、`tcpCloseRaw`、`TcpHandle`、`TcpListenerRaw`、`TcpStreamRaw`；
- 接口：`Context`、`SocketAddress`、`SocketOptions`、`TcpStream`、`Error`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`Context`、`SocketAddress`、`SocketOptions`、`TcpStream`、`Error`、`TcpHandle`、`tcpListenRaw`、`tcpAcceptRaw`、`tcpAcceptDeadlineRaw`、`tcpCloseRaw`、`unavailableError`。

---

## 11. 所有权与并发

拥有监听句柄；必须 close；一个 accept 循环；close 可并发；无共享。

---

## 12. 示例与反例

正确：`TcpListener.bind(ctx, new SocketAddress(IpAddress.any(IpFamily.Ipv4).value(), 0))`。  
反例：close 后继续 accept；多个任务并发 accept；接受连接不 close；依赖监听器关闭关闭已接受流。

---

## 13. 测试/场景义务

绑定/实际地址；选项绑定；接受；截止接受；取消；关闭后 accept；重复 close；端口占用；并发 close；已接受连接独立性。

---

## 14. XNull 伪代码

```xnull
class TcpListener {
    final TcpHandle _handle
    final SocketAddress _local
    Bool _open

    private TcpListener(TcpHandle handle, SocketAddress local) {
        _handle = handle
        _local = local
        _open = true
    }

    static Result<TcpListener, Error> bind(Context context, SocketAddress local) {
        return TcpListener.bind(context, local, new SocketOptions())
    }

    static Result<TcpListener, Error> bind(Context context, SocketAddress local, SocketOptions options) {
        if context == null || local == null || options == null {
            throw "TcpListener.bind: null argument"
        }
        Result<TcpListenerRaw, Error> raw = tcpListenRaw(context, local, options.copy())
        if raw.isErr() { return Err(raw.error()) }
        return Ok(new TcpListener(raw.value().handle(), raw.value().local()))
    }

    Result<TcpStream, Error> accept(Context context) {
        if context == null { throw "TcpListener.accept: null context" }
        if !_open { return Err(unavailableError("tcp listener")) }
        Result<TcpStreamRaw, Error> raw = tcpAcceptRaw(_handle, context)
        if raw.isErr() { return Err(raw.error()) }
        TcpStreamRaw accepted = raw.value()
        return Ok(new TcpStream(accepted.handle(), accepted.local(), accepted.remote()))
    }

    Result<TcpStream, Error> acceptDeadline(Context context, Long deadlineMonoMillis) {
        if context == null { throw "TcpListener.acceptDeadline: null context" }
        if !_open { return Err(unavailableError("tcp listener")) }
        Result<TcpStreamRaw, Error> raw = tcpAcceptDeadlineRaw(_handle, context, deadlineMonoMillis)
        if raw.isErr() { return Err(raw.error()) }
        TcpStreamRaw accepted = raw.value()
        return Ok(new TcpStream(accepted.handle(), accepted.local(), accepted.remote()))
    }

    SocketAddress localAddress() { return _local }
    Bool isOpen() { return _open }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        return tcpCloseRaw(_handle)
    }
}
```

> `TcpHandle`、`TcpListenerRaw`、`TcpStreamRaw`、`tcpListenRaw`、`tcpAcceptRaw`、`tcpAcceptDeadlineRaw`、`tcpCloseRaw` 是运行时 TCP 原语；不是 XDK 公共类型。
