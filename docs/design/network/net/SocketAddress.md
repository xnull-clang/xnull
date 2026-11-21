# `SocketAddress`

| 项 | 值 |
| --- | --- |
| 类型 | `class SocketAddress` |
| 包 | `xdk.net` |
| 稳定性 | `preview` |
| 依赖 | `IpAddress`、`IpFamily`、`Error` |

---

## 1. 定位

不可变 IP + 端口地址：构造、文本解析、规范文本、值相等。

不做：DNS 解析、Unix domain socket、IPv6 zone id、服务名解析。

---

## 2. 设计逻辑

- 字段 `_address: IpAddress`、`_port: Int`。
- 端口 0..65535；0 合法（内核分配/通配）。
- `parse` 支持 `a.b.c.d:port` 与 `[ipv6]:port`；由运行时原语处理方括号。
- `text` 对 IPv6 加方括号。
- 不可变；无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_address` | `IpAddress` | IP |
| `_port` | `Int` | 0..65535 |

不变量：address 非 null；port 合法；不可变。

---

## 4. 生命周期

构造/解析后不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `SocketAddress(IpAddress address, Int port)` | address/port | 非 null；0..65535 | 非法 → panic |
| `SocketAddress.parse(String text)` | text | 非 null | `InvalidArgument` |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `parse` | 解析地址 | `String text` | `Result<SocketAddress, Error>` | `InvalidArgument` |
| `address` | IP | 无 | `IpAddress` | 无 |
| `port` | 端口 | 无 | `Int` | 无 |
| `text` | 规范文本 | 无 | `String` | 无 |
| `equals` | 值相等 | `SocketAddress other` | `Bool` | 无 |
| `compare` | 排序 | `SocketAddress other` | `Int` | null → panic |
| `toString` | 文本 | 无 | `String` | 无 |

---

## 8. 使用的技术

- IP + 端口；
- IPv6 方括号；
- 运行时地址解析。

---

## 9. 需要的支撑

- 语言：class、Int、Bool、String、Result；
- 运行时：`parseSocketAddressRaw`、`SocketAddressRaw`；
- 接口：`IpAddress`、`IpFamily`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`IpAddress`、`IpFamily`、`Error`、`BasicError`、`ErrorKind`、`parseSocketAddressRaw`。

---

## 11. 所有权与并发

不可变；无资源；可共享。

---

## 12. 示例与反例

正确：`SocketAddress.parse("127.0.0.1:9000")`；`[::1]:9000`。  
反例：端口 -1；把 IPv6 裸文本当 `host:port`；用 0 表示缺失（0 是合法端口）。

---

## 13. 测试/场景义务

IPv4/IPv6 解析；方括号；端口 0/65535；越界；非法文本；text 往返；equals/compare。

---

## 14. XNull 伪代码

```xnull
class SocketAddress {
    final IpAddress _address
    final Int _port

    SocketAddress(IpAddress address, Int port) {
        if address == null { throw "SocketAddress: null address" }
        if port < 0 || port > 65535 {
            throw "SocketAddress: invalid port"
        }
        _address = address
        _port = port
    }

    static Result<SocketAddress, Error> parse(String text) {
        if text == null { throw "SocketAddress.parse: null text" }
        Result<SocketAddressRaw, Error> raw = parseSocketAddressRaw(text)
        if raw.isErr() { return Err(raw.error()) }
        return Ok(new SocketAddress(raw.value().address(), raw.value().port()))
    }

    IpAddress address() { return _address }
    Int port() { return _port }

    String text() {
        String host = _address.text()
        if _address.family() == IpFamily.Ipv6 {
            host = "[" + host + "]"
        }
        return host + ":" + str(_port)
    }

    Bool equals(SocketAddress other) {
        if other == null { return false }
        return _address.equals(other.address()) && _port == other.port()
    }

    Int compare(SocketAddress other) {
        if other == null { throw "SocketAddress.compare: null" }
        Int result = _address.compare(other.address())
        if result != 0 { return result }
        if _port < other.port() { return -1 }
        if _port > other.port() { return 1 }
        return 0
    }

    String toString() { return self.text() }
}
```

> `SocketAddressRaw`、`parseSocketAddressRaw` 是运行时地址原语；不是 XDK 公共类型。
