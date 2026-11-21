# `DnsResolver`

| 项 | 值 |
| --- | --- |
| 类型 | `class DnsResolver` |
| 包 | `xdk.net` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`DnsRecord`、`DnsResolverOptions`、`DnsCacheStats`、`Error` |

---

## 1. 定位

显式 DNS resolver：正向/反向解析、TTL 缓存、缓存统计、关闭。

不做：DoH/DoT、DNSSEC、全局缓存、系统配置修改。

---

## 2. 设计逻辑

- 字段 `_handle`（运行时 resolver）、`_options`、`_open`。
- 构造时复制 options；运行时创建缓存/查询上下文。
- `resolve` 返回带 TTL 的 `DnsRecord`；缓存由 resol​​ver 持有，不共享。
- `resolveOne` 在结果中按族过滤；`Unspecified` 任意。
- `close` 停止后台刷新/释放缓存；幂等；关闭后查询 `Unavailable`。
- 无全局状态；每个 resolver 独立。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_handle` | `DnsResolverHandle` | 运行时句柄 |
| `_options` | `DnsResolverOptions` | 配置副本 |
| `_open` | `Bool` | 是否可用 |

不变量：handle/options 非 null；close 后 open=false。

---

## 4. 生命周期

构造创建；必须 close；close 幂等；关闭后查询 `Unavailable`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `DnsResolver()` | 无 | 默认 options | `Unavailable` |
| `DnsResolver(DnsResolverOptions options)` | options | 非 null | 同上 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `resolve` | 正向解析 | `Context, String host` | `Result<List<DnsRecord>, Error>` | `NotFound`/`Network`/`Timeout`/`Cancelled`/`Unavailable` |
| `resolveOne` | 首个匹配族 | `Context, String host, IpFamily family` | `Result<DnsRecord, Error>` | 同上 |
| `reverse` | 反向解析 | `Context, IpAddress address` | `Result<String, Error>` | 同上 |
| `clearCache` | 清空缓存 | 无 | `void` | 无 |
| `cacheStats` | 缓存统计 | 无 | `DnsCacheStats` | 关闭 → panic |
| `options` | 配置快照 | 无 | `DnsResolverOptions` | 无 |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |

---

## 8. 使用的技术

- 显式缓存；
- TTL；
- 运行时 DNS；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、List、String、Bool、Result；
- 运行时：`dnsResolverCreateRaw`、`dnsResolverResolveRaw`、`dnsResolverReverseRaw`、`dnsResolverClearRaw`、`dnsResolverStatsRaw`、`dnsResolverCloseRaw`、`DnsResolverHandle`；
- 接口：`Context`、`DnsRecord`、`DnsResolverOptions`、`DnsCacheStats`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`Context`、`DnsRecord`、`DnsResolverOptions`、`DnsCacheStats`、`DnsResolverHandle`、DNS 运行时原语、`Error`。

---

## 11. 所有权与并发

引用语义；拥有 resolver 句柄/缓存；查询可并发；close 可并发；关闭后不可用。

---

## 12. 示例与反例

正确：`resolver.resolve(ctx,"example.com")`；`resolver.cacheStats()`。  
反例：跨 resolver 共享缓存；close 后查询；修改 options 期望已有 resolver 变化；依赖全局缓存。

---

## 13. 测试/场景义务

默认/自定义 options；正/负缓存；TTL 过期；resolveOne 族过滤；反向；clear；stats；cancel/timeout；close 幂等。

---

## 14. XNull 伪代码

```xnull
class DnsResolver {
    final DnsResolverHandle _handle
    final DnsResolverOptions _options
    Bool _open

    DnsResolver() {
        DnsResolverOptions options = new DnsResolverOptions()
        Result<DnsResolverHandle, Error> raw = dnsResolverCreateRaw(options)
        if raw.isErr() {
            throw "DnsResolver: create failed: " + raw.error().describe()
        }
        _handle = raw.value()
        _options = options.copy()
        _open = true
    }

    DnsResolver(DnsResolverOptions options) {
        if options == null { throw "DnsResolver: null options" }
        Result<DnsResolverHandle, Error> raw = dnsResolverCreateRaw(options)
        if raw.isErr() {
            throw "DnsResolver: create failed: " + raw.error().describe()
        }
        _handle = raw.value()
        _options = options.copy()
        _open = true
    }

    Result<List<DnsRecord>, Error> resolve(Context context, String host) {
        if context == null { throw "DnsResolver.resolve: null context" }
        if host == null || host == "" { throw "DnsResolver.resolve: empty host" }
        if !_open { return Err(unavailableError("dns resolver")) }
        return dnsResolverResolveRaw(_handle, context, host)
    }

    Result<DnsRecord, Error> resolveOne(Context context, String host, IpFamily family) {
        Result<List<DnsRecord>, Error> resolved = self.resolve(context, host)
        if resolved.isErr() { return Err(resolved.error()) }
        List<DnsRecord> records = resolved.value()
        Int index = 0
        while index < records.length() {
            DnsRecord record = records.get(index)
            if family == IpFamily.Unspecified || record.address().family() == family {
                return Ok(record)
            }
            index = index + 1
        }
        return Err(new BasicError(ErrorKind.NotFound, "no matching record: " + host))
    }

    Result<String, Error> reverse(Context context, IpAddress address) {
        if context == null { throw "DnsResolver.reverse: null context" }
        if address == null { throw "DnsResolver.reverse: null address" }
        if !_open { return Err(unavailableError("dns resolver")) }
        return dnsResolverReverseRaw(_handle, context, address)
    }

    void clearCache() {
        if _open { dnsResolverClearRaw(_handle) }
    }

    DnsCacheStats cacheStats() {
        if !_open { throw "DnsResolver.cacheStats: closed" }
        return dnsResolverStatsRaw(_handle)
    }

    DnsResolverOptions options() { return _options.copy() }
    Bool isOpen() { return _open }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        return dnsResolverCloseRaw(_handle)
    }
}
```

> `DnsResolverHandle`、`dnsResolver*Raw` 是运行时 DNS resolver 原语；不是 XDK 公共类型。
