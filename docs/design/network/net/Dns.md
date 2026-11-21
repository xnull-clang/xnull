# `Dns`

| 项 | 值 |
| --- | --- |
| 类型 | `class Dns` |
| 包 | `xdk.net` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`IpAddress`、`IpFamily`、`Error` |

---

## 1. 定位

DNS 正向/反向解析的静态入口：全部地址、首个匹配族地址、反向名称。

不做：全局缓存、TTL、定制 DNS 服务器、DoH/DoT、EDNS、搜索域；这些是 X 的显式 resolver。

---

## 2. 设计逻辑

- 无实例状态；构造器私有；全部静态方法。
- 每次解析都走运行时 DNS 原语；不维护全局缓存。
- `resolveOne` 先 `resolve`，再按 family 过滤；`Unspecified` 表示任意族。
- 首个匹配地址；没有匹配返回 `NotFound`。
- 阻塞解析首参 `Context`；取消/超时由原语返回。
- 无 close；可并发调用。

---

## 3. 表示与不变量

无实例字段。

---

## 4. 生命周期

静态命名空间；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Dns()` | 无 | 私有 | 外部构造 → 编译错误 |

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `resolve` | 解析全部地址 | `Context context, String host` | `Result<List<IpAddress>, Error>` | `NotFound`/`Network`/`Timeout`/`Cancelled` |
| `resolveOne` | 首个匹配族 | `Context context, String host, IpFamily family` | `Result<IpAddress, Error>` | 同上 + `NotFound` |
| `reverse` | 反向解析 | `Context context, IpAddress address` | `Result<String, Error>` | `NotFound`/`Network`/`Timeout`/`Cancelled` |

说明：

- `host` 非空；null/空 → panic。
- `resolve` 返回空列表视为 `NotFound`。
- `resolveOne` 不改变 `resolve` 结果顺序。
- `reverse` 返回主机名；无 PTR 记录 `NotFound`。

---

## 8. 使用的技术

- 系统 DNS；
- 地址族过滤；
- Context 取消。

---

## 9. 需要的支撑

- 语言：class、List、String、Result；
- 运行时：`dnsResolveRaw`、`dnsReverseRaw`；
- 接口：`Context`、`IpAddress`、`IpFamily`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Context`、`IpAddress`、`IpFamily`、`BasicError`、`ErrorKind`、`dnsResolveRaw`、`dnsReverseRaw`。

---

## 11. 所有权与并发

无状态；可并发；无资源；不缓存结果。

---

## 12. 示例与反例

正确：`Dns.resolveOne(ctx,"example.com",IpFamily.Ipv4)`。  
反例：依赖全局 DNS 缓存；把 `Unspecified` 只当 IPv4；忽略 `Context`。

---

## 13. 测试/场景义务

成功/不存在；多地址；族过滤；Unspecified；反向解析；取消/超时；空 host；无缓存。

---

## 14. XNull 伪代码

```xnull
class Dns {
    private Dns() {
    }

    static Result<List<IpAddress>, Error> resolve(Context context, String host) {
        if context == null { throw "Dns.resolve: null context" }
        if host == null || host == "" { throw "Dns.resolve: empty host" }
        Result<List<IpAddress>, Error> result = dnsResolveRaw(context, host)
        if result.isErr() { return Err(result.error()) }
        if result.value().length() == 0 {
            return Err(new BasicError(ErrorKind.NotFound, "host not found: " + host))
        }
        return result
    }

    static Result<IpAddress, Error> resolveOne(Context context, String host, IpFamily family) {
        Result<List<IpAddress>, Error> resolved = Dns.resolve(context, host)
        if resolved.isErr() { return Err(resolved.error()) }
        List<IpAddress> addresses = resolved.value()
        Int index = 0
        while index < addresses.length() {
            IpAddress address = addresses.get(index)
            if family == IpFamily.Unspecified || address.family() == family {
                return Ok(address)
            }
            index = index + 1
        }
        return Err(new BasicError(ErrorKind.NotFound, "no matching address: " + host))
    }

    static Result<String, Error> reverse(Context context, IpAddress address) {
        if context == null { throw "Dns.reverse: null context" }
        if address == null { throw "Dns.reverse: null address" }
        return dnsReverseRaw(context, address)
    }
}
```

> `dnsResolveRaw`、`dnsReverseRaw` 是运行时 DNS 原语；不是 XDK 公共类型。
