# `Matrix`

| 项 | 值 |
| --- | --- |
| 类型 | `class Matrix` |
| 包 | `xdk.linalg` |
| 稳定性 | `preview` |
| 依赖 | `Vector` |

---

## 1. 定位

不可变实数稠密矩阵：行列数、按 `(rowIndex, columnIndex)` 读取、复制式更新、矩阵乘、矩阵-向量乘、转置、取行/列、扁平列表副本。

不做：原地修改、稀疏存储、分块、GPU、复数、广播、张量 rank > 2。

---

## 2. 设计逻辑

- `Double` 是唯一元素类型；`List<Double>` 按 row-major 存放，`rowCount × columnCount == values.length()`。
- 用 `class` 封装维度与列表；构造时复制，保证不可变。
- 不提供 `set`；`withValue` 复制后返回新矩阵，避免行/列视图或分解结果持有可变别名。
- 维度用 `Int`；元素数等于列表长度，天然受 `Int` 上限约束。
- 形状检查是合同：`multiply` 的内维、`multiplyVector` 的长度、索引越界都 panic。
- `row`/`column` 返回 `Vector` 副本；不是视图。
- 允许 NaN/±Inf 元素；分解/求解入口负责拒绝非有限输入。
- `equals` 逐元素精确比较；NaN 不等，`-0.0` 与 `0.0` 相等。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_rowCount` | `Int` | final | 行数，≥0 |
| `_columnCount` | `Int` | final | 列数，≥0 |
| `_values` | `List<Double>` | final | row-major 元素，长度 = 行×列 |

不变量：行/列 ≥0；列表非 null；`values.length() == rowCount × columnCount`；构造后不被外部改写；索引域 `[0,rowCount) × [0,columnCount)`。

---

## 4. 生命周期

构造后不可变；无 close；无资源；可共享；无取消点。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Matrix(Int rowCount, Int columnCount, List<Double> values)` | 行数、列数、row-major 元素 | 行/列 ≥0；列表非 null；长度精确等于行×列；乘积可放入 `Int` | 违约 → panic |

构造器复制 `values`；调用方之后修改原列表不影响矩阵。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `rowCount` | 行数 | 无 | `Int` | 无 | O(1) |
| `columnCount` | 列数 | 无 | `Int` | 无 | O(1) |
| `isSquare` | 是否方阵 | 无 | `Bool` | 无 | 行=列 |
| `get` | 读取元素 | `Int rowIndex, Int columnIndex` | `Double` | 越界 → panic | O(1) |
| `withValue` | 复制并替换元素 | `Int rowIndex, Int columnIndex, Double value` | `Matrix` | 越界 → panic | 新对象；O(rows×cols) |
| `multiply` | 矩阵乘 | `Matrix other` | `Matrix` | 内维不等/null → panic | 新对象；O(m×k×n) |
| `multiplyVector` | 矩阵-向量乘 | `Vector vector` | `Vector` | 长度不等/null → panic | 新对象；O(m×n) |
| `transpose` | 转置 | 无 | `Matrix` | 无 | 新对象；O(m×n) |
| `row` | 取一行 | `Int rowIndex` | `Vector` | 越界 → panic | 副本；O(cols) |
| `column` | 取一列 | `Int columnIndex` | `Vector` | 越界 → panic | 副本；O(rows) |
| `toList` | row-major 副本 | 无 | `List<Double>` | 无 | 新列表 |
| `copy` | 矩阵副本 | 无 | `Matrix` | 无 | 独立列表 |
| `equals` | 值比较 | `Matrix other` | `Bool` | null → false | 维度+元素；NaN 不等 |
| `describe` | 单行描述 | 无 | `String` | 无 | `rowsxcols` |

---

## 8. 使用的技术

- 不可变值对象；
- row-major 扁平索引；
- 列表复制；
- 三重循环矩阵乘；
- 维度检查；
- IEEE 浮点语义。

---

## 9. 需要的支撑

- 语言：class、final 字段、List、Int、Double、Bool、String；
- 运行时：列表复制、索引读写、字符串拼接；
- 接口：[`Vector`](Vector.md)、[`Linalg`](Linalg.md)、[`LuDecomposition`](LuDecomposition.md)、[`QrDecomposition`](QrDecomposition.md)、[`Svd`](Svd.md)、[`EigenDecomposition`](EigenDecomposition.md)。

---

## 10. 依赖的特性/接口/类

[`Vector`](Vector.md)、[`Linalg`](Linalg.md)、[`LuDecomposition`](LuDecomposition.md)、[`QrDecomposition`](QrDecomposition.md)、[`Svd`](Svd.md)、[`EigenDecomposition`](EigenDecomposition.md)、[`Tensor`](../tensor/Tensor.md)。

---

## 11. 所有权与并发

不可变；可共享；`toList()` 返回新列表；`withValue/transpose/copy` 返回新矩阵；`row/column` 返回新向量；无资源；无取消点。  
相等：`equals` 维度+逐元素值比较；`==` 是引用身份；不推荐作 `Map` 键（无冻结哈希契约）。

---

## 12. 示例与反例

正确：`Matrix matrix = new Matrix(2, 3, values)`；`matrix.get(1, 2)`；`matrix.multiply(other)`；`matrix.transpose()`；`matrix.withValue(0, 0, 9.0)` 原矩阵不变。  
反例：期望 `matrix.set(rowIndex, columnIndex, value)`；用列优先列表构造；`multiply` 两个内维不等的矩阵；把 `row()` 当可写视图；用 `==` 比较内容相同的矩阵；在分解后修改原矩阵期望分解跟着变。

---

## 13. 测试/场景义务

0×0/0×n/m×0；方阵/非方阵；构造长度不匹配 panic；负维度 panic；`get/withValue/row/column` 越界；`multiply` 内维不匹配；`multiplyVector` 长度不匹配；转置两次还原；`multiply` 与手算一致；`equals` 的 NaN/-0/维度不同；`toList` 独立性；`describe`。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class Matrix {
    final Int _rowCount
    final Int _columnCount
    final List<Double> _values

    Matrix(Int rowCount, Int columnCount, List<Double> values) {
        if rowCount < 0 || columnCount < 0 {
            throw "Matrix: negative dimension"
        }
        if values == null {
            throw "Matrix: null values"
        }
        Long expectedCount = (rowCount as Long) * (columnCount as Long)
        if expectedCount != values.length() as Long {
            throw "Matrix: value count mismatch"
        }
        _rowCount = rowCount
        _columnCount = columnCount
        _values = values.copy()
    }

    Int rowCount() { return _rowCount }

    Int columnCount() { return _columnCount }

    Bool isSquare() { return _rowCount == _columnCount }

    Double get(Int rowIndex, Int columnIndex) {
        if rowIndex < 0 || rowIndex >= _rowCount {
            throw "Matrix.get: row index out of range"
        }
        if columnIndex < 0 || columnIndex >= _columnCount {
            throw "Matrix.get: column index out of range"
        }
        return _values.get(rowIndex * _columnCount + columnIndex)
    }

    Matrix withValue(Int rowIndex, Int columnIndex, Double value) {
        if rowIndex < 0 || rowIndex >= _rowCount {
            throw "Matrix.withValue: row index out of range"
        }
        if columnIndex < 0 || columnIndex >= _columnCount {
            throw "Matrix.withValue: column index out of range"
        }
        List<Double> updated = _values.copy()
        updated.set(rowIndex * _columnCount + columnIndex, value)
        return new Matrix(_rowCount, _columnCount, updated)
    }

    Matrix multiply(Matrix other) {
        if other == null {
            throw "Matrix.multiply: null matrix"
        }
        if _columnCount != other.rowCount() {
            throw "Matrix.multiply: inner dimension mismatch"
        }
        List<Double> result = []
        Int rowIndex = 0
        while rowIndex < _rowCount {
            Int columnIndex = 0
            while columnIndex < other.columnCount() {
                Double total = 0.0
                Int innerIndex = 0
                while innerIndex < _columnCount {
                    total = total + self.get(rowIndex, innerIndex)
                        * other.get(innerIndex, columnIndex)
                    innerIndex = innerIndex + 1
                }
                result.push(total)
                columnIndex = columnIndex + 1
            }
            rowIndex = rowIndex + 1
        }
        return new Matrix(_rowCount, other.columnCount(), result)
    }

    Vector multiplyVector(Vector vector) {
        if vector == null {
            throw "Matrix.multiplyVector: null vector"
        }
        if vector.length() != _columnCount {
            throw "Matrix.multiplyVector: length mismatch"
        }
        List<Double> result = []
        Int rowIndex = 0
        while rowIndex < _rowCount {
            Double total = 0.0
            Int columnIndex = 0
            while columnIndex < _columnCount {
                total = total + self.get(rowIndex, columnIndex)
                    * vector.get(columnIndex)
                columnIndex = columnIndex + 1
            }
            result.push(total)
            rowIndex = rowIndex + 1
        }
        return new Vector(result)
    }

    Matrix transpose() {
        List<Double> result = []
        Int targetRow = 0
        while targetRow < _columnCount {
            Int targetColumn = 0
            while targetColumn < _rowCount {
                result.push(self.get(targetColumn, targetRow))
                targetColumn = targetColumn + 1
            }
            targetRow = targetRow + 1
        }
        return new Matrix(_columnCount, _rowCount, result)
    }

    Vector row(Int rowIndex) {
        if rowIndex < 0 || rowIndex >= _rowCount {
            throw "Matrix.row: row index out of range"
        }
        List<Double> result = []
        Int columnIndex = 0
        while columnIndex < _columnCount {
            result.push(self.get(rowIndex, columnIndex))
            columnIndex = columnIndex + 1
        }
        return new Vector(result)
    }

    Vector column(Int columnIndex) {
        if columnIndex < 0 || columnIndex >= _columnCount {
            throw "Matrix.column: column index out of range"
        }
        List<Double> result = []
        Int rowIndex = 0
        while rowIndex < _rowCount {
            result.push(self.get(rowIndex, columnIndex))
            rowIndex = rowIndex + 1
        }
        return new Vector(result)
    }

    List<Double> toList() { return _values.copy() }

    Matrix copy() { return new Matrix(_rowCount, _columnCount, _values) }

    Bool equals(Matrix other) {
        if other == null {
            return false
        }
        if _rowCount != other.rowCount() || _columnCount != other.columnCount() {
            return false
        }
        List<Double> otherValues = other.toList()
        Int index = 0
        while index < _values.length() {
            if _values.get(index) != otherValues.get(index) {
                return false
            }
            index = index + 1
        }
        return true
    }

    String describe() {
        return "matrix " + str(_rowCount) + "x" + str(_columnCount)
    }
}
```
