# `WebSocketOptions`

| 项 | 值 |
| --- | --- |
| 类型 | `class WebSocketOptions` |
| 包 | `xdk.net.websocket` |
| 稳定性 | `preview` |
| 依赖 | `HttpHeaders`、`TlsConfig` |

---

## 1. 定位

WebSocket 连接选项：额外头、子协议、帧/消息/发送队列上限、心跳、Origin、TLS。

不做：压缩、重连策略、HTTP/2 WebSocket。

---

## 2. 设计逻辑

- 可变 builder；连接时复制。
- 默认消息 16MiB、帧 1MiB、发送队列 8MiB、ping 0（关闭）、pong 30s。
- 上限 >0；超时 ≥0。
- 无 close；非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_headers` | `HttpHeaders` | 额外头 |
| `_subprotocols` | `List<String>` | 子协议 |
| `_maxFrameBytes` | `Long` | 帧上限 |
| `_maxMessageBytes` | `Long` | 消息上限 |
| `_maxSendQueueBytes` | `Long` | 发送队列上限 |
| `_pingIntervalMillis` | `Long` | ping 间隔 |
| `_pongTimeoutMillis` | `Long` | pong 超时 |
| `_origin` | `String` | Origin |
| `_tlsConfig` | `TlsConfig?` | wss TLS |

---

## 4. 生命周期

可变；连接复制；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `WebSocketOptions()` | 无 | 默认 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `header` | 额外头 | `String, String` | `WebSocketOptions` | 非法 → panic |
| `subprotocol` | 子协议 | `String` | `WebSocketOptions` | 空 → panic |
| `maxFrameBytes` | 帧上限 | `Long` | `WebSocketOptions` | ≤0 → panic |
| `maxMessageBytes` | 消息上限 | `Long` | `WebSocketOptions` | ≤0 → panic |
| `maxSendQueueBytes` | 队列上限 | `Long` | `WebSocketOptions` | ≤0 → panic |
| `pingIntervalMillis` | ping | `Long` | `WebSocketOptions` | <0 → panic |
| `pongTimeoutMillis` | pong | `Long` | `WebSocketOptions` | <0 → panic |
| `origin` | Origin | `String` | `WebSocketOptions` | 空 → panic |
| `tlsConfig` | TLS | `TlsConfig` | `WebSocketOptions` | null → panic |
| `headers` | 头副本 | 无 | `HttpHeaders` | 无 |
| `subprotocols` | 子协议快照 | 无 | `List<String>` | 无 |
| `getMaxFrameBytes` | 帧上限 | 无 | `Long` | 无 |
| `getMaxMessageBytes` | 消息上限 | 无 | `Long` | 无 |
| `getMaxSendQueueBytes` | 队列上限 | 无 | `Long` | 无 |
| `getPingIntervalMillis` | ping | 无 | `Long` | 无 |
| `getPongTimeoutMillis` | pong | 无 | `Long` | 无 |
| `getOrigin` | Origin | 无 | `String` | 无 |
| `getTlsConfig` | TLS | 无 | `TlsConfig?` | 无 |
| `copy` | 快照 | 无 | `WebSocketOptions` | 无 |

---

## 8. 使用的技术

- builder；
- 上限/心跳；
- 快照。

---

## 9. 需要的支撑

- 语言：class、List、Long、String；
- 运行时：无；
- 接口：`HttpHeaders`、`HttpHeader`、`TlsConfig`。

---

## 10. 依赖的特性/接口/类

`HttpHeaders`、`HttpHeader`、`TlsConfig`。

---

## 11. 所有权与并发

可变；非线程安全；无资源；copy 独立。

---

## 12. 示例与反例

正确：`new WebSocketOptions().subprotocol("chat").pingIntervalMillis(30000)`。  
反例：0 上限；负超时；修改 options 期望已有连接变化。

---

## 13. 测试/场景义务

默认；setter；非法；copy；头/子协议/TLS；心跳。

---

## 14. XNull 伪代码

```xnull
class WebSocketOptions {
    HttpHeaders _headers = new HttpHeaders()
    List<String> _subprotocols = []
    Long _maxFrameBytes = 1048576
    Long _maxMessageBytes = 16777216
    Long _maxSendQueueBytes = 8388608
    Long _pingIntervalMillis = 0
    Long _pongTimeoutMillis = 30000
    String _origin = ""
    TlsConfig? _tlsConfig = null

    WebSocketOptions() {
    }

    WebSocketOptions header(String name, String value) {
        _headers.add(name, value)
        return self
    }

    WebSocketOptions subprotocol(String value) {
        if value == null || value == "" { throw "WebSocketOptions.subprotocol: empty" }
        _subprotocols.push(value)
        return self
    }

    WebSocketOptions maxFrameBytes(Long value) {
        if value <= 0 { throw "WebSocketOptions.maxFrameBytes: invalid" }
        _maxFrameBytes = value
        return self
    }

    WebSocketOptions maxMessageBytes(Long value) {
        if value <= 0 { throw "WebSocketOptions.maxMessageBytes: invalid" }
        _maxMessageBytes = value
        return self
    }

    WebSocketOptions maxSendQueueBytes(Long value) {
        if value <= 0 { throw "WebSocketOptions.maxSendQueueBytes: invalid" }
        _maxSendQueueBytes = value
        return self
    }

    WebSocketOptions pingIntervalMillis(Long value) {
        if value < 0 { throw "WebSocketOptions.pingIntervalMillis: negative" }
        _pingIntervalMillis = value
        return self
    }

    WebSocketOptions pongTimeoutMillis(Long value) {
        if value < 0 { throw "WebSocketOptions.pongTimeoutMillis: negative" }
        _pongTimeoutMillis = value
        return self
    }

    WebSocketOptions origin(String value) {
        if value == null || value == "" { throw "WebSocketOptions.origin: empty" }
        _origin = value
        return self
    }

    WebSocketOptions tlsConfig(TlsConfig value) {
        if value == null { throw "WebSocketOptions.tlsConfig: null" }
        _tlsConfig = value
        return self
    }

    HttpHeaders headers() { return _headers.copy() }
    List<String> subprotocols() { return _subprotocols.copy() }
    Long getMaxFrameBytes() { return _maxFrameBytes }
    Long getMaxMessageBytes() { return _maxMessageBytes }
    Long getMaxSendQueueBytes() { return _maxSendQueueBytes }
    Long getPingIntervalMillis() { return _pingIntervalMillis }
    Long getPongTimeoutMillis() { return _pongTimeoutMillis }
    String getOrigin() { return _origin }
    TlsConfig? getTlsConfig() { return _tlsConfig }

    WebSocketOptions copy() {
        WebSocketOptions result = new WebSocketOptions()
        List<HttpHeader> entries = _headers.entries()
        Int index = 0
        while index < entries.length() {
            result.header(entries.get(index).name(), entries.get(index).value())
            index = index + 1
        }
        index = 0
        while index < _subprotocols.length() {
            result.subprotocol(_subprotocols.get(index))
            index = index + 1
        }
        result.maxFrameBytes(_maxFrameBytes)
        result.maxMessageBytes(_maxMessageBytes)
        result.maxSendQueueBytes(_maxSendQueueBytes)
        result.pingIntervalMillis(_pingIntervalMillis)
        result.pongTimeoutMillis(_pongTimeoutMillis)
        if _origin != "" { result.origin(_origin) }
        if _tlsConfig != null { result.tlsConfig(_tlsConfig as TlsConfig) }
        return result
    }
}
```
