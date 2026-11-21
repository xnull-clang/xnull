# `Datagram`

| 项 | 值 |
| --- | --- |
| 类型 | `class Datagram` |
| 包 | `xdk.net` |
| 稳定性 | `preview` |
| 依赖 | `Bytes`、`SocketAddress` |

---

## 1. 定位

UDP 数据报值对象：数据副本、远端地址、长度、截断标记。

不做：自动重传、排序、连接状态、校验和、分片。

---

## 2. 设计逻辑

- 字段 `_data: Bytes`、`_remote: SocketAddress`、`_truncated: Bool`。
- 构造时复制数据；`data()` 返回副本；接收方拥有数据。
- 接收缓冲不足时 `_truncated=true`，不静默丢弃。
- 不可变；无 close；可跨任务共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_data` | `Bytes` | 数据副本 |
| `_remote` | `SocketAddress` | 远端 |
| `_local` | `SocketAddress?` | 本地地址/无 |
| `_truncated` | `Bool` | 是否截断 |
| `_receivedAtMono` | `Long?` | 接收单调时间/无 |
| `_interfaceIndex` | `Int` | 接收接口索引 |

不变量：data/remote 非 null；不可变。

---

## 4. 生命周期

不可变；无 close；接收方拥有；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Datagram(Bytes data, SocketAddress remote)` | data/remote | 非 null | null → panic |
| `Datagram(Bytes data, SocketAddress remote, Bool truncated)` | 同上 + flag | 非 null | null → panic |
| `Datagram(Bytes data, SocketAddress remote, SocketAddress? local, Bool truncated, Long? receivedAtMono, Int interfaceIndex)` | 接收元数据 | data/remote 非 null；索引 ≥0 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `data` | 数据副本 | 无 | `Bytes` | 无 |
| `remote` | 远端地址 | 无 | `SocketAddress` | 无 |
| `length` | 字节数 | 无 | `Int` | 无 |
| `isTruncated` | 是否截断 | 无 | `Bool` | 无 |
| `local` | 本地地址/无 | 无 | `SocketAddress?` | 无 |
| `receivedAtMono` | 接收单调时间/无 | 无 | `Long?` | 无 |
| `interfaceIndex` | 接收接口索引 | 无 | `Int` | 无 |

---

## 8. 使用的技术

- 不可变值对象；
- 数据复制；
- 截断标记。

---

## 9. 需要的支撑

- 语言：class、Bytes、Bool、Int；
- 运行时：无；
- 接口：`SocketAddress`、`Bytes`。

---

## 10. 依赖的特性/接口/类

`Bytes`、`SocketAddress`。

---

## 11. 所有权与并发

不可变；`data()` 返回副本；数据归接收方；可共享。

---

## 12. 示例与反例

正确：`new Datagram(data, remote)`；`received.isTruncated()`。  
反例：修改 `data()` 期望 Datagram 变化；把截断包当完整包；复用发送缓冲区不复制。

---

## 13. 测试/场景义务

数据副本；length；remote/local；truncated；receivedAtMono；interfaceIndex；空数据报；零长度；发送/接收往返。

---

## 14. XNull 伪代码

```xnull
class Datagram {
    final Bytes _data
    final SocketAddress _remote
    final SocketAddress? _local
    final Bool _truncated
    final Long? _receivedAtMono
    final Int _interfaceIndex

    Datagram(Bytes data, SocketAddress remote) {
        if data == null || remote == null {
            throw "Datagram: null argument"
        }
        _data = data.copy()
        _remote = remote
        _local = null
        _truncated = false
        _receivedAtMono = null
        _interfaceIndex = 0
    }

    Datagram(Bytes data, SocketAddress remote, Bool truncated) {
        if data == null || remote == null {
            throw "Datagram: null argument"
        }
        _data = data.copy()
        _remote = remote
        _local = null
        _truncated = truncated
        _receivedAtMono = null
        _interfaceIndex = 0
    }

    Datagram(Bytes data, SocketAddress remote, SocketAddress? local,
             Bool truncated, Long? receivedAtMono, Int interfaceIndex) {
        if data == null || remote == null {
            throw "Datagram: null argument"
        }
        if interfaceIndex < 0 { throw "Datagram: invalid interface index" }
        if receivedAtMono != null {
            Long value = receivedAtMono as Long
            if value < 0 { throw "Datagram: negative receive time" }
        }
        _data = data.copy()
        _remote = remote
        _local = local
        _truncated = truncated
        _receivedAtMono = receivedAtMono
        _interfaceIndex = interfaceIndex
    }

    Bytes data() { return _data.copy() }
    SocketAddress remote() { return _remote }
    SocketAddress? local() { return _local }
    Int length() { return _data.length() }
    Bool isTruncated() { return _truncated }
    Long? receivedAtMono() { return _receivedAtMono }
    Int interfaceIndex() { return _interfaceIndex }
}
```
