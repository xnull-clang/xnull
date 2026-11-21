# `LuDecomposition`

| 项 | 值 |
| --- | --- |
| 类型 | `class LuDecomposition` |
| 包 | `xdk.linalg` |
| 稳定性 | `preview` |
| 依赖 | `Matrix`、`Vector` |

---

## 1. 定位

方阵的 LU 分解（带部分主元）：解决 `A x = b`、计算行列式、报告是否奇异。

不做：复数、稀疏、分块、迭代改进、条件数估计、非方阵最小二乘、原地因子更新。

---

## 2. 设计逻辑

- 分解只对非空方阵；非方阵/空矩阵/非有限值由 `factor` 返回 `Result`，不让构造器产生半合法对象。
- 部分主元：每列选绝对值最大的行交换，减少小主元放大误差；同时记录排列与符号。
- 存储 `P A = L U` 的紧凑形式：`_lu` 的下三角（不含对角线）是 L 的乘数，上三角含对角线是 U；L 的对角线隐含为 1。
- `_permutation[newRow] = oldRow`；求解时先对右端项做同样置换。
- 奇异是数值状态而不是构造错误：`factor` 成功返回对象，`isSingular()` 为 true；`solve` 返回 `InvalidArgument`。
- 不可变：因子、排列、符号在构造后不再改变。
- 不做阈值秩判定；对角主元精确为 0 才标记奇异；病态但非零的矩阵仍可分解，稳定性由 X 的改进/条件数能力补足。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_size` | `Int` | final | 方阵阶数，≥1 |
| `_lu` | `Matrix` | final | 紧凑 LU，size×size |
| `_permutation` | `List<Int>` | final | 行排列，长度 size |
| `_parity` | `Int` | final | 排列符号，+1 或 −1 |
| `_singular` | `Bool` | final | 是否遇到零主元 |

不变量：`_lu` 为方阵且阶数等于 `_size`；`_permutation` 是 `0..size-1` 的排列；`_parity` 为 ±1；`_singular` 与零主元一致；构造后不可变。

---

## 4. 生命周期

由 `factor` 创建；不可变；无 close；无资源；可共享；无取消点。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `LuDecomposition.factor(Matrix matrix)` | 方阵 | 非 null；行=列；阶数 ≥1；所有元素有限 | `InvalidArgument` |
| 私有构造器 | 因子/排列/符号 | 仅 `factor` 调用；已校验 | 不对外 |

奇异矩阵不是构造失败；`factor` 返回 `Ok`，由 `isSingular` 报告。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `factor` | 执行 LU 分解 | `Matrix matrix` | `Result<LuDecomposition, Error>` | 非方阵/空/非有限 → `InvalidArgument` | O(n³) |
| `solve` | 解 `A x = b` | `Vector rightHandSide` | `Result<Vector, Error>` | 长度不符 → panic；奇异 → `InvalidArgument` | O(n²) |
| `determinant` | 行列式 | 无 | `Double` | 无 | 奇异返回 0.0 |
| `isSingular` | 是否奇异 | 无 | `Bool` | 无 | 零主元 |
| `size` | 阶数 | 无 | `Int` | 无 | ≥1 |

---

## 8. 使用的技术

- 部分主元高斯消元；
- 紧凑 LU 存储；
- 行排列与符号；
- 前代/回代；
- 检查式有限性验证；
- `Result` 失败通道。

---

## 9. 需要的支撑

- 语言：class、final 字段、List、Int、Double、Bool、Result；
- 数学：`abs`、`isFinite`；
- 错误：`BasicError`、`ErrorKind.InvalidArgument`；
- 接口：[`Matrix`](Matrix.md)、[`Vector`](Vector.md)。

---

## 10. 依赖的特性/接口/类

[`Matrix`](Matrix.md)、[`Vector`](Vector.md)、[`Linalg`](Linalg.md)、[`QrDecomposition`](QrDecomposition.md)、[`Svd`](Svd.md)。

---

## 11. 所有权与并发

不可变；可共享；`solve` 返回新 `Vector`；`_permutation` 构造时复制；无资源；无取消点。  
相等：引用身份；不提供 `equals`；不作为 `Map` 键。

---

## 12. 示例与反例

正确：`Result<LuDecomposition, Error> result = LuDecomposition.factor(matrix)`；成功后 `result.value().solve(rightHandSide)`；奇异时检查 `isSingular()` 并处理 `Err`。  
反例：对非方阵调用 `factor` 却忽略 `Err`；在 `isSingular()` 为 true 时继续 `solve` 并假设成功；用 `determinant` 判断是否可解（接近奇异仍可能非零）；把 `_lu` 当完整 L/U 两个矩阵。

---

## 13. 测试/场景义务

1×1；2×2/3×3；需要换行的矩阵；已上三角；零矩阵；奇异矩阵；非方阵/空矩阵/NaN/Inf；`solve` 长度不符 panic；`determinant` 与手算/乘积累积一致；`solve` 结果代回 `A x ≈ b`；`factor` 不改原矩阵；重复 `solve` 结果一致。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class LuDecomposition {
    final Int _size
    final Matrix _lu
    final List<Int> _permutation
    final Int _parity
    final Bool _singular

    private LuDecomposition(Int size, Matrix combinedLu, List<Int> permutation,
                            Int parity, Bool singular) {
        _size = size
        _lu = combinedLu
        _permutation = permutation.copy()
        _parity = parity
        _singular = singular
    }

    static Result<LuDecomposition, Error> factor(Matrix matrix) {
        if matrix == null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "LuDecomposition.factor: null matrix"))
        }
        Int size = matrix.rowCount()
        if size == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "LuDecomposition.factor: empty matrix"))
        }
        if size != matrix.columnCount() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "LuDecomposition.factor: matrix must be square"))
        }
        Int rowIndex = 0
        while rowIndex < size {
            Int columnIndex = 0
            while columnIndex < size {
                if !isFinite(matrix.get(rowIndex, columnIndex)) {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "LuDecomposition.factor: non-finite element"))
                }
                columnIndex = columnIndex + 1
            }
            rowIndex = rowIndex + 1
        }
        List<Double> working = matrix.toList()
        List<Int> permutation = []
        rowIndex = 0
        while rowIndex < size {
            permutation.push(rowIndex)
            rowIndex = rowIndex + 1
        }
        Int parity = 1
        Bool singular = false
        Int columnIndex = 0
        while columnIndex < size {
            Int pivotRow = columnIndex
            Double pivotMagnitude = abs(working.get(columnIndex * size + columnIndex))
            rowIndex = columnIndex + 1
            while rowIndex < size {
                Double candidate = abs(working.get(rowIndex * size + columnIndex))
                if candidate > pivotMagnitude {
                    pivotMagnitude = candidate
                    pivotRow = rowIndex
                }
                rowIndex = rowIndex + 1
            }
            if pivotMagnitude == 0.0 {
                singular = true
                columnIndex = columnIndex + 1
                continue
            }
            if pivotRow != columnIndex {
                Int swapColumn = 0
                while swapColumn < size {
                    Double temporary = working.get(columnIndex * size + swapColumn)
                    working.set(columnIndex * size + swapColumn,
                        working.get(pivotRow * size + swapColumn))
                    working.set(pivotRow * size + swapColumn, temporary)
                    swapColumn = swapColumn + 1
                }
                Int temporaryRow = permutation.get(columnIndex)
                permutation.set(columnIndex, permutation.get(pivotRow))
                permutation.set(pivotRow, temporaryRow)
                parity = -parity
            }
            Double pivot = working.get(columnIndex * size + columnIndex)
            rowIndex = columnIndex + 1
            while rowIndex < size {
                Double multiplier = working.get(rowIndex * size + columnIndex) / pivot
                working.set(rowIndex * size + columnIndex, multiplier)
                Int innerColumn = columnIndex + 1
                while innerColumn < size {
                    Double updated = working.get(rowIndex * size + innerColumn)
                        - multiplier * working.get(columnIndex * size + innerColumn)
                    working.set(rowIndex * size + innerColumn, updated)
                    innerColumn = innerColumn + 1
                }
                rowIndex = rowIndex + 1
            }
            columnIndex = columnIndex + 1
        }
        return Ok(new LuDecomposition(size, new Matrix(size, size, working),
            permutation, parity, singular))
    }

    Result<Vector, Error> solve(Vector rightHandSide) {
        if rightHandSide == null {
            throw "LuDecomposition.solve: null vector"
        }
        if rightHandSide.length() != _size {
            throw "LuDecomposition.solve: length mismatch"
        }
        if _singular {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "LuDecomposition.solve: singular matrix"))
        }
        List<Double> permuted = []
        Int rowIndex = 0
        while rowIndex < _size {
            permuted.push(rightHandSide.get(_permutation.get(rowIndex)))
            rowIndex = rowIndex + 1
        }
        List<Double> intermediate = []
        rowIndex = 0
        while rowIndex < _size {
            Double total = permuted.get(rowIndex)
            Int columnIndex = 0
            while columnIndex < rowIndex {
                total = total - _lu.get(rowIndex, columnIndex)
                    * intermediate.get(columnIndex)
                columnIndex = columnIndex + 1
            }
            intermediate.push(total)
            rowIndex = rowIndex + 1
        }
        List<Double> solution = []
        rowIndex = 0
        while rowIndex < _size {
            solution.push(0.0)
            rowIndex = rowIndex + 1
        }
        rowIndex = _size - 1
        while rowIndex >= 0 {
            Double diagonal = _lu.get(rowIndex, rowIndex)
            if diagonal == 0.0 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "LuDecomposition.solve: zero pivot"))
            }
            Double total = intermediate.get(rowIndex)
            Int columnIndex = rowIndex + 1
            while columnIndex < _size {
                total = total - _lu.get(rowIndex, columnIndex)
                    * solution.get(columnIndex)
                columnIndex = columnIndex + 1
            }
            solution.set(rowIndex, total / diagonal)
            rowIndex = rowIndex - 1
        }
        return Ok(new Vector(solution))
    }

    Double determinant() {
        if _singular {
            return 0.0
        }
        Double result = 1.0
        if _parity < 0 {
            result = -1.0
        }
        Int diagonalIndex = 0
        while diagonalIndex < _size {
            result = result * _lu.get(diagonalIndex, diagonalIndex)
            diagonalIndex = diagonalIndex + 1
        }
        return result
    }

    Bool isSingular() { return _singular }

    Int size() { return _size }
}
```
