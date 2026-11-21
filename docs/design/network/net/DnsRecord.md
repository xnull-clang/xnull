# `DnsRecord`

| 项 | 值 |
| --- | --- |
| 类型 | `class DnsRecord` |
| 包 | `xdk.net` |
| 稳定性 | `preview` |
| 依赖 | `IpAddress` |

---

## 1. 定位

一条 DNS 正向记录：地址、TTL、绝对过期时间。

不做：DNS 报文、CNAME 链、MX/TXT、DNSSEC。

---

## 2. 设计逻辑

- 不可变字段 `_address`、`_ttlSeconds`、`_expiresAtMillis`。
- `expiresAtMillis` 是墙钟毫秒；缓存判断用它，不用 TTL 重新累加。
- `isExpired(nowMillis)` 纯比较。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_address` | `IpAddress` | 地址 |
| `_ttlSeconds` | `Long` | TTL 秒 |
| `_expiresAtMillis` | `Long` | 墙钟过期 |

不变量：address 非 null；ttl ≥0；expiresAt ≥0；不可变。

---

## 4. 生命周期

解析/构造后不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `DnsRecord(IpAddress address, Long ttlSeconds, Long expiresAtMillis)` | 见字段 | address 非 null；ttl/expires ≥0 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `address` | 地址 | 无 | `IpAddress` | 无 |
| `ttlSeconds` | TTL | 无 | `Long` | 无 |
| `expiresAtMillis` | 过期墙钟 | 无 | `Long` | 无 |
| `isExpired` | 是否过期 | `Long nowMillis` | `Bool` | 无 |
| `toString` | 摘要 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 不可变记录；
- TTL/过期时间。

---

## 9. 需要的支撑

- 语言：class、Long、Bool；
- 运行时：无；
- 接口：`IpAddress`。

---

## 10. 依赖的特性/接口/类

`IpAddress`。

---

## 11. 所有权与并发

不可变；无资源；可共享。

---

## 12. 示例与反例

正确：`record.isExpired(nowWall())`。  
反例：用 TTL 重新计算每次请求；把过期时间当单调时间；TTL 负数。

---

## 13. 测试/场景义务

边界 0；过期/未过期；TTL；地址；不可变；toString。

---

## 14. XNull 伪代码

```xnull
class DnsRecord {
    final IpAddress _address
    final Long _ttlSeconds
    final Long _expiresAtMillis

    DnsRecord(IpAddress address, Long ttlSeconds, Long expiresAtMillis) {
        if address == null { throw "DnsRecord: null address" }
        if ttlSeconds < 0 || expiresAtMillis < 0 {
            throw "DnsRecord: negative value"
        }
        _address = address
        _ttlSeconds = ttlSeconds
        _expiresAtMillis = expiresAtMillis
    }

    IpAddress address() { return _address }
    Long ttlSeconds() { return _ttlSeconds }
    Long expiresAtMillis() { return _expiresAtMillis }

    Bool isExpired(Long nowMillis) {
        return nowMillis >= _expiresAtMillis
    }

    String toString() {
        return _address.text() + " ttl=" + str(_ttlSeconds)
    }
}
```
