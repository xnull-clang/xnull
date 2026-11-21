# `HttpClient`

| 项 | 值 |
| --- | --- |
| 类型 | `class HttpClient` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`HttpRequest`、`HttpResponse`、`HttpClientOptions`、`HttpBody`、`Uri`、`Error` |

---

## 1. 定位

HTTP/1.1 客户端：发请求、便捷方法、TLS/重定向/CookieJar 配置、关闭。

不做：HTTP/2、代理、WebSocket、全局连接池、自动重试。

---

## 2. 设计逻辑

- 字段 `_handle`、`_options`、`_open`。
- 构造时复制 options；运行时创建客户端/连接池。
- `request` 发送一个请求；状态码不是 `Err`。
- `get/post/put/delete` 是便捷封装。
- `close` 幂等；关闭后请求 `Unavailable`。
- 可选 CookieJar 由 options 提供；客户端调用方持有。
- 可并发 `request`。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_handle` | `HttpClientHandle` | 运行时客户端 |
| `_options` | `HttpClientOptions` | 配置副本 |
| `_open` | `Bool` | 是否可用 |

不变量：handle/options 非 null；close 后 open=false。

---

## 4. 生命周期

构造创建；必须 close；close 幂等；关闭后请求 `Unavailable`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `HttpClient()` | 无 | 默认 options | 无 |
| `HttpClient(HttpClientOptions options)` | options | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `request` | 发请求 | `Context, HttpRequest` | `Result<HttpResponse, Error>` | `Network`/`Timeout`/`Cancelled`/`DataCorrupted`/`PermissionDenied`/`Unavailable` |
| `get` | GET | `Context, Uri` | `Result<HttpResponse, Error>` | 同上 |
| `post` | POST | `Context, Uri, HttpBody` | `Result<HttpResponse, Error>` | 同上 |
| `put` | PUT | `Context, Uri, HttpBody` | `Result<HttpResponse, Error>` | 同上 |
| `delete` | DELETE | `Context, Uri` | `Result<HttpResponse, Error>` | 同上 |
| `options` | 配置快照 | 无 | `HttpClientOptions` | 无 |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |

---

## 8. 使用的技术

- HTTP/1.1 报文；
- 重定向/连接池/TLS 由运行时原语；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、Bool、Result；
- 运行时：`httpClientCreateRaw`、`httpClientRequestRaw`、`httpClientCloseRaw`、`HttpClientHandle`；
- 接口：`Context`、`HttpRequest`、`HttpResponse`、`HttpClientOptions`、`HttpBody`、`Uri`、`Error`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`Context`、`HttpRequest`、`HttpResponse`、`HttpClientOptions`、`HttpBody`、`Uri`、`Error`、`HttpClientHandle`、HTTP 运行时原语。

---

## 11. 所有权与并发

引用语义；拥有客户端句柄；可并发 request；close 可并发；无全局。

---

## 12. 示例与反例

正确：`client.post(ctx, uri, HttpBody.fromText(json))`。  
反例：close 后请求；把 404 当 Err；不 close 客户端；共享可变 options。

---

## 13. 测试/场景义务

GET/POST/PUT/DELETE；状态码；重定向；TLS；CookieJar；取消/超时；close 幂等；并发请求。

---

## 14. XNull 伪代码

```xnull
class HttpClient {
    final HttpClientHandle _handle
    final HttpClientOptions _options
    Bool _open

    HttpClient() {
        HttpClientOptions options = new HttpClientOptions()
        Result<HttpClientHandle, Error> raw = httpClientCreateRaw(options.copy())
        if raw.isErr() {
            throw "HttpClient: create failed: " + raw.error().describe()
        }
        _handle = raw.value()
        _options = options.copy()
        _open = true
    }

    HttpClient(HttpClientOptions options) {
        if options == null { throw "HttpClient: null options" }
        Result<HttpClientHandle, Error> raw = httpClientCreateRaw(options.copy())
        if raw.isErr() {
            throw "HttpClient: create failed: " + raw.error().describe()
        }
        _handle = raw.value()
        _options = options.copy()
        _open = true
    }

    Result<HttpResponse, Error> request(Context context, HttpRequest request) {
        if context == null || request == null {
            throw "HttpClient.request: null argument"
        }
        if !_open { return Err(unavailableError("http client")) }
        return httpClientRequestRaw(_handle, context, request)
    }

    Result<HttpResponse, Error> get(Context context, Uri uri) {
        return self.request(context, new HttpRequest(HttpMethod.Get, uri))
    }

    Result<HttpResponse, Error> post(Context context, Uri uri, HttpBody body) {
        HttpRequest request = new HttpRequest(HttpMethod.Post, uri)
        return self.request(context, request.withBody(body))
    }

    Result<HttpResponse, Error> put(Context context, Uri uri, HttpBody body) {
        HttpRequest request = new HttpRequest(HttpMethod.Put, uri)
        return self.request(context, request.withBody(body))
    }

    Result<HttpResponse, Error> delete(Context context, Uri uri) {
        return self.request(context, new HttpRequest(HttpMethod.Delete, uri))
    }

    HttpClientOptions options() { return _options.copy() }
    Bool isOpen() { return _open }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        return httpClientCloseRaw(_handle)
    }
}
```

> `HttpClientHandle`、`httpClient*Raw` 是运行时 HTTP 客户端原语；不是 XDK 公共类型。
