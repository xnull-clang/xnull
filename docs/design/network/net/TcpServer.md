# `TcpServer`

| 项 | 值 |
| --- | --- |
| 类型 | `class TcpServer` |
| 包 | `xdk.net` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`SocketAddress`、`TcpListener`、`TcpHandler`、`TcpServerOptions`、`Error` |

---

## 1. 定位

TCP 服务端角色：绑定、accept 循环、每连接分派、连接上限、关闭。

不做：TLS、HTTP、连接池、线程池调优。

---

## 2. 设计逻辑

- 字段 `_listener`、`_options`、`_open`。
- `bind` 用 listener + options 创建；`serve` 单 accept 循环。
- 每连接交给 handler；超过 maxConnections 时拒绝/退避。
- Context 取消或 close 停止 accept；在途连接由 handler 关闭。
- close 幂等；无全局。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_listener` | `TcpListener` | 监听器 |
| `_options` | `TcpServerOptions` | 配置副本 |
| `_open` | `Bool` | 是否监听 |

---

## 4. 生命周期

bind 创建；必须 close；close 幂等。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `TcpServer.bind(Context, SocketAddress)` | 非 null | 非 null | 绑定失败 |
| `TcpServer.bind(Context, SocketAddress, TcpServerOptions)` | + options | 非 null | 绑定失败 |

构造器私有。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `bind` | 绑定 | `Context, SocketAddress` | `Result<TcpServer, Error>` | 绑定失败 |
| `bind` | 带选项 | `Context, SocketAddress, TcpServerOptions` | `Result<TcpServer, Error>` | 绑定失败 |
| `serve` | accept/分派 | `Context, TcpHandler` | `Result<Unit, Error>` | `Cancelled`/`Unavailable`/`Network` |
| `localAddress` | 地址 | 无 | `SocketAddress` | 无 |
| `isOpen` | 是否监听 | 无 | `Bool` | 无 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |

---

## 8. 使用的技术

- accept 循环；
- 每连接任务；
- 连接上限/退避；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、Bool、Result；
- 运行时：`tcpServerServeRaw`；
- 接口：`Context`、`SocketAddress`、`TcpListener`、`TcpHandler`、`TcpServerOptions`、`Error`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`Context`、`SocketAddress`、`TcpListener`、`TcpHandler`、`TcpServerOptions`、`Error`、`tcpServerServeRaw`。

---

## 11. 所有权与并发

引用语义；拥有 listener；一个 serve 循环；close 可并发；无全局。

---

## 12. 示例与反例

正确：`TcpServer.bind(ctx, local).value().serve(ctx, handler)`。  
反例：多 serve 循环；close 后 serve；handler 不 close 流。

---

## 13. 测试/场景义务

绑定；serve；多连接；上限；取消；close 幂等；地址；handler 错误。

---

## 14. XNull 伪代码

```xnull
class TcpServer {
    final TcpListener _listener
    final TcpServerOptions _options
    Bool _open

    private TcpServer(TcpListener listener, TcpServerOptions options) {
        _listener = listener
        _options = options
        _open = true
    }

    static Result<TcpServer, Error> bind(Context context, SocketAddress local) {
        return TcpServer.bind(context, local, new TcpServerOptions())
    }

    static Result<TcpServer, Error> bind(Context context, SocketAddress local,
                                          TcpServerOptions options) {
        if context == null || local == null || options == null {
            throw "TcpServer.bind: null argument"
        }
        Result<TcpListener, Error> listener = TcpListener.bind(
            context, local, options.getConnectionOptions())
        if listener.isErr() { return Err(listener.error()) }
        return Ok(new TcpServer(listener.value(), options.copy()))
    }

    Result<Unit, Error> serve(Context context, TcpHandler handler) {
        if context == null || handler == null {
            throw "TcpServer.serve: null argument"
        }
        if !_open { return Err(unavailableError("tcp server")) }
        return tcpServerServeRaw(_listener, context, handler, _options)
    }

    SocketAddress localAddress() { return _listener.localAddress() }
    Bool isOpen() { return _open }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        return _listener.close()
    }
}
```

> `tcpServerServeRaw` 是运行时 accept/分派原语；不是 XDK 公共类型。
