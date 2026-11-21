# `Sampler`

| 项 | 值 |
| --- | --- |
| 类型 | `class Sampler` |
| 包 | `xdk.trace` |
| 稳定性 | `preview` |
| 依赖 | `SpanContext`、`isNaN`、`str` |

---

## 1. 定位

采样决策器：alwaysOn、alwaysOff、按比例采样。

不做：按属性采样、按错误/延迟采样、tail sampling、动态调整、全局随机状态。

---

## 2. 设计逻辑

- 三种模式：全采样、全不采样、比例采样。
- `ratio(value)` 接受 `[0,1]` 闭区间；0 等价 alwaysOff，1 等价 alwaysOn；NaN/越界 panic。
- `shouldSample` 只看 `SpanContext.traceId`，不看 span 名、属性、时间。
- 比例采样使用 traceId 的稳定哈希：同一 traceId 在所有进程得到相同决策，避免客户端采样、服务端不采样。
- 无效上下文返回 false，不抛异常；null 上下文 panic。
- 实例不可变；无随机状态；线程安全；无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_mode` | `Int` | 0=alwaysOn，1=alwaysOff，2=ratio |
| `_ratio` | `Double` | 仅在 mode=2 时有效；0..1 |

不变量：`_mode` 只取 0/1/2；mode=2 时 `_ratio` 在 `[0,1]`；对象构造后不变。

---

## 4. 生命周期

不可变值语义对象；无 close；无资源；可跨任务共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Sampler(Int mode, Double ratio)` | mode/ratio | 私有；mode 0/1/2 | 外部构造 → 编译错误 |
| `Sampler.alwaysOn()` | 无 | 无 | 无 |
| `Sampler.alwaysOff()` | 无 | 无 | 无 |
| `Sampler.ratio(Double value)` | value | 0..1，非 NaN | 越界/NaN → panic |

---

## 6. 字段表

见 §3；字段私有且 `final`。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `alwaysOn` | 全采样 | 无 | `Sampler` | 无 |
| `alwaysOff` | 全不采样 | 无 | `Sampler` | 无 |
| `ratio` | 比例采样 | `Double` | `Sampler` | 越界/NaN → panic |
| `shouldSample` | 采样决策 | `SpanContext` | `Bool` | null → panic；无效上下文 → false |
| `describe` | 诊断文本 | 无 | `String` | 无 |

说明：

- `alwaysOn().shouldSample(ctx)` 对有效上下文恒 true。
- `alwaysOff().shouldSample(ctx)` 对有效上下文恒 false。
- `ratio(0.0)`/`ratio(1.0)` 有快速路径；其他值走稳定哈希。
- `describe()` 返回 `always_on`、`always_off` 或 `ratio(<value>)`，用于诊断，不用于机器解析。

---

## 8. 使用的技术

- 确定性哈希采样；
- FNV-1a 64 位哈希（按 64 位回绕）；
- 单调映射到 `[0,1)`；
- 不可变策略对象。

---

## 9. 需要的支撑

- 语言：class、Int、Long、Double、Bool、String、`isNaN`、`str`；
- 运行时：无（不依赖随机数生成器）；
- 接口：`SpanContext`。

---

## 10. 依赖的特性/接口/类

`SpanContext`、`isNaN`、`str`。

---

## 11. 所有权与并发

不可变；线程安全；可跨任务共享；无资源；无全局状态。

---

## 12. 示例与反例

正确：`Sampler sampler = Sampler.ratio(0.25)`；同一 traceId 重复调用结果一致。  
反例：`Sampler.ratio(-0.1)`；`Sampler.ratio(1.5)`；`Sampler.ratio(NaN)`；用 `Random` 每次重新掷骰子；对无效上下文抛异常导致停机路径失败。

---

## 13. 测试/场景义务

三种模式；ratio 0/1/边界；NaN/越界；同一 traceId 确定性；不同 traceId 分布近似；无效上下文 false；`describe`；线程安全；与 `TraceOptions` 组合。

---

## 14. XNull 伪代码

```xnull
class Sampler {
    final Int _mode
    final Double _ratio

    private Sampler(Int mode, Double ratio) {
        _mode = mode
        _ratio = ratio
    }

    static Sampler alwaysOn() {
        return new Sampler(0, 1.0)
    }

    static Sampler alwaysOff() {
        return new Sampler(1, 0.0)
    }

    static Sampler ratio(Double value) {
        if isNaN(value) || value < 0.0 || value > 1.0 {
            throw "Sampler.ratio: value outside [0,1]"
        }
        return new Sampler(2, value)
    }

    Bool shouldSample(SpanContext context) {
        if context == null { throw "Sampler.shouldSample: null context" }
        if !context.isValid() { return false }
        if _mode == 0 { return true }
        if _mode == 1 { return false }
        if _ratio <= 0.0 { return false }
        if _ratio >= 1.0 { return true }
        return Sampler.sampleUnit(context.traceId()) < _ratio
    }

    String describe() {
        if _mode == 0 { return "always_on" }
        if _mode == 1 { return "always_off" }
        return "ratio(" + str(_ratio) + ")"
    }

    private static Double sampleUnit(String traceId) {
        Long hash = 1469598103934665603 as Long
        Int index = 0
        while index < traceId.length() {
            hash = hash ^ (traceId.charAt(index) as Long)
            hash = hash * (1099511628211 as Long)
            index = index + 1
        }
        Long positive = hash & (9223372036854775807 as Long)
        return (positive as Double) / 9223372036854775807.0
    }
}
```
