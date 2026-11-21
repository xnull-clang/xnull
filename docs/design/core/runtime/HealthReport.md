# `HealthReport`

| 项 | 值 |
| --- | --- |
| 类型 | `class HealthReport` |
| 包 | `xdk.runtime` |
| 稳定性 | `preview` |
| 依赖 | `HealthState` |

---

## 1. 定位

单项/聚合健康快照：状态、消息、单调时间戳、键值细节。

不做：错误链、日志、HTTP 序列化、指标、告警。

---

## 2. 设计逻辑

- 不可变快照；`with*` 返回新对象。
- `timestampMono` 使用单调毫秒，避免墙钟回拨影响排序/超时。
- `details` 是 `String -> String` 快照；键非空、不含换行/制表。
- `message` 单行；空串允许；不承载错误分类。
- `isHealthy` 只对 `Healthy` 为 true；`isReady` 对 `Healthy/Degraded` 为 true。
- 无 close；可跨任务只读共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_state` | `HealthState` | final | 非 null |
| `_message` | `String` | final | 单行；可为空 |
| `_timestampMono` | `Long` | final | ≥0 |
| `_details` | `Map<String,String>` | final | 键值快照 |

不变量：state 非 null；timestamp ≥0；message 单行；details 键合法；不可变。

---

## 4. 生命周期

构造后不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `HealthReport(HealthState state, String message, Long timestampMono, Map<String,String> details)` | 全部 | state 非 null；timestamp ≥0；message/details 非 null | null/负值 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `of` | 当前时间快照 | `HealthState state, String message` | `HealthReport` | null → panic |
| `healthy` | 健康快照 | `String message` | `HealthReport` | null → panic |
| `degraded` | 降级快照 | `String message` | `HealthReport` | null → panic |
| `unhealthy` | 不健康快照 | `String message` | `HealthReport` | null → panic |
| `state` | 状态 | 无 | `HealthState` | 无 |
| `message` | 消息 | 无 | `String` | 无 |
| `timestampMono` | 时间戳 | 无 | `Long` | 无 |
| `details` | 细节快照 | 无 | `Map<String,String>` | 无 |
| `detailOr` | 细节/兜底 | `String key, String fallback` | `String` | null → panic |
| `hasDetail` | 是否有细节 | `String key` | `Bool` | null → panic |
| `detailCount` | 细节数 | 无 | `Int` | 无 |
| `withMessage` | 派生消息 | `String value` | `HealthReport` | null → panic |
| `withDetail` | 派生细节 | `String key, String value` | `HealthReport` | 非法 → panic |
| `isHealthy` | 是否健康 | 无 | `Bool` | 无 |
| `isReady` | 是否可服务 | 无 | `Bool` | 无 |
| `isTerminal` | 是否终态 | 无 | `Bool` | 无 |
| `describe` | 单行文本 | 无 | `String` | 无 |
| `copy` | 复制 | 无 | `HealthReport` | 无 |

---

## 8. 使用的技术

- 不可变快照；
- 单调时间戳；
- 键值细节校验；
- 字符串拼接。

---

## 9. 需要的支撑

- 语言：class、final 字段、Map、String、Long、Int、Bool；
- 运行时：`nowMono`；
- 接口：`HealthState`、`healthStateIsHealthy`、`healthStateIsReady`、`healthStateIsTerminal`。

---

## 10. 依赖的特性/接口/类

`HealthState`、`nowMono`、`healthStateName`、`healthStateIsHealthy`、`healthStateIsReady`、
`healthStateIsTerminal`。

---

## 11. 所有权与并发

不可变；可跨任务共享；`details` 返回副本；无资源；无取消点。
相等：引用身份；值比较请比较 state/message/details；不推荐作为 `Map` 键。

---

## 12. 示例与反例

正确：`HealthReport.unhealthy("db down").withDetail("db", "primary")`。  
反例：用 wall clock 当时间戳；details 键含换行；把 `Degraded` 当不健康；修改 `details()`
期望改快照。

---

## 13. 测试/场景义务

构造校验；每个状态；withMessage/withDetail；details 快照；isHealthy/isReady/isTerminal；
describe；时间戳；空 details；非法键。

---

## 14. XNull 伪代码

```xnull
class HealthReport {
    final HealthState _state
    final String _message
    final Long _timestampMono
    final Map<String, String> _details

    HealthReport(HealthState state, String message, Long timestampMono,
                 Map<String, String> details) {
        if state == null { throw "HealthReport: null state" }
        if message == null { throw "HealthReport: null message" }
        if timestampMono < 0 { throw "HealthReport: negative timestamp" }
        if details == null { throw "HealthReport: null details" }
        _state = state
        _message = message
        _timestampMono = timestampMono
        _details = [:]
        List<String> keys = details.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            if key == "" || key.indexOf("\n") >= 0 || key.indexOf("\t") >= 0 {
                throw "HealthReport: invalid detail key"
            }
            String value = details.getOr(key, "")
            if value.indexOf("\n") >= 0 || value.indexOf("\t") >= 0 {
                throw "HealthReport: invalid detail value"
            }
            _details.put(key, value)
            index = index + 1
        }
    }

    static HealthReport of(HealthState state, String message) {
        return new HealthReport(state, message, nowMono(), [:])
    }

    static HealthReport healthy(String message) {
        return HealthReport.of(HealthState.Healthy, message)
    }

    static HealthReport degraded(String message) {
        return HealthReport.of(HealthState.Degraded, message)
    }

    static HealthReport unhealthy(String message) {
        return HealthReport.of(HealthState.Unhealthy, message)
    }

    HealthState state() { return _state }
    String message() { return _message }
    Long timestampMono() { return _timestampMono }
    Int detailCount() { return _details.length() }

    Map<String, String> details() {
        Map<String, String> result = [:]
        List<String> keys = _details.keys()
        Int index = 0
        while index < keys.length() {
            result.put(keys.get(index), _details.getOr(keys.get(index), ""))
            index = index + 1
        }
        return result
    }

    String detailOr(String key, String fallback) {
        if key == null { throw "HealthReport.detailOr: null key" }
        return _details.getOr(key, fallback)
    }

    Bool hasDetail(String key) {
        if key == null { throw "HealthReport.hasDetail: null key" }
        return _details.has(key)
    }

    HealthReport withMessage(String value) {
        if value == null { throw "HealthReport.withMessage: null" }
        return new HealthReport(_state, value, _timestampMono, _details)
    }

    HealthReport withDetail(String key, String value) {
        if key == null || key == "" { throw "HealthReport.withDetail: invalid key" }
        if value == null { throw "HealthReport.withDetail: null value" }
        Map<String, String> next = self.details()
        next.put(key, value)
        return new HealthReport(_state, _message, _timestampMono, next)
    }

    Bool isHealthy() { return healthStateIsHealthy(_state) }
    Bool isReady() { return healthStateIsReady(_state) }
    Bool isTerminal() { return healthStateIsTerminal(_state) }

    String describe() {
        return healthStateName(_state) + ": " + _message
            + " details=" + str(_details.length())
    }

    HealthReport copy() {
        return new HealthReport(_state, _message, _timestampMono, _details)
    }
}
```
