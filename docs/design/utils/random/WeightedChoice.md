# `WeightedChoice`

| 项 | 值 |
| --- | --- |
| 类型 | `class WeightedChoice<T>` |
| 包 | `xdk.random` |
| 稳定性 | `preview` |
| 依赖 | `RandomSource` |

---

## 1. 定位

加权选择表：添加值/权重、按随机源抽取、总权重、清空。

不做：别名表优化、动态权重、线程安全。

---

## 2. 设计逻辑

- 字段 `_values: List<T>`、`_weights: List<Double>`、`_total: Double`。
- 权重必须 >0 且有限；`add` 追加。
- `pick` 生成 [0,total)，线性扫描。
- 可变；非线程安全；无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_values` | `List<T>` | 值 |
| `_weights` | `List<Double>` | 权重 |
| `_total` | `Double` | 总权重 |

不变量：等长；权重 >0；total >0（非空）。

---

## 4. 生命周期

可变；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `WeightedChoice()` | 无 | 空 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `add` | 添加 | `T value, Double weight` | `void` | 非法 → panic |
| `pick` | 抽取 | `RandomSource random` | `T` | 空 → panic |
| `totalWeight` | 总权重 | 无 | `Double` | 无 |
| `length` | 数量 | 无 | `Int` | 无 |
| `clear` | 清空 | 无 | `void` | 无 |

---

## 8. 使用的技术

- 线性加权采样；
- 累积和。

---

## 9. 需要的支撑

- 语言：class、泛型、List、Double、Int；
- 运行时：无；
- 接口：`RandomSource`。

---

## 10. 依赖的特性/接口/类

`RandomSource`。

---

## 11. 所有权与并发

可变；非线程安全；无资源。

---

## 12. 示例与反例

正确：`choice.add("a", 1.0); choice.pick(random)`。  
反例：零/负权重；空表 pick；多任务共享。

---

## 13. 测试/场景义务

单/多值；权重比例；零/负；空表；clear；总权重。

---

## 14. XNull 伪代码

```xnull
class WeightedChoice<T> {
    List<T> _values = []
    List<Double> _weights = []
    Double _total = 0.0

    WeightedChoice() {
    }

    void add(T value, Double weight) {
        if value == null { throw "WeightedChoice.add: null value" }
        if weight <= 0.0 { throw "WeightedChoice.add: invalid weight" }
        _values.push(value)
        _weights.push(weight)
        _total = _total + weight
    }

    T pick(RandomSource random) {
        if random == null || _values.length() == 0 {
            throw "WeightedChoice.pick: empty"
        }
        Double point = random.nextDouble() * _total
        Double cumulative = 0.0
        Int index = 0
        while index < _values.length() {
            cumulative = cumulative + _weights.get(index)
            if point < cumulative {
                return _values.get(index)
            }
            index = index + 1
        }
        return _values.get(_values.length() - 1)
    }

    Double totalWeight() { return _total }
    Int length() { return _values.length() }

    void clear() {
        _values.clear()
        _weights.clear()
        _total = 0.0
    }
}
```
