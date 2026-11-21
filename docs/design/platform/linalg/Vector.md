# `Vector`

| 项 | 值 |
| --- | --- |
| 类型 | `class Vector` |
| 包 | `xdk.linalg` |
| 稳定性 | `preview` |
| 依赖 | 无（仅 core `math`） |

---

## 1. 定位

不可变实数向量：长度、按索引读取、点积、欧氏范数、加法、缩放、列表副本。

不做：原地修改、稀疏向量、复数、GPU 向量、广播、矩阵行/列以外的布局。

---

## 2. 设计逻辑

- `Double` 是唯一元素类型；不引入泛型或 `Float` 包装。
- 用 `class` 包装 `List<Double>`，构造时复制，避免调用方列表别名。
- 所有算术返回新 `Vector`；不提供 `set`。
- 长度是形状合同：`dot/add` 长度不等直接 panic。
- `norm` 使用缩放平方和，避免大数平方溢出/小数下溢；NaN/Inf 按 IEEE 传播。
- `equals` 逐元素精确比较；NaN 不等于任何值（包括自身），`-0.0` 与 `0.0` 相等。
- 允许向量含 NaN/±Inf；需要有限输入的分解/求解在各自入口拒绝。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_values` | `List<Double>` | final | 元素列表；长度即向量长度 |

不变量：列表非 null；构造后不被外部改写；`length() == _values.length()`；无隐藏填充/容量语义。

---

## 4. 生命周期

构造后不可变；无 close；无资源；可共享；无取消点。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Vector(List<Double> values)` | 元素列表 | 非 null；元素可为任意 `Double`（含 NaN/Inf） | null → panic |

构造器复制列表；调用方之后修改原列表不影响向量。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `length` | 元素数 | 无 | `Int` | 无 | O(1) |
| `get` | 读取元素 | `Int index` | `Double` | 越界 → panic | O(1) |
| `dot` | 点积 | `Vector other` | `Double` | 长度不等/null → panic | O(n) |
| `norm` | 欧氏范数 | 无 | `Double` | 无 | 缩放平方和；O(n) |
| `add` | 逐元素加 | `Vector other` | `Vector` | 长度不等/null → panic | 新对象；O(n) |
| `scale` | 标量乘 | `Double factor` | `Vector` | 无 | 新对象；O(n) |
| `toList` | 元素副本 | 无 | `List<Double>` | 无 | 新列表 |
| `copy` | 向量副本 | 无 | `Vector` | 无 | 独立列表 |
| `equals` | 值比较 | `Vector other` | `Bool` | null → false | 逐元素精确；NaN 不等 |
| `describe` | 单行描述 | 无 | `String` | 无 | 长度摘要 |

复杂度：`length/get` O(1)；其余见备注。

---

## 8. 使用的技术

- 不可变值对象；
- 列表复制；
- 缩放平方和范数；
- IEEE 浮点语义；
- 逐元素循环。

---

## 9. 需要的支撑

- 语言：class、final 字段、List、Int、Double、Bool、String；
- 数学：`abs`、`sqrt`、`isNaN`、`isInf`、`NaN`、`Inf`；
- 接口：[`Matrix`](Matrix.md)、[`Linalg`](Linalg.md)。

---

## 10. 依赖的特性/接口/类

[`Matrix`](Matrix.md)、[`Linalg`](Linalg.md)、[`QrDecomposition`](QrDecomposition.md)、[`LuDecomposition`](LuDecomposition.md)。

---

## 11. 所有权与并发

不可变；可共享；`toList()` 返回新列表；`add/scale/copy` 返回新向量；无资源；无取消点。  
相等：`equals` 逐元素值比较；`==` 是引用身份；不推荐作 `Map` 键（无冻结哈希契约）。

---

## 12. 示例与反例

正确：`Vector vector = new Vector([1.0, 2.0, 3.0])`；`vector.dot(other)`；`vector.norm()`；`vector.add(other).scale(0.5)`。  
反例：期望 `vector.scale(2.0)` 修改原向量；用 `==` 比较两个内容相同的向量；对长度不同的向量做 `dot`；假设 `norm()` 对 Inf 返回有限值；把 `toList()` 当内部列表修改。

---

## 13. 测试/场景义务

构造复制/空向量；`get` 越界；`dot` 长度不等；`norm` 的 0、单元素、大数、小数、NaN、Inf；`add`/`scale` 不改变原对象；`equals` 的 NaN/-0/长度不同；`toList` 独立性；`describe`。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class Vector {
    final List<Double> _values

    Vector(List<Double> values) {
        if values == null {
            throw "Vector: null values"
        }
        _values = values.copy()
    }

    Int length() { return _values.length() }

    Double get(Int index) {
        if index < 0 || index >= _values.length() {
            throw "Vector.get: index out of range"
        }
        return _values.get(index)
    }

    Double dot(Vector other) {
        if other == null {
            throw "Vector.dot: null vector"
        }
        if _values.length() != other.length() {
            throw "Vector.dot: length mismatch"
        }
        Double total = 0.0
        Int index = 0
        while index < _values.length() {
            total = total + _values.get(index) * other.get(index)
            index = index + 1
        }
        return total
    }

    Double norm() {
        Double scale = 0.0
        Double sumSquares = 1.0
        Int index = 0
        while index < _values.length() {
            Double value = _values.get(index)
            if isNaN(value) {
                return NaN()
            }
            if isInf(value) {
                return Inf()
            }
            Double absolute = abs(value)
            if absolute == 0.0 {
                index = index + 1
                continue
            }
            if scale < absolute {
                Double ratio = scale / absolute
                sumSquares = 1.0 + sumSquares * ratio * ratio
                scale = absolute
            } else {
                Double ratio = absolute / scale
                sumSquares = sumSquares + ratio * ratio
            }
            index = index + 1
        }
        return scale * sqrt(sumSquares)
    }

    Vector add(Vector other) {
        if other == null {
            throw "Vector.add: null vector"
        }
        if _values.length() != other.length() {
            throw "Vector.add: length mismatch"
        }
        List<Double> result = []
        Int index = 0
        while index < _values.length() {
            result.push(_values.get(index) + other.get(index))
            index = index + 1
        }
        return new Vector(result)
    }

    Vector scale(Double factor) {
        List<Double> result = []
        Int index = 0
        while index < _values.length() {
            result.push(_values.get(index) * factor)
            index = index + 1
        }
        return new Vector(result)
    }

    List<Double> toList() { return _values.copy() }

    Vector copy() { return new Vector(_values) }

    Bool equals(Vector other) {
        if other == null {
            return false
        }
        if _values.length() != other.length() {
            return false
        }
        Int index = 0
        while index < _values.length() {
            if _values.get(index) != other.get(index) {
                return false
            }
            index = index + 1
        }
        return true
    }

    String describe() {
        return "vector length=" + str(_values.length())
    }
}
```
