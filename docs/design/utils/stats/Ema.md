# `Ema`

| 项 | 值 |
| --- | --- |
| 类型 | `class Ema` |
| 包 | `xdk.stats` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

指数移动平均：按 alpha 对当前值与历史值加权。

不做：双指数/三指数平滑、时间衰减、线程安全、持久化。

---

## 2. 设计逻辑

- 字段：alpha、当前值、是否已初始化、样本数。
- 首个值直接作为初始 EMA；后续 `value = alpha*x + (1-alpha)*value`。
- alpha=1 等价当前值；alpha=0 保持首值。
- 空数据 `value()` 返回 null，不是 0。
- 非线程安全；无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_alpha` | `Double` | 0..1 |
| `_value` | `Double?` | 当前 EMA |
| `_initialized` | `Bool` | 是否有值 |
| `_count` | `Long` | 样本数 |

不变量：alpha ∈ [0,1]；initialized=true 时 value 非 null；count ≥0。

---

## 4. 生命周期

构造后可变；`reset` 清空；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Ema(Double alpha)` | alpha | 0.0..1.0 | 越界/NaN → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `add` | 加入值 | `Double value` | `void` | 无 |
| `value` | 当前 EMA/无 | 无 | `Double?` | 无 |
| `alpha` | 平滑系数 | 无 | `Double` | 无 |
| `count` | 样本数 | 无 | `Long` | 无 |
| `isInitialized` | 是否有值 | 无 | `Bool` | 无 |
| `reset` | 清空 | 无 | `void` | 无 |

说明：

- `add(NaN)` 会使当前值变为 NaN；调用方应过滤。
- `reset` 后 `value()` 返回 null，count=0。
- alpha 越小越平滑，滞后越大。

---

## 8. 使用的技术

- 指数加权；
- 单值状态；
- 初始化分支。

---

## 9. 需要的支撑

- 语言：class、Double、Long、Bool、可空；
- 运行时：`isNaN`；
- 接口：无。

---

## 10. 依赖的特性/接口/类

`xdk.math.isNaN`（构造校验）。

---

## 11. 所有权与并发

引用语义；非线程安全；`add`/`reset` 不可并发；无资源。

---

## 12. 示例与反例

正确：alpha=0.5，首值 10，再加 20 → 15。  
反例：alpha=1.5；空 EMA 当 0；并发 add；用 EMA 代替精确均值。

---

## 13. 测试/场景义务

alpha 0/0.5/1；空 value；首值；多值；reset；count；NaN；负值。

---

## 14. XNull 伪代码

```xnull
class Ema {
    final Double _alpha
    Double? _value = null
    Bool _initialized = false
    Long _count = 0

    Ema(Double alpha) {
        if isNaN(alpha) { throw "Ema: NaN alpha" }
        if alpha < 0.0 || alpha > 1.0 { throw "Ema: alpha out of range" }
        _alpha = alpha
    }

    void add(Double value) {
        if !_initialized {
            _value = value
            _initialized = true
        } else {
            _value = _alpha * value + (1.0 - _alpha) * (_value as Double)
        }
        _count = _count + 1
    }

    Double? value() { return _value }
    Double alpha() { return _alpha }
    Long count() { return _count }
    Bool isInitialized() { return _initialized }

    void reset() {
        _value = null
        _initialized = false
        _count = 0
    }
}
```
