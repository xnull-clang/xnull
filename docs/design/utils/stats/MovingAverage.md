# `MovingAverage`

| 项 | 值 |
| --- | --- |
| 类型 | `class MovingAverage` |
| 包 | `xdk.stats` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

固定窗口简单移动平均：最近 N 个值的算术平均。

不做：加权移动平均、指数平均（用 `Ema`）、时间窗口、线程安全。

---

## 2. 设计逻辑

- 字段：窗口大小、当前值列表、和、环形写入位置。
- 未满窗口时追加；满后覆盖最旧值并更新和。
- `average` 是当前窗口均值；空窗口返回 NaN。
- 窗口大小构造时固定；`reset` 清空但保留窗口。
- 非线程安全；无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_window` | `Int` | ≥1 |
| `_values` | `List<Double>` | 当前窗口值 |
| `_sum` | `Double` | 当前和 |
| `_index` | `Int` | 下一个覆盖位置 |

不变量：values.length ≤ window；index ∈ [0,window)；sum 与 values 一致。

---

## 4. 生命周期

构造后可变；`reset` 清空；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `MovingAverage(Int window)` | window | ≥1 | ≤0 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `add` | 加入值 | `Double value` | `void` | 无 |
| `average` | 当前均值 | 无 | `Double` | 空 → NaN |
| `window` | 窗口大小 | 无 | `Int` | 无 |
| `count` | 当前样本数 | 无 | `Int` | 无 |
| `isFull` | 窗口是否已满 | 无 | `Bool` | 无 |
| `reset` | 清空 | 无 | `void` | 无 |

说明：

- `count` 最大等于 window。
- NaN 会传播到 `_sum`，此后 average 为 NaN；调用方应过滤。
- 覆盖顺序严格按调用顺序。

---

## 8. 使用的技术

- 环形窗口；
- 增量求和；
- 固定内存。

---

## 9. 需要的支撑

- 语言：class、List、Double、Int、Bool；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

引用语义；非线程安全；`add`/`reset` 不可并发；无资源。

---

## 12. 示例与反例

正确：窗口 3，依次 1/2/3 → average 2；再加 4 → average 3。  
反例：窗口 0；并发 add；把移动平均当精确总量；NaN 未过滤。

---

## 13. 测试/场景义务

窗口 1/N；未满/满/覆盖；空 average；reset；count/isFull；NaN；负值。

---

## 14. XNull 伪代码

```xnull
class MovingAverage {
    final Int _window
    final List<Double> _values
    Double _sum = 0.0
    Int _index = 0

    MovingAverage(Int window) {
        if window < 1 { throw "MovingAverage: window < 1" }
        _window = window
        _values = []
    }

    void add(Double value) {
        if _values.length() < _window {
            _values.push(value)
            _sum = _sum + value
            if _values.length() == _window { _index = 0 }
        } else {
            Double old = _values.get(_index)
            _sum = _sum - old + value
            _values.set(_index, value)
            _index = (_index + 1) % _window
        }
    }

    Double average() {
        if _values.isEmpty() { return NaN }
        return _sum / (_values.length() as Double)
    }

    Int window() { return _window }
    Int count() { return _values.length() }
    Bool isFull() { return _values.length() == _window }

    void reset() {
        _values.clear()
        _sum = 0.0
        _index = 0
    }
}
```
