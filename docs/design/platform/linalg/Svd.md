# `Svd`

| 项 | 值 |
| --- | --- |
| 类型 | `class Svd` |
| 包 | `xdk.linalg` |
| 稳定性 | `preview` |
| 依赖 | `Matrix`、`Vector`、`EigenDecomposition` |

---

## 1. 定位

实矩阵的 economy 奇异值分解：`A = U diag(s) Vᵀ`，只保留 `k = min(rows, columns)` 个奇异三元组；提供奇异值、U、Vᵀ、数值秩、条件数。

不做：全 SVD、复数、稀疏、批处理、截断 SVD、增量更新、GPU、BLAS/LAPACK 绑定。

---

## 2. 设计逻辑

- economy 形状：高矩阵 `U` 为 m×n、`Vᵀ` 为 n×n；宽矩阵 `U` 为 m×m、`Vᵀ` 为 m×n。
- 基线实现复用对称特征分解：
  - 高矩阵：对 `AᵀA` 先对称化，再做对称特征分解得到 `V` 与 `s²`，再算 `U = A V / s`；
  - 宽矩阵：对 `AAᵀ` 先对称化，再做对称特征分解得到 `U` 与 `s²`，再算 `V = Aᵀ U / s`。
- 这条路径的代价是条件数被平方：`cond(AᵀA) = cond(A)²`。因此基线只适合小到中等、条件数不极端的矩阵；高精度 SVD 是 X。
- 零奇异值对应的列用标准基做 Gram-Schmidt 补全，保证 U/V 的半正交性；补全失败返回 `Internal`。
- 奇异值降序；每列做符号规范：非零奇异值对应 U 列的绝对值最大分量取正，同时翻转 Vᵀ 对应行，保持 `A = U S Vᵀ`。
- 秩与条件数使用固定相对阈值 `1e-12`；它们是数值诊断，不是精确代数秩。
- 不可变；U/S/Vᵀ 构造后不再改变。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_u` | `Matrix` | final | m×k 左奇异向量 |
| `_singularValues` | `Vector` | final | k 个非负奇异值，降序 |
| `_vt` | `Matrix` | final | k×n 右奇异向量转置 |
| `_rank` | `Int` | final | 数值秩，0..k |

不变量：`k = min(m,n)`；`_u` 为 m×k；`_singularValues.length() == k`；`_vt` 为 k×n；`UᵀU = I_k`、`VᵀV = I_k`（浮点误差内）；`A = U diag(s) Vᵀ`；奇异值降序且 ≥0；`_rank` 按阈值计算；构造后不可变。

---

## 4. 生命周期

由 `decompose` 创建；不可变；无 close；无资源；可共享；无取消点。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Svd.decompose(Matrix matrix)` | 任意非空实矩阵 | 非 null；行/列 ≥1；所有元素有限 | 空/非有限 → `InvalidArgument`；内部特征分解/补全失败 → 传播其 `Error`（通常 `Internal`） |
| 私有构造器 | U/奇异值/Vᵀ | 仅工厂调用；已校验 | 不对外 |

`decompose` 不修改输入矩阵。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `decompose` | economy SVD | `Matrix matrix` | `Result<Svd, Error>` | 空/非有限 → `InvalidArgument`；内部失败 → 传播 | 高矩阵 O(m×n²+n³)；宽矩阵 O(n×m²+m³) |
| `u` | 左奇异向量 | 无 | `Matrix` | 无 | m×k，共享不可变引用 |
| `singularValues` | 奇异值 | 无 | `Vector` | 无 | k 个，降序 |
| `vt` | 右奇异向量转置 | 无 | `Matrix` | 无 | k×n |
| `rank` | 数值秩 | 无 | `Int` | 无 | 相对阈值 |
| `condition` | 条件数 | 无 | `Double` | 无 | 最小奇异值为 0 → `Inf()` |

---

## 8. 使用的技术

- Gram 矩阵 + 对称化 + 对称特征分解；
- economy 形状裁剪；
- 零列 Gram-Schmidt 补全；
- 奇异值降序；
- U 列符号规范；
- 相对秩/条件数阈值；
- `Result` 失败通道。

---

## 9. 需要的支撑

- 语言：class、final 字段、List、Int、Double、Bool、Result、Unit；
- 数学：`abs`、`sqrt`、`isFinite`、`Inf`；
- 错误：`BasicError`、`ErrorKind.InvalidArgument`、`ErrorKind.Internal`；
- 接口：[`Matrix`](Matrix.md)、[`Vector`](Vector.md)、[`EigenDecomposition`](EigenDecomposition.md)、[`Linalg`](Linalg.md)。

---

## 10. 依赖的特性/接口/类

[`Matrix`](Matrix.md)、[`Vector`](Vector.md)、[`EigenDecomposition`](EigenDecomposition.md)、[`QrDecomposition`](QrDecomposition.md)、[`Linalg`](Linalg.md)。

---

## 11. 所有权与并发

不可变；可共享；`u()/singularValues()/vt()` 返回不可变引用；无资源；无取消点。  
相等：引用身份；不提供 `equals`；不作为 `Map` 键。

---

## 12. 示例与反例

正确：`Svd.decompose(matrix)`；`u().multiply(diagonal).multiply(vt()) ≈ matrix`；`singularValues()` 降序；`rank()`/`condition()` 用于诊断。  
反例：把 economy SVD 当全 SVD（`u()` 不是 m×m）；忽略条件数平方误差，用基线处理高度病态矩阵；假设零奇异值对应的 U/V 列唯一；用 `rank()` 做精确代数秩；在非有限输入上忽略 `Err`。

---

## 13. 测试/场景义务

1×1；高矩阵/宽矩阵/方阵；满秩/秩亏/零矩阵；Gram 对称化；重复奇异值；非有限/空矩阵；`UᵀU ≈ I`、`VᵀV ≈ I`；重构误差；奇异值降序/非负；`rank` 阈值；`condition` 的零最小奇异值 → `Inf`；符号规范；`decompose` 不改原矩阵；内部补全失败路径（测试变体）。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class Svd {
    final Matrix _u
    final Vector _singularValues
    final Matrix _vt
    final Int _rank

    private Svd(Matrix leftSingularVectors, Vector singularValues,
                Matrix rightSingularVectorsTranspose) {
        _u = leftSingularVectors
        _singularValues = singularValues
        _vt = rightSingularVectorsTranspose
        Double maximum = 0.0
        if singularValues.length() > 0 {
            maximum = singularValues.get(0)
        }
        Double threshold = maximum * 1e-12
        Int rank = 0
        Int index = 0
        while index < singularValues.length() {
            if singularValues.get(index) > threshold {
                rank = rank + 1
            }
            index = index + 1
        }
        _rank = rank
    }

    static Result<Svd, Error> decompose(Matrix matrix) {
        if matrix == null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Svd.decompose: null matrix"))
        }
        Int rowCount = matrix.rowCount()
        Int columnCount = matrix.columnCount()
        if rowCount == 0 || columnCount == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Svd.decompose: empty matrix"))
        }
        Int rowIndex = 0
        while rowIndex < rowCount {
            Int columnIndex = 0
            while columnIndex < columnCount {
                if !isFinite(matrix.get(rowIndex, columnIndex)) {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "Svd.decompose: non-finite element"))
                }
                columnIndex = columnIndex + 1
            }
            rowIndex = rowIndex + 1
        }
        if rowCount >= columnCount {
            return Svd.decomposeTall(matrix)
        }
        return Svd.decomposeWide(matrix)
    }

    private static Result<Svd, Error> decomposeTall(Matrix matrix) {
        Int rowCount = matrix.rowCount()
        Int columnCount = matrix.columnCount()
        Matrix gram = Svd.symmetrize(matrix.transpose().multiply(matrix))
        Result<EigenDecomposition, Error> eigenResult =
            EigenDecomposition.ofSymmetric(gram)
        if eigenResult.isErr() {
            return Err(eigenResult.error())
        }
        EigenDecomposition eigen = eigenResult.value()
        Vector eigenvalues = eigen.values()
        Matrix eigenvectors = eigen.eigenvectors()
        Double maximumEigenvalue = abs(eigenvalues.get(0))
        Double negativeTolerance = 1e-12 * maximumEigenvalue
        List<Double> singularValues = []
        Int index = 0
        while index < columnCount {
            Double eigenvalue = eigenvalues.get(index)
            Double sigma = 0.0
            if eigenvalue > 0.0 {
                sigma = sqrt(eigenvalue)
            } else if eigenvalue < -negativeTolerance {
                return Err(new BasicError(ErrorKind.Internal,
                    "Svd.decomposeTall: negative Gram eigenvalue"))
            }
            singularValues.push(sigma)
            index = index + 1
        }
        List<Double> uValues = []
        Int rowIndex = 0
        while rowIndex < rowCount {
            Int columnIndex = 0
            while columnIndex < columnCount {
                uValues.push(0.0)
                columnIndex = columnIndex + 1
            }
            rowIndex = rowIndex + 1
        }
        index = 0
        while index < columnCount {
            Double sigma = singularValues.get(index)
            if sigma > 0.0 {
                rowIndex = 0
                while rowIndex < rowCount {
                    Double total = 0.0
                    Int innerIndex = 0
                    while innerIndex < columnCount {
                        total = total + matrix.get(rowIndex, innerIndex)
                            * eigenvectors.get(innerIndex, index)
                        innerIndex = innerIndex + 1
                    }
                    uValues.set(rowIndex * columnCount + index, total / sigma)
                    rowIndex = rowIndex + 1
                }
            }
            index = index + 1
        }
        Result<Unit, Error> completion = Svd.completeOrthonormalColumns(
            uValues, rowCount, columnCount)
        if completion.isErr() {
            return Err(completion.error())
        }
        List<Double> vtValues = eigenvectors.transpose().toList()
        Svd.normalizeSvdSigns(uValues, rowCount, columnCount,
            vtValues, columnCount, singularValues)
        return Ok(new Svd(new Matrix(rowCount, columnCount, uValues),
            new Vector(singularValues),
            new Matrix(columnCount, columnCount, vtValues)))
    }

    private static Result<Svd, Error> decomposeWide(Matrix matrix) {
        Int rowCount = matrix.rowCount()
        Int columnCount = matrix.columnCount()
        Matrix gram = Svd.symmetrize(matrix.multiply(matrix.transpose()))
        Result<EigenDecomposition, Error> eigenResult =
            EigenDecomposition.ofSymmetric(gram)
        if eigenResult.isErr() {
            return Err(eigenResult.error())
        }
        EigenDecomposition eigen = eigenResult.value()
        Vector eigenvalues = eigen.values()
        Matrix eigenvectors = eigen.eigenvectors()
        Double maximumEigenvalue = abs(eigenvalues.get(0))
        Double negativeTolerance = 1e-12 * maximumEigenvalue
        List<Double> singularValues = []
        Int index = 0
        while index < rowCount {
            Double eigenvalue = eigenvalues.get(index)
            Double sigma = 0.0
            if eigenvalue > 0.0 {
                sigma = sqrt(eigenvalue)
            } else if eigenvalue < -negativeTolerance {
                return Err(new BasicError(ErrorKind.Internal,
                    "Svd.decomposeWide: negative Gram eigenvalue"))
            }
            singularValues.push(sigma)
            index = index + 1
        }
        List<Double> uValues = eigenvectors.toList()
        List<Double> vValues = []
        Int columnIndex = 0
        while columnIndex < columnCount {
            Int singularIndex = 0
            while singularIndex < rowCount {
                vValues.push(0.0)
                singularIndex = singularIndex + 1
            }
            columnIndex = columnIndex + 1
        }
        index = 0
        while index < rowCount {
            Double sigma = singularValues.get(index)
            if sigma > 0.0 {
                columnIndex = 0
                while columnIndex < columnCount {
                    Double total = 0.0
                    Int innerIndex = 0
                    while innerIndex < rowCount {
                        total = total + matrix.get(innerIndex, columnIndex)
                            * eigenvectors.get(innerIndex, index)
                        innerIndex = innerIndex + 1
                    }
                    vValues.set(columnIndex * rowCount + index, total / sigma)
                    columnIndex = columnIndex + 1
                }
            }
            index = index + 1
        }
        Result<Unit, Error> completion = Svd.completeOrthonormalColumns(
            vValues, columnCount, rowCount)
        if completion.isErr() {
            return Err(completion.error())
        }
        List<Double> vtValues = []
        Int targetRow = 0
        while targetRow < rowCount {
            Int targetColumn = 0
            while targetColumn < columnCount {
                vtValues.push(vValues.get(targetColumn * rowCount + targetRow))
                targetColumn = targetColumn + 1
            }
            targetRow = targetRow + 1
        }
        Svd.normalizeSvdSigns(uValues, rowCount, rowCount,
            vtValues, columnCount, singularValues)
        return Ok(new Svd(new Matrix(rowCount, rowCount, uValues),
            new Vector(singularValues),
            new Matrix(rowCount, columnCount, vtValues)))
    }

    private static Matrix symmetrize(Matrix matrix) {
        Int size = matrix.rowCount()
        List<Double> values = []
        Int rowIndex = 0
        while rowIndex < size {
            Int columnIndex = 0
            while columnIndex < size {
                Double average = (matrix.get(rowIndex, columnIndex)
                    + matrix.get(columnIndex, rowIndex)) / 2.0
                values.push(average)
                columnIndex = columnIndex + 1
            }
            rowIndex = rowIndex + 1
        }
        return new Matrix(size, size, values)
    }

    private static Result<Unit, Error> completeOrthonormalColumns(
            List<Double> columns, Int rowCount, Int columnCount) {
        Int columnIndex = 0
        while columnIndex < columnCount {
            Double normSquared = 0.0
            Int rowIndex = 0
            while rowIndex < rowCount {
                Double value = columns.get(rowIndex * columnCount + columnIndex)
                normSquared = normSquared + value * value
                rowIndex = rowIndex + 1
            }
            if sqrt(normSquared) > 1e-12 {
                columnIndex = columnIndex + 1
                continue
            }
            Bool filled = false
            Int candidateIndex = 0
            while candidateIndex < rowCount && !filled {
                List<Double> candidate = []
                rowIndex = 0
                while rowIndex < rowCount {
                    if rowIndex == candidateIndex {
                        candidate.push(1.0)
                    } else {
                        candidate.push(0.0)
                    }
                    rowIndex = rowIndex + 1
                }
                Int otherColumn = 0
                while otherColumn < columnCount {
                    if otherColumn != columnIndex {
                        Double projection = 0.0
                        rowIndex = 0
                        while rowIndex < rowCount {
                            projection = projection + candidate.get(rowIndex)
                                * columns.get(rowIndex * columnCount + otherColumn)
                            rowIndex = rowIndex + 1
                        }
                        rowIndex = 0
                        while rowIndex < rowCount {
                            candidate.set(rowIndex, candidate.get(rowIndex)
                                - projection * columns.get(
                                    rowIndex * columnCount + otherColumn))
                            rowIndex = rowIndex + 1
                        }
                    }
                    otherColumn = otherColumn + 1
                }
                Double candidateNormSquared = 0.0
                rowIndex = 0
                while rowIndex < rowCount {
                    candidateNormSquared = candidateNormSquared
                        + candidate.get(rowIndex) * candidate.get(rowIndex)
                    rowIndex = rowIndex + 1
                }
                Double candidateNorm = sqrt(candidateNormSquared)
                if candidateNorm > 1e-12 {
                    rowIndex = 0
                    while rowIndex < rowCount {
                        columns.set(rowIndex * columnCount + columnIndex,
                            candidate.get(rowIndex) / candidateNorm)
                        rowIndex = rowIndex + 1
                    }
                    filled = true
                }
                candidateIndex = candidateIndex + 1
            }
            if !filled {
                return Err(new BasicError(ErrorKind.Internal,
                    "Svd: cannot complete orthonormal basis"))
            }
            columnIndex = columnIndex + 1
        }
        return Ok(unit)
    }

    private static void normalizeSvdSigns(List<Double> uValues, Int uRowCount,
                                          Int rankSize, List<Double> vtValues,
                                          Int vtColumnCount,
                                          List<Double> singularValues) {
        Int singularIndex = 0
        while singularIndex < rankSize {
            if singularValues.get(singularIndex) > 0.0 {
                Int pivotRow = 0
                Double maximum = abs(uValues.get(singularIndex))
                Int rowIndex = 1
                while rowIndex < uRowCount {
                    Double magnitude = abs(
                        uValues.get(rowIndex * rankSize + singularIndex))
                    if magnitude > maximum {
                        maximum = magnitude
                        pivotRow = rowIndex
                    }
                    rowIndex = rowIndex + 1
                }
                if uValues.get(pivotRow * rankSize + singularIndex) < 0.0 {
                    rowIndex = 0
                    while rowIndex < uRowCount {
                        uValues.set(rowIndex * rankSize + singularIndex,
                            -uValues.get(rowIndex * rankSize + singularIndex))
                        rowIndex = rowIndex + 1
                    }
                    Int columnIndex = 0
                    while columnIndex < vtColumnCount {
                        vtValues.set(singularIndex * vtColumnCount + columnIndex,
                            -vtValues.get(
                                singularIndex * vtColumnCount + columnIndex))
                        columnIndex = columnIndex + 1
                    }
                }
            }
            singularIndex = singularIndex + 1
        }
    }

    Matrix u() { return _u }

    Vector singularValues() { return _singularValues }

    Matrix vt() { return _vt }

    Int rank() { return _rank }

    Double condition() {
        if _singularValues.length() == 0 {
            return Inf()
        }
        Double maximum = _singularValues.get(0)
        Double minimum = _singularValues.get(_singularValues.length() - 1)
        if minimum <= 0.0 {
            return Inf()
        }
        return maximum / minimum
    }
}
```

> 基线 SVD 走 Gram 矩阵路径，条件数会被平方；需要高精度/病态矩阵时使用 X 的单边 Jacobi 或其他稳定实现，公共 API 形状不变。
