# `NetworkInterface`

| 项 | 值 |
| --- | --- |
| 类型 | `class NetworkInterface` |
| 包 | `xdk.net` |
| 稳定性 | `preview` |
| 依赖 | `IpPrefix`、`Error` |

---

## 1. 定位

本机网络接口快照：名称、显示名、地址/前缀、up/loopback/multicast、MTU、硬件地址。

不做：修改接口、路由表、流量统计、无线扫描、虚拟网卡管理。

---

## 2. 设计逻辑

- 不可变快照；字段由运行时接口枚举原语提供。
- `addresses` 返回 `List<IpPrefix>`，同时保留 IP 与前缀长度。
- `hardwareAddress` 可空（loopback/虚拟接口）。
- `list`/`byName` 每次重新枚举；不缓存全局结果。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | 系统名 |
| `_displayName` | `String` | 显示名 |
| `_addresses` | `List<IpPrefix>` | 地址/前缀 |
| `_isUp` | `Bool` | 是否 up |
| `_isLoopback` | `Bool` | 是否 loopback |
| `_isMulticast` | `Bool` | 是否支持组播 |
| `_mtu` | `Int` | MTU |
| `_hardwareAddress` | `String?` | 硬件地址 |

不变量：name/displayName 非空；mtu >0；addresses 非 null；不可变。

---

## 4. 生命周期

快照；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `NetworkInterface.list()` | 无 | 平台支持 | `Unavailable` |
| `NetworkInterface.byName(String name)` | name | 非空 | null（不存在） |

构造器私有。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `list` | 枚举接口 | 无 | `Result<List<NetworkInterface>, Error>` | `Unavailable` |
| `byName` | 按名查找 | `String name` | `Result<NetworkInterface, Error>` | `Unavailable`/`NotFound` |
| `name` | 系统名 | 无 | `String` | 无 |
| `displayName` | 显示名 | 无 | `String` | 无 |
| `addresses` | 地址/前缀快照 | 无 | `List<IpPrefix>` | 无 |
| `isUp` | 是否 up | 无 | `Bool` | 无 |
| `isLoopback` | 是否 loopback | 无 | `Bool` | 无 |
| `isMulticast` | 是否支持组播 | 无 | `Bool` | 无 |
| `mtu` | MTU | 无 | `Int` | 无 |
| `hardwareAddress` | 硬件地址/无 | 无 | `String?` | 无 |

---

## 8. 使用的技术

- 接口枚举；
- 地址/前缀；
- 快照。

---

## 9. 需要的支撑

- 语言：class、List、String、Bool、Int、Result；
- 运行时：`listNetworkInterfacesRaw`、`NetworkInterfaceRaw`；
- 接口：`IpPrefix`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`IpPrefix`、`Error`、`BasicError`、`ErrorKind`、`listNetworkInterfacesRaw`。

---

## 11. 所有权与并发

不可变；`addresses()` 返回副本；无资源；可共享。

---

## 12. 示例与反例

正确：`NetworkInterface.byName("en0").addresses()`。  
反例：修改 addresses 期望接口变化；依赖接口顺序；把 loopback 当可组播。

---

## 13. 测试/场景义务

枚举；byName 命中/缺失；up/loopback/multicast；MTU；硬件地址可空；地址前缀；快照独立。

---

## 14. XNull 伪代码

```xnull
class NetworkInterface {
    final String _name
    final String _displayName
    final List<IpPrefix> _addresses
    final Bool _isUp
    final Bool _isLoopback
    final Bool _isMulticast
    final Int _mtu
    final String? _hardwareAddress

    private NetworkInterface(String name, String displayName, List<IpPrefix> addresses,
                             Bool isUp, Bool isLoopback, Bool isMulticast, Int mtu,
                             String? hardwareAddress) {
        _name = name
        _displayName = displayName
        _addresses = addresses.copy()
        _isUp = isUp
        _isLoopback = isLoopback
        _isMulticast = isMulticast
        _mtu = mtu
        _hardwareAddress = hardwareAddress
    }

    static Result<List<NetworkInterface>, Error> list() {
        Result<List<NetworkInterfaceRaw>, Error> raw = listNetworkInterfacesRaw()
        if raw.isErr() { return Err(raw.error()) }
        List<NetworkInterface> result = []
        Int index = 0
        while index < raw.value().length() {
            NetworkInterfaceRaw item = raw.value().get(index)
            result.push(new NetworkInterface(
                item.name(), item.displayName(), item.addresses(), item.isUp(),
                item.isLoopback(), item.isMulticast(), item.mtu(), item.hardwareAddress()))
            index = index + 1
        }
        return Ok(result)
    }

    static Result<NetworkInterface, Error> byName(String name) {
        if name == null || name == "" { throw "NetworkInterface.byName: empty" }
        Result<List<NetworkInterface>, Error> all = NetworkInterface.list()
        if all.isErr() { return Err(all.error()) }
        Int index = 0
        while index < all.value().length() {
            if all.value().get(index).name() == name {
                return Ok(all.value().get(index))
            }
            index = index + 1
        }
        return Err(new BasicError(ErrorKind.NotFound, "interface not found: " + name))
    }

    String name() { return _name }
    String displayName() { return _displayName }
    List<IpPrefix> addresses() { return _addresses.copy() }
    Bool isUp() { return _isUp }
    Bool isLoopback() { return _isLoopback }
    Bool isMulticast() { return _isMulticast }
    Int mtu() { return _mtu }
    String? hardwareAddress() { return _hardwareAddress }
}
```

> `NetworkInterfaceRaw`、`listNetworkInterfacesRaw` 是运行时接口枚举原语；不是 XDK 公共类型。
