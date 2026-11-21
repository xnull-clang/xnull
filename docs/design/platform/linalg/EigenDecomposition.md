# `EigenDecomposition`

| 项 | 值 |
| --- | --- |
| 类型 | `class EigenDecomposition` |
| 包 | `xdk.linalg` |
| 稳定性 | `preview` |
| 依赖 | `Matrix`、`Vector` |

---

## 1. 定位

实对称矩阵的特征分解：特征值降序、特征向量按列排列，满足 `A V = V diag(values)`。

不做：非对称实矩阵、复特征值、广义特征值、奇异值分解、稀疏/分块、部分特征对。

---

## 2. 设计逻辑

- 只接受非空、有限、实对称方阵；非对称输入返回 `Unsupported`，因为一般实矩阵可能产生复特征值（X）。
- 对称性用相对容差判定：`|a_ij − a_ji| ≤ 1e-12 × max(|a_ij|, |a_ji|)`；超过则拒绝。
- 使用循环 Jacobi 旋转：每轮消去一对最大非对角元，保持对称性与正交相似。
- 最多 100 轮，收敛阈值 `1e-12`（相对最大非对角/对角量级）；未收敛返回 `Internal`，不返回半成品。
- 特征值按降序排序；特征向量列随特征值一起交换。
- 每列做符号规范：绝对值最大的分量取正，保证相同输入得到可复现输出。
- 特征向量列两两正交且单位长度；`eigenvectors()` 返回 n×n 矩阵。
- 不可变；值和向量构造后不再改变。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_values` | `Vector` | final | n 个特征值，降序 |
| `_eigenvectors` | `Matrix` | final | n×n，第 i 列对应 `_values[i]` |

不变量：`n >= 1`；`_values.length() == n`；`_eigenvectors` 为 n×n；列单位正交；`A V = V diag(values)` 在浮点误差内成立；值降序；签名规范；构造后不可变。

---

## 4. 生命周期

由 `ofSymmetric` 创建；不可变；无 close；无资源；可共享；无取消点。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `EigenDecomposition.ofSymmetric(Matrix matrix)` | 实对称方阵 | 非 null；方阵；阶数 ≥1；所有元素有限；对称 | 非方阵/空/非有限 → `InvalidArgument`；非对称 → `Unsupported`；未收敛 → `Internal` |
| 私有构造器 | 值/向量 | 仅工厂调用；已校验 | 不对外 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `ofSymmetric` | 对称特征分解 | `Matrix matrix` | `Result<EigenDecomposition, Error>` | 见 §5 | O(n³) 每轮，最多 100 轮 |
| `values` | 特征值 | 无 | `Vector` | 无 | 降序，共享不可变引用 |
| `eigenvectors` | 特征向量 | 无 | `Matrix` | 无 | 列对应值，n×n |

---

## 8. 使用的技术

- 循环 Jacobi 旋转；
- 对称正交相似；
- 相对收敛阈值；
- 降序排序与列交换；
- 特征向量符号规范；
- `Result` 失败通道。

---

## 9. 需要的支撑

- 语言：class、final 字段、List、Int、Double、Bool、Result；
- 数学：`abs`、`sqrt`、`isFinite`；
- 错误：`BasicError`、`ErrorKind.InvalidArgument`、`ErrorKind.Unsupported`、`ErrorKind.Internal`；
- 接口：[`Matrix`](Matrix.md)、[`Vector`](Vector.md)、[`Svd`](Svd.md)。

---

## 10. 依赖的特性/接口/类

[`Matrix`](Matrix.md)、[`Vector`](Vector.md)、[`Svd`](Svd.md)、[`Linalg`](Linalg.md)、[`LuDecomposition`](LuDecomposition.md)。

---

## 11. 所有权与并发

不可变；可共享；`values()/eigenvectors()` 返回不可变引用；无资源；无取消点。  
相等：引用身份；不提供 `equals`；不作为 `Map` 键。

---

## 12. 示例与反例

正确：`EigenDecomposition.ofSymmetric(symmetricMatrix)`；`values()` 降序；`eigenvectors().column(0)` 对应第一个值；用 `A.multiply(eigenvectors())` 与 `eigenvectors().multiply(diagonal)` 对照。  
反例：把非对称矩阵传给 `ofSymmetric` 并假设得到实特征值；假设特征值按升序；忽略 `Err`；把特征向量当行向量；假设重特征值的向量顺序跨实现稳定（本包只保证降序和符号规范）。

---

## 13. 测试/场景义务

1×1；对角矩阵；单位阵；2×2/3×3 对称矩阵；重特征值；零矩阵；非对称返回 `Unsupported`；非方阵/空/NaN/Inf 返回 `InvalidArgument`；`A V ≈ V diag`；列正交/单位长度；值降序；符号规范；`ofSymmetric` 不改原矩阵；未收敛路径（内部测试可注入更小迭代上限）。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class EigenDecomposition {
    final Vector _values
    final Matrix _eigenvectors

    private EigenDecomposition(Vector values, Matrix eigenvectors) {
        _values = values
        _eigenvectors = eigenvectors
    }

    static Result<EigenDecomposition, Error> ofSymmetric(Matrix matrix) {
        if matrix == null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "EigenDecomposition.ofSymmetric: null matrix"))
        }
        Int size = matrix.rowCount()
        if size == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "EigenDecomposition.ofSymmetric: empty matrix"))
        }
        if size != matrix.columnCount() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "EigenDecomposition.ofSymmetric: matrix must be square"))
        }
        Int rowIndex = 0
        while rowIndex < size {
            Int columnIndex = 0
            while columnIndex < size {
                if !isFinite(matrix.get(rowIndex, columnIndex)) {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "EigenDecomposition.ofSymmetric: non-finite element"))
                }
                columnIndex = columnIndex + 1
            }
            rowIndex = rowIndex + 1
        }
        rowIndex = 0
        while rowIndex < size {
            Int columnIndex = rowIndex + 1
            while columnIndex < size {
                Double first = matrix.get(rowIndex, columnIndex)
                Double second = matrix.get(columnIndex, rowIndex)
                Double scale = abs(first)
                if abs(second) > scale {
                    scale = abs(second)
                }
                if abs(first - second) > 1e-12 * scale {
                    return Err(new BasicError(ErrorKind.Unsupported,
                        "EigenDecomposition.ofSymmetric: matrix is not symmetric"))
                }
                columnIndex = columnIndex + 1
            }
            rowIndex = rowIndex + 1
        }
        List<Double> working = matrix.toList()
        List<Double> vectors = []
        rowIndex = 0
        while rowIndex < size {
            Int columnIndex = 0
            while columnIndex < size {
                if rowIndex == columnIndex {
                    vectors.push(1.0)
                } else {
                    vectors.push(0.0)
                }
                columnIndex = columnIndex + 1
            }
            rowIndex = rowIndex + 1
        }
        Int maximumSweeps = 100
        Double convergenceTolerance = 1e-12
        Int sweep = 0
        Bool converged = false
        while sweep < maximumSweeps && !converged {
            Double maximumOffDiagonal = 0.0
            Double maximumDiagonal = 0.0
            Int firstIndex = 0
            while firstIndex < size {
                Double diagonalValue = abs(working.get(firstIndex * size + firstIndex))
                if diagonalValue > maximumDiagonal {
                    maximumDiagonal = diagonalValue
                }
                Int secondIndex = firstIndex + 1
                while secondIndex < size {
                    Double offDiagonal = abs(
                        working.get(firstIndex * size + secondIndex))
                    if offDiagonal > maximumOffDiagonal {
                        maximumOffDiagonal = offDiagonal
                    }
                    secondIndex = secondIndex + 1
                }
                firstIndex = firstIndex + 1
            }
            Double scale = maximumDiagonal
            if maximumOffDiagonal > scale {
                scale = maximumOffDiagonal
            }
            Double threshold = convergenceTolerance * scale
            if maximumOffDiagonal <= threshold {
                converged = true
            } else {
                Int rotationFirstIndex = 0
                while rotationFirstIndex < size {
                    Int rotationSecondIndex = rotationFirstIndex + 1
                    while rotationSecondIndex < size {
                        Double offDiagonal = working.get(
                            rotationFirstIndex * size + rotationSecondIndex)
                        if abs(offDiagonal) > threshold {
                            Double firstDiagonal = working.get(
                                rotationFirstIndex * size + rotationFirstIndex)
                            Double secondDiagonal = working.get(
                                rotationSecondIndex * size + rotationSecondIndex)
                            Double theta = (secondDiagonal - firstDiagonal)
                                / (2.0 * offDiagonal)
                            Double tangent = 0.0
                            if theta == 0.0 {
                                tangent = 1.0
                            } else {
                                Double sign = 1.0
                                if theta < 0.0 {
                                    sign = -1.0
                                }
                                tangent = sign / (abs(theta) + sqrt(theta * theta + 1.0))
                            }
                            Double cosine = 1.0 / sqrt(tangent * tangent + 1.0)
                            Double sine = tangent * cosine
                            Int scanIndex = 0
                            while scanIndex < size {
                                if scanIndex != rotationFirstIndex && scanIndex != rotationSecondIndex {
                                    Double firstValue = working.get(
                                        scanIndex * size + rotationFirstIndex)
                                    Double secondValue = working.get(
                                        scanIndex * size + rotationSecondIndex)
                                    Double updatedFirst = cosine * firstValue
                                        - sine * secondValue
                                    Double updatedSecond = sine * firstValue
                                        + cosine * secondValue
                                    working.set(scanIndex * size + rotationFirstIndex, updatedFirst)
                                    working.set(rotationFirstIndex * size + scanIndex, updatedFirst)
                                    working.set(scanIndex * size + rotationSecondIndex, updatedSecond)
                                    working.set(rotationSecondIndex * size + scanIndex, updatedSecond)
                                }
                                scanIndex = scanIndex + 1
                            }
                            Double updatedFirstDiagonal = cosine * cosine * firstDiagonal
                                - 2.0 * sine * cosine * offDiagonal
                                + sine * sine * secondDiagonal
                            Double updatedSecondDiagonal = sine * sine * firstDiagonal
                                + 2.0 * sine * cosine * offDiagonal
                                + cosine * cosine * secondDiagonal
                            working.set(rotationFirstIndex * size + rotationFirstIndex,
                                updatedFirstDiagonal)
                            working.set(rotationSecondIndex * size + rotationSecondIndex,
                                updatedSecondDiagonal)
                            working.set(rotationFirstIndex * size + rotationSecondIndex, 0.0)
                            working.set(rotationSecondIndex * size + rotationFirstIndex, 0.0)
                            scanIndex = 0
                            while scanIndex < size {
                                Double firstVectorValue = vectors.get(
                                    scanIndex * size + rotationFirstIndex)
                                Double secondVectorValue = vectors.get(
                                    scanIndex * size + rotationSecondIndex)
                                vectors.set(scanIndex * size + rotationFirstIndex,
                                    cosine * firstVectorValue - sine * secondVectorValue)
                                vectors.set(scanIndex * size + rotationSecondIndex,
                                    sine * firstVectorValue + cosine * secondVectorValue)
                                scanIndex = scanIndex + 1
                            }
                        }
                        rotationSecondIndex = rotationSecondIndex + 1
                    }
                    rotationFirstIndex = rotationFirstIndex + 1
                }
                sweep = sweep + 1
            }
        }
        if !converged {
            return Err(new BasicError(ErrorKind.Internal,
                "EigenDecomposition.ofSymmetric: did not converge"))
        }
        List<Double> values = []
        Int diagonalIndex = 0
        while diagonalIndex < size {
            values.push(working.get(diagonalIndex * size + diagonalIndex))
            diagonalIndex = diagonalIndex + 1
        }
        Int start = 0
        while start < size {
            Int best = start
            Int scan = start + 1
            while scan < size {
                if values.get(scan) > values.get(best) {
                    best = scan
                }
                scan = scan + 1
            }
            if best != start {
                Double temporary = values.get(start)
                values.set(start, values.get(best))
                values.set(best, temporary)
                rowIndex = 0
                while rowIndex < size {
                    Double firstVectorValue = vectors.get(rowIndex * size + start)
                    Double secondVectorValue = vectors.get(rowIndex * size + best)
                    vectors.set(rowIndex * size + start, secondVectorValue)
                    vectors.set(rowIndex * size + best, firstVectorValue)
                    rowIndex = rowIndex + 1
                }
            }
            start = start + 1
        }
        Int columnIndex = 0
        while columnIndex < size {
            Int pivotRow = 0
            Double maximum = abs(vectors.get(columnIndex))
            Int scanRow = 1
            while scanRow < size {
                Double magnitude = abs(vectors.get(scanRow * size + columnIndex))
                if magnitude > maximum {
                    maximum = magnitude
                    pivotRow = scanRow
                }
                scanRow = scanRow + 1
            }
            if vectors.get(pivotRow * size + columnIndex) < 0.0 {
                scanRow = 0
                while scanRow < size {
                    vectors.set(scanRow * size + columnIndex,
                        -vectors.get(scanRow * size + columnIndex))
                    scanRow = scanRow + 1
                }
            }
            columnIndex = columnIndex + 1
        }
        return Ok(new EigenDecomposition(new Vector(values),
            new Matrix(size, size, vectors)))
    }

    Vector values() { return _values }

    Matrix eigenvectors() { return _eigenvectors }
}
```
