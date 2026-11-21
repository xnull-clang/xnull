# `HttpServer`

| 项 | 值 |
| --- | --- |
| 类型 | `class HttpServer` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`SocketAddress`、`TlsConfig`、`HttpHandler`、`HttpServerOptions`、`Error` |

---

## 1. 定位

HTTP/1.1 服务端：明文/TLS 绑定、serve 循环、地址查询、关闭。

不做：HTTP/2、代理、路由、中间件、优雅关闭超时（X）。

---

## 2. 设计逻辑

- 字段 `_handle`、`_options`、`_open`。
- `bind`/`bindTls` 创建监听；`serve` 接受并分派 handler。
- 每连接内部子任务；请求 body/交换由 handler close。
- Context 取消或 close 停止 accept；在途连接由运行时关闭。
- close 幂等；关闭后 serve/accept `Unavailable`。
- 无全局服务器。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_handle` | `HttpServerHandle` | 运行时服务器 |
| `_options` | `HttpServerOptions` | 配置副本 |
| `_open` | `Bool` | 是否监听 |

不变量：handle/options 非 null；close 后 open=false。

---

## 4. 生命周期

bind/bindTls 创建；必须 close；close 幂等。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `HttpServer.bind(Context, SocketAddress)` | context/local | 非 null | `InvalidArgument`/`PermissionDenied`/`Network` |
| `HttpServer.bind(Context, SocketAddress, HttpServerOptions)` | + options | 非 null | 同上 |
| `HttpServer.bindTls(Context, SocketAddress, TlsConfig)` | + TLS | 非 null | 同上 + TLS |
| `HttpServer.bindTls(Context, SocketAddress, TlsConfig, HttpServerOptions)` | 全部 | 非 null | 同上 |

构造器私有。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `bind` | 明文监听 | `Context, SocketAddress` | `Result<HttpServer, Error>` | 绑定失败 |
| `bind` | 明文+选项 | `Context, SocketAddress, HttpServerOptions` | `Result<HttpServer, Error>` | 绑定失败 |
| `bindTls` | TLS 监听 | `Context, SocketAddress, TlsConfig` | `Result<HttpServer, Error>` | 绑定/TLS 失败 |
| `bindTls` | TLS+选项 | `Context, SocketAddress, TlsConfig, HttpServerOptions` | `Result<HttpServer, Error>` | 同上 |
| `serve` | 接受/分派 | `Context, HttpHandler` | `Result<Unit, Error>` | `Cancelled`/`Unavailable`/`Network` |
| `localAddress` | 实际地址 | 无 | `SocketAddress` | 无 |
| `isOpen` | 是否监听 | 无 | `Bool` | 无 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |

---

## 8. 使用的技术

- HTTP/1.1 服务端；
- TLS 组合；
- 每连接任务；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、Bool、Result；
- 运行时：`httpServerBindRaw`、`httpServerServeRaw`、`httpServerCloseRaw`、`HttpServerHandle`；
- 接口：`Context`、`SocketAddress`、`TlsConfig`、`HttpHandler`、`HttpServerOptions`、`Error`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`Context`、`SocketAddress`、`TlsConfig`、`HttpHandler`、`HttpServerOptions`、`Error`、`HttpServerHandle`、HTTP 运行时原语。

---

## 11. 所有权与并发

引用语义；拥有服务器句柄；一个 serve 循环；close 可并发；无全局。

---

## 12. 示例与反例

正确：`HttpServer.bind(ctx, local).value().serve(ctx, handler)`。  
反例：close 后 serve；多个 serve 循环；不 close；handler 不响应。

---

## 13. 测试/场景义务

明文/TLS 绑定；serve；每连接；取消；close 幂等；地址；绑定失败；handler 错误/未响应。

---

## 14. XNull 伪代码

```xnull
class HttpServer {
    final HttpServerHandle _handle
    final HttpServerOptions _options
    Bool _open

    private HttpServer(HttpServerHandle handle, HttpServerOptions options) {
        _handle = handle
        _options = options
        _open = true
    }

    static Result<HttpServer, Error> bind(Context context, SocketAddress local) {
        return HttpServer.bind(context, local, new HttpServerOptions())
    }

    static Result<HttpServer, Error> bind(Context context, SocketAddress local,
                                          HttpServerOptions options) {
        if context == null || local == null || options == null {
            throw "HttpServer.bind: null argument"
        }
        Result<HttpServerHandle, Error> raw = httpServerBindRaw(
            context, local, options.copy(), null)
        if raw.isErr() { return Err(raw.error()) }
        return Ok(new HttpServer(raw.value(), options.copy()))
    }

    static Result<HttpServer, Error> bindTls(Context context, SocketAddress local,
                                             TlsConfig tlsConfig) {
        return HttpServer.bindTls(context, local, tlsConfig, new HttpServerOptions())
    }

    static Result<HttpServer, Error> bindTls(Context context, SocketAddress local,
                                             TlsConfig tlsConfig, HttpServerOptions options) {
        if context == null || local == null || tlsConfig == null || options == null {
            throw "HttpServer.bindTls: null argument"
        }
        Result<HttpServerHandle, Error> raw = httpServerBindRaw(
            context, local, options.copy(), tlsConfig)
        if raw.isErr() { return Err(raw.error()) }
        return Ok(new HttpServer(raw.value(), options.copy()))
    }

    Result<Unit, Error> serve(Context context, HttpHandler handler) {
        if context == null || handler == null {
            throw "HttpServer.serve: null argument"
        }
        if !_open { return Err(unavailableError("http server")) }
        return httpServerServeRaw(_handle, context, handler)
    }

    SocketAddress localAddress() { return httpServerLocalAddressRaw(_handle) }
    Bool isOpen() { return _open }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        return httpServerCloseRaw(_handle)
    }
}
```

> `HttpServerHandle`、`httpServer*Raw` 是运行时 HTTP 服务端原语；不是 XDK 公共类型。
