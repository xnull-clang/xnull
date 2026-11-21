# `HttpProxyServer`

| 项 | 值 |
| --- | --- |
| 类型 | `class HttpProxyServer` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`SocketAddress`、`HttpProxyHandler`、`HttpProxyOptions`、`Error` |

---

## 1. 定位

HTTP 代理服务端：绑定、serve、地址、关闭。

不做：认证后端、缓存、TLS 终止、SOCKS、PAC。

---

## 2. 设计逻辑

- 字段 `_handle`、`_options`、`_open`。
- `bind` 创建监听；`serve` 接受并分派 `HttpProxyHandler`。
- 每连接内部任务；Context 取消/close 停止 accept。
- close 幂等；无全局。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_handle` | `HttpProxyServerHandle` | 运行时服务器 |
| `_options` | `HttpProxyOptions` | 配置副本 |
| `_open` | `Bool` | 是否监听 |

---

## 4. 生命周期

bind 创建；必须 close；close 幂等。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `HttpProxyServer.bind(Context, SocketAddress)` | 非 null | 非 null | 绑定失败 |
| `HttpProxyServer.bind(Context, SocketAddress, HttpProxyOptions)` | + options | 非 null | 绑定失败 |

构造器私有。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `bind` | 绑定 | `Context, SocketAddress` | `Result<HttpProxyServer, Error>` | 绑定失败 |
| `bind` | 带选项 | `Context, SocketAddress, HttpProxyOptions` | `Result<HttpProxyServer, Error>` | 绑定失败 |
| `serve` | 接受/分派 | `Context, HttpProxyHandler` | `Result<Unit, Error>` | `Cancelled`/`Unavailable`/`Network` |
| `localAddress` | 地址 | 无 | `SocketAddress` | 无 |
| `isOpen` | 是否监听 | 无 | `Bool` | 无 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |

---

## 8. 使用的技术

- 代理服务端；
- 每连接任务；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、Bool、Result；
- 运行时：`httpProxyServerBindRaw`、`httpProxyServerServeRaw`、`httpProxyServerCloseRaw`、`HttpProxyServerHandle`；
- 接口：`Context`、`SocketAddress`、`HttpProxyHandler`、`HttpProxyOptions`、`Error`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`Context`、`SocketAddress`、`HttpProxyHandler`、`HttpProxyOptions`、`Error`、代理运行时原语。

---

## 11. 所有权与并发

引用语义；一个 serve 循环；close 可并发；无全局。

---

## 12. 示例与反例

正确：`HttpProxyServer.bind(ctx, local).value().serve(ctx, handler)`。  
反例：close 后 serve；多 serve 循环；handler 不响应。

---

## 13. 测试/场景义务

绑定；serve；forward/tunnel；取消；close 幂等；地址；绑定失败；handler 错误。

---

## 14. XNull 伪代码

```xnull
class HttpProxyServer {
    final HttpProxyServerHandle _handle
    final HttpProxyOptions _options
    Bool _open

    private HttpProxyServer(HttpProxyServerHandle handle, HttpProxyOptions options) {
        _handle = handle
        _options = options
        _open = true
    }

    static Result<HttpProxyServer, Error> bind(Context context, SocketAddress local) {
        return HttpProxyServer.bind(context, local, new HttpProxyOptions())
    }

    static Result<HttpProxyServer, Error> bind(Context context, SocketAddress local,
                                               HttpProxyOptions options) {
        if context == null || local == null || options == null {
            throw "HttpProxyServer.bind: null argument"
        }
        Result<HttpProxyServerHandle, Error> raw = httpProxyServerBindRaw(
            context, local, options.copy())
        if raw.isErr() { return Err(raw.error()) }
        return Ok(new HttpProxyServer(raw.value(), options.copy()))
    }

    Result<Unit, Error> serve(Context context, HttpProxyHandler handler) {
        if context == null || handler == null {
            throw "HttpProxyServer.serve: null argument"
        }
        if !_open { return Err(unavailableError("http proxy server")) }
        return httpProxyServerServeRaw(_handle, context, handler)
    }

    SocketAddress localAddress() { return httpProxyServerLocalAddressRaw(_handle) }
    Bool isOpen() { return _open }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        return httpProxyServerCloseRaw(_handle)
    }
}
```

> `HttpProxyServerHandle`、`httpProxyServer*Raw` 是运行时代理服务器原语；不是 XDK 公共类型。
