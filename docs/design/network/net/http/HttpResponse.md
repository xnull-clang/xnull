# `HttpResponse`

| 项 | 值 |
| --- | --- |
| 类型 | `class HttpResponse` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | `HttpStatus`、`HttpVersion`、`HttpHeaders`、`HttpBody` |

---

## 1. 定位

HTTP 响应值对象：状态、版本、头、body；类别判断与派生。

不做：发送、重定向执行、body 解码、错误映射。

---

## 2. 设计逻辑

- 字段 status/version/headers/body；构造复制 headers。
- `of(Int)` 构造空 body 响应；默认 HTTP/1.1。
- `headers()` 返回副本；`with*` 派生。
- 状态码不是 `Err`；4xx/5xx 仍是正常响应。
- 不可变结构；body 流式需 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_status` | `HttpStatus` | 状态 |
| `_version` | `HttpVersion` | 版本 |
| `_headers` | `HttpHeaders` | 头 |
| `_body` | `HttpBody` | body |

不变量：status/version/headers/body 非 null；不可变结构。

---

## 4. 生命周期

构造/派生后不可变；body 流式需 close；无资源句柄。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `HttpResponse.of(Int status)` | status | 100..599 | 越界 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `of` | 构造 | `Int status` | `HttpResponse` | 越界 → panic |
| `status` | 状态 | 无 | `HttpStatus` | 无 |
| `version` | 版本 | 无 | `HttpVersion` | 无 |
| `headers` | 头副本 | 无 | `HttpHeaders` | 无 |
| `body` | body | 无 | `HttpBody` | 无 |
| `withHeader` | 派生头 | `String name, String value` | `HttpResponse` | 非法 → panic |
| `withHeaders` | 派生头集合 | `HttpHeaders headers` | `HttpResponse` | null → panic |
| `withBody` | 派生 body | `HttpBody body` | `HttpResponse` | null → panic |
| `withStatus` | 派生状态 | `Int status` | `HttpResponse` | 越界 → panic |
| `isSuccess` | 2xx | 无 | `Bool` | 无 |
| `isRedirect` | 3xx | 无 | `Bool` | 无 |
| `isClientError` | 4xx | 无 | `Bool` | 无 |
| `isServerError` | 5xx | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 不可变值对象；
- 状态分类；
- 头副本。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Int；
- 运行时：无；
- 接口：`HttpStatus`、`HttpVersion`、`HttpHeaders`、`HttpBody`。

---

## 10. 依赖的特性/接口/类

`HttpStatus`、`HttpVersion`、`HttpHeaders`、`HttpBody`。

---

## 11. 所有权与并发

不可变结构；headers 快照；body 引用；无资源。

---

## 12. 示例与反例

正确：`HttpResponse.of(404).isClientError()`。  
反例：把 500 当 `Err`；修改 headers 副本期望响应变化；复用流式 body。

---

## 13. 测试/场景义务

of/越界；with*；状态类别；头副本；body；不可变。

---

## 14. XNull 伪代码

```xnull
class HttpResponse {
    final HttpStatus _status
    final HttpVersion _version
    final HttpHeaders _headers
    final HttpBody _body

    static HttpResponse of(Int status) {
        return new HttpResponse(HttpStatus.of(status), HttpVersion.Http11,
            new HttpHeaders(), HttpBody.empty())
    }

    private HttpResponse(HttpStatus status, HttpVersion version,
                         HttpHeaders headers, HttpBody body) {
        if status == null || version == null || headers == null || body == null {
            throw "HttpResponse: null argument"
        }
        _status = status
        _version = version
        _headers = headers.copy()
        _body = body
    }

    HttpStatus status() { return _status }
    HttpVersion version() { return _version }
    HttpHeaders headers() { return _headers.copy() }
    HttpBody body() { return _body }

    HttpResponse withHeader(String name, String value) {
        HttpHeaders next = _headers.copy()
        next.add(name, value)
        return new HttpResponse(_status, _version, next, _body)
    }

    HttpResponse withHeaders(HttpHeaders headers) {
        if headers == null { throw "HttpResponse.withHeaders: null" }
        return new HttpResponse(_status, _version, headers, _body)
    }

    HttpResponse withBody(HttpBody body) {
        if body == null { throw "HttpResponse.withBody: null" }
        return new HttpResponse(_status, _version, _headers, body)
    }

    HttpResponse withStatus(Int status) {
        return new HttpResponse(HttpStatus.of(status), _version, _headers, _body)
    }

    Bool isSuccess() { return _status.isSuccess() }
    Bool isRedirect() { return _status.isRedirect() }
    Bool isClientError() { return _status.isClientError() }
    Bool isServerError() { return _status.isServerError() }
}
```
