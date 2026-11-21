# `TensorOps`

| 项 | 值 |
| --- | --- |
| 类型 | `class TensorOps`（静态算子） |
| 包 | `xdk.tensor` |
| 稳定性 | `preview` |
| 依赖 | `Tensor`、`TensorShape`、`TensorDType`、`Bytes` |

---

## 1. 定位

张量静态算子命名空间：创建、填充、从 `List<Double>` 装入、形状变换、逐元素加/乘、二维矩阵乘、求和。

不做：自动微分、GPU kernel、广播、批量矩阵乘、卷积、归约轴参数、dtype 提升、Bool 逻辑运算、原地写入。

---

## 2. 设计逻辑

- 无实例状态，用 `class` 只作为静态命名空间；私有构造器禁止 `new TensorOps()`。
- 所有算子返回新 `Tensor`；输入只读，不保留可变引用。
- dtype 规则冻结：
  - `zeros/ones/fill/fromDoubles` 支持五种 dtype；
  - `reshape/transpose` 对任意 dtype 只搬字节；
  - `add/mul/matmul/sum` 只支持数值 dtype（Float32/Float64/Int32/Int64），Bool 明确 panic；
  - 两个输入 dtype 必须相同，结果 dtype 相同；不做隐式提升。
- 形状是合同：不匹配直接 panic，错误文本包含算子名与失败类别；不返回 `Result`。
- 整数算术是检查式：每个加/乘步骤都检查目标 dtype 范围，溢出 panic，不回绕；Float32 以 `Double` 计算、写回时一次舍入到 binary32，超出范围会得到 ±Inf。
- 没有广播：所有逐元素算子要求形状完全相等；`matmul` 只接受 rank 2。
- `sum` 返回 0 维张量，dtype 与输入相同；整数和在 `Long` 中累加，最后检查目标 dtype 范围。
- `reshape` 不改变元素顺序；`transpose` 反转全部维度；两者都产生独立字节副本。

---

## 3. 表示与不变量

无实例字段；类不可实例化。

不变量：

- 任何公开算子都不修改输入张量；
- 任何返回的 `Tensor` 都通过构造器重新校验 dtype/shape/字节长度；
- 不缓存、不持有全局状态、不注册后端；
- 不进行未在 §2 写明的 dtype 转换；
- 整数结果必须在目标 dtype 范围内，否则 panic；
- 生成的 `Bool` 字节只能是 0/1。

---

## 4. 生命周期

类本身无生命周期；静态调用即用即走；无 close；无资源；无取消点。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `TensorOps()` | 无 | 私有；禁止外部实例化 | 外部 `new` 不可用 |

所有能力通过静态方法提供。

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `zeros` | 全 0 张量 | `TensorDType tensorDType, TensorShape tensorShape` | `Tensor` | 空参数 → panic | Bool 为 false |
| `ones` | 全 1 张量 | `TensorDType tensorDType, TensorShape tensorShape` | `Tensor` | 空参数 → panic | Bool 为 true |
| `fill` | 指定值填充 | `TensorDType tensorDType, TensorShape tensorShape, Double value` | `Tensor` | 空参数/值不合法 → panic | Bool 只接受 0/1 |
| `fromDoubles` | 从扁平数值装入 | `TensorDType tensorDType, TensorShape tensorShape, List<Double> values` | `Tensor` | 长度不等/值不合法 → panic | 顺序为 row-major；Int64 仅保证 Double 可精确表示的范围 |
| `reshape` | 改形状、保顺序 | `Tensor tensor, TensorShape tensorShape` | `Tensor` | null/元素数不等 → panic | 复制字节 |
| `transpose` | 反转全部维度 | `Tensor tensor` | `Tensor` | null → panic | rank 0/1 等价复制 |
| `add` | 逐元素加 | `Tensor left, Tensor right` | `Tensor` | null/dtype/形状不匹配、Bool、整数溢出 → panic | 结果 dtype 同输入 |
| `mul` | 逐元素乘 | `Tensor left, Tensor right` | `Tensor` | 同 `add` | 结果 dtype 同输入 |
| `matmul` | 二维矩阵乘 | `Tensor left, Tensor right` | `Tensor` | null/rank 非 2/内维不等/dtype 不匹配/Bool/溢出 → panic | `[m,k] × [k,n] → [m,n]` |
| `sum` | 全元素和 | `Tensor tensor` | `Tensor` | null/Bool/整数溢出 → panic | 0 维、同 dtype；空张量为 0 |

复杂度：创建/填充/装入/逐元素/求和为 O(elementCount)；`reshape` 为 O(elementCount)；`transpose` 为 O(elementCount)；`matmul` 为 O(m×k×n)。

---

## 8. 使用的技术

- 静态命名空间；
- 连续字节分配与 row-major 循环；
- 整数检查加/乘；
- Float32 单次舍入；
- 元素级字节复制；
- 多维扁平下标互转；
- 0 维结果张量。

---

## 9. 需要的支撑

- 语言：class、List、Int、Long、Double、Bool、String；
- 包：`Bytes` 分配/读写；`Tensor` 构造器与 `atFlat/atFlatLong`；`TensorShape`；`TensorDType`；
- 数值原语：`tensorDTypeByteWidth`、`tensorDTypeIsFloatingPoint`、`tensorDTypeIsInteger`、`tensorByteLength`、`validateTensorElementValue`、`checkDTypeRange`；
- 检查算术：`checkedAddLong`、`checkedMultiplyLong`（溢出或越界时 panic）；
- 编解码：`readTensorDouble`、`readTensorLong`、`writeTensorDouble`、`writeTensorLong`；
- 扁平化：`flatToIndices`；元素复制：`copyTensorElement`；
- 数学：`sqrt`、`floor`、`isFinite`（由值校验原语使用）。

---

## 10. 依赖的特性/接口/类

[`Tensor`](Tensor.md)、[`TensorShape`](TensorShape.md)、[`TensorDType`](TensorDType.md)、[`Bytes`](../../core/bytes/Bytes.md)。

---

## 11. 所有权与并发

静态；无共享可变状态；输入只借用，输出为新 `Tensor`；结果与输入字节独立。  
可并发调用；无 close；无取消点。  
相等：类不可实例化，无实例相等语义。

---

## 12. 示例与反例

正确：`Tensor tensor = TensorOps.fromDoubles(TensorDType.Float64, new TensorShape([2, 3]), values)`；`TensorOps.add(tensor, tensor)`；`TensorOps.matmul(left, right)`；`TensorOps.sum(tensor).at([])`。  
反例：`add` 两个 `[2,3]` 与 `[3,2]` 期望广播；`add` 把 `Int32` 与 `Float64` 混用；对 Bool 调 `add`；期望整数溢出回绕；期望 `sum` 返回 `Double`；把 `reshape` 后的结果当原张量的别名；用 `transpose` 改变原张量。

---

## 13. 测试/场景义务

五种 dtype 的 zeros/ones/fill/fromDoubles；Bool 非法值；values 长度不匹配；reshape 元素数不匹配；reshape 保持 row-major 顺序；transpose 对 rank 0/1/2/3；add/mul 的 dtype/形状不匹配；整数溢出；Float32 舍入；matmul 方阵/非方阵/内维不匹配/rank 非 2；sum 的标量/空张量/Int32 溢出/Int64 累加；结果与输入独立；NaN/Inf 传播；超过字节上限的创建。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class TensorOps {
    private TensorOps() {}

    static Tensor zeros(TensorDType tensorDType, TensorShape tensorShape) {
        return TensorOps.fill(tensorDType, tensorShape, 0.0)
    }

    static Tensor ones(TensorDType tensorDType, TensorShape tensorShape) {
        return TensorOps.fill(tensorDType, tensorShape, 1.0)
    }

    static Tensor fill(TensorDType tensorDType, TensorShape tensorShape, Double value) {
        if tensorDType == null || tensorShape == null {
            throw "TensorOps.fill: null argument"
        }
        validateTensorElementValue(tensorDType, value)
        Bytes data = TensorOps.allocateTensorData(tensorDType, tensorShape)
        Long elementIndex = 0
        while elementIndex < tensorShape.elementCount() {
            writeTensorDouble(data, tensorDType, elementIndex, value)
            elementIndex = elementIndex + 1
        }
        return new Tensor(tensorDType, tensorShape, data)
    }

    static Tensor fromDoubles(TensorDType tensorDType, TensorShape tensorShape,
                              List<Double> values) {
        if tensorDType == null || tensorShape == null || values == null {
            throw "TensorOps.fromDoubles: null argument"
        }
        if (values.length() as Long) != tensorShape.elementCount() {
            throw "TensorOps.fromDoubles: value count mismatch"
        }
        Bytes data = TensorOps.allocateTensorData(tensorDType, tensorShape)
        Int index = 0
        while index < values.length() {
            Double value = values.get(index)
            validateTensorElementValue(tensorDType, value)
            writeTensorDouble(data, tensorDType, index as Long, value)
            index = index + 1
        }
        return new Tensor(tensorDType, tensorShape, data)
    }

    static Tensor reshape(Tensor tensor, TensorShape tensorShape) {
        if tensor == null || tensorShape == null {
            throw "TensorOps.reshape: null argument"
        }
        if tensor.elementCount() != tensorShape.elementCount() {
            throw "TensorOps.reshape: element count mismatch"
        }
        Bytes data = TensorOps.allocateTensorData(tensor.tensorDType(), tensorShape)
        Long elementIndex = 0
        while elementIndex < tensor.elementCount() {
            copyTensorElement(tensor, elementIndex, data, elementIndex)
            elementIndex = elementIndex + 1
        }
        return new Tensor(tensor.tensorDType(), tensorShape, data)
    }

    static Tensor transpose(Tensor tensor) {
        if tensor == null {
            throw "TensorOps.transpose: null tensor"
        }
        TensorShape sourceShape = tensor.tensorShape()
        List<Int> reversedDimensions = []
        Int dimensionIndex = sourceShape.rank() - 1
        while dimensionIndex >= 0 {
            reversedDimensions.push(sourceShape.dim(dimensionIndex))
            dimensionIndex = dimensionIndex - 1
        }
        TensorShape targetShape = new TensorShape(reversedDimensions)
        Bytes data = TensorOps.allocateTensorData(tensor.tensorDType(), targetShape)
        Long sourceIndex = 0
        while sourceIndex < tensor.elementCount() {
            List<Int> sourceIndices = flatToIndices(sourceShape, sourceIndex)
            List<Int> targetIndices = []
            Int cursor = sourceIndices.length() - 1
            while cursor >= 0 {
                targetIndices.push(sourceIndices.get(cursor))
                cursor = cursor - 1
            }
            Long targetIndex = targetShape.flatIndex(targetIndices)
            copyTensorElement(tensor, sourceIndex, data, targetIndex)
            sourceIndex = sourceIndex + 1
        }
        return new Tensor(tensor.tensorDType(), targetShape, data)
    }

    static Tensor add(Tensor left, Tensor right) {
        if left == null || right == null {
            throw "TensorOps.add: null argument"
        }
        validateNumericTensorDType(left.tensorDType())
        if left.tensorDType() != right.tensorDType() {
            throw "TensorOps.add: dtype mismatch"
        }
        if !left.tensorShape().equals(right.tensorShape()) {
            throw "TensorOps.add: shape mismatch"
        }
        TensorDType tensorDType = left.tensorDType()
        TensorShape tensorShape = left.tensorShape()
        Bytes data = TensorOps.allocateTensorData(tensorDType, tensorShape)
        Long elementIndex = 0
        if tensorDTypeIsInteger(tensorDType) {
            while elementIndex < tensorShape.elementCount() {
                Long result = checkedAddLong(left.atFlatLong(elementIndex),
                    right.atFlatLong(elementIndex), tensorDType)
                writeTensorLong(data, tensorDType, elementIndex, result)
                elementIndex = elementIndex + 1
            }
        } else {
            while elementIndex < tensorShape.elementCount() {
                Double result = left.atFlat(elementIndex) + right.atFlat(elementIndex)
                writeTensorDouble(data, tensorDType, elementIndex, result)
                elementIndex = elementIndex + 1
            }
        }
        return new Tensor(tensorDType, tensorShape, data)
    }

    static Tensor mul(Tensor left, Tensor right) {
        if left == null || right == null {
            throw "TensorOps.mul: null argument"
        }
        validateNumericTensorDType(left.tensorDType())
        if left.tensorDType() != right.tensorDType() {
            throw "TensorOps.mul: dtype mismatch"
        }
        if !left.tensorShape().equals(right.tensorShape()) {
            throw "TensorOps.mul: shape mismatch"
        }
        TensorDType tensorDType = left.tensorDType()
        TensorShape tensorShape = left.tensorShape()
        Bytes data = TensorOps.allocateTensorData(tensorDType, tensorShape)
        Long elementIndex = 0
        if tensorDTypeIsInteger(tensorDType) {
            while elementIndex < tensorShape.elementCount() {
                Long result = checkedMultiplyLong(left.atFlatLong(elementIndex),
                    right.atFlatLong(elementIndex), tensorDType)
                writeTensorLong(data, tensorDType, elementIndex, result)
                elementIndex = elementIndex + 1
            }
        } else {
            while elementIndex < tensorShape.elementCount() {
                Double result = left.atFlat(elementIndex) * right.atFlat(elementIndex)
                writeTensorDouble(data, tensorDType, elementIndex, result)
                elementIndex = elementIndex + 1
            }
        }
        return new Tensor(tensorDType, tensorShape, data)
    }

    static Tensor matmul(Tensor left, Tensor right) {
        if left == null || right == null {
            throw "TensorOps.matmul: null argument"
        }
        validateNumericTensorDType(left.tensorDType())
        if left.tensorDType() != right.tensorDType() {
            throw "TensorOps.matmul: dtype mismatch"
        }
        if left.rank() != 2 || right.rank() != 2 {
            throw "TensorOps.matmul: rank must be 2"
        }
        Int leftRows = left.tensorShape().dim(0)
        Int leftColumns = left.tensorShape().dim(1)
        Int rightRows = right.tensorShape().dim(0)
        Int rightColumns = right.tensorShape().dim(1)
        if leftColumns != rightRows {
            throw "TensorOps.matmul: inner dimension mismatch"
        }
        List<Int> resultDimensions = []
        resultDimensions.push(leftRows)
        resultDimensions.push(rightColumns)
        TensorShape resultShape = new TensorShape(resultDimensions)
        TensorDType tensorDType = left.tensorDType()
        Bytes data = TensorOps.allocateTensorData(tensorDType, resultShape)
        Int rowIndex = 0
        while rowIndex < leftRows {
            Int columnIndex = 0
            while columnIndex < rightColumns {
                if tensorDTypeIsInteger(tensorDType) {
                    Long total = 0
                    Int innerIndex = 0
                    while innerIndex < leftColumns {
                        Long leftValue = left.atFlatLong(
                            (rowIndex as Long) * (leftColumns as Long)
                                + (innerIndex as Long))
                        Long rightValue = right.atFlatLong(
                            (innerIndex as Long) * (rightColumns as Long)
                                + (columnIndex as Long))
                        Long product = checkedMultiplyLong(
                            leftValue, rightValue, tensorDType)
                        total = checkedAddLong(total, product, tensorDType)
                        innerIndex = innerIndex + 1
                    }
                    writeTensorLong(data, tensorDType,
                        (rowIndex as Long) * (rightColumns as Long)
                            + (columnIndex as Long), total)
                } else {
                    Double total = 0.0
                    Int innerIndex = 0
                    while innerIndex < leftColumns {
                        Double leftValue = left.atFlat(
                            (rowIndex as Long) * (leftColumns as Long)
                                + (innerIndex as Long))
                        Double rightValue = right.atFlat(
                            (innerIndex as Long) * (rightColumns as Long)
                                + (columnIndex as Long))
                        total = total + leftValue * rightValue
                        innerIndex = innerIndex + 1
                    }
                    writeTensorDouble(data, tensorDType,
                        (rowIndex as Long) * (rightColumns as Long)
                            + (columnIndex as Long), total)
                }
                columnIndex = columnIndex + 1
            }
            rowIndex = rowIndex + 1
        }
        return new Tensor(tensorDType, resultShape, data)
    }

    static Tensor sum(Tensor tensor) {
        if tensor == null {
            throw "TensorOps.sum: null tensor"
        }
        validateNumericTensorDType(tensor.tensorDType())
        TensorDType tensorDType = tensor.tensorDType()
        TensorShape scalarShape = new TensorShape([])
        Bytes data = TensorOps.allocateTensorData(tensorDType, scalarShape)
        if tensorDTypeIsInteger(tensorDType) {
            Long total = 0
            Long elementIndex = 0
            while elementIndex < tensor.elementCount() {
                total = checkedAddLong(total, tensor.atFlatLong(elementIndex), tensorDType)
                elementIndex = elementIndex + 1
            }
            writeTensorLong(data, tensorDType, 0, total)
        } else {
            Double total = 0.0
            Long elementIndex = 0
            while elementIndex < tensor.elementCount() {
                total = total + tensor.atFlat(elementIndex)
                elementIndex = elementIndex + 1
            }
            writeTensorDouble(data, tensorDType, 0, total)
        }
        return new Tensor(tensorDType, scalarShape, data)
    }

    private static Bytes allocateTensorData(TensorDType tensorDType,
                                            TensorShape tensorShape) {
        Long byteCount = tensorByteLength(tensorDType, tensorShape)
        if byteCount > 2147483647 {
            throw "TensorOps: tensor exceeds byte length limit"
        }
        return Bytes.alloc(byteCount as Int)
    }
}
```

> `validateNumericTensorDType`、`flatToIndices`、`checkedAddLong`、`checkedMultiplyLong`、`copyTensorElement` 是包内数值/布局原语，不是公开 API；其合同见 §9。
