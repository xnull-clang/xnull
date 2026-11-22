# `TensorView`

| 项 | 值 |
| --- | --- |
| 类型 | `class TensorView` |
| 包 | `xdk.tensor` |
| 稳定性 | `preview` |
| 依赖 | `Tensor`、`TensorShape` |

---

## 1. 定位

对 `Tensor` 的只读、零拷贝视图：用 offset、shape、stride 描述另一组逻辑索引，不移动数据。

不做：写入、负步长、广播（含 stride 0 扩展）、跨张量拼接、切片语法糖、所有权转移、close、GPU 视图。

---

## 2. 设计逻辑

- 用 `class`：视图需要保存基张量引用、形状、步长和偏移，且必须做边界校验。
- 只读：基 `Tensor` 不可变，因此视图永远看到一致数据；不提供 `withValue`，避免“视图写回基张量”的别名语义。
- 无 copy：`at` 通过 `offset + Σ(index × stride)` 计算基张量扁平下标；只有 `toTensor` 才复制。
- 步长用元素数，不用字节；非负步长让边界检查可单调计算，也避免反向视图的复杂生命周期。
- 不做广播：视图不通过 stride 0 把同一元素暴露给多个逻辑索引。非空视图中 `dim > 1` 的维度 stride 0 是构造错误；只有 `dim <= 1` 的维度或整个空视图允许 stride 0。
- 最大基元素下标用带检查的 `Long` 乘加计算；任何溢出都在构造时 panic，不回绕、不截断。
- 只允许基于 `Tensor` 建视图，不允许视图套视图；这样 rank/边界/偏移只有一层。
- 不持有资源，故不提供 `close`；基张量由引用保持存活。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_baseTensor` | `Tensor` | final | 被观察的基张量 |
| `_tensorShape` | `TensorShape` | final | 视图逻辑形状 |
| `_strides` | `List<Long>` | final | 每个维度的元素步长，均 ≥0 |
| `_elementOffset` | `Long` | final | 视图起点在基张量中的元素偏移，≥0 |

不变量：

- `_baseTensor`、`_tensorShape`、`_strides` 非 null；
- `_strides.length() == _tensorShape.rank()`；
- 每个 stride ≥0，offset ≥0；
- 非空视图（`elementCount > 0`）：对每个 `dim(i) > 1` 的维度，`stride(i) > 0`；`dim(i) == 0` 或 `dim(i) == 1` 的维度允许 `stride(i) == 0`；
- 空视图（任一维为 0）：所有 stride 允许为 0（也可为正）；此时不存在可读取下标，stride 不影响可观察结果；`TensorShape.rowMajorStrides()` 对空形状返回全 0，构造空视图必须接受；
- 非空视图：`offset + Σ((dim(i)−1) × stride(i))` 用带检查的 `Long` 乘加计算，且结果 `< base.elementCount()`；任何中间溢出 → panic；
- 空视图：`offset ≤ base.elementCount()`，无需计算最大下标；
- 视图只读；`_strides` 私有且构造时复制。

---

## 4. 生命周期

由 `of` 创建；借用基张量；无 close；GC 管理引用；基张量不可变，因此视图无需失效通知。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `TensorView.of(Tensor baseTensor, TensorShape tensorShape, List<Long> strides, Long elementOffset)` | 基张量、形状、步长、偏移 | 非 null；rank 相等；stride ≥0；offset ≥0；非空视图 `dim > 1` 的维度 `stride > 0`；空视图允许全 0 步长；最大下标用带检查的 `Long` 乘加计算且不溢出、不越界 | 违约或 `Long` 溢出 → panic |

构造器私有；`of` 是唯一公开入口。`transpose()` 通过私有构造器创建新视图，只重排已验证的 shape/stride，不改变可达下标集合，因此复用同一不变量。

**stride 0 政策（冻结）**：`TensorView` 不做广播。非空视图（`elementCount > 0`）中，`dim > 1` 的维度 stride 必须 `> 0`；`stride == 0` → `of` panic（`TensorView.of: stride 0 on non-empty dimension`）。`dim == 0` 或 `dim == 1` 的维度允许 stride 0，因为至多只有一个可寻址索引。空视图（任一维为 0）接受全 0 步长，因为没有任何可读取下标；这与 `TensorShape.rowMajorStrides()` 对空形状返回全 0 对齐。该例外不是广播，不得用它读取或物化出多个元素。

**溢出失败语义**：`of` 用带检查的 `Long` 乘法与加法计算 `offset + Σ((dim−1)×stride)`。任何中间结果超出 `Long` → panic（`TensorView.of: maximum element index overflow`）；不得回绕、截断后继续边界比较。失败是调用方违约，统一 panic，不返回 `Result`，不产生半构造视图。

---

## 6. 字段表

见 §3；字段私有，不暴露基张量数据。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `of` | 创建视图 | `Tensor baseTensor, TensorShape tensorShape, List<Long> strides, Long elementOffset` | `TensorView` | 空/rank/负值/非空维 stride 0/越界/`Long` 溢出 → panic | 复制步长列表；不做广播 |
| `baseTensor` | 基张量 | 无 | `Tensor` | 无 | 共享不可变引用 |
| `tensorShape` | 视图形状 | 无 | `TensorShape` | 无 | 不可变 |
| `rank` | 维度数 | 无 | `Int` | 无 | 委托 shape |
| `elementCount` | 元素数 | 无 | `Long` | 无 | 委托 shape |
| `stride` | 某维步长 | `Int dimensionIndex` | `Long` | 越界 → panic | 元素单位；0 仅出现在 size ≤1 维或空视图 |
| `offset` | 起点偏移 | 无 | `Long` | 无 | 元素单位 |
| `at` | 按视图索引读 | `List<Int> indices` | `Double` | rank/越界 → panic | 不复制；构造已保证下标不溢出；Bool 映射 0/1；Int64 大值用 `atLong` |
| `atLong` | 按视图索引读整数 | `List<Int> indices` | `Long` | dtype 非整数/rank/越界 → panic | 构造已保证下标不溢出；保留 Int64 精度 |
| `isContiguous` | 是否 row-major 连续 | 无 | `Bool` | 无 | 严格比较 `rowMajorStrides`；size ≤1 维的 0 步长不特殊放宽 |
| `transpose` | 反转所有维度 | 无 | `TensorView` | 无 | 仍是视图 |
| `toTensor` | 物化为独立张量 | 无 | `Tensor` | 过大 → panic | 保留原始元素字节 |
| `describe` | 单行描述 | 无 | `String` | 无 | shape/offset |

复杂度：`at/atLong` 为 O(rank)；`isContiguous` 为 O(rank)；`transpose` 为 O(rank)；`toTensor` 为 O(elementCount)。

---

## 8. 使用的技术

- 步长索引；
- 惰性视图；
- 边界预校验；
- 里程表式多维遍历（物化）；
- 元素级字节复制。

---

## 9. 需要的支撑

- 语言：class、final 字段、List、Int、Long、Double、Bool、String；
- 运行时/包：`Bytes.alloc`、`Tensor.atFlat`、`Tensor.atFlatLong`、`Tensor` 构造器；
- 包内原语：`copyTensorElement(Tensor source, Long sourceElementIndex, Bytes targetData, Long targetElementIndex)`；`tensorByteLength(TensorDType, TensorShape)`；
- 接口：[`Tensor`](Tensor.md)、[`TensorShape`](TensorShape.md)、[`TensorDType`](TensorDType.md)。

---

## 10. 依赖的特性/接口/类

[`Tensor`](Tensor.md)、[`TensorShape`](TensorShape.md)、[`TensorDType`](TensorDType.md)。

---

## 11. 所有权与并发

视图不拥有基张量，只保持引用；`of` 复制步长列表；`baseTensor()` 返回共享的不可变基张量；`toTensor()` 返回独立副本。  
基张量不可变，因此视图可共享、可并发读取；无 close；无取消点。  
相等：引用身份；不提供 `equals`；不作为 `Map` 键。需要值比较时用 `toTensor().equals(other)`。

---

## 12. 示例与反例

正确：`TensorView view = TensorView.of(tensor, new TensorShape([3, 2]), [1, 3], 0)`；`view.transpose()` 反转维度；`view.toTensor()` 得到连续副本。

正确：`new TensorShape([1, 3])` 配 `[0, 1]`；size 1 维的 stride 0 合法，只对应唯一索引，不是广播。

正确：空形状 `new TensorShape([0, 3])` 配 `[0, 0]`；空视图允许全 0 步长，`elementCount() == 0`，`toTensor()` 为空。

正确：构造参数使最大下标恰好为 `base.elementCount() − 1` 时通过；再大或 `Long` 溢出时 panic。

反例：对视图调用 `set`/`withValue` 期望写回基张量；视图 `close()`；用负 stride 做反向视图；假设视图一定连续；构造 offset 超出基张量的视图；视图套视图；用 stride 0 在 `dim > 1` 的非空维上做广播；假设空视图的 stride 0 可以读取元素或物化出非空数据；期望 `offset + Σ` 溢出后回绕并继续构造。

---

## 13. 测试/场景义务

连续视图与非连续视图；转置视图的 `at`/`atLong`；offset 非零；rank 0/1/多维；含 0 维；`at/atLong` 越界 panic；构造越界 panic；stride 长度不符 panic；非空视图 `dim > 1` 且 stride 0 → panic（不是广播）；`dim == 1` 的 stride 0 可构造且 `at` 只命中唯一索引；空视图（如 `[0,3]` 配 `[0,0]`）可构造、`elementCount() == 0`、`toTensor()` 为空；最大下标恰好等于 `base.elementCount() − 1` 通过；`offset + Σ` 的乘法或加法溢出 → panic 且消息含 `overflow`，不回绕；`isContiguous` 正反例（含 `[1,3]` 配 `[0,1]`：非广播但严格比较为 false）；`toTensor` 与基元素一致且副本独立；`baseTensor()` 身份；`transpose` 维度/步长反转；`describe`。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class TensorView {
    final Tensor _baseTensor
    final TensorShape _tensorShape
    final List<Long> _strides
    final Long _elementOffset

    private TensorView(Tensor baseTensor, TensorShape tensorShape,
                       List<Long> strides, Long elementOffset) {
        _baseTensor = baseTensor
        _tensorShape = tensorShape
        _strides = strides.copy()
        _elementOffset = elementOffset
    }

    // 合同级辅助：参数均为非负 Long；溢出时 panic，不回绕。
    private static Long checkedAddLong(Long left, Long right, String message) {
        if left > 9223372036854775807 - right {
            throw message
        }
        return left + right
    }

    private static Long checkedMultiplyLong(Long left, Long right, String message) {
        if left == 0 || right == 0 {
            return 0
        }
        if left > 9223372036854775807 / right {
            throw message
        }
        return left * right
    }

    static TensorView of(Tensor baseTensor, TensorShape tensorShape,
                         List<Long> strides, Long elementOffset) {
        if baseTensor == null || tensorShape == null || strides == null {
            throw "TensorView.of: null argument"
        }
        if strides.length() != tensorShape.rank() {
            throw "TensorView.of: stride rank mismatch"
        }
        if elementOffset < 0 {
            throw "TensorView.of: negative offset"
        }
        Long viewElementCount = tensorShape.elementCount()
        Int dimensionIndex = 0
        while dimensionIndex < strides.length() {
            Long dimensionStride = strides.get(dimensionIndex)
            if dimensionStride < 0 {
                throw "TensorView.of: negative stride"
            }
            if viewElementCount > 0
                && tensorShape.dim(dimensionIndex) > 1
                && dimensionStride == 0 {
                throw "TensorView.of: stride 0 on non-empty dimension"
            }
            dimensionIndex = dimensionIndex + 1
        }
        if viewElementCount == 0 {
            if elementOffset > baseTensor.elementCount() {
                throw "TensorView.of: empty view offset out of range"
            }
        } else {
            Long maximumElementIndex = elementOffset
            dimensionIndex = 0
            while dimensionIndex < tensorShape.rank() {
                Int dimensionSize = tensorShape.dim(dimensionIndex)
                if dimensionSize > 1 {
                    Long term = checkedMultiplyLong(
                        (dimensionSize - 1) as Long,
                        strides.get(dimensionIndex),
                        "TensorView.of: maximum element index overflow")
                    maximumElementIndex = checkedAddLong(
                        maximumElementIndex,
                        term,
                        "TensorView.of: maximum element index overflow")
                }
                dimensionIndex = dimensionIndex + 1
            }
            if maximumElementIndex >= baseTensor.elementCount() {
                throw "TensorView.of: view exceeds base tensor"
            }
        }
        return new TensorView(baseTensor, tensorShape, strides, elementOffset)
    }

    Tensor baseTensor() { return _baseTensor }

    TensorShape tensorShape() { return _tensorShape }

    Int rank() { return _tensorShape.rank() }

    Long elementCount() { return _tensorShape.elementCount() }

    Long stride(Int dimensionIndex) {
        if dimensionIndex < 0 || dimensionIndex >= _strides.length() {
            throw "TensorView.stride: dimension index out of range"
        }
        return _strides.get(dimensionIndex)
    }

    Long offset() { return _elementOffset }

    Double at(List<Int> indices) {
        if indices == null {
            throw "TensorView.at: null indices"
        }
        if indices.length() != _tensorShape.rank() {
            throw "TensorView.at: rank mismatch"
        }
        // 构造已用 checked Long 验证最大下标；索引都在维内，后续乘加不会溢出。
        Long baseElementIndex = _elementOffset
        Int dimensionIndex = 0
        while dimensionIndex < _tensorShape.rank() {
            Int index = indices.get(dimensionIndex)
            Int dimensionSize = _tensorShape.dim(dimensionIndex)
            if index < 0 || index >= dimensionSize {
                throw "TensorView.at: index out of range"
            }
            baseElementIndex = baseElementIndex
                + (index as Long) * _strides.get(dimensionIndex)
            dimensionIndex = dimensionIndex + 1
        }
        return _baseTensor.atFlat(baseElementIndex)
    }

    Long atLong(List<Int> indices) {
        if indices == null {
            throw "TensorView.atLong: null indices"
        }
        if indices.length() != _tensorShape.rank() {
            throw "TensorView.atLong: rank mismatch"
        }
        // 构造已用 checked Long 验证最大下标；索引都在维内，后续乘加不会溢出。
        Long baseElementIndex = _elementOffset
        Int dimensionIndex = 0
        while dimensionIndex < _tensorShape.rank() {
            Int index = indices.get(dimensionIndex)
            Int dimensionSize = _tensorShape.dim(dimensionIndex)
            if index < 0 || index >= dimensionSize {
                throw "TensorView.atLong: index out of range"
            }
            baseElementIndex = baseElementIndex
                + (index as Long) * _strides.get(dimensionIndex)
            dimensionIndex = dimensionIndex + 1
        }
        return _baseTensor.atFlatLong(baseElementIndex)
    }

    Bool isContiguous() {
        List<Long> expected = _tensorShape.rowMajorStrides()
        Int dimensionIndex = 0
        while dimensionIndex < _strides.length() {
            if _strides.get(dimensionIndex) != expected.get(dimensionIndex) {
                return false
            }
            dimensionIndex = dimensionIndex + 1
        }
        return true
    }

    TensorView transpose() {
        List<Int> reversedDimensions = []
        List<Long> reversedStrides = []
        Int dimensionIndex = _tensorShape.rank() - 1
        while dimensionIndex >= 0 {
            reversedDimensions.push(_tensorShape.dim(dimensionIndex))
            reversedStrides.push(_strides.get(dimensionIndex))
            dimensionIndex = dimensionIndex - 1
        }
        TensorShape transposedShape = new TensorShape(reversedDimensions)
        return new TensorView(_baseTensor, transposedShape,
            reversedStrides, _elementOffset)
    }

    Tensor toTensor() {
        Long byteCount = tensorByteLength(_baseTensor.tensorDType(), _tensorShape)
        if byteCount > 2147483647 {
            throw "TensorView.toTensor: tensor exceeds byte length limit"
        }
        Bytes data = Bytes.alloc(byteCount as Int)
        List<Int> indices = []
        Int dimensionIndex = 0
        while dimensionIndex < _tensorShape.rank() {
            indices.push(0)
            dimensionIndex = dimensionIndex + 1
        }
        Long targetElementIndex = 0
        while targetElementIndex < _tensorShape.elementCount() {
            Long sourceElementIndex = _elementOffset
            dimensionIndex = 0
            while dimensionIndex < _tensorShape.rank() {
                sourceElementIndex = sourceElementIndex
                    + (indices.get(dimensionIndex) as Long) * _strides.get(dimensionIndex)
                dimensionIndex = dimensionIndex + 1
            }
            copyTensorElement(_baseTensor, sourceElementIndex,
                data, targetElementIndex)
            Int cursor = _tensorShape.rank() - 1
            while cursor >= 0 {
                Int nextIndex = indices.get(cursor) + 1
                if nextIndex < _tensorShape.dim(cursor) {
                    indices.set(cursor, nextIndex)
                    break
                }
                indices.set(cursor, 0)
                cursor = cursor - 1
            }
            targetElementIndex = targetElementIndex + 1
        }
        return new Tensor(_baseTensor.tensorDType(), _tensorShape, data)
    }

    String describe() {
        return "view shape=" + _tensorShape.describe()
            + " offset=" + str(_elementOffset)
            + " contiguous=" + str(self.isContiguous())
    }
}
```
