# `HttpClientOptions`

| 项 | 值 |
| --- | --- |
| 类型 | `class HttpClientOptions` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | `TlsConfig`、`Uri`、`CookieJar`、`HttpVersion` |

---

## 1. 定位

HTTP 客户端配置：TLS、连接/读超时、重定向、UA、base URI、最大连接、CookieJar。

不做：全局配置、代理、HTTP/2、重试策略、连接池细节。

---

## 2. 设计逻辑

- 可变构建期；`HttpClient` 构造时复制。
- 默认 HTTP/1.1、跟随重定向、最多 5 次、UA `XDK`、最大 32 连接。
- 超时 ≥0；maxRedirects ≥0；maxConnections >0。
- `cookieJar` 可空；不自动创建。
- 无 close；非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_tlsConfig` | `TlsConfig?` | TLS |
| `_connectTimeoutMillis` | `Long` | 连接超时 |
| `_readTimeoutMillis` | `Long` | 读超时 |
| `_followRedirects` | `Bool` | 跟随重定向 |
| `_maxRedirects` | `Int` | 最大重定向 |
| `_userAgent` | `String` | UA |
| `_baseUri` | `Uri?` | 相对 URI 基址 |
| `_maxConnections` | `Int` | 最大连接 |
| `_cookieJar` | `CookieJar?` | Cookie |
| `_preferredVersion` | `HttpVersion` | 首选版本 |

不变量：超时 ≥0；maxRedirects ≥0；maxConnections >0；UA 非空。

---

## 4. 生命周期

可变；无 close；构造客户端时复制。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `HttpClientOptions()` | 无 | 默认 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `tlsConfig` | TLS | `TlsConfig value` | `HttpClientOptions` | null → panic |
| `connectTimeoutMillis` | 连接超时 | `Long value` | `HttpClientOptions` | <0 → panic |
| `readTimeoutMillis` | 读超时 | `Long value` | `HttpClientOptions` | <0 → panic |
| `followRedirects` | 重定向开关 | `Bool value` | `HttpClientOptions` | 无 |
| `maxRedirects` | 重定向上限 | `Int value` | `HttpClientOptions` | <0 → panic |
| `userAgent` | UA | `String value` | `HttpClientOptions` | 空/null → panic |
| `baseUri` | 基址 | `Uri value` | `HttpClientOptions` | null → panic |
| `maxConnections` | 最大连接 | `Int value` | `HttpClientOptions` | ≤0 → panic |
| `cookieJar` | CookieJar | `CookieJar value` | `HttpClientOptions` | null → panic |
| `preferredVersion` | 首选版本 | `HttpVersion value` | `HttpClientOptions` | 无 |
| `getTlsConfig` | TLS | 无 | `TlsConfig?` | 无 |
| `getConnectTimeoutMillis` | 连接超时 | 无 | `Long` | 无 |
| `getReadTimeoutMillis` | 读超时 | 无 | `Long` | 无 |
| `isFollowRedirects` | 重定向 | 无 | `Bool` | 无 |
| `getMaxRedirects` | 上限 | 无 | `Int` | 无 |
| `getUserAgent` | UA | 无 | `String` | 无 |
| `getBaseUri` | 基址 | 无 | `Uri?` | 无 |
| `getMaxConnections` | 最大连接 | 无 | `Int` | 无 |
| `getCookieJar` | CookieJar | 无 | `CookieJar?` | 无 |
| `getPreferredVersion` | 首选版本 | 无 | `HttpVersion` | 无 |
| `copy` | 独立快照 | 无 | `HttpClientOptions` | 无 |

---

## 8. 使用的技术

- builder；
- 快照。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Int、Long；
- 运行时：无；
- 接口：`TlsConfig`、`Uri`、`CookieJar`、`HttpVersion`。

---

## 10. 依赖的特性/接口/类

`TlsConfig`、`Uri`、`CookieJar`、`HttpVersion`。

---

## 11. 所有权与并发

可变；非线程安全；客户端复制；无资源。

---

## 12. 示例与反例

正确：`new HttpClientOptions().followRedirects(false).readTimeoutMillis(5000)`。  
反例：negative timeout；base URI 非绝对；全局 options。

---

## 13. 测试/场景义务

默认值；setter；非法；copy 独立；客户端快照；CookieJar 可空。

---

## 14. XNull 伪代码

```xnull
class HttpClientOptions {
    TlsConfig? _tlsConfig = null
    Long _connectTimeoutMillis = 10000
    Long _readTimeoutMillis = 30000
    Bool _followRedirects = true
    Int _maxRedirects = 5
    String _userAgent = "XDK"
    Uri? _baseUri = null
    Int _maxConnections = 32
    CookieJar? _cookieJar = null
    HttpVersion _preferredVersion = HttpVersion.Http11

    HttpClientOptions() {
    }

    HttpClientOptions tlsConfig(TlsConfig value) {
        if value == null { throw "HttpClientOptions.tlsConfig: null" }
        _tlsConfig = value
        return self
    }

    HttpClientOptions connectTimeoutMillis(Long value) {
        if value < 0 { throw "HttpClientOptions.connectTimeoutMillis: negative" }
        _connectTimeoutMillis = value
        return self
    }

    HttpClientOptions readTimeoutMillis(Long value) {
        if value < 0 { throw "HttpClientOptions.readTimeoutMillis: negative" }
        _readTimeoutMillis = value
        return self
    }

    HttpClientOptions followRedirects(Bool value) {
        _followRedirects = value
        return self
    }

    HttpClientOptions maxRedirects(Int value) {
        if value < 0 { throw "HttpClientOptions.maxRedirects: negative" }
        _maxRedirects = value
        return self
    }

    HttpClientOptions userAgent(String value) {
        if value == null || value == "" { throw "HttpClientOptions.userAgent: empty" }
        _userAgent = value
        return self
    }

    HttpClientOptions baseUri(Uri value) {
        if value == null { throw "HttpClientOptions.baseUri: null" }
        _baseUri = value
        return self
    }

    HttpClientOptions maxConnections(Int value) {
        if value <= 0 { throw "HttpClientOptions.maxConnections: invalid" }
        _maxConnections = value
        return self
    }

    HttpClientOptions cookieJar(CookieJar value) {
        if value == null { throw "HttpClientOptions.cookieJar: null" }
        _cookieJar = value
        return self
    }

    HttpClientOptions preferredVersion(HttpVersion value) {
        _preferredVersion = value
        return self
    }

    TlsConfig? getTlsConfig() { return _tlsConfig }
    Long getConnectTimeoutMillis() { return _connectTimeoutMillis }
    Long getReadTimeoutMillis() { return _readTimeoutMillis }
    Bool isFollowRedirects() { return _followRedirects }
    Int getMaxRedirects() { return _maxRedirects }
    String getUserAgent() { return _userAgent }
    Uri? getBaseUri() { return _baseUri }
    Int getMaxConnections() { return _maxConnections }
    CookieJar? getCookieJar() { return _cookieJar }
    HttpVersion getPreferredVersion() { return _preferredVersion }

    HttpClientOptions copy() {
        HttpClientOptions result = new HttpClientOptions()
        if _tlsConfig != null { result.tlsConfig(_tlsConfig as TlsConfig) }
        result.connectTimeoutMillis(_connectTimeoutMillis)
        result.readTimeoutMillis(_readTimeoutMillis)
        result.followRedirects(_followRedirects)
        result.maxRedirects(_maxRedirects)
        result.userAgent(_userAgent)
        if _baseUri != null { result.baseUri(_baseUri as Uri) }
        result.maxConnections(_maxConnections)
        if _cookieJar != null { result.cookieJar(_cookieJar as CookieJar) }
        result.preferredVersion(_preferredVersion)
        return result
    }
}
```
