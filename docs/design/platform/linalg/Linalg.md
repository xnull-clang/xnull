# `Linalg`

| 项 | 值 |
| --- | --- |
| 类型 | `class Linalg`（静态算子） |
| 包 | `xdk.linalg` |
| 稳定性 | `preview` |
| 依赖 | `Vector`、`Matrix`、`LuDecomposition`、`Tensor` |

---

## 1. 定位

线性代数静态门面：点积、叉积、范数、线性系统求解、求逆、行列式、迹、单位阵，以及二维张量桥接。

不做：复数、稀疏、迭代求解、最小二乘（用 `QrDecomposition`）、SVD/特征分解（用对应类）、BLAS/LAPACK 绑定、GPU。

---

## 2. 设计逻辑

- 无实例状态；私有构造器禁止 `new Linalg()`。
- `dot/norm` 委托 `Vector`；`solve/inverse/determinant` 委托 `LuDecomposition`，避免重复消元逻辑。
- 方阵要求是合同：`solve/inverse/determinant/trace` 对非方阵直接 panic。
- 奇异/非有限输入走 `Result`：`solve/inverse` 返回 `Err`；`determinant` 对非有限输入返回 `NaN`，对奇异返回 `0.0`。
- `inverse` 只分解一次，然后对 n 个单位基向量求解；结果按 row-major 组装。
- 张量桥接默认 `Float64`；`matrixFromTensor` 拒绝 Bool 与非二维，`tensorFromMatrix` 不失败（除分配上限）。
- 不暴露 BLAS/LAPACK；当前实现是纯 XNull 语义，未来可替换内核而不改公共 API。
- 无复数：一般非对称特征值/复数矩阵是 X。

---

## 3. 表示与不变量

无实例字段；类不可实例化。

不变量：

- 所有方法不修改输入；
- 返回的 `Vector`/`Matrix` 都是新对象或不可变共享对象；
- 方阵检查在入口完成；
- 不缓存分解、不持有全局后端；
- 张量桥接只处理 rank 2，Bool 明确拒绝。

---

## 4. 生命周期

类本身无生命周期；静态调用；无 close；无资源；无取消点。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Linalg()` | 无 | 私有；禁止外部实例化 | 外部 `new` 不可用 |

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `dot` | 向量点积 | `Vector left, Vector right` | `Double` | null/长度不等 → panic | 委托 `Vector.dot` |
| `cross` | 三维叉积 | `Vector left, Vector right` | `Vector` | null/长度非 3 → panic | 右手系 |
| `norm` | 欧氏范数 | `Vector vector` | `Double` | null → panic | 委托 `Vector.norm` |
| `solve` | 解 `A x = b` | `Matrix matrix, Vector rightHandSide` | `Result<Vector, Error>` | 非方阵/长度不符 → panic；奇异/非有限 → `InvalidArgument` | 方阵 |
| `inverse` | 逆矩阵 | `Matrix matrix` | `Result<Matrix, Error>` | 非方阵 → panic；奇异/非有限 → `InvalidArgument` | 方阵；O(n³) |
| `determinant` | 行列式 | `Matrix matrix` | `Double` | 非方阵 → panic | 奇异 0.0；非有限/空矩阵 NaN |
| `trace` | 迹 | `Matrix matrix` | `Double` | 非方阵 → panic | 对角线和 |
| `identity` | 单位阵 | `Int size` | `Matrix` | 负值/过大 → panic | size×size |
| `matrixFromTensor` | 二维张量 → 矩阵 | `Tensor tensor` | `Result<Matrix, Error>` | rank 非 2 → `InvalidArgument`；Bool → `Unsupported` | 元素转 `Double`；Int64 超出 2^53 可能丢精度 |
| `tensorFromMatrix` | 矩阵 → 二维张量 | `Matrix matrix` | `Tensor` | null/过大 → panic | `Float64` |

---

## 8. 使用的技术

- 静态门面；
- LU 分解复用；
- 单位基列求解求逆；
- 方阵/长度检查；
- 张量/矩阵转换；
- `Result` 与 `NaN` 的失败语义。

---

## 9. 需要的支撑

- 语言：class、List、Int、Long、Double、Bool、Result；
- 数学：`NaN`；
- 错误：`BasicError`、`ErrorKind.InvalidArgument`、`ErrorKind.Unsupported`；
- 接口：[`Vector`](Vector.md)、[`Matrix`](Matrix.md)、[`LuDecomposition`](LuDecomposition.md)、[`Tensor`](../tensor/Tensor.md)、[`TensorOps`](../tensor/TensorOps.md)、[`TensorShape`](../tensor/TensorShape.md)、[`TensorDType`](../tensor/TensorDType.md)。

---

## 10. 依赖的特性/接口/类

[`Vector`](Vector.md)、[`Matrix`](Matrix.md)、[`LuDecomposition`](LuDecomposition.md)、[`QrDecomposition`](QrDecomposition.md)、[`Svd`](Svd.md)、[`EigenDecomposition`](EigenDecomposition.md)、[`Tensor`](../tensor/Tensor.md)、[`TensorOps`](../tensor/TensorOps.md)。

---

## 11. 所有权与并发

静态；无共享可变状态；输入只借用，输出为新对象或不可变共享对象。  
可并发调用；无 close；无取消点。  
相等：类不可实例化，无实例相等语义。

---

## 12. 示例与反例

正确：`Linalg.solve(matrix, rightHandSide)`；`Linalg.inverse(matrix)` 处理 `Err`；`Linalg.determinant(matrix)`；`Linalg.identity(3)`；`Linalg.matrixFromTensor(tensor)` 只传 rank 2 张量。  
反例：对非方阵调用 `solve` 并期望 `Err`（实际是 panic）；忽略 `inverse` 的 `Err`；把 `determinant` 的 0.0 当“可逆”；对 Bool 张量做桥接；期望复数支持；期望 BLAS 级性能。

---

## 13. 测试/场景义务

`dot/norm` 委托一致性；`cross` 的基向量/平行向量；`solve` 方阵/奇异/非有限/长度不符；`inverse` 乘原矩阵 ≈ I；`determinant` 与 LU 一致；`trace`；`identity` 0/1/n；`matrixFromTensor` 的 rank/Bool/Int64；`tensorFromMatrix` 的 dtype/shape；输入不被修改；非方阵 panic；并发只读。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class Linalg {
    private Linalg() {}

    static Double dot(Vector left, Vector right) {
        if left == null || right == null {
            throw "Linalg.dot: null vector"
        }
        return left.dot(right)
    }

    static Vector cross(Vector left, Vector right) {
        if left == null || right == null {
            throw "Linalg.cross: null vector"
        }
        if left.length() != 3 || right.length() != 3 {
            throw "Linalg.cross: vectors must have length 3"
        }
        List<Double> result = []
        result.push(left.get(1) * right.get(2) - left.get(2) * right.get(1))
        result.push(left.get(2) * right.get(0) - left.get(0) * right.get(2))
        result.push(left.get(0) * right.get(1) - left.get(1) * right.get(0))
        return new Vector(result)
    }

    static Double norm(Vector vector) {
        if vector == null {
            throw "Linalg.norm: null vector"
        }
        return vector.norm()
    }

    static Result<Vector, Error> solve(Matrix matrix, Vector rightHandSide) {
        if matrix == null || rightHandSide == null {
            throw "Linalg.solve: null argument"
        }
        if matrix.rowCount() != matrix.columnCount() {
            throw "Linalg.solve: matrix must be square"
        }
        Result<LuDecomposition, Error> factorResult =
            LuDecomposition.factor(matrix)
        if factorResult.isErr() {
            return Err(factorResult.error())
        }
        return factorResult.value().solve(rightHandSide)
    }

    static Result<Matrix, Error> inverse(Matrix matrix) {
        if matrix == null {
            throw "Linalg.inverse: null matrix"
        }
        if matrix.rowCount() != matrix.columnCount() {
            throw "Linalg.inverse: matrix must be square"
        }
        Int size = matrix.rowCount()
        Long elementCount = (size as Long) * (size as Long)
        if elementCount > 2147483647 {
            throw "Linalg.inverse: matrix too large"
        }
        Result<LuDecomposition, Error> factorResult =
            LuDecomposition.factor(matrix)
        if factorResult.isErr() {
            return Err(factorResult.error())
        }
        LuDecomposition decomposition = factorResult.value()
        List<Double> values = []
        Long index = 0
        while index < elementCount {
            values.push(0.0)
            index = index + 1
        }
        Int columnIndex = 0
        while columnIndex < size {
            List<Double> basis = []
            Int rowIndex = 0
            while rowIndex < size {
                if rowIndex == columnIndex {
                    basis.push(1.0)
                } else {
                    basis.push(0.0)
                }
                rowIndex = rowIndex + 1
            }
            Result<Vector, Error> columnResult =
                decomposition.solve(new Vector(basis))
            if columnResult.isErr() {
                return Err(columnResult.error())
            }
            Vector column = columnResult.value()
            rowIndex = 0
            while rowIndex < size {
                values.set(rowIndex * size + columnIndex, column.get(rowIndex))
                rowIndex = rowIndex + 1
            }
            columnIndex = columnIndex + 1
        }
        return Ok(new Matrix(size, size, values))
    }

    static Double determinant(Matrix matrix) {
        if matrix == null {
            throw "Linalg.determinant: null matrix"
        }
        if matrix.rowCount() != matrix.columnCount() {
            throw "Linalg.determinant: matrix must be square"
        }
        Result<LuDecomposition, Error> factorResult =
            LuDecomposition.factor(matrix)
        if factorResult.isErr() {
            return NaN()
        }
        return factorResult.value().determinant()
    }

    static Double trace(Matrix matrix) {
        if matrix == null {
            throw "Linalg.trace: null matrix"
        }
        if matrix.rowCount() != matrix.columnCount() {
            throw "Linalg.trace: matrix must be square"
        }
        Double total = 0.0
        Int diagonalIndex = 0
        while diagonalIndex < matrix.rowCount() {
            total = total + matrix.get(diagonalIndex, diagonalIndex)
            diagonalIndex = diagonalIndex + 1
        }
        return total
    }

    static Matrix identity(Int size) {
        if size < 0 {
            throw "Linalg.identity: negative size"
        }
        Long elementCount = (size as Long) * (size as Long)
        if elementCount > 2147483647 {
            throw "Linalg.identity: matrix too large"
        }
        List<Double> values = []
        Int rowIndex = 0
        while rowIndex < size {
            Int columnIndex = 0
            while columnIndex < size {
                if rowIndex == columnIndex {
                    values.push(1.0)
                } else {
                    values.push(0.0)
                }
                columnIndex = columnIndex + 1
            }
            rowIndex = rowIndex + 1
        }
        return new Matrix(size, size, values)
    }

    static Result<Matrix, Error> matrixFromTensor(Tensor tensor) {
        if tensor == null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Linalg.matrixFromTensor: null tensor"))
        }
        if tensor.rank() != 2 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Linalg.matrixFromTensor: tensor rank must be 2"))
        }
        if tensor.tensorDType() == TensorDType.Bool {
            return Err(new BasicError(ErrorKind.Unsupported,
                "Linalg.matrixFromTensor: bool tensor is not supported"))
        }
        TensorShape tensorShape = tensor.tensorShape()
        return Ok(new Matrix(tensorShape.dim(0), tensorShape.dim(1),
            tensor.toDoubles()))
    }

    static Tensor tensorFromMatrix(Matrix matrix) {
        if matrix == null {
            throw "Linalg.tensorFromMatrix: null matrix"
        }
        List<Int> dimensions = []
        dimensions.push(matrix.rowCount())
        dimensions.push(matrix.columnCount())
        TensorShape tensorShape = new TensorShape(dimensions)
        return TensorOps.fromDoubles(TensorDType.Float64, tensorShape,
            matrix.toList())
    }
}
```
