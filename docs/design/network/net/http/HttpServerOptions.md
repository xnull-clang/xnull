# `HttpServerOptions`

| 项 | 值 |
| --- | --- |
| 类型 | `class HttpServerOptions` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

HTTP 服务端配置：头/body 上限、读写超时、keep-alive、最大连接。

不做：路由、中间件、TLS 配置（由 `HttpServer.bindTls` 传入）、HTTP/2。

---

## 2. 设计逻辑

- 可变构建期；服务器构造时复制。
- 默认头 64 KiB、body 16 MiB、读/写 30s、keep-alive 开、最大 128 连接。
- 上限/超时 >0；非法 panic。
- 无 close；非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_maxHeaderBytes` | `Int` | 头上限 |
| `_maxBodyBytes` | `Long` | body 上限 |
| `_readTimeoutMillis` | `Long` | 读超时 |
| `_writeTimeoutMillis` | `Long` | 写超时 |
| `_keepAlive` | `Bool` | keep-alive |
| `_maxConnections` | `Int` | 最大连接 |
| `_http2` | `Bool` | 是否启用 HTTP/2 |

不变量：上限/超时 >0；maxConnections >0。

---

## 4. 生命周期

可变；服务器复制；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `HttpServerOptions()` | 无 | 默认 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `maxHeaderBytes` | 头上限 | `Int value` | `HttpServerOptions` | ≤0 → panic |
| `maxBodyBytes` | body 上限 | `Long value` | `HttpServerOptions` | ≤0 → panic |
| `readTimeoutMillis` | 读超时 | `Long value` | `HttpServerOptions` | ≤0 → panic |
| `writeTimeoutMillis` | 写超时 | `Long value` | `HttpServerOptions` | ≤0 → panic |
| `keepAlive` | keep-alive | `Bool value` | `HttpServerOptions` | 无 |
| `maxConnections` | 最大连接 | `Int value` | `HttpServerOptions` | ≤0 → panic |
| `http2` | HTTP/2 开关 | `Bool value` | `HttpServerOptions` | 无 |
| `getMaxHeaderBytes` | 头上限 | 无 | `Int` | 无 |
| `getMaxBodyBytes` | body 上限 | 无 | `Long` | 无 |
| `getReadTimeoutMillis` | 读超时 | 无 | `Long` | 无 |
| `getWriteTimeoutMillis` | 写超时 | 无 | `Long` | 无 |
| `isKeepAlive` | keep-alive | 无 | `Bool` | 无 |
| `getMaxConnections` | 最大连接 | 无 | `Int` | 无 |
| `isHttp2` | HTTP/2 | 无 | `Bool` | 无 |
| `copy` | 独立快照 | 无 | `HttpServerOptions` | 无 |

---

## 8. 使用的技术

- builder；
- 上限/超时。

---

## 9. 需要的支撑

- 语言：class、Int、Long、Bool；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

可变；非线程安全；服务器复制；无资源。

---

## 12. 示例与反例

正确：`new HttpServerOptions().maxBodyBytes(1_000_000)`。  
反例：0 上限；负超时；修改 options 期望已有服务器变化。

---

## 13. 测试/场景义务

默认值；setter；非法；copy 独立；服务器快照；keep-alive。

---

## 14. XNull 伪代码

```xnull
class HttpServerOptions {
    Int _maxHeaderBytes = 65536
    Long _maxBodyBytes = 16777216
    Long _readTimeoutMillis = 30000
    Long _writeTimeoutMillis = 30000
    Bool _keepAlive = true
    Int _maxConnections = 128
    Bool _http2 = false

    HttpServerOptions() {
    }

    HttpServerOptions maxHeaderBytes(Int value) {
        if value <= 0 { throw "HttpServerOptions.maxHeaderBytes: invalid" }
        _maxHeaderBytes = value
        return self
    }

    HttpServerOptions maxBodyBytes(Long value) {
        if value <= 0 { throw "HttpServerOptions.maxBodyBytes: invalid" }
        _maxBodyBytes = value
        return self
    }

    HttpServerOptions readTimeoutMillis(Long value) {
        if value <= 0 { throw "HttpServerOptions.readTimeoutMillis: invalid" }
        _readTimeoutMillis = value
        return self
    }

    HttpServerOptions writeTimeoutMillis(Long value) {
        if value <= 0 { throw "HttpServerOptions.writeTimeoutMillis: invalid" }
        _writeTimeoutMillis = value
        return self
    }

    HttpServerOptions keepAlive(Bool value) {
        _keepAlive = value
        return self
    }

    HttpServerOptions maxConnections(Int value) {
        if value <= 0 { throw "HttpServerOptions.maxConnections: invalid" }
        _maxConnections = value
        return self
    }

    HttpServerOptions http2(Bool value) {
        _http2 = value
        return self
    }

    Int getMaxHeaderBytes() { return _maxHeaderBytes }
    Long getMaxBodyBytes() { return _maxBodyBytes }
    Long getReadTimeoutMillis() { return _readTimeoutMillis }
    Long getWriteTimeoutMillis() { return _writeTimeoutMillis }
    Bool isKeepAlive() { return _keepAlive }
    Int getMaxConnections() { return _maxConnections }
    Bool isHttp2() { return _http2 }

    HttpServerOptions copy() {
        HttpServerOptions result = new HttpServerOptions()
        result.maxHeaderBytes(_maxHeaderBytes)
        result.maxBodyBytes(_maxBodyBytes)
        result.readTimeoutMillis(_readTimeoutMillis)
        result.writeTimeoutMillis(_writeTimeoutMillis)
        result.keepAlive(_keepAlive)
        result.maxConnections(_maxConnections)
        result.http2(_http2)
        return result
    }
}
```
