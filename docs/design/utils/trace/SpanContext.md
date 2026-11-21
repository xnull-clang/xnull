# `SpanContext`

| 项 | 值 |
| --- | --- |
| 类型 | `class SpanContext` |
| 包 | `xdk.trace` |
| 稳定性 | `preview` |
| 依赖 | `Map`、`List`、`Char` |

---

## 1. 定位

不可变的 trace 身份快照：traceId、spanId、可选父 spanId、采样标志、baggage。

不做：ID 生成、采样决策、传播编码、span 生命周期、baggage 修改。

---

## 2. 设计逻辑

- `traceId` 是 32 位小写十六进制；`spanId` 与 `parentSpanId` 是 16 位小写十六进制。
- traceId/spanId 不能全零；`parentSpanId` 不能等于 `spanId`。
- `sampled` 只表示当前 span 是否应记录；不表示父 span 是否存在。
- baggage 是 `Map<String,String>` 的防御性副本；键大小写敏感，值原样保留。
- 构造器只做 null 检查、大小写归一和 baggage 复制；完整格式校验由 `isValid()` 承担。
- `isValid()` 是有效性权威；`Tracer` 拒绝无效父上下文，`Propagator.extract` 对无效输入返回 null。
- `copy()` 返回独立实例和独立 baggage 副本；不可变对象仍提供 copy 以便边界清晰。
- 值语义；无 close；无资源。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_traceId` | `String` | 32 位小写十六进制 |
| `_spanId` | `String` | 16 位小写十六进制 |
| `_parentSpanId` | `String?` | 根为 null；非根为 16 位十六进制 |
| `_sampled` | `Bool` | 是否采样 |
| `_baggage` | `Map<String,String>` | 不可变快照 |

不变量：traceId/spanId 非 null；parentSpanId 为 null 或非空；baggage 非 null；`isValid()` 为 true 时满足 §2 的格式与上限；baggage 最多 64 项，键 1..256 字符，值 0..1024 字符。

---

## 4. 生命周期

构造后不可变；无 close；GC 管理；可跨任务共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `SpanContext(String traceId, String spanId, String? parentSpanId, Bool sampled, Map<String,String> baggage)` | 全部 | traceId/spanId/baggage 非 null | null → panic；格式非法不 panic，`isValid()` 返回 false |

构造主要供 `Tracer`、`Propagator` 实现和测试使用；业务代码不应直接拼 ID。

---

## 6. 字段表

见 §3；字段私有且 `final`。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `traceId` | 读取 traceId | 无 | `String` | 无 |
| `spanId` | 读取 spanId | 无 | `String` | 无 |
| `parentSpanId` | 读取父 spanId | 无 | `String?` | 无 |
| `sampled` | 读取采样标志 | 无 | `Bool` | 无 |
| `baggage` | baggage 副本 | 无 | `Map<String,String>` | 无 |
| `isRoot` | 是否根上下文 | 无 | `Bool` | 无 |
| `isValid` | W3C 格式/上限校验 | 无 | `Bool` | 无 |
| `copy` | 独立副本 | 无 | `SpanContext` | 无 |

说明：

- `baggage()` 每次返回新 Map；修改返回值不影响本对象。
- `copy()` 复制 baggage；调用的结果与本对象内容相同但引用独立。
- `isValid()` 不抛异常；对任意字段组合都返回 Bool。
- `isValid()` 校验：traceId 32 位十六进制且非全零；spanId 16 位且非全零；parentSpanId 为 null 或 16 位、非全零、不等于 spanId；baggage 项数与键值长度在上限内。
- 不提供 `with*`/`setBaggage`；需要新 baggage 时构造新上下文。

---

## 8. 使用的技术

- W3C trace context 标识格式；
- 十六进制校验；
- 不可变值对象；
- 防御性复制；
- 有界 baggage。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Char、Map、List、可空引用；
- 运行时：无；
- 接口：无。

---

## 10. 依赖的特性/接口/类

`Map`、`List`、`Char`。

---

## 11. 所有权与并发

不可变；线程安全；可跨任务共享；baggage 在构造时复制，读取时再复制；无资源。

---

## 12. 示例与反例

正确：

```text
traceId = "4bf92f3577b34da6a3ce929d0e0e4736"
spanId  = "00f067aa0ba902b7"
SpanContext context = new SpanContext(traceId, spanId, null, true, [:])
context.isValid() == true
```

反例：parentSpanId 等于 spanId；traceId 含 `g`；baggage 超过 64 项；构造后修改传入 Map 期望上下文变化；把 `sampled=false` 当无效上下文。

---

## 13. 测试/场景义务

合法根/子上下文；traceId/spanId 长度；非十六进制；全零；parent 等于 span；parent 非法；大小写归一；baggage 复制；baggage 项数/键值长度边界；`copy` 独立性；`isRoot`；`isValid` 不抛异常。

---

## 14. XNull 伪代码

```xnull
class SpanContext {
    final String _traceId
    final String _spanId
    final String? _parentSpanId
    final Bool _sampled
    final Map<String, String> _baggage

    SpanContext(String traceId, String spanId, String? parentSpanId, Bool sampled,
                Map<String, String> baggage) {
        if traceId == null || spanId == null || baggage == null {
            throw "SpanContext: null argument"
        }
        _traceId = traceId.toLower()
        _spanId = spanId.toLower()
        if parentSpanId == null {
            _parentSpanId = null
        } else {
            String parent = parentSpanId as String
            _parentSpanId = parent.toLower()
        }
        _sampled = sampled
        _baggage = baggage.copy()
    }

    String traceId() { return _traceId }
    String spanId() { return _spanId }
    String? parentSpanId() { return _parentSpanId }
    Bool sampled() { return _sampled }
    Map<String, String> baggage() { return _baggage.copy() }
    Bool isRoot() { return _parentSpanId == null }

    Bool isValid() {
        if !SpanContext.isValidTraceId(_traceId) { return false }
        if !SpanContext.isValidSpanId(_spanId) { return false }
        if !SpanContext.isValidParent(_parentSpanId, _spanId) { return false }
        return SpanContext.isValidBaggage(_baggage)
    }

    SpanContext copy() {
        return new SpanContext(_traceId, _spanId, _parentSpanId, _sampled, _baggage)
    }

    private static Bool isValidTraceId(String value) {
        if value.length() != 32 { return false }
        if !SpanContext.isHex(value) { return false }
        return !SpanContext.isZero(value)
    }

    private static Bool isValidSpanId(String value) {
        if value.length() != 16 { return false }
        if !SpanContext.isHex(value) { return false }
        return !SpanContext.isZero(value)
    }

    private static Bool isValidParent(String? value, String spanId) {
        if value == null { return true }
        String parent = value as String
        if parent.length() != 16 { return false }
        if parent == spanId { return false }
        if !SpanContext.isHex(parent) { return false }
        return !SpanContext.isZero(parent)
    }

    private static Bool isValidBaggage(Map<String, String> baggage) {
        if baggage.length() > 64 { return false }
        List<String> keys = baggage.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            if key == null || key.length() == 0 || key.length() > 256 {
                return false
            }
            String value = baggage.get(key)
            if value == null || value.length() > 1024 {
                return false
            }
            index = index + 1
        }
        return true
    }

    private static Bool isHex(String value) {
        Int index = 0
        while index < value.length() {
            Char character = value.charAt(index)
            Bool digit = character >= '0' && character <= '9'
            Bool lower = character >= 'a' && character <= 'f'
            Bool upper = character >= 'A' && character <= 'F'
            if !digit && !lower && !upper { return false }
            index = index + 1
        }
        return true
    }

    private static Bool isZero(String value) {
        Int index = 0
        while index < value.length() {
            if value.charAt(index) != '0' { return false }
            index = index + 1
        }
        return true
    }
}
```
