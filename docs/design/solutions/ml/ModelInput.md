# `ModelInput`

| 项 | 值 |
| --- | --- |
| 类型 | `class ModelInput` |
| 包 | `xdk.ml` |
| 稳定性 | `preview` |
| 依赖 | `TensorDType`、`TensorShape`、`Tensor` |

---

## 1. 定位

单个模型输入的静态声明：名称、元素类型、每维大小、哪些维度是动态的。

只描述“运行时接受的张量形状合同”，不携带数据、批大小、预处理规则或设备放置。动态维度表示该轴长度由调用方决定，不做广播/补齐。

不做：可选输入、默认值、填充、截断、布局转换（NCHW/NHWC）、量化参数、名称别名。

---

## 2. 设计逻辑

- 用 `class`：需要复制两个并行列表、校验长度一致，并把“动态轴”表达成显式布尔列表，而不是用负数哨兵。
- `_dimensions` 与 `_dimensionDynamic` 一一对应；动态轴声明值必须为 `0`，实际值在 `run` 时接受任意非负长度。
- 固定轴用 `_dimensions[i]` 精确匹配；固定轴允许 `0`，表示合法的空张量维度。
- `rank` 等于列表长度；`rank == 0` 是标量输入，两个列表都为空。
- 不提供“可选输入”：基线 `InferenceSession.run` 接收位置对应的 `List<Tensor>`，缺输入用数量不足显式失败；可选输入是 X。
- `accepts` 只做 dtype/rank/维度合同，不做数值范围、NaN、布局或批次语义检查。
- 不可变；两个列表返回副本；可安全共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_name` | `String` | final | 非空输入名 |
| `_tensorDType` | `TensorDType` | final | 非 null |
| `_dimensions` | `List<Int>` | final | 每维 ≥0；动态轴为 0 |
| `_dimensionDynamic` | `List<Bool>` | final | 与维度等长；元素非 null |

不变量：名称非空；dtype 非 null；两个列表非 null、等长；每维 ≥0；动态轴声明值为 0；固定轴可为 0；列表私有且返回副本。

---

## 4. 生命周期

构造后不可变；无 close；无资源；可跨任务共享；无取消点。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ModelInput(String name, TensorDType tensorDType, List<Int> dimensions, List<Bool> dimensionDynamic)` | 名称、dtype、维度、动态标志 | name 非空；dtype 非 null；两列表非 null、等长；维度 ≥0；动态轴维度为 0；标志元素非 null | 违约 → panic |

构造器复制两个列表；调用方之后修改原列表不影响声明。

---

## 6. 字段表

见 §3；字段私有。不暴露张量数据、批次大小或设备信息。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `name` | 输入名 | 无 | `String` | 无 | 非空 |
| `tensorDType` | 元素类型 | 无 | `TensorDType` | 无 | O(1) |
| `dimensions` | 维度副本 | 无 | `List<Int>` | 无 | 动态轴为 0 |
| `dimensionDynamic` | 动态标志副本 | 无 | `List<Bool>` | 无 | 与维度等长 |
| `rank` | 维度数 | 无 | `Int` | 无 | 标量为 0 |
| `hasDynamicDimensions` | 是否含动态轴 | 无 | `Bool` | 无 | O(rank) |
| `fixedShape` | 固定形状 | 无 | `TensorShape?` | 无 | 含动态轴 → null |
| `accepts` | 张量是否匹配 | `Tensor tensor` | `Bool` | null → false | 不检查数值 |
| `describe` | 单行描述 | 无 | `String` | 无 | 动态轴显示 `?` |
| `equals` | 声明值比较 | `ModelInput other` | `Bool` | null → false | 逐字段比较 |
| `copy` | 复制 | 无 | `ModelInput` | 无 | 独立列表 |

说明：

- `accepts` 要求 dtype 相同、rank 相同；固定轴长度精确相等；动态轴接受任意 `Int` 长度。
- `fixedShape` 只对完全固定声明返回 `TensorShape`；动态声明返回 `null`，调用方必须先用 `accepts` 或读取维度。
- `equals` 比较名称、dtype、维度、动态标志；不比较运行时数据。
- 不提供 `withDimension`/`withDynamic` 修改器；需要变更时用构造器创建新声明。
- 名称在同一 `Model` 的输入列表中必须唯一，由 [`Model`](Model.md) 校验；本类只保证非空。

---

## 8. 使用的技术

- 不可变值对象；
- 并行列表 + 长度校验；
- 显式动态轴标志；
- 形状合同匹配；
- 列表复制与逐字段比较。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Bool、Int、List；
- 张量：`TensorDType`、`TensorShape`、`Tensor` 的 dtype/rank/dim 读取；
- 接口：[`Model`](Model.md)、[`ModelOutput`](ModelOutput.md)、[`InferenceSession`](InferenceSession.md)。

---

## 10. 依赖的特性/接口/类

[`TensorDType`](../../platform/tensor/TensorDType.md)、[`TensorShape`](../../platform/tensor/TensorShape.md)、[`Tensor`](../../platform/tensor/Tensor.md)、[`Model`](Model.md)、[`ModelOutput`](ModelOutput.md)、[`InferenceSession`](InferenceSession.md)。

不重复定义张量类型；不依赖具体模型格式或运行时。

---

## 11. 所有权与并发

不可变；可共享；列表返回副本；`accepts` 只读传入张量；无资源；无取消点。  
相等：`equals` 按声明值比较；`==` 是引用身份；不推荐作 `Map` 键（比较 O(rank) 且无冻结哈希）。

---

## 12. 示例与反例

正确：`new ModelInput("input_ids", TensorDType.Int32, [1, 128], [true, false])` 表示动态批次、固定序列长度 128；`new ModelInput("x", TensorDType.Float32, [1, 3, 224, 224], [false, false, false, false])` 表示固定输入；标量用空列表。  
反例：用 `-1` 表示动态维度；把动态轴声明为固定 0；用 `accepts` 检查数值范围/NaN；期望可选输入可省略；把 NCHW 当 NHWC 并假定运行时自动转置；修改 `dimensions()` 返回值并期望声明变化。

---

## 13. 测试/场景义务

名称空串 panic；dtype null panic；列表 null/不等长 panic；负维度 panic；动态轴声明非 0 panic；动态标志 null panic；标量、固定、单动态、多动态；`accepts` 的 dtype/rank/固定维不匹配；动态维任意长度；`fixedShape` 固定/动态；`equals`/`copy` 独立性；`describe` 稳定文本。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class ModelInput {
    final String _name
    final TensorDType _tensorDType
    final List<Int> _dimensions
    final List<Bool> _dimensionDynamic

    ModelInput(String name, TensorDType tensorDType, List<Int> dimensions,
               List<Bool> dimensionDynamic) {
        if name == null || tensorDType == null {
            throw "ModelInput: null name or dtype"
        }
        if dimensions == null || dimensionDynamic == null {
            throw "ModelInput: null dimension list"
        }
        if name == "" {
            throw "ModelInput: empty name"
        }
        if dimensions.length() != dimensionDynamic.length() {
            throw "ModelInput: dimension flag length mismatch"
        }
        _dimensions = dimensions.copy()
        _dimensionDynamic = dimensionDynamic.copy()
        Int dimensionIndex = 0
        while dimensionIndex < _dimensions.length() {
            Int dimensionSize = _dimensions.get(dimensionIndex)
            Bool dynamic = _dimensionDynamic.get(dimensionIndex)
            if dimensionSize < 0 {
                throw "ModelInput: negative dimension"
            }
            if dynamic == null {
                throw "ModelInput: null dynamic flag"
            }
            if dynamic && dimensionSize != 0 {
                throw "ModelInput: dynamic dimension must be declared as 0"
            }
            dimensionIndex = dimensionIndex + 1
        }
        _name = name
        _tensorDType = tensorDType
    }

    String name() { return _name }
    TensorDType tensorDType() { return _tensorDType }
    List<Int> dimensions() { return _dimensions.copy() }
    List<Bool> dimensionDynamic() { return _dimensionDynamic.copy() }
    Int rank() { return _dimensions.length() }

    Bool hasDynamicDimensions() {
        Int dimensionIndex = 0
        while dimensionIndex < _dimensionDynamic.length() {
            if _dimensionDynamic.get(dimensionIndex) {
                return true
            }
            dimensionIndex = dimensionIndex + 1
        }
        return false
    }

    TensorShape? fixedShape() {
        if self.hasDynamicDimensions() {
            return null
        }
        return new TensorShape(_dimensions)
    }

    Bool accepts(Tensor tensor) {
        if tensor == null {
            return false
        }
        if tensor.tensorDType() != _tensorDType {
            return false
        }
        if tensor.rank() != _dimensions.length() {
            return false
        }
        Int dimensionIndex = 0
        while dimensionIndex < _dimensions.length() {
            if !_dimensionDynamic.get(dimensionIndex) {
                if tensor.tensorShape().dim(dimensionIndex)
                        != _dimensions.get(dimensionIndex) {
                    return false
                }
            }
            dimensionIndex = dimensionIndex + 1
        }
        return true
    }

    String describe() {
        String shapeText = "["
        Int dimensionIndex = 0
        while dimensionIndex < _dimensions.length() {
            if dimensionIndex > 0 {
                shapeText = shapeText + ","
            }
            if _dimensionDynamic.get(dimensionIndex) {
                shapeText = shapeText + "?"
            } else {
                shapeText = shapeText + str(_dimensions.get(dimensionIndex))
            }
            dimensionIndex = dimensionIndex + 1
        }
        shapeText = shapeText + "]"
        return "input " + _name + " dtype=" + tensorDTypeName(_tensorDType)
            + " shape=" + shapeText
    }

    Bool equals(ModelInput other) {
        if other == null {
            return false
        }
        if _name != other.name() || _tensorDType != other.tensorDType() {
            return false
        }
        if _dimensions.length() != other.rank() {
            return false
        }
        List<Int> otherDimensions = other.dimensions()
        List<Bool> otherDynamic = other.dimensionDynamic()
        Int dimensionIndex = 0
        while dimensionIndex < _dimensions.length() {
            if _dimensions.get(dimensionIndex)
                    != otherDimensions.get(dimensionIndex) {
                return false
            }
            if _dimensionDynamic.get(dimensionIndex)
                    != otherDynamic.get(dimensionIndex) {
                return false
            }
            dimensionIndex = dimensionIndex + 1
        }
        return true
    }

    ModelInput copy() {
        return new ModelInput(_name, _tensorDType, _dimensions,
            _dimensionDynamic)
    }
}
```
