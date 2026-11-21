# `Server`

| 项 | 值 |
| --- | --- |
| 类型 | `class Server` |
| 包 | `xdk.net.service` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`SocketAddress`、`ServiceOptions`、`ServiceState`、`ServiceStats`、`SessionHandler`、`ConnectionHandler`、`Error` |

---

## 1. 定位

流式服务端角色：绑定本地地址、接受连接、分派会话或原始连接、连接上限/背压、优雅停机、立即关闭、状态与统计。

不做：HTTP/WS、路由、中间件、TLS 证书管理、连接池、协议编解码、多监听器、UDP 数据报、裸 socket。

`Server` 是  `TcpServer` 的服务层组合：运行时内部使用 `TcpListener`、`TcpStream`、`TlsStream.accept`；公开面不重复这些类型，也不暴露监听句柄。

---

## 2. 设计逻辑

- 字段：不透明服务器句柄、配置快照、已 serve 标志、已关闭标志。
- `bind` 创建句柄；`serve`/`serveConnections` 二选一，只能调用一次；运行时负责 accept 循环、TLS 握手、连接/会话创建、上限与背压。
- `serve` 是会话模式：每连接一个 `Session`，驱动 `SessionHandler`；`serveConnections` 是原始模式：驱动 `ConnectionHandler`。
- 运行时在 accept 后：检查 `maxConnections` 与 `BackpressurePolicy`；TLS 配置存在时执行 `TlsStream.accept`；包装 `Connection`；会话模式再 `openSession`；按 `ServiceOptions` 应用读/写/空闲截止与心跳；然后分派。
- 单个 accepted 连接由独立任务处理；同连接回调串行；连接结束关闭流并更新统计。
- `shutdown` 停止接受、置 `Draining`、关闭空闲会话、等待正在处理回调的会话；`Context` 或 `gracefulShutdownTimeoutMillis` 先到则强制关闭剩余连接。
- `close` 立即关闭监听与活动连接；幂等；与 `shutdown` 可并发。
- 无全局服务器；无重连；无应用层写队列。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_handle` | `NetworkServerHandle` | final | 运行时不透明句柄；非 null |
| `_options` | `ServiceOptions` | final | 配置快照 |
| `_served` | `Bool` | 可变 | 是否已调用 serve |
| `_closed` | `Bool` | 可变 | 是否已 close |

不变量：`_handle`/`_options` 非 null；`serve` 与 `serveConnections` 互斥；`_served` 只从 false 变 true；`close` 后 `_closed=true`；`close` 后 `isOpen=false`。

---

## 4. 生命周期

`bind` 创建 → `serve`/`serveConnections`（一次）→ `shutdown`（优雅）或 `close`（立即）→ `close` 释放。`bind` 后未 serve 也可 `shutdown`/`close`。`close` 幂等；关闭后不能重新 serve，需新建实例。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Server.bind(Context context, SocketAddress local)` | 非 null | 默认 options | 绑定失败 |
| `Server.bind(Context context, SocketAddress local, ServiceOptions options)` | 非 null | 非 null；TLS 服务端组合在绑定时校验 | `InvalidArgument`/`PermissionDenied`/`Network`/TLS |
| `Server(NetworkServerHandle handle, ServiceOptions options)` | 非 null | 非 null | 仅运行时/测试；null → panic |

构造器私有；业务使用静态 `bind`。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `bind` | 默认绑定 | `Context context, SocketAddress local` | `Result<Server, Error>` | 绑定失败 |
| `bind` | 带选项绑定 | `Context context, SocketAddress local, ServiceOptions options` | `Result<Server, Error>` | 绑定失败/TLS |
| `serve` | 会话模式分派 | `Context context, SessionHandler handler` | `Result<Unit, Error>` | `Cancelled`/`Unavailable`/`Network` |
| `serveConnections` | 原始模式分派 | `Context context, ConnectionHandler handler` | `Result<Unit, Error>` | 同上 |
| `shutdown` | 优雅停机 | `Context context` | `Result<Unit, Error>` | `Timeout`/`Cancelled`/`Io` |
| `localAddress` | 实际本地地址 | 无 | `SocketAddress` | 无 |
| `state` | 生命周期快照 | 无 | `ServiceState` | 无 |
| `stats` | 统计快照 | 无 | `ServiceStats` | 无 |
| `isOpen` | 是否监听 | 无 | `Bool` | 无 |
| `isServing` | 是否正在 serve | 无 | `Bool` | 无 |
| `options` | 配置副本 | 无 | `ServiceOptions` | 无 |
| `close` | 立即关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |

说明：

- `bind` 返回时已监听；端口 0 由系统分配，`localAddress` 返回实际地址。
- `serve`/`serveConnections` 是阻塞调用；重复调用返回 `AlreadyExists`（或运行时定义的等价错误），关闭后返回 `Unavailable`。
- `serve` 在 `shutdown` 正常排空后返回 `Ok(unit)`；调用方 `Context` 取消返回 `Cancelled`；致命 accept 错误返回 `Network`。
- `shutdown` 可重复调用；已停止返回 `Ok(unit)`；先停止接受、关闭空闲会话，再等待活动会话；超时/取消后仍会强制关闭剩余连接，再返回对应错误。若运行时已进入 `Failed`，`shutdown` 执行强制关闭并转 `Closed`（等价于关闭资源），`close` 仍幂等。
- `shutdown` 不释放句柄；`close` 释放。`close` 后 `shutdown` 返回 `Ok(unit)`（幂等）。
- `state` 由运行时维护；`isOpen` 与 `state` 可能瞬时不一致，以运行时快照为准。
- `stats` 计数从 `bind` 起累计；关闭后仍可读取最后一次快照。
- `options` 返回副本，修改不影响运行中的服务器。
- TLS：`ServiceOptions.tlsConfig` 非空时，服务端必须有证书/私钥；握手失败关闭该连接并计入错误，不调用 handler。

---

## 8. 使用的技术

- `TcpListener` accept；
- `TlsStream.accept` 组合；
- 每连接任务；
- 连接上限/接受队列/背压水位；
- 优雅排空；
- 幂等关闭；
- 统计快照。

---

## 9. 需要的支撑

- 语言：class、Bool、Long、Result；
- 运行时：`networkServerBindRaw`、`networkServerServeRaw`、`networkServerServeConnectionsRaw`、`networkServerShutdownRaw`、`networkServerCloseRaw`、`networkServerStateRaw`、`networkServerStatsRaw`、`networkServerLocalAddressRaw`、`networkServerIsOpenRaw`、`NetworkServerHandle`；
- 接口：`Context`、`SocketAddress`、`ServiceOptions`、`ServiceState`、`ServiceStats`、`SessionHandler`、`ConnectionHandler`、`Error`、`unavailableError`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Context`、`SocketAddress`、`TcpListener`、`TcpStream`、`TlsStream`、`TlsConfig`、`Connection`、`Session`、`ServiceOptions`、`ServiceState`、`ServiceStats`、`SessionHandler`、`ConnectionHandler`、`Error`、`networkServerBindRaw`、`networkServerServeRaw`、`networkServerServeConnectionsRaw`、`networkServerShutdownRaw`、`networkServerCloseRaw`、`networkServerStateRaw`、`networkServerStatsRaw`、`networkServerLocalAddressRaw`、`networkServerIsOpenRaw`、`NetworkServerHandle`。

---

## 11. 所有权与并发

引用语义；拥有运行时服务器句柄；一个 serve 循环；`shutdown`/`close` 可并发且幂等；`serve` 与 `serveConnections` 互斥；`state`/`stats` 可并发读取。
相等：引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：`Server server = Server.bind(context, local, options).value()`；`server.serve(context, sessionHandler)`；另一任务 `server.shutdown(shutdownContext)`；最后 `server.close()`。  
反例：`serve` 与 `serveConnections` 同时调用；`close` 后重新 `serve`；多任务并发 `serve`；忽略 `shutdown` 返回的 `Timeout`；TLS 配置缺证书；handler 不处理取消。

---

## 13. 测试/场景义务

绑定/实际地址/端口 0；默认与带选项；TLS 绑定/握手失败；serve/serveConnections 互斥/重复；多连接/上限/拒绝；会话模式/原始模式；backpressure 暂停/拒绝；优雅停机排空/超时/取消；`close` 幂等/关闭后 serve；`state` 迁移；`stats` 计数；`localAddress`/`isOpen`；handler 错误/取消。

---

## 14. XNull 伪代码

```xnull
class Server {
    final NetworkServerHandle _handle
    final ServiceOptions _options
    Bool _served
    Bool _closed

    private Server(NetworkServerHandle handle, ServiceOptions options) {
        if handle == null || options == null {
            throw "Server: null argument"
        }
        _handle = handle
        _options = options
        _served = false
        _closed = false
    }

    static Result<Server, Error> bind(Context context, SocketAddress local) {
        return Server.bind(context, local, new ServiceOptions())
    }

    static Result<Server, Error> bind(Context context, SocketAddress local,
                                      ServiceOptions options) {
        if context == null || local == null || options == null {
            throw "Server.bind: null argument"
        }
        Result<NetworkServerHandle, Error> raw = networkServerBindRaw(
            context, local, options.copy())
        if raw.isErr() { return Err(raw.error()) }
        return Ok(new Server(raw.value(), options.copy()))
    }

    Result<Unit, Error> serve(Context context, SessionHandler handler) {
        if context == null || handler == null {
            throw "Server.serve: null argument"
        }
        if _closed { return Err(unavailableError("server")) }
        if _served {
            return Err(new BasicError(ErrorKind.AlreadyExists,
                "server already serving"))
        }
        _served = true
        return networkServerServeRaw(_handle, context, handler)
    }

    Result<Unit, Error> serveConnections(Context context,
                                          ConnectionHandler handler) {
        if context == null || handler == null {
            throw "Server.serveConnections: null argument"
        }
        if _closed { return Err(unavailableError("server")) }
        if _served {
            return Err(new BasicError(ErrorKind.AlreadyExists,
                "server already serving"))
        }
        _served = true
        return networkServerServeConnectionsRaw(_handle, context, handler)
    }

    Result<Unit, Error> shutdown(Context context) {
        if context == null { throw "Server.shutdown: null context" }
        if _closed { return Ok(unit) }
        return networkServerShutdownRaw(_handle, context,
            _options.getGracefulShutdownTimeoutMillis())
    }

    SocketAddress localAddress() {
        return networkServerLocalAddressRaw(_handle)
    }

    ServiceState state() {
        return networkServerStateRaw(_handle)
    }

    ServiceStats stats() {
        return networkServerStatsRaw(_handle)
    }

    Bool isOpen() {
        if _closed { return false }
        return networkServerIsOpenRaw(_handle)
    }

    Bool isServing() {
        if _closed || !_served { return false }
        ServiceState current = self.state()
        return current == ServiceState.Running
            || current == ServiceState.Draining
    }

    ServiceOptions options() { return _options.copy() }

    Result<Unit, Error> close() {
        if _closed { return Ok(unit) }
        _closed = true
        return networkServerCloseRaw(_handle)
    }
}
```
