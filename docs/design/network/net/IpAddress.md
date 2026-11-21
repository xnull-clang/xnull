# `IpAddress`

| 项 | 值 |
| --- | --- |
| 类型 | `class IpAddress` |
| 包 | `xdk.net` |
| 稳定性 | `preview` |
| 依赖 | `IpFamily`、`Bytes`、`Error` |

---

## 1. 定位

不可变 IP 地址：解析、格式化、4/16 字节表示、回环/通配/组播分类、值相等。

不做：端口（`SocketAddress`）、前缀/网段、DNS、IPv6 zone id、私有/全局分类（X）。

---

## 2. 设计逻辑

- 字段 `_family: IpFamily`、`_bytes: Bytes`；构造时复制。
- IPv4 为 4 字节，IPv6 为 16 字节；拒绝 `Unspecified` 实例。
- `parse` 调用运行时 IP 解析原语；支持 IPv4/IPv6。
- `text` 调用运行时格式化；IPv6 规范压缩。
- 分类由运行时原语判断；不重复实现地址算术。
- 不可变；无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_family` | `IpFamily` | Ipv4/Ipv6 |
| `_bytes` | `Bytes` | 4/16 字节 |

不变量：family 非 Unspecified；bytes 长度与 family 匹配；不可变。

---

## 4. 生命周期

解析/常量构造后不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `IpAddress.parse(String text)` | text | 非 null | `InvalidArgument` |
| `IpAddress.loopback(IpFamily family)` | family | Ipv4/Ipv6 | `Unsupported` |
| `IpAddress.any(IpFamily family)` | family | Ipv4/Ipv6 | `Unsupported` |

构造器私有。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `parse` | 解析 IP | `String text` | `Result<IpAddress, Error>` | `InvalidArgument` |
| `loopback` | 回环地址 | `IpFamily family` | `Result<IpAddress, Error>` | `Unsupported` |
| `any` | 通配地址 | `IpFamily family` | `Result<IpAddress, Error>` | `Unsupported` |
| `family` | 地址族 | 无 | `IpFamily` | 无 |
| `text` | 规范文本 | 无 | `String` | 无 |
| `bytes` | 字节副本 | 无 | `Bytes` | 无 |
| `isLoopback` | 是否回环 | 无 | `Bool` | 无 |
| `isUnspecified` | 是否通配 | 无 | `Bool` | 无 |
| `isMulticast` | 是否组播 | 无 | `Bool` | 无 |
| `isPrivate` | 是否私有地址 | 无 | `Bool` | 无 |
| `isLinkLocal` | 是否链路本地 | 无 | `Bool` | 无 |
| `isGlobal` | 是否全局 | 无 | `Bool` | 无 |
| `equals` | 值相等 | `IpAddress other` | `Bool` | 无 |
| `compare` | 排序 | `IpAddress other` | `Int` | null → panic |
| `toString` | 文本 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 4/16 字节表示；
- IP 解析/格式化原语；
- 地址分类原语；
- 值相等。

---

## 9. 需要的支撑

- 语言：class、Bytes、Bool、Result；
- 运行时：`parseIpRaw`、`formatIpRaw`、`ipLoopbackRaw`、`ipAnyRaw`、`ipIsLoopbackRaw`、`ipIsUnspecifiedRaw`、`ipIsMulticastRaw`、`ipIsPrivateRaw`、`ipIsLinkLocalRaw`、`ipIsGlobalRaw`、`ipCompareRaw`；
- 接口：`IpFamily`、`Error`、`BasicError`、`ErrorKind`、`equals`。

---

## 10. 依赖的特性/接口/类

`IpFamily`、`Bytes`、`Error`、`BasicError`、`ErrorKind`、`equals`。

---

## 11. 所有权与并发

不可变；`bytes` 返回副本；无资源；可共享。

---

## 12. 示例与反例

正确：`IpAddress.parse("192.0.2.1")`；`IpAddress.parse("2001:db8::1")`。  
反例：用 `Unspecified` 构造实例；修改 `bytes()` 期望地址变化；把 IPv4 字符串当 16 字节。

---

## 13. 测试/场景义务

IPv4/IPv6 解析；格式化往返；回环/通配/组播；私有/链路本地/全局；非法文本；bytes 长度；equals/compare；IPv6 压缩。

---

## 14. XNull 伪代码

```xnull
class IpAddress {
    final IpFamily _family
    final Bytes _bytes

    private IpAddress(IpFamily family, Bytes bytes) {
        if family == IpFamily.Unspecified {
            throw "IpAddress: unspecified family"
        }
        _family = family
        _bytes = bytes.copy()
    }

    static Result<IpAddress, Error> parse(String text) {
        if text == null { throw "IpAddress.parse: null text" }
        Result<IpAddressRaw, Error> parsed = parseIpRaw(text)
        if parsed.isErr() { return Err(parsed.error()) }
        IpAddressRaw raw = parsed.value()
        return Ok(new IpAddress(raw.family(), raw.bytes()))
    }

    static Result<IpAddress, Error> loopback(IpFamily family) {
        if family == IpFamily.Unspecified {
            return Err(new BasicError(ErrorKind.Unsupported, "unspecified family"))
        }
        Result<IpAddressRaw, Error> raw = ipLoopbackRaw(family)
        if raw.isErr() { return Err(raw.error()) }
        return Ok(new IpAddress(raw.value().family(), raw.value().bytes()))
    }

    static Result<IpAddress, Error> any(IpFamily family) {
        if family == IpFamily.Unspecified {
            return Err(new BasicError(ErrorKind.Unsupported, "unspecified family"))
        }
        Result<IpAddressRaw, Error> raw = ipAnyRaw(family)
        if raw.isErr() { return Err(raw.error()) }
        return Ok(new IpAddress(raw.value().family(), raw.value().bytes()))
    }

    IpFamily family() { return _family }
    String text() { return formatIpRaw(_family, _bytes) }
    Bytes bytes() { return _bytes.copy() }

    Bool isLoopback() { return ipIsLoopbackRaw(_family, _bytes) }
    Bool isUnspecified() { return ipIsUnspecifiedRaw(_family, _bytes) }
    Bool isMulticast() { return ipIsMulticastRaw(_family, _bytes) }
    Bool isPrivate() { return ipIsPrivateRaw(_family, _bytes) }
    Bool isLinkLocal() { return ipIsLinkLocalRaw(_family, _bytes) }
    Bool isGlobal() { return ipIsGlobalRaw(_family, _bytes) }

    Bool equals(IpAddress other) {
        if other == null { return false }
        if _family != other.family() { return false }
        return equals(_bytes, other.bytes())
    }

    Int compare(IpAddress other) {
        if other == null { throw "IpAddress.compare: null" }
        Int result = ipCompareRaw(_family, _bytes, other.family(), other.bytes())
        return result
    }

    String toString() { return self.text() }
}
```

> `IpAddressRaw`、`parseIpRaw`、`formatIpRaw`、`ipLoopbackRaw`、`ipAnyRaw`、`ipIs*Raw` 是运行时 IP 原语；不是 XDK 公共类型。
