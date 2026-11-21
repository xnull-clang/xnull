# `TcpServerOptions`

| 项 | 值 |
| --- | --- |
| 类型 | `class TcpServerOptions` |
| 包 | `xdk.net` |
| 稳定性 | `preview` |
| 依赖 | `SocketOptions` |

---

## 1. 定位

TCP 服务端配置：最大连接、accept 失败退避、连接 socket 选项。

不做：TLS、HTTP、连接池、多 accept 循环。

---

## 2. 设计逻辑

- 可变 builder；`TcpServer.bind` 时复制。
- 默认最大 128 连接、accept 失败退避 100ms、默认 SocketOptions。
- 上限 >0；退避 ≥0。
- 无 close；非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_maxConnections` | `Int` | 最大连接 |
| `_acceptBackoffMillis` | `Long` | accept 退避 |
| `_connectionOptions` | `SocketOptions` | 连接选项 |

---

## 4. 生命周期

可变；服务器复制；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `TcpServerOptions()` | 无 | 默认 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `maxConnections` | 设置 | `Int` | `TcpServerOptions` | ≤0 → panic |
| `acceptBackoffMillis` | 设置 | `Long` | `TcpServerOptions` | <0 → panic |
| `connectionOptions` | 设置 | `SocketOptions` | `TcpServerOptions` | null → panic |
| `getMaxConnections` | 读取 | 无 | `Int` | 无 |
| `getAcceptBackoffMillis` | 读取 | 无 | `Long` | 无 |
| `getConnectionOptions` | 读取副本 | 无 | `SocketOptions` | 无 |
| `copy` | 快照 | 无 | `TcpServerOptions` | 无 |

---

## 8. 使用的技术

- builder；
- 连接上限/退避。

---

## 9. 需要的支撑

- 语言：class、Int、Long；
- 运行时：无；
- 接口：`SocketOptions`。

---

## 10. 依赖的特性/接口/类

`SocketOptions`。

---

## 11. 所有权与并发

可变；非线程安全；copy 独立。

---

## 12. 示例与反例

正确：`new TcpServerOptions().maxConnections(256)`。  
反例：0 连接；负退避；共享可变 options。

---

## 13. 测试/场景义务

默认；setter；非法；copy；连接选项。

---

## 14. XNull 伪代码

```xnull
class TcpServerOptions {
    Int _maxConnections = 128
    Long _acceptBackoffMillis = 100
    SocketOptions _connectionOptions = new SocketOptions()

    TcpServerOptions() {
    }

    TcpServerOptions maxConnections(Int value) {
        if value <= 0 { throw "TcpServerOptions.maxConnections: invalid" }
        _maxConnections = value
        return self
    }

    TcpServerOptions acceptBackoffMillis(Long value) {
        if value < 0 { throw "TcpServerOptions.acceptBackoffMillis: negative" }
        _acceptBackoffMillis = value
        return self
    }

    TcpServerOptions connectionOptions(SocketOptions value) {
        if value == null { throw "TcpServerOptions.connectionOptions: null" }
        _connectionOptions = value.copy()
        return self
    }

    Int getMaxConnections() { return _maxConnections }
    Long getAcceptBackoffMillis() { return _acceptBackoffMillis }
    SocketOptions getConnectionOptions() { return _connectionOptions.copy() }

    TcpServerOptions copy() {
        TcpServerOptions result = new TcpServerOptions()
        result.maxConnections(_maxConnections)
        result.acceptBackoffMillis(_acceptBackoffMillis)
        result.connectionOptions(_connectionOptions)
        return result
    }
}
```
