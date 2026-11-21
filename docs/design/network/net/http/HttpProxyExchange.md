# `HttpProxyExchange`

| 项 | 值 |
| --- | --- |
| 类型 | `class HttpProxyExchange` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`HttpRequest`、`HttpResponse`、`Uri`、`SocketAddress`、`ByteStream`、`Error` |

---

## 1. 定位

代理单次交换：读请求、转发、开隧道、写响应、关闭。

不做：路由策略、缓存、认证后端、TLS 终止。

---

## 2. 设计逻辑

- 字段 `_handle`、`_request`、`_remote`、`_local`、`_responded`、`_closed`。
- `forward` 转发到目标 URI 并返回上游响应；`openTunnel` 返回裸隧道流。
- `respond` 写响应；与 `openTunnel` 互斥。
- `close` 幂等。
- 由 `HttpProxyServer` 创建。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_handle` | `HttpProxyExchangeHandle` | 运行时交换 |
| `_request` | `HttpRequest` | 请求 |
| `_remote` | `SocketAddress` | 客户端 |
| `_local` | `SocketAddress` | 本地 |
| `_responded` | `Bool` | 已响应 |
| `_closed` | `Bool` | 已关闭 |

---

## 4. 生命周期

由服务器创建；respond/forward/tunnel 后 close；close 幂等。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `HttpProxyExchange(...)` | 见字段 | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `request` | 请求 | 无 | `HttpRequest` | 无 |
| `forward` | 转发 | `Context, Uri target` | `Result<HttpResponse, Error>` | `Network`/`Timeout`/`Cancelled`/`Unavailable` |
| `openTunnel` | 开隧道 | `Context, SocketAddress target` | `Result<ByteStream, Error>` | 同上 |
| `respond` | 写响应 | `HttpResponse response` | `Result<Unit, Error>` | `InvalidArgument`/`Unavailable`/`Io` |
| `remoteAddress` | 客户端 | 无 | `SocketAddress` | 无 |
| `localAddress` | 本地 | 无 | `SocketAddress` | 无 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |

---

## 8. 使用的技术

- 正向/隧道代理；
- 单次交换状态机；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、Bool、Result；
- 运行时：`httpProxyExchangeForwardRaw`、`httpProxyExchangeTunnelRaw`、`httpProxyExchangeRespondRaw`、`httpProxyExchangeCloseRaw`、`HttpProxyExchangeHandle`；
- 接口：`Context`、`HttpRequest`、`HttpResponse`、`Uri`、`SocketAddress`、`ByteStream`、`Error`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`Context`、`HttpRequest`、`HttpResponse`、`Uri`、`SocketAddress`、`ByteStream`、`Error`、代理运行时原语。

---

## 11. 所有权与并发

引用语义；由服务器持有；单次响应；close 可并发；无全局。

---

## 12. 示例与反例

正确：`exchange.forward(ctx, target)` → `exchange.respond(response)`。  
反例：forward 后 tunnel；重复 respond；不 close。

---

## 13. 测试/场景义务

forward；tunnel；respond；冲突；取消/超时；close 幂等；地址。

---

## 14. XNull 伪代码

```xnull
class HttpProxyExchange {
    final HttpProxyExchangeHandle _handle
    final HttpRequest _request
    final SocketAddress _remote
    final SocketAddress _local
    Bool _responded
    Bool _closed

    HttpProxyExchange(HttpProxyExchangeHandle handle, HttpRequest request,
                      SocketAddress remote, SocketAddress local) {
        if handle == null || request == null || remote == null || local == null {
            throw "HttpProxyExchange: null argument"
        }
        _handle = handle
        _request = request
        _remote = remote
        _local = local
        _responded = false
        _closed = false
    }

    HttpRequest request() { return _request }
    SocketAddress remoteAddress() { return _remote }
    SocketAddress localAddress() { return _local }

    Result<HttpResponse, Error> forward(Context context, Uri target) {
        if context == null || target == null {
            throw "HttpProxyExchange.forward: null argument"
        }
        if _closed || _responded { return Err(unavailableError("proxy exchange")) }
        return httpProxyExchangeForwardRaw(_handle, context, target)
    }

    Result<ByteStream, Error> openTunnel(Context context, SocketAddress target) {
        if context == null || target == null {
            throw "HttpProxyExchange.openTunnel: null argument"
        }
        if _closed || _responded { return Err(unavailableError("proxy exchange")) }
        return httpProxyExchangeTunnelRaw(_handle, context, target)
    }

    Result<Unit, Error> respond(HttpResponse response) {
        if response == null { throw "HttpProxyExchange.respond: null" }
        if _closed || _responded { return Err(unavailableError("proxy exchange")) }
        Result<Unit, Error> written = httpProxyExchangeRespondRaw(_handle, response)
        if written.isOk() { _responded = true }
        return written
    }

    Result<Unit, Error> close() {
        if _closed { return Ok(unit) }
        _closed = true
        return httpProxyExchangeCloseRaw(_handle)
    }
}
```

> `HttpProxyExchangeHandle`、`httpProxyExchange*Raw` 是运行时代理原语；不是 XDK 公共类型。
