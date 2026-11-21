# `RateLimitPolicy`

| 项 | 值 |
| --- | --- |
| 类型 | `class RateLimitPolicy` |
| 包 | `xdk.api` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`ApiContext`、`ApiRoute`、`Mutex`、`HttpHeaders`、`Error` |

---

## 1. 定位

单实例固定窗口限流策略：按主体/头/远端地址计数，写入 `RateLimit-*` 响应头，超限返回 `Busy` 并附 `Retry-After`。

不做：分布式限流、滑动窗口、令牌桶、漏桶、并发限流、配额计费、跨进程共享。

---

## 2. 设计逻辑

- 构造参数：每窗口请求数 `limit` 与窗口毫秒 `windowMillis`；都 >0。
- 键默认包含路由模式（`includeRoute=true`）+ 主体：
  - 已认证：principal；
  - 配置 `keyHeader`：该请求头的值；缺失时回退 principal/远端地址；
  - 否则远端地址。
- 固定窗口：窗口起点 + 计数；窗口过期后重置。
- 每次 `acquire` 都写 `RateLimit-Limit`/`RateLimit-Remaining`/`RateLimit-Reset`。
- 超限：`RateLimit-Remaining: 0`、`Retry-After`，返回 `Err(Busy)`。
- 键数量有上限；超过上限先清理过期窗口，仍超限时新键落入 `overflow` 桶，避免内存被任意头值撑爆。
- 状态用 `Mutex<Bool>` 保护；`acquire` 临界区短，不做 I/O。
- `copy` 只复制配置，不复制计数；`reset` 清空计数。
- 无 close；可作为全局策略共享，也可按路由覆盖。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_limit` | `Int` | 每窗口上限，>0 |
| `_windowMillis` | `Long` | 窗口毫秒，>0 |
| `_includeRoute` | `Bool` | 键是否含路由 |
| `_keyHeader` | `String?` | 可选键头 |
| `_maximumKeys` | `Int` | 键上限，>0 |
| `_counts` | `Map<String,Int>` | 当前窗口计数 |
| `_windowStarts` | `Map<String,Long>` | 窗口起点（单调毫秒） |
| `_mutex` | `Mutex<Bool>` | 状态锁 |

不变量：`_counts`/`_windowStarts` 键一致；计数 ≥0；键数 ≤ `_maximumKeys` + 1（overflow）；窗口起点 ≤ now。

---

## 4. 生命周期

构造；`acquire` 持续更新；`reset` 清空；无 close；可跨任务共享；策略状态不是持久化数据。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `RateLimitPolicy(Int limit, Long windowMillis)` | limit/windowMillis | >0 | ≤0 → panic |

---

## 6. 字段表

见 §3；字段私有。`_mutex` 保护两个 Map；`_keyHeader` 为空表示不使用头键。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `limit` | 窗口上限 | 无 | `Int` | 无 |
| `windowMillis` | 窗口毫秒 | 无 | `Long` | 无 |
| `includeRoute` | 设置路由作用域 | `Bool value` | `RateLimitPolicy` | 无 |
| `includeRoute` | 是否含路由 | 无 | `Bool` | 无 |
| `keyHeader` | 设置键头 | `String name` | `RateLimitPolicy` | 空/换行 → panic |
| `withoutKeyHeader` | 清除键头 | 无 | `RateLimitPolicy` | 无 |
| `keyHeader` | 读取键头 | 无 | `String?` | 无 |
| `maximumKeys` | 设置键上限 | `Int value` | `RateLimitPolicy` | ≤0 → panic |
| `maximumKeys` | 读取键上限 | 无 | `Int` | 无 |
| `acquire` | 获取配额 | `Context context, ApiContext exchange` | `Result<Unit, Error>` | `Busy`/`Cancelled` |
| `reset` | 清空计数 | `Context context` | `Result<Unit, Error>` | `Cancelled` |
| `copy` | 复制配置/空状态 | 无 | `RateLimitPolicy` | 无 |

说明：

- `acquire` 无 I/O；`Context` 只用于锁等待取消。
- `acquire` 由 `ApiServer` 按全局/路由策略调用；业务代码不要重复调用，否则重复计数。
- 成功/失败都写标准头；失败额外写 `Retry-After`。
- `RateLimit-Reset` 是相对秒数；`Retry-After` 与其一致。
- `reset` 不清除配置，只清空计数/窗口起点。
- `copy` 新实例计数为空；配置相同。
- 同一个策略实例被多个路由共享时，`includeRoute` 决定是否按路由分开计数。

---

## 8. 使用的技术

- 固定窗口计数器；
- 单调时钟；
- 键规范化；
- 有界 Map + overflow 桶；
- Mutex 临界区；
- IETF RateLimit 头字段。

---

## 9. 需要的支撑

- 语言：class、Map、String、Int、Long、Bool、Result；
- 运行时：`nowMono`、`Mutex<Bool>`；
- 接口：`Context`、`ApiContext`、`ApiRoute`、`HttpHeaders`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Context`、`ApiContext`、`ApiRoute`、`Mutex`、`HttpHeaders`、`Error`、`BasicError`、`ErrorKind`、`nowMono`。

---

## 11. 所有权与并发

引用语义；线程安全；`acquire`/`reset` 可并发；临界区短；`copy` 不复制状态；无资源；无 close。

---

## 12. 示例与反例

正确：

```text
RateLimitPolicy policy = new RateLimitPolicy(100, 60000)
    .includeRoute(true)
    .keyHeader("X-Api-Key")
ApiOptions options = new ApiOptions().rateLimitPolicy(policy)
```

反例：

- 用 `X-Forwarded-For` 作为键但代理未清洗；
- 期望多进程共享计数；
- 期望滑动窗口平滑边界；
- 用 API key 明文作为日志键；
- 键头任意值导致 Map 无限增长；
- 忽略 overflow 桶的共享耗尽风险；
- 超限不返回 `Retry-After`。

---

## 13. 测试/场景义务

窗口内/跨窗口；limit=1；并发 acquire；includeRoute 开/关；principal/header/remote 键；头缺失回退；overflow 桶；过期清理；maximumKeys；reset；copy 空状态；Cancelled；响应头数值/秒数；429 映射。

---

## 14. XNull 伪代码

> 非可执行设计伪代码。

```xnull
class RateLimitPolicy {
    final Int _limit
    final Long _windowMillis
    Bool _includeRoute = true
    String? _keyHeader = null
    Int _maximumKeys = 65536
    Map<String, Int> _counts = [:]
    Map<String, Long> _windowStarts = [:]
    final Mutex<Bool> _mutex

    RateLimitPolicy(Int limit, Long windowMillis) {
        if limit <= 0 || windowMillis <= 0 {
            throw "RateLimitPolicy: invalid limit or window"
        }
        _limit = limit
        _windowMillis = windowMillis
        _mutex = new Mutex<Bool>(false)
    }

    Int limit() { return _limit }
    Long windowMillis() { return _windowMillis }

    RateLimitPolicy includeRoute(Bool value) {
        _includeRoute = value
        return self
    }

    Bool includeRoute() { return _includeRoute }

    RateLimitPolicy keyHeader(String name) {
        if name == null || name == "" {
            throw "RateLimitPolicy.keyHeader: empty"
        }
        if name.indexOf("\n") >= 0 || name.indexOf("\r") >= 0 {
            throw "RateLimitPolicy.keyHeader: multiline"
        }
        _keyHeader = name
        return self
    }

    RateLimitPolicy withoutKeyHeader() {
        _keyHeader = null
        return self
    }

    String? keyHeader() { return _keyHeader }

    RateLimitPolicy maximumKeys(Int value) {
        if value <= 0 { throw "RateLimitPolicy.maximumKeys: invalid" }
        _maximumKeys = value
        return self
    }

    Int maximumKeys() { return _maximumKeys }

    Result<Unit, Error> acquire(Context context, ApiContext exchange) {
        if context == null || exchange == null {
            throw "RateLimitPolicy.acquire: null argument"
        }
        Bool allowed = false
        Int remaining = 0
        Long resetSeconds = 0
        String selectedKey = ""
        Result<Unit, Error> locked = _mutex.withLock(context, (Bool guard) -> {
            Long now = nowMono()
            if _counts.length() >= _maximumKeys {
                self.prune(now)
            }
            selectedKey = self.keyFor(exchange, now)
            Long start = _windowStarts.getOr(selectedKey, now)
            Int count = _counts.getOr(selectedKey, 0)
            if now - start >= _windowMillis {
                start = now
                count = 0
            }
            count = count + 1
            _windowStarts.put(selectedKey, start)
            _counts.put(selectedKey, count)
            Long resetMillis = start + _windowMillis - now
            if resetMillis < 0 { resetMillis = 0 }
            resetSeconds = (resetMillis + 999) / 1000
            remaining = _limit - count
            if remaining < 0 { remaining = 0 }
            allowed = count <= _limit
        })
        if locked.isErr() { return Err(locked.error()) }
        exchange.setHeader("RateLimit-Limit", str(_limit))
        exchange.setHeader("RateLimit-Remaining", str(remaining))
        exchange.setHeader("RateLimit-Reset", str(resetSeconds))
        if !allowed {
            exchange.setHeader("Retry-After", str(resetSeconds))
            return Err(new BasicError(ErrorKind.Busy, "rate limit exceeded"))
        }
        return Ok(unit)
    }

    private String keyFor(ApiContext exchange, Long now) {
        String routePart = "global"
        if _includeRoute && exchange.route() != null {
            routePart = (exchange.route() as ApiRoute).pattern()
        }
        String subject = ""
        if _keyHeader != null {
            String? headerValue = exchange.header(_keyHeader as String)
            if headerValue != null && headerValue != "" {
                subject = "header:" + headerValue
            }
        }
        if subject == "" && exchange.isAuthenticated() {
            subject = "principal:" + (exchange.principalName() as String)
        }
        if subject == "" {
            subject = "remote:" + exchange.remoteAddress().text()
        }
        if subject == "" { subject = "anonymous" }
        String key = routePart + "|" + subject
        if !_counts.has(key) && _counts.length() >= _maximumKeys {
            key = "overflow"
        }
        return key
    }

    private void prune(Long now) {
        List<String> names = _counts.keys()
        Int index = 0
        while index < names.length() {
            String name = names.get(index)
            Long start = _windowStarts.getOr(name, now)
            if now - start >= _windowMillis {
                _counts.remove(name)
                _windowStarts.remove(name)
            }
            index = index + 1
        }
    }

    Result<Unit, Error> reset(Context context) {
        if context == null { throw "RateLimitPolicy.reset: null context" }
        return _mutex.withLock(context, (Bool guard) -> {
            _counts.clear()
            _windowStarts.clear()
        })
    }

    RateLimitPolicy copy() {
        RateLimitPolicy result = new RateLimitPolicy(_limit, _windowMillis)
            .includeRoute(_includeRoute)
            .maximumKeys(_maximumKeys)
        if _keyHeader != null {
            result.keyHeader(_keyHeader as String)
        }
        return result
    }
}
```
