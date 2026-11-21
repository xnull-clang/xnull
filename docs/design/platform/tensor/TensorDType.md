# `TensorDType`

| 项 | 值 |
| --- | --- |
| 类型 | `enum TensorDType` |
| 包 | `xdk.tensor` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

张量元素类型：32/64 位浮点、32/64 位有符号整数、布尔。

不做：复数、无符号整数、半精度/bf16、量化类型、字符串、任意精度；不做隐式类型提升。

---

## 2. 设计逻辑

- 元素类型必须显式写在每个 `Tensor` 上，运算不根据值猜类型。
- 字节宽度固定，才能把 `Bytes` 解释为元素数组；端序由 `Tensor` 统一为小端。
- `Bool` 是独立类型，不用 `Int32` 假装；只允许 0/1 字节。
- 枚举不定义实例方法；名称、宽度、分类由顶层函数映射，避免枚举依赖 `String`/`Result`。
- 成员只允许追加；已有序号与名称冻结。

---

## 3. 表示与不变量

| 成员 | 序号 | 字节宽度 | 数值域 |
| --- | ---: | ---: | --- |
| `Float32` | 0 | 4 | IEEE 754 binary32，允许 NaN/±Inf |
| `Float64` | 1 | 8 | IEEE 754 binary64，允许 NaN/±Inf |
| `Int32` | 2 | 4 | −2^31 .. 2^31−1，二补码 |
| `Int64` | 3 | 8 | −2^63 .. 2^63−1，二补码 |
| `Bool` | 4 | 1 | 0（false）或 1（true） |

不变量：成员固定；序号 0..4 固定；字节宽度固定；`Bool` 仅 0/1；无隐式提升。

---

## 4. 生命周期

值类型；无构造器、无 close；可自由复制与共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| 枚举成员 | 无 | 五个成员之一 | 不存在非法成员 |
| `tensorDTypeFromName` | `String name` | 任意文本 | 未知/空 → `null` |

枚举成员直接使用；不允许 `new TensorDType()`，不允许应用扩展成员。

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

`TensorDType` 没有实例方法。相关顶层函数：

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `tensorDTypeByteWidth` | 元素的字节宽度 | `TensorDType tensorDType` | `Int` | 无 | 4/8/1，见 §3 |
| `tensorDTypeName` | 稳定小写名 | `TensorDType tensorDType` | `String` | 无 | `"float32"` 等 |
| `tensorDTypeFromName` | 名称解析 | `String name` | `TensorDType?` | 无 | 去空白、忽略大小写；未知 → `null` |
| `tensorDTypeIsFloatingPoint` | 是否浮点 | `TensorDType tensorDType` | `Bool` | 无 | Float32/Float64 |
| `tensorDTypeIsInteger` | 是否有符号整数 | `TensorDType tensorDType` | `Bool` | 无 | Int32/Int64 |
| `tensorDTypeIsBoolean` | 是否布尔 | `TensorDType tensorDType` | `Bool` | 无 | 仅 Bool |

名称是交换/日志合同；不得把 `"float"`、`"int"`、`"f32"` 解析为合法成员。

---

## 8. 使用的技术

- 简单枚举 + 固定序号；
- 固定宽度表；
- 名称双向映射；
- 类型分类谓词。

---

## 9. 需要的支撑

- 语言：enum、Int、String、Bool；
- 运行时：字符串去空白/小写；
- 接口：`Tensor`、`TensorOps`（仅使用本枚举）。

---

## 10. 依赖的特性/接口/类

[`Tensor`](Tensor.md)、[`TensorShape`](TensorShape.md)、[`TensorOps`](TensorOps.md)。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。  
相等：按枚举底层值比较；可作 `Map`/`Set` 键。

---

## 12. 示例与反例

正确：`TensorDType.Float32` 表示单精度；`tensorDTypeByteWidth(TensorDType.Int64) == 8`；`TensorDType.Bool` 只存 0/1。  
反例：假设所有元素都是 8 字节；把 `Int64` 当 `Float64` 位模式重解释；让 `add` 自动把 `Int32` 提升为 `Float64`；把未知名称猜成 `Float32`。

---

## 13. 测试/场景义务

五个成员的名称/宽度/序号；`tensorDTypeFromName` 的大小写、空白、未知、空串；浮点/整数/布尔谓词互斥且完备；枚举值可作 `Map` 键；不出现第六个成员。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
enum TensorDType {
    Float32 = 0,
    Float64 = 1,
    Int32 = 2,
    Int64 = 3,
    Bool = 4,
}

Int tensorDTypeByteWidth(TensorDType tensorDType) {
    if tensorDType == TensorDType.Float32 { return 4 }
    if tensorDType == TensorDType.Float64 { return 8 }
    if tensorDType == TensorDType.Int32 { return 4 }
    if tensorDType == TensorDType.Int64 { return 8 }
    return 1
}

String tensorDTypeName(TensorDType tensorDType) {
    if tensorDType == TensorDType.Float32 { return "float32" }
    if tensorDType == TensorDType.Float64 { return "float64" }
    if tensorDType == TensorDType.Int32 { return "int32" }
    if tensorDType == TensorDType.Int64 { return "int64" }
    return "bool"
}

TensorDType? tensorDTypeFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "float32" { return TensorDType.Float32 }
    if normalized == "float64" { return TensorDType.Float64 }
    if normalized == "int32" { return TensorDType.Int32 }
    if normalized == "int64" { return TensorDType.Int64 }
    if normalized == "bool" { return TensorDType.Bool }
    return null
}

Bool tensorDTypeIsFloatingPoint(TensorDType tensorDType) {
    if tensorDType == TensorDType.Float32 { return true }
    if tensorDType == TensorDType.Float64 { return true }
    return false
}

Bool tensorDTypeIsInteger(TensorDType tensorDType) {
    if tensorDType == TensorDType.Int32 { return true }
    if tensorDType == TensorDType.Int64 { return true }
    return false
}

Bool tensorDTypeIsBoolean(TensorDType tensorDType) {
    return tensorDType == TensorDType.Bool
}
```
