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

不做：写入、负步长、跨张量拼接、切片语法糖、所有权转移、close、GPU 视图。

---

## 2. 设计逻辑

- 用 `class`：视图需要保存基张量引用、形状、步长和偏移，且必须做边界校验。
- 只读：基 `Tensor` 不可变，因此视图永远看到一致数据；不提供 `withValue`，避免“视图写回基张量”的别名语义。
- 无 copy：`at` 通过 `offset + Σ(index × stride)` 计算基张量扁平下标；只有 `toTensor` 才复制。
- 步长用元素数，不用字节；非负步长让边界检查可单调计算，也避免反向视图的复杂生命周期。
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
- 非空视图：`offset + Σ((dim(i)−1) × stride(i)) < base.elementCount()`；
- 空视图：`offset ≤ base.elementCount()`；
- 视图只读；`_strides` 私有且构造时复制。

---

## 4. 生命周期

由 `of` 创建；借用基张量；无 close；GC 管理引用；基张量不可变，因此视图无需失效通知。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `TensorView.of(Tensor baseTensor, TensorShape tensorShape, List<Long> strides, Long elementOffset)` | 基张量、形状、步长、偏移 | 非 null；rank 相等；stride ≥0；offset ≥0；所有可达下标在基张量内 | 违约 → panic |

构造器私有；`of` 是唯一公开入口。`transpose()` 通过私有构造器创建新视图，复用已验证的边界。

---

## 6. 字段表

见 §3；字段私有，不暴露基张量数据。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `of` | 创建视图 | `Tensor baseTensor, TensorShape tensorShape, List<Long> strides, Long elementOffset` | `TensorView` | 空/rank/负值/越界 → panic | 复制步长列表 |
| `baseTensor` | 基张量 | 无 | `Tensor` | 无 | 共享不可变引用 |
| `tensorShape` | 视图形状 | 无 | `TensorShape` | 无 | 不可变 |
| `rank` | 维度数 | 无 | `Int` | 无 | 委托 shape |
| `elementCount` | 元素数 | 无 | `Long` | 无 | 委托 shape |
| `stride` | 某维步长 | `Int dimensionIndex` | `Long` | 越界 → panic | 元素单位 |
| `offset` | 起点偏移 | 无 | `Long` | 无 | 元素单位 |
| `at` | 按视图索引读 | `List<Int> indices` | `Double` | rank/越界 → panic | 不复制；Bool 映射 0/1；Int64 大值用 `atLong` |
| `atLong` | 按视图索引读整数 | `List<Int> indices` | `Long` | dtype 非整数/rank/越界 → panic | 保留 Int64 精度 |
| `isContiguous` | 是否 row-major 连续 | 无 | `Bool` | 无 | 只比较步长 |
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
反例：对视图调用 `set`/`withValue` 期望写回基张量；视图 `close()`；用负 stride 做反向视图；假设视图一定连续；构造 offset 超出基张量的视图；视图套视图。

---

## 13. 测试/场景义务

连续视图与非连续视图；转置视图的 `at`/`atLong`；offset 非零；rank 0/1/多维；含 0 维；`at/atLong` 越界 panic；构造越界 panic；stride 长度不符 panic；`isContiguous` 正反例；`toTensor` 与基元素一致且副本独立；`baseTensor()` 身份；`transpose` 维度/步长反转；`describe`。

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
        Int dimensionIndex = 0
        while dimensionIndex < strides.length() {
            if strides.get(dimensionIndex) < 0 {
                throw "TensorView.of: negative stride"
            }
            dimensionIndex = dimensionIndex + 1
        }
        if tensorShape.elementCount() == 0 {
            if elementOffset > baseTensor.elementCount() {
                throw "TensorView.of: empty view offset out of range"
            }
        } else {
            Long maximumElementIndex = elementOffset
            dimensionIndex = 0
            while dimensionIndex < tensorShape.rank() {
                Int dimensionSize = tensorShape.dim(dimensionIndex)
                if dimensionSize > 0 {
                    maximumElementIndex = maximumElementIndex
                        + ((dimensionSize - 1) as Long) * strides.get(dimensionIndex)
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
