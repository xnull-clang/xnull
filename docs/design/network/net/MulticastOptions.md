# `MulticastOptions`

| 项 | 值 |
| --- | --- |
| 类型 | `class MulticastOptions` |
| 包 | `xdk.net` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

UDP 组播加入选项：网卡名、回环、TTL。

不做：源过滤、IGMP 版本、组播路由、广播开关（`UdpSocket.setBroadcast`）。

---

## 2. 设计逻辑

- 可变构建期；加入组播时读取快照。
- 默认回环 true、TTL 1；网卡名 null 表示系统默认。
- TTL 0..255；非法是合同错误。
- 无 close；非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_interfaceName` | `String?` | 网卡名；null 默认 |
| `_loopback` | `Bool` | 是否回环 |
| `_ttl` | `Int` | 0..255 |

---

## 4. 生命周期

构造后可变；无 close；`copy` 独立。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `MulticastOptions()` | 无 | 默认 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `interfaceName` | 设置网卡 | `String name` | `MulticastOptions` | 空/null → panic |
| `loopback` | 设置回环 | `Bool value` | `MulticastOptions` | 无 |
| `ttl` | 设置 TTL | `Int value` | `MulticastOptions` | 越界 → panic |
| `getInterfaceName` | 网卡/无 | 无 | `String?` | 无 |
| `isLoopback` | 回环 | 无 | `Bool` | 无 |
| `getTtl` | TTL | 无 | `Int` | 无 |
| `copy` | 独立快照 | 无 | `MulticastOptions` | 无 |

---

## 8. 使用的技术

- builder；
- 可空网卡；
- 快照。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Int；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

可变；非线程安全；无资源。

---

## 12. 示例与反例

正确：`new MulticastOptions().interfaceName("en0").ttl(2)`。  
反例：TTL 256；空网卡名；加入组播后修改期望生效。

---

## 13. 测试/场景义务

默认值；setter；TTL 0/255/越界；copy 独立；空网卡名。

---

## 14. XNull 伪代码

```xnull
class MulticastOptions {
    String? _interfaceName = null
    Bool _loopback = true
    Int _ttl = 1

    MulticastOptions() {
    }

    MulticastOptions interfaceName(String name) {
        if name == null || name == "" {
            throw "MulticastOptions.interfaceName: empty"
        }
        _interfaceName = name
        return self
    }

    MulticastOptions loopback(Bool value) {
        _loopback = value
        return self
    }

    MulticastOptions ttl(Int value) {
        if value < 0 || value > 255 {
            throw "MulticastOptions.ttl: invalid value"
        }
        _ttl = value
        return self
    }

    String? getInterfaceName() { return _interfaceName }
    Bool isLoopback() { return _loopback }
    Int getTtl() { return _ttl }

    MulticastOptions copy() {
        MulticastOptions result = new MulticastOptions()
        if _interfaceName != null {
            result.interfaceName(_interfaceName as String)
        }
        result.loopback(_loopback)
        result.ttl(_ttl)
        return result
    }
}
```
