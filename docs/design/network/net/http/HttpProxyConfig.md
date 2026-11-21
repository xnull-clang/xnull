# `HttpProxyConfig`

| 项 | 值 |
| --- | --- |
| 类型 | `class HttpProxyConfig` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | `Uri`、`HttpHeaders`、`ProxyMode` |

---

## 1. 定位

HTTP 代理客户端配置：代理 URI、额外头、no-proxy、连接超时、模式。

不做：代理服务器、认证协商、PAC、SOCKS。

---

## 2. 设计逻辑

- 可变 builder；客户端复制。
- `proxyUri` 非 null；`withBasicAuth` 设置 Proxy-Authorization；`withHeader` 追加。
- `noProxy` 主机列表；空表示不例外。
- 模式默认 `Tunnel`；`Reverse` 由服务端配置使用。
- 无 close；非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_proxyUri` | `Uri` | 代理 |
| `_headers` | `HttpHeaders` | 额外头 |
| `_noProxy` | `List<String>` | 直连主机 |
| `_connectTimeoutMillis` | `Long` | 连接超时 |
| `_mode` | `ProxyMode` | 模式 |

---

## 4. 生命周期

可变；客户端复制；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `HttpProxyConfig(Uri proxyUri)` | proxyUri | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `withBasicAuth` | 设置代理认证 | `String user, String password` | `HttpProxyConfig` | 空/null → panic |
| `withHeader` | 添加头 | `String name, String value` | `HttpProxyConfig` | 非法 → panic |
| `withHeaders` | 替换头 | `HttpHeaders headers` | `HttpProxyConfig` | null → panic |
| `withNoProxy` | 直连列表 | `List<String> hosts` | `HttpProxyConfig` | null → panic |
| `withConnectTimeout` | 连接超时 | `Long millis` | `HttpProxyConfig` | <0 → panic |
| `withMode` | 模式 | `ProxyMode mode` | `HttpProxyConfig` | 无 |
| `proxyUri` | 代理 URI | 无 | `Uri` | 无 |
| `headers` | 头副本 | 无 | `HttpHeaders` | 无 |
| `noProxy` | 直连主机 | 无 | `List<String>` | 无 |
| `connectTimeoutMillis` | 超时 | 无 | `Long` | 无 |
| `mode` | 模式 | 无 | `ProxyMode` | 无 |
| `copy` | 快照 | 无 | `HttpProxyConfig` | 无 |

---

## 8. 使用的技术

- builder；
- 代理头；
- 快照。

---

## 9. 需要的支撑

- 语言：class、List、String、Long；
- 运行时：`HttpAuth.basic`；
- 接口：`Uri`、`HttpHeaders`、`ProxyMode`。

---

## 10. 依赖的特性/接口/类

`Uri`、`HttpHeaders`、`ProxyMode`、`HttpAuth`。

---

## 11. 所有权与并发

可变；非线程安全；无资源；copy 独立。

---

## 12. 示例与反例

正确：`new HttpProxyConfig(uri).withBasicAuth("u","p")`。  
反例：空代理 URI；把 no-proxy 当 CIDR；忽略 mode。

---

## 13. 测试/场景义务

代理 URI；认证头；额外头；noProxy；超时；模式；copy。

---

## 14. XNull 伪代码

```xnull
class HttpProxyConfig {
    final Uri _proxyUri
    HttpHeaders _headers = new HttpHeaders()
    List<String> _noProxy = []
    Long _connectTimeoutMillis = 10000
    ProxyMode _mode = ProxyMode.Tunnel

    HttpProxyConfig(Uri proxyUri) {
        if proxyUri == null { throw "HttpProxyConfig: null uri" }
        _proxyUri = proxyUri
    }

    HttpProxyConfig withBasicAuth(String user, String password) {
        _headers.set("proxy-authorization", HttpAuth.basic(user, password))
        return self
    }

    HttpProxyConfig withHeader(String name, String value) {
        _headers.add(name, value)
        return self
    }

    HttpProxyConfig withHeaders(HttpHeaders headers) {
        if headers == null { throw "HttpProxyConfig.withHeaders: null" }
        _headers = headers.copy()
        return self
    }

    HttpProxyConfig withNoProxy(List<String> hosts) {
        if hosts == null { throw "HttpProxyConfig.withNoProxy: null" }
        _noProxy = hosts.copy()
        return self
    }

    HttpProxyConfig withConnectTimeout(Long millis) {
        if millis < 0 { throw "HttpProxyConfig.withConnectTimeout: negative" }
        _connectTimeoutMillis = millis
        return self
    }

    HttpProxyConfig withMode(ProxyMode mode) {
        _mode = mode
        return self
    }

    Uri proxyUri() { return _proxyUri }
    HttpHeaders headers() { return _headers.copy() }
    List<String> noProxy() { return _noProxy.copy() }
    Long connectTimeoutMillis() { return _connectTimeoutMillis }
    ProxyMode mode() { return _mode }

    HttpProxyConfig copy() {
        HttpProxyConfig result = new HttpProxyConfig(_proxyUri)
        result.withHeaders(_headers)
        result.withNoProxy(_noProxy)
        result.withConnectTimeout(_connectTimeoutMillis)
        result.withMode(_mode)
        return result
    }
}
```
