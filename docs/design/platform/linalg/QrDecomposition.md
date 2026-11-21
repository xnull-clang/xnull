# `QrDecomposition`

| 项 | 值 |
| --- | --- |
| 类型 | `class QrDecomposition` |
| 包 | `xdk.linalg` |
| 稳定性 | `preview` |
| 依赖 | `Matrix`、`Vector` |

---

## 1. 定位

实矩阵的经济 QR 分解：`A = Q R`，`Q` 为 m×n 半正交矩阵，`R` 为 n×n 上三角矩阵；用于最小二乘。

不做：欠定系统、全 QR、秩揭示 QR、复数、稀疏、分块、迭代 refinement。

---

## 2. 设计逻辑

- 只接受高矩阵或方阵（`rowCount >= columnCount`）；欠定系统是 X，`factor` 返回 `Unsupported`。
- Householder 反射逐列消元；`Q` 通过逆序左乘反射子累积，保持 m×n economy 形状，不构造 m×m 全 Q。
- `R` 取工作矩阵的前 n 行/列；下三角部分在精确算术下为 0。
- 奇异/秩亏不是构造错误：`factor` 仍返回对象，`isFullRank` 为 false；`solveLeastSquares` 返回 `InvalidArgument`。
- 满秩阈值固定为 `1e-12 × max|R[i,i]|`；这是基线策略，不是通用秩判定。
- 不可变：Q/R 构造后不再改变；`q()/r()` 返回不可变矩阵引用。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_q` | `Matrix` | final | m×n，列半正交 |
| `_r` | `Matrix` | final | n×n 上三角 |
| `_fullRank` | `Bool` | final | 对角是否全部超过阈值 |
| `_rowCount` | `Int` | final | m，≥1 |
| `_columnCount` | `Int` | final | n，≥1 |

不变量：`m >= n >= 1`；`_q` 为 m×n；`_r` 为 n×n 且上三角；`A = Q R` 在浮点误差内成立；`_fullRank` 与 R 对角阈值一致；构造后不可变。

---

## 4. 生命周期

由 `factor` 创建；不可变；无 close；无资源；可共享；无取消点。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `QrDecomposition.factor(Matrix matrix)` | 高矩阵/方阵 | 非 null；行 ≥ 列；行/列 ≥1；所有元素有限 | 空/非有限 → `InvalidArgument`；行 < 列 → `Unsupported` |
| 私有构造器 | Q/R/满秩标志 | 仅 `factor` 调用；已校验 | 不对外 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `factor` | 执行 economy QR | `Matrix matrix` | `Result<QrDecomposition, Error>` | 空/非有限 → `InvalidArgument`；欠定 → `Unsupported` | O(m×n²) |
| `q` | 正交因子 | 无 | `Matrix` | 无 | m×n，共享不可变引用 |
| `r` | 上三角因子 | 无 | `Matrix` | 无 | n×n |
| `solveLeastSquares` | 最小二乘解 | `Vector rightHandSide` | `Result<Vector, Error>` | 长度不符 → panic；秩亏 → `InvalidArgument` | O(m×n) |
| `isFullRank` | 是否满列秩 | 无 | `Bool` | 无 | 阈值判定 |
| `rowCount` | 行数 | 无 | `Int` | 无 | m |
| `columnCount` | 列数 | 无 | `Int` | 无 | n |

---

## 8. 使用的技术

- Householder 反射；
- economy QR；
- 反射子逆序左乘累积 Q；
- 上三角回代；
- 有限性校验；
- 相对对角阈值。

---

## 9. 需要的支撑

- 语言：class、final 字段、List、Int、Double、Bool、Result；
- 数学：`abs`、`sqrt`、`isFinite`；
- 错误：`BasicError`、`ErrorKind.InvalidArgument`、`ErrorKind.Unsupported`；
- 接口：[`Matrix`](Matrix.md)、[`Vector`](Vector.md)。

---

## 10. 依赖的特性/接口/类

[`Matrix`](Matrix.md)、[`Vector`](Vector.md)、[`LuDecomposition`](LuDecomposition.md)、[`Svd`](Svd.md)、[`Linalg`](Linalg.md)。

---

## 11. 所有权与并发

不可变；可共享；`q()/r()` 返回不可变矩阵引用；`solveLeastSquares` 返回新 `Vector`；无资源；无取消点。  
相等：引用身份；不提供 `equals`；不作为 `Map` 键。

---

## 12. 示例与反例

正确：`QrDecomposition.factor(tallMatrix)`；`decomposition.q()`/`r()` 检查形状；`solveLeastSquares(rightHandSide)` 处理 `Err`。  
反例：对宽矩阵调用 `factor` 并假设成功；用 `q()` 当 m×m 全正交矩阵；在 `isFullRank()` 为 false 时继续求解；把阈值当精确秩；忽略非有限输入的错误。

---

## 13. 测试/场景义务

方阵/高矩阵；1×1；m×1；秩亏；欠定返回 `Unsupported`；空/NaN/Inf 返回 `InvalidArgument`；`QᵀQ ≈ I`；`Q R ≈ A`；`R` 上三角；`solveLeastSquares` 结果代回残差；长度不符 panic；重复求解一致；`factor` 不改原矩阵。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class QrDecomposition {
    final Matrix _q
    final Matrix _r
    final Bool _fullRank
    final Int _rowCount
    final Int _columnCount

    private QrDecomposition(Matrix orthogonalMatrix,
                            Matrix upperTriangularMatrix,
                            Bool fullRank, Int rowCount, Int columnCount) {
        _q = orthogonalMatrix
        _r = upperTriangularMatrix
        _fullRank = fullRank
        _rowCount = rowCount
        _columnCount = columnCount
    }

    static Result<QrDecomposition, Error> factor(Matrix matrix) {
        if matrix == null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "QrDecomposition.factor: null matrix"))
        }
        Int rowCount = matrix.rowCount()
        Int columnCount = matrix.columnCount()
        if rowCount == 0 || columnCount == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "QrDecomposition.factor: empty matrix"))
        }
        if rowCount < columnCount {
            return Err(new BasicError(ErrorKind.Unsupported,
                "QrDecomposition.factor: underdetermined matrix is X"))
        }
        Int rowIndex = 0
        while rowIndex < rowCount {
            Int columnIndex = 0
            while columnIndex < columnCount {
                if !isFinite(matrix.get(rowIndex, columnIndex)) {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "QrDecomposition.factor: non-finite element"))
                }
                columnIndex = columnIndex + 1
            }
            rowIndex = rowIndex + 1
        }
        List<Double> working = matrix.toList()
        List<Double> reflectors = []
        List<Double> betas = []
        Int reflectorIndex = 0
        while reflectorIndex < columnCount {
            Double normSquared = 0.0
            rowIndex = reflectorIndex
            while rowIndex < rowCount {
                Double value = working.get(rowIndex * columnCount + reflectorIndex)
                normSquared = normSquared + value * value
                rowIndex = rowIndex + 1
            }
            Double columnNorm = sqrt(normSquared)
            if columnNorm == 0.0 {
                Int zeroEntry = 0
                while zeroEntry < rowCount {
                    reflectors.push(0.0)
                    zeroEntry = zeroEntry + 1
                }
                betas.push(0.0)
                reflectorIndex = reflectorIndex + 1
                continue
            }
            Double diagonal = working.get(
                reflectorIndex * columnCount + reflectorIndex)
            Double alpha = -columnNorm
            if diagonal < 0.0 {
                alpha = columnNorm
            }
            List<Double> reflector = []
            rowIndex = 0
            while rowIndex < rowCount {
                reflector.push(0.0)
                rowIndex = rowIndex + 1
            }
            reflector.set(reflectorIndex, diagonal - alpha)
            Double reflectorNormSquared = (diagonal - alpha) * (diagonal - alpha)
            rowIndex = reflectorIndex + 1
            while rowIndex < rowCount {
                Double value = working.get(rowIndex * columnCount + reflectorIndex)
                reflector.set(rowIndex, value)
                reflectorNormSquared = reflectorNormSquared + value * value
                rowIndex = rowIndex + 1
            }
            if reflectorNormSquared == 0.0 {
                Int zeroEntry = 0
                while zeroEntry < rowCount {
                    reflectors.push(0.0)
                    zeroEntry = zeroEntry + 1
                }
                betas.push(0.0)
                reflectorIndex = reflectorIndex + 1
                continue
            }
            Double beta = 2.0 / reflectorNormSquared
            Int reflectorEntry = 0
            while reflectorEntry < rowCount {
                reflectors.push(reflector.get(reflectorEntry))
                reflectorEntry = reflectorEntry + 1
            }
            betas.push(beta)
            Int columnIndex = reflectorIndex
            while columnIndex < columnCount {
                Double dot = 0.0
                rowIndex = reflectorIndex
                while rowIndex < rowCount {
                    dot = dot + reflector.get(rowIndex)
                        * working.get(rowIndex * columnCount + columnIndex)
                    rowIndex = rowIndex + 1
                }
                rowIndex = reflectorIndex
                while rowIndex < rowCount {
                    Double updated = working.get(rowIndex * columnCount + columnIndex)
                        - beta * reflector.get(rowIndex) * dot
                    working.set(rowIndex * columnCount + columnIndex, updated)
                    rowIndex = rowIndex + 1
                }
                columnIndex = columnIndex + 1
            }
            reflectorIndex = reflectorIndex + 1
        }
        List<Double> rValues = []
        Int rRow = 0
        while rRow < columnCount {
            Int rColumn = 0
            while rColumn < columnCount {
                rValues.push(working.get(rRow * columnCount + rColumn))
                rColumn = rColumn + 1
            }
            rRow = rRow + 1
        }
        List<Double> qWorking = []
        Int qRow = 0
        while qRow < rowCount {
            Int qColumn = 0
            while qColumn < columnCount {
                if qRow == qColumn {
                    qWorking.push(1.0)
                } else {
                    qWorking.push(0.0)
                }
                qColumn = qColumn + 1
            }
            qRow = qRow + 1
        }
        Int reverseIndex = columnCount - 1
        while reverseIndex >= 0 {
            Double beta = betas.get(reverseIndex)
            if beta != 0.0 {
                Int qColumn = 0
                while qColumn < columnCount {
                    Double dot = 0.0
                    qRow = reverseIndex
                    while qRow < rowCount {
                        dot = dot + reflectors.get(reverseIndex * rowCount + qRow)
                            * qWorking.get(qRow * columnCount + qColumn)
                        qRow = qRow + 1
                    }
                    qRow = reverseIndex
                    while qRow < rowCount {
                        Double updated = qWorking.get(qRow * columnCount + qColumn)
                            - beta * reflectors.get(reverseIndex * rowCount + qRow)
                            * dot
                        qWorking.set(qRow * columnCount + qColumn, updated)
                        qRow = qRow + 1
                    }
                    qColumn = qColumn + 1
                }
            }
            reverseIndex = reverseIndex - 1
        }
        Matrix orthogonalMatrix = new Matrix(rowCount, columnCount, qWorking)
        Matrix upperTriangularMatrix = new Matrix(columnCount, columnCount, rValues)
        Double maximumDiagonal = 0.0
        Int diagonalIndex = 0
        while diagonalIndex < columnCount {
            Double magnitude = abs(upperTriangularMatrix.get(diagonalIndex, diagonalIndex))
            if magnitude > maximumDiagonal {
                maximumDiagonal = magnitude
            }
            diagonalIndex = diagonalIndex + 1
        }
        Double threshold = 1e-12 * maximumDiagonal
        Bool fullRank = true
        diagonalIndex = 0
        while diagonalIndex < columnCount {
            if abs(upperTriangularMatrix.get(diagonalIndex, diagonalIndex)) <= threshold {
                fullRank = false
            }
            diagonalIndex = diagonalIndex + 1
        }
        return Ok(new QrDecomposition(orthogonalMatrix, upperTriangularMatrix, fullRank, rowCount, columnCount))
    }

    Matrix q() { return _q }

    Matrix r() { return _r }

    Result<Vector, Error> solveLeastSquares(Vector rightHandSide) {
        if rightHandSide == null {
            throw "QrDecomposition.solveLeastSquares: null vector"
        }
        if rightHandSide.length() != _rowCount {
            throw "QrDecomposition.solveLeastSquares: length mismatch"
        }
        if !_fullRank {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "QrDecomposition.solveLeastSquares: rank deficient"))
        }
        List<Double> projected = []
        Int columnIndex = 0
        while columnIndex < _columnCount {
            Double total = 0.0
            Int rowIndex = 0
            while rowIndex < _rowCount {
                total = total + _q.get(rowIndex, columnIndex)
                    * rightHandSide.get(rowIndex)
                rowIndex = rowIndex + 1
            }
            projected.push(total)
            columnIndex = columnIndex + 1
        }
        List<Double> solution = []
        Int rowIndex = 0
        while rowIndex < _columnCount {
            solution.push(0.0)
            rowIndex = rowIndex + 1
        }
        rowIndex = _columnCount - 1
        while rowIndex >= 0 {
            Double diagonal = _r.get(rowIndex, rowIndex)
            if diagonal == 0.0 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "QrDecomposition.solveLeastSquares: zero diagonal"))
            }
            Double total = projected.get(rowIndex)
            Int innerIndex = rowIndex + 1
            while innerIndex < _columnCount {
                total = total - _r.get(rowIndex, innerIndex)
                    * solution.get(innerIndex)
                innerIndex = innerIndex + 1
            }
            solution.set(rowIndex, total / diagonal)
            rowIndex = rowIndex - 1
        }
        return Ok(new Vector(solution))
    }

    Bool isFullRank() { return _fullRank }

    Int rowCount() { return _rowCount }

    Int columnCount() { return _columnCount }
}
```
