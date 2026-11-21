# `WebSocketServer`

| 项 | 值 |
| --- | --- |
| 类型 | `class WebSocketServer` |
| 包 | `xdk.net.websocket` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`SocketAddress`、`TlsConfig`、`WebSocketOptions`、`WebSocketHandler`、`Error` |

---

## 1. 定位

WebSocket 服务端角色：HTTP 监听、升级、握手、分派 `WebSocketHandler`、关闭。

不做：HTTP 路由、TLS 证书管理、消息重放、HTTP/2 WebSocket。

---

## 2. 设计逻辑

- 字段 `_handle`、`_options`、`_open`。
- `bind`/`bindTls` 创建 HTTP 监听；`serve` 接受连接并完成 upgrade/握手。
- Handler 拥有 `WebSocket`，必须 close。
- Context 取消/close 停止 accept；在途连接关闭。
- close 幂等；无全局。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_handle` | `WebSocketServerHandle` | 运行时服务器 |
| `_options` | `WebSocketOptions` | 握手选项 |
| `_open` | `Bool` | 是否监听 |

---

## 4. 生命周期

bind/bindTls 创建；必须 close；close 幂等。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `WebSocketServer.bind(Context, SocketAddress, WebSocketOptions)` | 非 null | 非 null | 绑定失败 |
| `WebSocketServer.bindTls(Context, SocketAddress, TlsConfig, WebSocketOptions)` | 非 null | 非 null | 绑定/TLS 失败 |

构造器私有。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `bind` | 明文监听 | `Context, SocketAddress, WebSocketOptions` | `Result<WebSocketServer, Error>` | 绑定失败 |
| `bindTls` | TLS 监听 | `Context, SocketAddress, TlsConfig, WebSocketOptions` | `Result<WebSocketServer, Error>` | 绑定/TLS 失败 |
| `serve` | accept/升级/分派 | `Context, WebSocketHandler` | `Result<Unit, Error>` | `Cancelled`/`Unavailable`/`Network` |
| `localAddress` | 地址 | 无 | `SocketAddress` | 无 |
| `isOpen` | 是否监听 | 无 | `Bool` | 无 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |

---

## 8. 使用的技术

- HTTP upgrade；
- WebSocket 握手；
- 每连接任务；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、Bool、Result；
- 运行时：`websocketServerBindRaw`、`websocketServerServeRaw`、`websocketServerCloseRaw`、`WebSocketServerHandle`；
- 接口：`Context`、`SocketAddress`、`TlsConfig`、`WebSocketOptions`、`WebSocketHandler`、`Error`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`Context`、`SocketAddress`、`TlsConfig`、`WebSocketOptions`、`WebSocketHandler`、`Error`、WebSocket 服务器原语。

---

## 11. 所有权与并发

引用语义；拥有服务器句柄；一个 serve 循环；close 可并发；无全局。

---

## 12. 示例与反例

正确：`WebSocketServer.bind(ctx, local, options).value().serve(ctx, handler)`。  
反例：close 后 serve；多 serve 循环；handler 不 close。

---

## 13. 测试/场景义务

明文/TLS 绑定；升级；握手；多连接；取消；close 幂等；地址；handler 错误。

---

## 14. XNull 伪代码

```xnull
class WebSocketServer {
    final WebSocketServerHandle _handle
    final WebSocketOptions _options
    Bool _open

    private WebSocketServer(WebSocketServerHandle handle, WebSocketOptions options) {
        _handle = handle
        _options = options
        _open = true
    }

    static Result<WebSocketServer, Error> bind(Context context, SocketAddress local,
                                                WebSocketOptions options) {
        if context == null || local == null || options == null {
            throw "WebSocketServer.bind: null argument"
        }
        Result<WebSocketServerHandle, Error> raw = websocketServerBindRaw(
            context, local, null, options.copy())
        if raw.isErr() { return Err(raw.error()) }
        return Ok(new WebSocketServer(raw.value(), options.copy()))
    }

    static Result<WebSocketServer, Error> bindTls(Context context, SocketAddress local,
                                                   TlsConfig tlsConfig, WebSocketOptions options) {
        if context == null || local == null || tlsConfig == null || options == null {
            throw "WebSocketServer.bindTls: null argument"
        }
        Result<WebSocketServerHandle, Error> raw = websocketServerBindRaw(
            context, local, tlsConfig, options.copy())
        if raw.isErr() { return Err(raw.error()) }
        return Ok(new WebSocketServer(raw.value(), options.copy()))
    }

    Result<Unit, Error> serve(Context context, WebSocketHandler handler) {
        if context == null || handler == null {
            throw "WebSocketServer.serve: null argument"
        }
        if !_open { return Err(unavailableError("websocket server")) }
        return websocketServerServeRaw(_handle, context, handler)
    }

    SocketAddress localAddress() { return websocketServerLocalAddressRaw(_handle) }
    Bool isOpen() { return _open }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        return websocketServerCloseRaw(_handle)
    }
}
```

> `WebSocketServerHandle`、`websocketServer*Raw` 是运行时 WebSocket 服务端原语；不是 XDK 公共类型。
