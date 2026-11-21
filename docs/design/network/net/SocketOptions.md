# `SocketOptions`

| 项 | 值 |
| --- | --- |
| 类型 | `class SocketOptions` |
| 包 | `xdk.net` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

TCP/UDP socket 通用选项构建器：reuseAddress、noDelay、keepAlive、缓冲、默认读写超时、linger。

不做：平台特有选项、TLS 选项、组播选项（`MulticastOptions`）、连接池选项。

---

## 2. 设计逻辑

- 可变构建期；`bind`/`connect` 时读取快照。
- 未设置的缓冲/超时/linger 为 null；不用 0 当“未设置”。
- 设置缓冲 >0、超时 ≥0、linger ≥0；非法是合同错误。
- `copy` 返回独立快照，便于绑定后复用模板。
- 无 close；非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_reuseAddress` | `Bool` | SO_REUSEADDR |
| `_noDelay` | `Bool` | TCP_NODELAY |
| `_keepAlive` | `Bool` | SO_KEEPALIVE |
| `_receiveBuffer` | `Int?` | 接收缓冲 |
| `_sendBuffer` | `Int?` | 发送缓冲 |
| `_readTimeoutMillis` | `Long?` | 默认读超时 |
| `_writeTimeoutMillis` | `Long?` | 默认写超时 |
| `_lingerSeconds` | `Int?` | linger |

不变量：缓冲 >0；超时 ≥0；linger ≥0；未设置用 null。

---

## 4. 生命周期

构造后可变；传给 bind/connect 后不再由实现持有；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `SocketOptions()` | 无 | 默认选项 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `reuseAddress` | 设置 reuse | `Bool value` | `SocketOptions` | 无 |
| `noDelay` | 设置 nodelay | `Bool value` | `SocketOptions` | 无 |
| `keepAlive` | 设置 keepalive | `Bool value` | `SocketOptions` | 无 |
| `receiveBuffer` | 设置接收缓冲 | `Int bytes` | `SocketOptions` | ≤0 → panic |
| `sendBuffer` | 设置发送缓冲 | `Int bytes` | `SocketOptions` | ≤0 → panic |
| `readTimeoutMillis` | 默认读超时 | `Long millis` | `SocketOptions` | <0 → panic |
| `writeTimeoutMillis` | 默认写超时 | `Long millis` | `SocketOptions` | <0 → panic |
| `lingerSeconds` | linger | `Int seconds` | `SocketOptions` | <0 → panic |
| `isReuseAddress` | 读 reuse | 无 | `Bool` | 无 |
| `isNoDelay` | 读 nodelay | 无 | `Bool` | 无 |
| `isKeepAlive` | 读 keepalive | 无 | `Bool` | 无 |
| `getReceiveBuffer` | 接收缓冲/无 | 无 | `Int?` | 无 |
| `getSendBuffer` | 发送缓冲/无 | 无 | `Int?` | 无 |
| `getReadTimeoutMillis` | 读超时/无 | 无 | `Long?` | 无 |
| `getWriteTimeoutMillis` | 写超时/无 | 无 | `Long?` | 无 |
| `getLingerSeconds` | linger/无 | 无 | `Int?` | 无 |
| `copy` | 独立快照 | 无 | `SocketOptions` | 无 |

---

## 8. 使用的技术

- builder；
- 可空可选值；
- 快照复制。

---

## 9. 需要的支撑

- 语言：class、Bool、Int、Long；
- 运行时：无；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

可变；非线程安全；copy 独立；无资源。

---

## 12. 示例与反例

正确：`new SocketOptions().reuseAddress(true).noDelay(true)`。  
反例：用 0 表示“未设置超时”；绑定后修改选项期望生效；并发修改。

---

## 13. 测试/场景义务

默认值；每个 setter；非法值；copy 独立；绑定/连接快照；null 可选值。

---

## 14. XNull 伪代码

```xnull
class SocketOptions {
    Bool _reuseAddress = false
    Bool _noDelay = false
    Bool _keepAlive = false
    Int? _receiveBuffer = null
    Int? _sendBuffer = null
    Long? _readTimeoutMillis = null
    Long? _writeTimeoutMillis = null
    Int? _lingerSeconds = null

    SocketOptions() {
    }

    SocketOptions reuseAddress(Bool value) {
        _reuseAddress = value
        return self
    }

    SocketOptions noDelay(Bool value) {
        _noDelay = value
        return self
    }

    SocketOptions keepAlive(Bool value) {
        _keepAlive = value
        return self
    }

    SocketOptions receiveBuffer(Int bytes) {
        if bytes <= 0 { throw "SocketOptions.receiveBuffer: invalid size" }
        _receiveBuffer = bytes
        return self
    }

    SocketOptions sendBuffer(Int bytes) {
        if bytes <= 0 { throw "SocketOptions.sendBuffer: invalid size" }
        _sendBuffer = bytes
        return self
    }

    SocketOptions readTimeoutMillis(Long millis) {
        if millis < 0 { throw "SocketOptions.readTimeoutMillis: negative" }
        _readTimeoutMillis = millis
        return self
    }

    SocketOptions writeTimeoutMillis(Long millis) {
        if millis < 0 { throw "SocketOptions.writeTimeoutMillis: negative" }
        _writeTimeoutMillis = millis
        return self
    }

    SocketOptions lingerSeconds(Int seconds) {
        if seconds < 0 { throw "SocketOptions.lingerSeconds: negative" }
        _lingerSeconds = seconds
        return self
    }

    Bool isReuseAddress() { return _reuseAddress }
    Bool isNoDelay() { return _noDelay }
    Bool isKeepAlive() { return _keepAlive }
    Int? getReceiveBuffer() { return _receiveBuffer }
    Int? getSendBuffer() { return _sendBuffer }
    Long? getReadTimeoutMillis() { return _readTimeoutMillis }
    Long? getWriteTimeoutMillis() { return _writeTimeoutMillis }
    Int? getLingerSeconds() { return _lingerSeconds }

    SocketOptions copy() {
        SocketOptions result = new SocketOptions()
        result.reuseAddress(_reuseAddress)
        result.noDelay(_noDelay)
        result.keepAlive(_keepAlive)
        if _receiveBuffer != null { result.receiveBuffer(_receiveBuffer as Int) }
        if _sendBuffer != null { result.sendBuffer(_sendBuffer as Int) }
        if _readTimeoutMillis != null { result.readTimeoutMillis(_readTimeoutMillis as Long) }
        if _writeTimeoutMillis != null { result.writeTimeoutMillis(_writeTimeoutMillis as Long) }
        if _lingerSeconds != null { result.lingerSeconds(_lingerSeconds as Int) }
        return result
    }
}
```
