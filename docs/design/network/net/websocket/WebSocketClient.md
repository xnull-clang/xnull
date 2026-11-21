# `WebSocketClient`

| 项 | 值 |
| --- | --- |
| 类型 | `class WebSocketClient` |
| 包 | `xdk.net.websocket` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Uri`、`WebSocket`、`WebSocketOptions`、`ReconnectPolicy`、`WebSocketClientState`、`WebSocketStats`、`Error` |

---

## 1. 定位

WebSocket 客户端：连接、保存当前 socket、状态、按策略重连、关闭。

不做：消息重放、连接迁移、持久化队列、HTTP/2 WebSocket。

---

## 2. 设计逻辑

- 字段 `_options`、`_policy`、`_socket`、`_state`、`_open`、`_attempt`。
- `connect` 创建 WebSocket；成功后 Open。
- `reconnect` 按 `ReconnectPolicy` 检查次数/延迟；失败保持状态。
- `close` 关闭 socket 并置 Closed；幂等。
- `stats` 从当前 socket/运行时取快照。
- 无全局。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_options` | `WebSocketOptions` | 配置 |
| `_policy` | `ReconnectPolicy` | 重连 |
| `_socket` | `WebSocket?` | 当前连接 |
| `_uri` | `Uri?` | 最近 URI |
| `_state` | `WebSocketClientState` | 状态 |
| `_open` | `Bool` | 客户端可用 |
| `_attempt` | `Int` | 重连次数 |

---

## 4. 生命周期

构造；connect/reconnect；close 幂等；关闭后 connect `Unavailable`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `WebSocketClient(WebSocketOptions options, ReconnectPolicy policy)` | 非 null | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `connect` | 首次连接 | `Context, Uri` | `Result<WebSocket, Error>` | 握手失败/`Unavailable` |
| `socket` | 当前 socket/无 | 无 | `WebSocket?` | 无 |
| `state` | 状态 | 无 | `WebSocketClientState` | 无 |
| `reconnect` | 重连 | `Context` | `Result<WebSocket, Error>` | 策略拒绝/握手失败 |
| `stats` | 统计 | 无 | `WebSocketStats` | `Unavailable` |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |

---

## 8. 使用的技术

- 自动重连；
- 退避策略；
- 状态机。

---

## 9. 需要的支撑

- 语言：class、Int、Bool、Result；
- 运行时：`webSocketClientStatsRaw`、`sleepMillis`；
- 接口：`Context`、`Uri`、`WebSocket`、`WebSocketOptions`、`ReconnectPolicy`、`WebSocketClientState`、`WebSocketStats`、`Error`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`Context`、`Uri`、`WebSocket`、`WebSocketOptions`、`ReconnectPolicy`、`WebSocketClientState`、`WebSocketStats`、`Error`。

---

## 11. 所有权与并发

引用语义；拥有当前 socket；非线程安全；close 可并发；无全局。

---

## 12. 示例与反例

正确：`client.connect(ctx, uri)`；失败后 `reconnect(ctx)`。  
反例：Closed 后重连；无限重试；多任务同时 reconnect。

---

## 13. 测试/场景义务

首次连接；重连次数/延迟；状态；socket 替换；close 幂等；stats；失败。

---

## 14. XNull 伪代码

```xnull
class WebSocketClient {
    final WebSocketOptions _options
    final ReconnectPolicy _policy
    WebSocket? _socket
    Uri? _uri
    WebSocketClientState _state
    Bool _open
    Int _attempt

    WebSocketClient(WebSocketOptions options, ReconnectPolicy policy) {
        if options == null || policy == null {
            throw "WebSocketClient: null argument"
        }
        _options = options.copy()
        _policy = policy
        _socket = null
        _uri = null
        _state = WebSocketClientState.Idle
        _open = true
        _attempt = 0
    }

    Result<WebSocket, Error> connect(Context context, Uri uri) {
        if context == null || uri == null { throw "WebSocketClient.connect: null" }
        if !_open { return Err(unavailableError("websocket client")) }
        _state = WebSocketClientState.Connecting
        Result<WebSocket, Error> result = WebSocket.connect(context, uri, _options)
        if result.isErr() {
            _state = WebSocketClientState.Closed
            return result
        }
        _socket = result.value()
        _uri = uri
        _state = WebSocketClientState.Open
        _attempt = 0
        return result
    }

    WebSocket? socket() { return _socket }
    WebSocketClientState state() { return _state }

    Result<WebSocket, Error> reconnect(Context context) {
        if context == null { throw "WebSocketClient.reconnect: null context" }
        if !_open { return Err(unavailableError("websocket client")) }
        if !_policy.shouldRetry(_attempt) {
            return Err(unavailableError("reconnect attempts exhausted"))
        }
        if _uri == null {
            return Err(unavailableError("no previous websocket uri"))
        }
        _state = WebSocketClientState.Reconnecting
        sleepMillis(_policy.delayMillis(_attempt))
        _attempt = _attempt + 1
        Result<WebSocket, Error> result = WebSocket.connect(context, _uri as Uri, _options)
        if result.isErr() {
            _state = WebSocketClientState.Reconnecting
            return result
        }
        _socket = result.value()
        _state = WebSocketClientState.Open
        _attempt = 0
        return result
    }

    WebSocketStats stats() {
        if !_open { throw "WebSocketClient.stats: closed" }
        return webSocketClientStatsRaw(_socket)
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        _state = WebSocketClientState.Closed
        if _socket == null { return Ok(unit) }
        return (_socket as WebSocket).close(Context.background())
    }

}
```

> `webSocketClientStatsRaw`、`sleepMillis` 是运行时原语；`reconnect` 使用最近一次成功连接 URI。
