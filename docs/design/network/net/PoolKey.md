# `PoolKey`

| 项 | 值 |
| --- | --- |
| 类型 | `class PoolKey` |
| 包 | `xdk.net` |
| 稳定性 | `preview` |
| 依赖 | `SocketAddress` |

---

## 1. 定位

连接池键：协议 scheme + 远端地址。

不做：TLS 配置/证书指纹、代理链、租户 ID；这些由调用方组合到 key 字符串或扩展。

---

## 2. 设计逻辑

- 不可变字段 `_scheme`、`_remote`。
- `scheme` 非空小写（`tcp`、`tls`、`http` 等）。
- 相同 scheme + remote 视为同一池键。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_scheme` | `String` | 协议标签 |
| `_remote` | `SocketAddress` | 远端 |

不变量：scheme 非空；remote 非 null；不可变。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `PoolKey(String scheme, SocketAddress remote)` | scheme/remote | 非空/非 null | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `scheme` | 协议标签 | 无 | `String` | 无 |
| `remote` | 远端 | 无 | `SocketAddress` | 无 |
| `equals` | 值相等 | `PoolKey other` | `Bool` | 无 |
| `toString` | 文本 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 不可变键；
- 值相等。

---

## 9. 需要的支撑

- 语言：class、String、Bool；
- 运行时：无；
- 接口：`SocketAddress`。

---

## 10. 依赖的特性/接口/类

`SocketAddress`。

---

## 11. 所有权与并发

不可变；无资源；可共享；可作 Map 键。

---

## 12. 示例与反例

正确：`new PoolKey("tcp", address)`。  
反例：scheme 空；忽略 TLS 配置导致复用错误连接；用可变对象做键。

---

## 13. 测试/场景义务

scheme/remote；equals；toString；大小写；作为 Map 键。

---

## 14. XNull 伪代码

```xnull
class PoolKey {
    final String _scheme
    final SocketAddress _remote

    PoolKey(String scheme, SocketAddress remote) {
        if scheme == null || scheme == "" { throw "PoolKey: empty scheme" }
        if remote == null { throw "PoolKey: null remote" }
        _scheme = scheme
        _remote = remote
    }

    String scheme() { return _scheme }
    SocketAddress remote() { return _remote }

    Bool equals(PoolKey other) {
        if other == null { return false }
        return _scheme == other.scheme() && _remote.equals(other.remote())
    }

    String toString() {
        return _scheme + "://" + _remote.text()
    }
}
```
