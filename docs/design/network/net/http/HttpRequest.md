# `HttpRequest`

| 项 | 值 |
| --- | --- |
| 类型 | `class HttpRequest` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | `HttpMethod`、`HttpVersion`、`Uri`、`HttpHeaders`、`HttpBody` |

---

## 1. 定位

HTTP 请求值对象：方法、URI、版本、头、body；`with*` 派生。

不做：发送、重定向、Cookie、认证、body 编码。

---

## 2. 设计逻辑

- 字段 method/uri/version/headers/body；构造复制 headers。
- `headers()` 返回副本；`withHeader/s` 在副本上修改。
- body 引用；服务端请求 body 由 `HttpExchange` 关闭。
- 不可变结构；无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_method` | `HttpMethod` | 方法 |
| `_uri` | `Uri` | 目标 |
| `_version` | `HttpVersion` | 版本 |
| `_headers` | `HttpHeaders` | 头 |
| `_body` | `HttpBody` | body |

不变量：method/uri/version/headers/body 非 null；不可变结构。

---

## 4. 生命周期

构造/派生后不可变；body 流式需 close；无资源句柄。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `HttpRequest(HttpMethod method, Uri uri)` | method/uri | 非 null | null → panic |

默认 HTTP/1.1、空头、空 body。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `method` | 方法 | 无 | `HttpMethod` | 无 |
| `uri` | URI | 无 | `Uri` | 无 |
| `version` | 版本 | 无 | `HttpVersion` | 无 |
| `headers` | 头副本 | 无 | `HttpHeaders` | 无 |
| `body` | body | 无 | `HttpBody` | 无 |
| `withHeader` | 派生头 | `String name, String value` | `HttpRequest` | 非法 → panic |
| `withHeaders` | 派生头集合 | `HttpHeaders headers` | `HttpRequest` | null → panic |
| `withBody` | 派生 body | `HttpBody body` | `HttpRequest` | null → panic |
| `withVersion` | 派生版本 | `HttpVersion version` | `HttpRequest` | 无 |
| `withUri` | 派生 URI | `Uri uri` | `HttpRequest` | null → panic |

---

## 8. 使用的技术

- 不可变值对象；
- 头副本；
- 派生。

---

## 9. 需要的支撑

- 语言：class、String、Bool；
- 运行时：无；
- 接口：`HttpMethod`、`HttpVersion`、`Uri`、`HttpHeaders`、`HttpBody`。

---

## 10. 依赖的特性/接口/类

`HttpMethod`、`HttpVersion`、`Uri`、`HttpHeaders`、`HttpBody`。

---

## 11. 所有权与并发

不可变结构；headers 快照；body 引用；无资源。

---

## 12. 示例与反例

正确：`new HttpRequest(HttpMethod.Get, uri).withHeader("Accept","application/json")`。  
反例：修改 `headers()` 期望请求变化；复用流式 body；把 URI 当绝对 URL 强制。

---

## 13. 测试/场景义务

默认版本/空 body；with*；头副本；body；URI；方法；不可变。

---

## 14. XNull 伪代码

```xnull
class HttpRequest {
    final HttpMethod _method
    final Uri _uri
    final HttpVersion _version
    final HttpHeaders _headers
    final HttpBody _body

    HttpRequest(HttpMethod method, Uri uri) {
        if method == null || uri == null {
            throw "HttpRequest: null argument"
        }
        _method = method
        _uri = uri
        _version = HttpVersion.Http11
        _headers = new HttpHeaders()
        _body = HttpBody.empty()
    }

    private HttpRequest(HttpMethod method, Uri uri, HttpVersion version,
                        HttpHeaders headers, HttpBody body) {
        if method == null || uri == null || version == null || headers == null || body == null {
            throw "HttpRequest: null argument"
        }
        _method = method
        _uri = uri
        _version = version
        _headers = headers.copy()
        _body = body
    }

    HttpMethod method() { return _method }
    Uri uri() { return _uri }
    HttpVersion version() { return _version }
    HttpHeaders headers() { return _headers.copy() }
    HttpBody body() { return _body }

    HttpRequest withHeader(String name, String value) {
        HttpHeaders next = _headers.copy()
        next.add(name, value)
        return new HttpRequest(_method, _uri, _version, next, _body)
    }

    HttpRequest withHeaders(HttpHeaders headers) {
        if headers == null { throw "HttpRequest.withHeaders: null" }
        return new HttpRequest(_method, _uri, _version, headers, _body)
    }

    HttpRequest withBody(HttpBody body) {
        if body == null { throw "HttpRequest.withBody: null" }
        return new HttpRequest(_method, _uri, _version, _headers, body)
    }

    HttpRequest withVersion(HttpVersion version) {
        return new HttpRequest(_method, _uri, version, _headers, _body)
    }

    HttpRequest withUri(Uri uri) {
        if uri == null { throw "HttpRequest.withUri: null" }
        return new HttpRequest(_method, uri, _version, _headers, _body)
    }
}
```
