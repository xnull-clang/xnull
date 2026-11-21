# `Tensor`

| 项 | 值 |
| --- | --- |
| 类型 | `class Tensor` |
| 包 | `xdk.tensor` |
| 稳定性 | `preview` |
| 依赖 | `TensorDType`、`TensorShape`、`Bytes` |

---

## 1. 定位

不可变逻辑张量：dtype、shape、行主序连续字节数据；提供元素读取、扁平读取、复制式更新、扁平化读取与值比较。

不做：原地 `set`、自动微分、GPU、广播、切片、稀疏表示、序列化、跨进程共享。

---

## 2. 设计逻辑

- 用 `class` 而不是 `struct`：需要封装 `Bytes`、校验长度、复制输入，且不暴露存储。
- 逻辑值不可变：构造后 `_data` 不再写入；`withValue` 复制后返回新张量。这样 `TensorView`、`TensorOps`、`Linalg` 都不会遇到“读取中途被改”的别名问题。
- 不提供 `set`：`set` 的命名暗示原地修改，与不可变合同冲突；需要更新时显式调用 `withValue`，调用方能看到新对象。
- 元素按 row-major 存放；`at` 用 `TensorShape.flatIndex` 转换，`atFlat` 直接访问连续下标。
- 定宽小端编码；`Bool` 只允许 0/1。构造器验证字节长度与 Bool 字节，避免半合法张量。
- 读取接口按 dtype 分流：`at` 返回数值投影，`atLong` 保留整数精度，`atBool` 只读布尔；向整数写入时校验范围与整数性。
- 单张量受 `Bytes` 的 `Int` 字节长度限制；`elementCount` 仍用 `Long`，因为形状本身可以更大。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_tensorDType` | `TensorDType` | final | 元素类型 |
| `_tensorShape` | `TensorShape` | final | 逻辑形状 |
| `_data` | `Bytes` | final | 行主序、小端、定宽元素 |

不变量：

- 三个字段非 null；
- `_data.length() == elementCount * tensorDTypeByteWidth(dtype)`；
- 字节长度可放入 `Int`，否则拒绝构造；
- `Bool` 的每个字节只能是 0 或 1；
- 构造后 `_data` 不再变化，且从不返回给调用方；
- 逻辑索引域由 `_tensorShape` 决定；扁平下标域为 `[0, elementCount)`。

---

## 4. 生命周期

由构造器或 `TensorOps` 工厂创建；构造后不可变；无 close；无外部资源；GC 管理内存；可跨任务共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Tensor(TensorDType tensorDType, TensorShape tensorShape, Bytes data)` | dtype、形状、字节数据 | 非 null；字节长度精确匹配；`Bool` 字节为 0/1；总字节数 ≤ `Int` 上限 | 违约 → panic |

构造器复制 `data`；调用方之后修改原 `Bytes` 不影响张量。`TensorOps.zeros/ones/fill/fromDoubles` 是常用入口；`Tensor` 不提供无数据构造。

---

## 6. 字段表

见 §3；字段私有，不暴露字节缓冲、容量或地址。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `tensorDType` | 元素类型 | 无 | `TensorDType` | 无 | 值类型 |
| `tensorShape` | 形状 | 无 | `TensorShape` | 无 | 不可变，可共享 |
| `rank` | 维度数 | 无 | `Int` | 无 | 委托 shape |
| `elementCount` | 元素数 | 无 | `Long` | 无 | 委托 shape |
| `byteLength` | 字节数 | 无 | `Long` | 无 | 等于元素数 × 元素宽度 |
| `isScalar` | 是否标量 | 无 | `Bool` | 无 | rank 为 0 |
| `at` | 按逻辑索引读数值 | `List<Int> indices` | `Double` | rank/越界 → panic | Bool 映射 0/1；Int64 可能丢精度 |
| `atFlat` | 按 row-major 扁平下标读数值 | `Long elementIndex` | `Double` | 越界 → panic | 用于视图/算子内核 |
| `atLong` | 读整数元素 | `List<Int> indices` | `Long` | dtype 非整数/越界 → panic | 保留 Int64 精度 |
| `atFlatLong` | 按扁平下标读整数 | `Long elementIndex` | `Long` | dtype 非整数/越界 → panic | 保留 Int64 精度 |
| `atBool` | 读布尔元素 | `List<Int> indices` | `Bool` | dtype 非 Bool/越界 → panic | 只接受 Bool |
| `withValue` | 复制并替换一个元素 | `List<Int> indices, Double value` | `Tensor` | 索引/类型/范围 → panic | 原张量不变；O(n) |
| `toDoubles` | 扁平数值副本 | 无 | `List<Double>` | 无 | Int64 可能丢精度 |
| `copy` | 独立副本 | 无 | `Tensor` | 无 | 复制字节 |
| `equals` | 值比较 | `Tensor other` | `Bool` | null → false | 浮点 NaN 不等；-0 与 0 相等 |
| `describe` | 单行描述 | 无 | `String` | 无 | dtype/shape/elements |

复杂度：元数据读取 O(1)；`at/atFlat/atLong/atFlatLong/atBool/withValue` 中索引检查 O(rank)，编解码 O(1)；`withValue/copy/toDoubles/equals` 为 O(elementCount)。

---

## 8. 使用的技术

- 连续字节缓冲；
- row-major 扁平索引；
- 定宽小端编解码；
- 复制式更新（copy-on-write 语义，不共享可变缓冲）；
- `Long` 元素计数与 `Int` 维度；
- `Bool` 规范字节校验；
- 整数/浮点分流读取。

---

## 9. 需要的支撑

- 语言：class、final 字段、List、Int、Long、Double、Bool、String；
- 运行时/包：`Bytes` 的分配、复制、读写；`TensorShape` 的索引/元素数；
- 数值原语：`tensorDTypeByteWidth`、`tensorDTypeName`、`tensorByteLength`、`validateTensorElementValue`；
- 编解码原语：`readTensorDouble`、`readTensorLong`、`readTensorBool`、`writeTensorDouble`；均按 dtype 做小端定宽读写；
- 接口：[`TensorShape`](TensorShape.md)、[`TensorDType`](TensorDType.md)、[`TensorOps`](TensorOps.md)、[`TensorView`](TensorView.md)。

---

## 10. 依赖的特性/接口/类

[`TensorDType`](TensorDType.md)、[`TensorShape`](TensorShape.md)、[`Bytes`](../../core/bytes/Bytes.md)、[`TensorOps`](TensorOps.md)、[`TensorView`](TensorView.md)。

---

## 11. 所有权与并发

构造器复制调用方的 `Bytes`；`tensorShape()` 返回不可变 `TensorShape` 的共享引用；`toDoubles()` 返回新列表；`withValue/copy` 返回新张量。  
不可变且不暴露可变缓冲，因此可跨任务共享、可并发读取；无 close；无取消点。  
相等：`equals` 按 dtype、形状、元素值比较；浮点 NaN 不等于自身，`-0.0` 与 `0.0` 相等；`==` 仍是引用身份；不推荐作 `Map` 键（比较 O(n)）。

---

## 12. 示例与反例

正确：`Tensor tensor = TensorOps.fromDoubles(TensorDType.Float32, new TensorShape([2, 3]), values)`；`tensor.at([1, 2])`；`Tensor updated = tensor.withValue([0, 0], 9.0)`，原 `tensor` 不变。  
反例：期望 `tensor.set(indices, value)` 原地修改；把外部 `Bytes` 传给构造器后继续改写它；用 `at` 读取 `Int64` 大整数并假设精确；用 `atBool` 读浮点张量；把 `atFlat` 的下标当逻辑多维下标。

---

## 13. 测试/场景义务

五种 dtype 的构造/读写；字节长度不匹配 panic；Bool 非法字节 panic；标量、含 0 维、多维；`at`/`atFlat`/`atLong`/`atFlatLong` 越界 panic；`atLong` 精度；`atBool` 类型检查；`withValue` 不改变原对象；`copy` 独立；`toDoubles` 顺序；`equals` 的 NaN/-0/不同 dtype/不同形状；`byteLength`；超过 `Int` 字节上限的拒绝。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class Tensor {
    final TensorDType _tensorDType
    final TensorShape _tensorShape
    final Bytes _data

    Tensor(TensorDType tensorDType, TensorShape tensorShape, Bytes data) {
        if tensorDType == null || tensorShape == null || data == null {
            throw "Tensor: null argument"
        }
        Long expectedBytes = tensorByteLength(tensorDType, tensorShape)
        if expectedBytes > 2147483647 {
            throw "Tensor: tensor exceeds byte length limit"
        }
        if (data.length() as Long) != expectedBytes {
            throw "Tensor: data length mismatch"
        }
        if tensorDType == TensorDType.Bool {
            Int byteIndex = 0
            while byteIndex < data.length() {
                Int byteValue = data.get(byteIndex)
                if byteValue != 0 && byteValue != 1 {
                    throw "Tensor: invalid bool byte"
                }
                byteIndex = byteIndex + 1
            }
        }
        _tensorDType = tensorDType
        _tensorShape = tensorShape
        _data = copy(data)
    }

    TensorDType tensorDType() { return _tensorDType }

    TensorShape tensorShape() { return _tensorShape }

    Int rank() { return _tensorShape.rank() }

    Long elementCount() { return _tensorShape.elementCount() }

    Long byteLength() { return _data.length() as Long }

    Bool isScalar() { return _tensorShape.isScalar() }

    Double at(List<Int> indices) {
        return self.atFlat(_tensorShape.flatIndex(indices))
    }

    Double atFlat(Long elementIndex) {
        if elementIndex < 0 || elementIndex >= _tensorShape.elementCount() {
            throw "Tensor.atFlat: element index out of range"
        }
        return readTensorDouble(_data, _tensorDType, elementIndex)
    }

    Long atLong(List<Int> indices) {
        return self.atFlatLong(_tensorShape.flatIndex(indices))
    }

    Long atFlatLong(Long elementIndex) {
        if elementIndex < 0 || elementIndex >= _tensorShape.elementCount() {
            throw "Tensor.atFlatLong: element index out of range"
        }
        if _tensorDType != TensorDType.Int32 && _tensorDType != TensorDType.Int64 {
            throw "Tensor.atFlatLong: dtype is not integer"
        }
        return readTensorLong(_data, _tensorDType, elementIndex)
    }

    Bool atBool(List<Int> indices) {
        if _tensorDType != TensorDType.Bool {
            throw "Tensor.atBool: dtype is not bool"
        }
        Long elementIndex = _tensorShape.flatIndex(indices)
        return readTensorBool(_data, elementIndex)
    }

    Tensor withValue(List<Int> indices, Double value) {
        Long elementIndex = _tensorShape.flatIndex(indices)
        validateTensorElementValue(_tensorDType, value)
        Bytes updated = copy(_data)
        writeTensorDouble(updated, _tensorDType, elementIndex, value)
        return new Tensor(_tensorDType, _tensorShape, updated)
    }

    List<Double> toDoubles() {
        List<Double> values = []
        Long elementIndex = 0
        while elementIndex < _tensorShape.elementCount() {
            values.push(self.atFlat(elementIndex))
            elementIndex = elementIndex + 1
        }
        return values
    }

    Tensor copy() {
        return new Tensor(_tensorDType, _tensorShape, _data)
    }

    Bool equals(Tensor other) {
        if other == null {
            return false
        }
        if _tensorDType != other.tensorDType() {
            return false
        }
        if !_tensorShape.equals(other.tensorShape()) {
            return false
        }
        Long elementIndex = 0
        if _tensorDType == TensorDType.Bool {
            while elementIndex < _tensorShape.elementCount() {
                if self.atFlat(elementIndex) != other.atFlat(elementIndex) {
                    return false
                }
                elementIndex = elementIndex + 1
            }
            return true
        }
        if _tensorDType == TensorDType.Int32 || _tensorDType == TensorDType.Int64 {
            while elementIndex < _tensorShape.elementCount() {
                if self.atFlatLong(elementIndex) != other.atFlatLong(elementIndex) {
                    return false
                }
                elementIndex = elementIndex + 1
            }
            return true
        }
        while elementIndex < _tensorShape.elementCount() {
            if self.atFlat(elementIndex) != other.atFlat(elementIndex) {
                return false
            }
            elementIndex = elementIndex + 1
        }
        return true
    }

    String describe() {
        return "tensor dtype=" + tensorDTypeName(_tensorDType)
            + " shape=" + _tensorShape.describe()
            + " elements=" + str(_tensorShape.elementCount())
    }
}
```
