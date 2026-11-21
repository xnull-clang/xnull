# `DnsResolverOptions`

| 项 | 值 |
| --- | --- |
| 类型 | `class DnsResolverOptions` |
| 包 | `xdk.net` |
| 稳定性 | `preview` |
| 依赖 | `IpAddress`、`IpFamily` |

---

## 1. 定位

显式 DNS resolver 配置：服务器、超时、缓存上限、正/负 TTL、地址族、搜索域、递归、EDNS。

不做：DoH/DoT、DNSSEC、系统 resolver 配置写回、全局缓存。

---

## 2. 设计逻辑

- 可变构建期；`DnsResolver` 构造时复制快照。
- 默认：空 servers（系统 DNS）、5000ms 超时、1024 缓存、正 TTL 300s、负 TTL 30s、任意族、递归开启、EDNS 关闭。
- 服务器空列表表示系统默认；搜索域空表示不追加。
- 非法负数/零缓存 → panic。
- 无 close；非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_servers` | `List<IpAddress>` | 自定义 DNS；空=系统 |
| `_timeoutMillis` | `Long` | 单次查询超时 |
| `_maxCacheEntries` | `Int` | 缓存上限 |
| `_positiveTtlSeconds` | `Long` | 正缓存上限 |
| `_negativeTtlSeconds` | `Long` | 负缓存 TTL |
| `_family` | `IpFamily` | 默认族偏好 |
| `_searchDomains` | `List<String>` | 搜索域 |
| `_recursionDesired` | `Bool` | RD |
| `_edns` | `Bool` | EDNS |

不变量：timeout >0；maxCache >0；TTL ≥0；列表非 null。

---

## 4. 生命周期

构造后可变；DnsResolver 快照；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `DnsResolverOptions()` | 无 | 默认配置 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `servers` | 设置服务器 | `List<IpAddress> values` | `DnsResolverOptions` | null → panic |
| `timeoutMillis` | 设置超时 | `Long value` | `DnsResolverOptions` | ≤0 → panic |
| `maxCacheEntries` | 缓存上限 | `Int value` | `DnsResolverOptions` | ≤0 → panic |
| `positiveTtlSeconds` | 正 TTL | `Long value` | `DnsResolverOptions` | <0 → panic |
| `negativeTtlSeconds` | 负 TTL | `Long value` | `DnsResolverOptions` | <0 → panic |
| `family` | 族偏好 | `IpFamily value` | `DnsResolverOptions` | 无 |
| `searchDomains` | 搜索域 | `List<String> values` | `DnsResolverOptions` | null/空串 → panic |
| `recursionDesired` | RD | `Bool value` | `DnsResolverOptions` | 无 |
| `edns` | EDNS | `Bool value` | `DnsResolverOptions` | 无 |
| `getServers` | 服务器快照 | 无 | `List<IpAddress>` | 无 |
| `getTimeoutMillis` | 超时 | 无 | `Long` | 无 |
| `getMaxCacheEntries` | 缓存上限 | 无 | `Int` | 无 |
| `getPositiveTtlSeconds` | 正 TTL | 无 | `Long` | 无 |
| `getNegativeTtlSeconds` | 负 TTL | 无 | `Long` | 无 |
| `getFamily` | 族 | 无 | `IpFamily` | 无 |
| `getSearchDomains` | 搜索域快照 | 无 | `List<String>` | 无 |
| `isRecursionDesired` | RD | 无 | `Bool` | 无 |
| `isEdns` | EDNS | 无 | `Bool` | 无 |
| `copy` | 独立快照 | 无 | `DnsResolverOptions` | 无 |

---

## 8. 使用的技术

- builder；
- 列表快照；
- 缓存/超时参数。

---

## 9. 需要的支撑

- 语言：class、List、String、Long、Int、Bool；
- 运行时：无；
- 接口：`IpAddress`、`IpFamily`。

---

## 10. 依赖的特性/接口/类

`IpAddress`、`IpFamily`。

---

## 11. 所有权与并发

可变；非线程安全；`DnsResolver` 复制；无资源。

---

## 12. 示例与反例

正确：`new DnsResolverOptions().timeoutMillis(1000).family(IpFamily.Ipv4)`。  
反例：负超时；0 缓存；空搜索域；修改 options 期望已有 resolver 变化。

---

## 13. 测试/场景义务

默认值；每个 setter；非法值；列表复制；copy 独立；解析器快照。

---

## 14. XNull 伪代码

```xnull
class DnsResolverOptions {
    List<IpAddress> _servers = []
    Long _timeoutMillis = 5000
    Int _maxCacheEntries = 1024
    Long _positiveTtlSeconds = 300
    Long _negativeTtlSeconds = 30
    IpFamily _family = IpFamily.Unspecified
    List<String> _searchDomains = []
    Bool _recursionDesired = true
    Bool _edns = false

    DnsResolverOptions() {
    }

    DnsResolverOptions servers(List<IpAddress> values) {
        if values == null { throw "DnsResolverOptions.servers: null" }
        _servers = values.copy()
        return self
    }

    DnsResolverOptions timeoutMillis(Long value) {
        if value <= 0 { throw "DnsResolverOptions.timeoutMillis: invalid" }
        _timeoutMillis = value
        return self
    }

    DnsResolverOptions maxCacheEntries(Int value) {
        if value <= 0 { throw "DnsResolverOptions.maxCacheEntries: invalid" }
        _maxCacheEntries = value
        return self
    }

    DnsResolverOptions positiveTtlSeconds(Long value) {
        if value < 0 { throw "DnsResolverOptions.positiveTtlSeconds: negative" }
        _positiveTtlSeconds = value
        return self
    }

    DnsResolverOptions negativeTtlSeconds(Long value) {
        if value < 0 { throw "DnsResolverOptions.negativeTtlSeconds: negative" }
        _negativeTtlSeconds = value
        return self
    }

    DnsResolverOptions family(IpFamily value) {
        _family = value
        return self
    }

    DnsResolverOptions searchDomains(List<String> values) {
        if values == null { throw "DnsResolverOptions.searchDomains: null" }
        Int index = 0
        while index < values.length() {
            if values.get(index) == null || values.get(index) == "" {
                throw "DnsResolverOptions.searchDomains: empty"
            }
            index = index + 1
        }
        _searchDomains = values.copy()
        return self
    }

    DnsResolverOptions recursionDesired(Bool value) {
        _recursionDesired = value
        return self
    }

    DnsResolverOptions edns(Bool value) {
        _edns = value
        return self
    }

    List<IpAddress> getServers() { return _servers.copy() }
    Long getTimeoutMillis() { return _timeoutMillis }
    Int getMaxCacheEntries() { return _maxCacheEntries }
    Long getPositiveTtlSeconds() { return _positiveTtlSeconds }
    Long getNegativeTtlSeconds() { return _negativeTtlSeconds }
    IpFamily getFamily() { return _family }
    List<String> getSearchDomains() { return _searchDomains.copy() }
    Bool isRecursionDesired() { return _recursionDesired }
    Bool isEdns() { return _edns }

    DnsResolverOptions copy() {
        DnsResolverOptions result = new DnsResolverOptions()
        result.servers(_servers)
        result.timeoutMillis(_timeoutMillis)
        result.maxCacheEntries(_maxCacheEntries)
        result.positiveTtlSeconds(_positiveTtlSeconds)
        result.negativeTtlSeconds(_negativeTtlSeconds)
        result.family(_family)
        result.searchDomains(_searchDomains)
        result.recursionDesired(_recursionDesired)
        result.edns(_edns)
        return result
    }
}
```
