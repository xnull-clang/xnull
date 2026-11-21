# `TensorShape`

| 项 | 值 |
| --- | --- |
| 类型 | `class TensorShape` |
| 包 | `xdk.tensor` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

不可变张量形状：维度列表、rank、元素数、标量判定、按维读取、替换一维、row-major 步长与扁平索引。

不做：dtype、数据存储、stride 视图、广播规则、维度命名（NCHW/NHWC 由上层约定）。

---

## 2. 设计逻辑

- 形状是值对象，但需要复制列表并在构造时校验，所以用 `class` 而不是 `struct`。
- 维度用 `Int`；元素数可能超过 `Int`，用 `Long`。
- 不变量在构造器建立；`withDim` 也走同一校验，不产生半合法形状。
- `rank == 0` 是标量，元素数为 1；`[1]` 是长度为 1 的向量，不是标量。
- 任一元为 0 → 元素数为 0；这是合法的空张量形状。
- `rowMajorStrides` 与 `flatIndex` 把布局约定集中在这里，`Tensor`/`TensorView` 不各自复制一份索引公式。
- 不可变；`dimensions()` 返回副本，避免调用方改写内部列表。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_dimensions` | `List<Int>` | final | 每维大小，均 ≥0 |
| `_elementCount` | `Long` | final | 所有维度的乘积；空列表为 1 |

不变量：列表非 null；每维 ≥0；`_elementCount` 等于各维乘积且不溢出 `Long`；空列表 ⇔ 标量；含 0 维时元素数为 0；列表私有且返回副本。

---

## 4. 生命周期

构造后不可变；无 close；可共享；无资源；无取消点。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `TensorShape(List<Int> dimensions)` | 维度列表 | 非 null；每维 ≥0；乘积可放入 `Long` | 违约 → panic |
| `withDim(Int dimensionIndex, Int dimensionSize)` | 维度下标与新大小 | 下标在 `[0, rank)`；新大小 ≥0；新乘积可放入 `Long` | 违约 → panic |

构造器复制输入列表；调用方之后修改原列表不影响形状。

---

## 6. 字段表

见 §3；字段私有，不暴露底层列表。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `rank` | 维度数 | 无 | `Int` | 无 | 标量为 0 |
| `elementCount` | 元素总数 | 无 | `Long` | 无 | 空列表为 1；含 0 维为 0 |
| `isScalar` | 是否标量 | 无 | `Bool` | 无 | `rank() == 0` |
| `dim` | 读取一维大小 | `Int dimensionIndex` | `Int` | 越界 → panic | 不改内部列表 |
| `dimensions` | 维度副本 | 无 | `List<Int>` | 无 | 新列表 |
| `withDim` | 替换一维 | `Int dimensionIndex, Int dimensionSize` | `TensorShape` | 越界/负值/溢出 → panic | 新实例 |
| `rowMajorStrides` | row-major 元素步长 | 无 | `List<Long>` | 无 | 长度等于 rank；空张量全 0 |
| `flatIndex` | 逻辑索引 → 扁平下标 | `List<Int> indices` | `Long` | rank 不符/越界 → panic | 标量用空列表 |
| `equals` | 形状值比较 | `TensorShape other` | `Bool` | `other == null` → false | 逐维比较 |
| `describe` | 单行描述 | 无 | `String` | 无 | 形如 `[2,3]` |
| `copy` | 复制 | 无 | `TensorShape` | 无 | 独立列表 |

复杂度：`rank/elementCount/isScalar/dim` 为 O(1)；`dimensions/copy/equals/describe` 为 O(rank)；`rowMajorStrides` 为 O(rank)；`flatIndex` 为 O(rank)。

---

## 8. 使用的技术

- 不可变值对象；
- 列表复制；
- 检查式 `Long` 乘法；
- row-major 步长计算；
- 逐维边界检查。

---

## 9. 需要的支撑

- 语言：class、final 字段、List、Int、Long、Bool、String；
- 运行时：列表复制、`Long` 检查乘法、字符串拼接；
- 接口：[`Tensor`](Tensor.md)、[`TensorOps`](TensorOps.md)、[`TensorView`](TensorView.md)。

---

## 10. 依赖的特性/接口/类

[`Tensor`](Tensor.md)、[`TensorView`](TensorView.md)、[`TensorOps`](TensorOps.md)、[`TensorDType`](TensorDType.md)。

---

## 11. 所有权与并发

不可变；可共享；`dimensions()` 返回副本；无资源；无取消点。  
相等：`equals` 是逐维值比较；`==` 仍是引用身份；由于没有冻结哈希契约，不推荐作 `Map` 键，需要时用 `describe()` 的规范文本作键。

---

## 12. 示例与反例

正确：`new TensorShape([])` 是标量，`elementCount() == 1`；`new TensorShape([2, 3]).flatIndex([1, 2]) == 5`；`shape.withDim(1, 4)` 返回新形状。  
反例：把 `[1]` 当标量；构造 `[-1, 3]` 期望得到空张量；把 `dimensions()` 的返回值当内部列表修改；用 `[1,2]` 去索引 rank 3 的形状；假设元素数一定放得进 `Int`。

---

## 13. 测试/场景义务

空列表/标量；一维/多维；含 0 维；负维 panic；乘积溢出 panic；`dim` 越界 panic；`withDim` 保留原对象；`rowMajorStrides` 与 `flatIndex` 对 `[2,3]`、`[2,3,4]`、`[0,3]` 的手算一致；空张量步长全 0；`equals`/`copy` 独立性；`describe` 稳定文本。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class TensorShape {
    final List<Int> _dimensions
    final Long _elementCount

    TensorShape(List<Int> dimensions) {
        if dimensions == null {
            throw "TensorShape: null dimensions"
        }
        _dimensions = dimensions.copy()
        Bool hasZeroDimension = false
        Int dimensionIndex = 0
        while dimensionIndex < _dimensions.length() {
            Int dimensionSize = _dimensions.get(dimensionIndex)
            if dimensionSize < 0 {
                throw "TensorShape: negative dimension"
            }
            if dimensionSize == 0 {
                hasZeroDimension = true
            }
            dimensionIndex = dimensionIndex + 1
        }
        Long count = 0
        if !hasZeroDimension {
            count = 1
            dimensionIndex = 0
            while dimensionIndex < _dimensions.length() {
                Int dimensionSize = _dimensions.get(dimensionIndex)
                if count > 9223372036854775807 / (dimensionSize as Long) {
                    throw "TensorShape: element count overflow"
                }
                count = count * (dimensionSize as Long)
                dimensionIndex = dimensionIndex + 1
            }
        }
        _elementCount = count
    }

    Int rank() { return _dimensions.length() }

    Long elementCount() { return _elementCount }

    Bool isScalar() { return _dimensions.length() == 0 }

    Int dim(Int dimensionIndex) {
        if dimensionIndex < 0 || dimensionIndex >= _dimensions.length() {
            throw "TensorShape.dim: dimension index out of range"
        }
        return _dimensions.get(dimensionIndex)
    }

    List<Int> dimensions() { return _dimensions.copy() }

    TensorShape withDim(Int dimensionIndex, Int dimensionSize) {
        if dimensionIndex < 0 || dimensionIndex >= _dimensions.length() {
            throw "TensorShape.withDim: dimension index out of range"
        }
        if dimensionSize < 0 {
            throw "TensorShape.withDim: negative dimension"
        }
        List<Int> updated = _dimensions.copy()
        updated.set(dimensionIndex, dimensionSize)
        return new TensorShape(updated)
    }

    List<Long> rowMajorStrides() {
        List<Long> strides = []
        Int dimensionIndex = 0
        while dimensionIndex < _dimensions.length() {
            strides.push(1)
            dimensionIndex = dimensionIndex + 1
        }
        if _elementCount == 0 {
            dimensionIndex = 0
            while dimensionIndex < strides.length() {
                strides.set(dimensionIndex, 0)
                dimensionIndex = dimensionIndex + 1
            }
            return strides
        }
        Long stride = 1
        dimensionIndex = _dimensions.length() - 1
        while dimensionIndex >= 0 {
            strides.set(dimensionIndex, stride)
            stride = stride * (_dimensions.get(dimensionIndex) as Long)
            dimensionIndex = dimensionIndex - 1
        }
        return strides
    }

    Long flatIndex(List<Int> indices) {
        if indices == null {
            throw "TensorShape.flatIndex: null indices"
        }
        if indices.length() != _dimensions.length() {
            throw "TensorShape.flatIndex: rank mismatch"
        }
        List<Long> strides = self.rowMajorStrides()
        Long flat = 0
        Int dimensionIndex = 0
        while dimensionIndex < _dimensions.length() {
            Int index = indices.get(dimensionIndex)
            Int dimensionSize = _dimensions.get(dimensionIndex)
            if index < 0 || index >= dimensionSize {
                throw "TensorShape.flatIndex: index out of range"
            }
            flat = flat + (index as Long) * strides.get(dimensionIndex)
            dimensionIndex = dimensionIndex + 1
        }
        return flat
    }

    Bool equals(TensorShape other) {
        if other == null {
            return false
        }
        if _dimensions.length() != other.rank() {
            return false
        }
        Int dimensionIndex = 0
        while dimensionIndex < _dimensions.length() {
            if _dimensions.get(dimensionIndex) != other.dim(dimensionIndex) {
                return false
            }
            dimensionIndex = dimensionIndex + 1
        }
        return true
    }

    String describe() {
        String text = "["
        Int dimensionIndex = 0
        while dimensionIndex < _dimensions.length() {
            if dimensionIndex > 0 {
                text = text + ","
            }
            text = text + str(_dimensions.get(dimensionIndex))
            dimensionIndex = dimensionIndex + 1
        }
        return text + "]"
    }

    TensorShape copy() {
        return new TensorShape(_dimensions)
    }
}
```
