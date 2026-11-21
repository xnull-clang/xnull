# `IpPrefix`

| 项 | 值 |
| --- | --- |
| 类型 | `class IpPrefix` |
| 包 | `xdk.net` |
| 稳定性 | `preview` |
| 依赖 | `IpAddress`、`IpFamily`、`Error` |

---

## 1. 定位

IP 前缀/网段：地址 + 前缀长度、网络地址、广播地址（IPv4）、包含判断、文本、比较。

不做：路由表、CIDR 合并、IPv6 广播、DNS、防火墙策略。

---

## 2. 设计逻辑

- 字段 `_address: IpAddress`、`_prefixLength: Int`。
- IPv4 前缀长度 0..32；IPv6 0..128；按地址族校验。
- `parse` 接受 `address/prefix`；调用运行时前缀解析。
- `network`/`broadcast`/`contains` 由运行时位运算原语完成。
- IPv6 `broadcast` 返回 null（无广播）。
- 不可变；无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_address` | `IpAddress` | 基准地址 |
| `_prefixLength` | `Int` | 前缀长度 |

不变量：address 非 null；prefixLength 在族范围内；不可变。

---

## 4. 生命周期

构造/解析后不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `IpPrefix(IpAddress address, Int prefixLength)` | address/prefix | 族范围 | 越界 → panic |
| `IpPrefix.parse(String text)` | text | 非 null | `InvalidArgument` |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `parse` | 解析前缀 | `String text` | `Result<IpPrefix, Error>` | `InvalidArgument` |
| `address` | 基准地址 | 无 | `IpAddress` | 无 |
| `prefixLength` | 前缀长度 | 无 | `Int` | 无 |
| `network` | 网络地址 | 无 | `IpAddress` | 无 |
| `broadcast` | 广播地址/无 | 无 | `IpAddress?` | 无 |
| `contains` | 是否包含地址 | `IpAddress address` | `Bool` | 无 |
| `containsPrefix` | 是否包含前缀 | `IpPrefix other` | `Bool` | 无 |
| `text` | CIDR 文本 | 无 | `String` | 无 |
| `equals` | 值相等 | `IpPrefix other` | `Bool` | 无 |
| `compare` | 排序 | `IpPrefix other` | `Int` | null → panic |

---

## 8. 使用的技术

- CIDR；
- 位掩码；
- 运行时前缀原语。

---

## 9. 需要的支撑

- 语言：class、Int、Bool、Result；
- 运行时：`parseIpPrefixRaw`、`ipPrefixNetworkRaw`、`ipPrefixBroadcastRaw`、`ipPrefixContainsRaw`、`ipPrefixContainsPrefixRaw`、`IpPrefixRaw`；
- 接口：`IpAddress`、`IpFamily`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`IpAddress`、`IpFamily`、`Error`、`BasicError`、`ErrorKind`、前缀运行时原语。

---

## 11. 所有权与并发

不可变；无资源；可共享。

---

## 12. 示例与反例

正确：`IpPrefix.parse("10.0.0.0/8").contains(IpAddress.parse("10.1.2.3").value())`。  
反例：IPv4 用 /64；IPv6 取 broadcast；把前缀长度当掩码。

---

## 13. 测试/场景义务

IPv4/IPv6 解析；/0、最大前缀；network/broadcast；contains；containsPrefix；越界；equals/compare。

---

## 14. XNull 伪代码

```xnull
class IpPrefix {
    final IpAddress _address
    final Int _prefixLength

    IpPrefix(IpAddress address, Int prefixLength) {
        if address == null { throw "IpPrefix: null address" }
        Int maximum = 32
        if address.family() == IpFamily.Ipv6 { maximum = 128 }
        if prefixLength < 0 || prefixLength > maximum {
            throw "IpPrefix: invalid prefix length"
        }
        _address = address
        _prefixLength = prefixLength
    }

    static Result<IpPrefix, Error> parse(String text) {
        if text == null { throw "IpPrefix.parse: null text" }
        Result<IpPrefixRaw, Error> raw = parseIpPrefixRaw(text)
        if raw.isErr() { return Err(raw.error()) }
        return Ok(new IpPrefix(raw.value().address(), raw.value().prefixLength()))
    }

    IpAddress address() { return _address }
    Int prefixLength() { return _prefixLength }
    IpAddress network() { return ipPrefixNetworkRaw(_address, _prefixLength) }
    IpAddress? broadcast() { return ipPrefixBroadcastRaw(_address, _prefixLength) }

    Bool contains(IpAddress address) {
        if address == null { return false }
        return ipPrefixContainsRaw(_address, _prefixLength, address)
    }

    Bool containsPrefix(IpPrefix other) {
        if other == null { return false }
        return ipPrefixContainsPrefixRaw(_address, _prefixLength, other.address(), other.prefixLength())
    }

    String text() { return _address.text() + "/" + str(_prefixLength) }

    Bool equals(IpPrefix other) {
        if other == null { return false }
        return _address.equals(other.address()) && _prefixLength == other.prefixLength()
    }

    Int compare(IpPrefix other) {
        if other == null { throw "IpPrefix.compare: null" }
        Int byAddress = _address.compare(other.address())
        if byAddress != 0 { return byAddress }
        if _prefixLength < other.prefixLength() { return -1 }
        if _prefixLength > other.prefixLength() { return 1 }
        return 0
    }
}
```

> `IpPrefixRaw` 和 `ipPrefix*Raw` 是运行时前缀原语；不是 XDK 公共类型。
