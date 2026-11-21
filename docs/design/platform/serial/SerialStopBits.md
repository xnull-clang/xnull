# `SerialStopBits`

| 项 | 值 |
| --- | --- |
| 类型 | `enum SerialStopBits` |
| 包 | `xdk.serial` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

串口停止位数量：1、1.5、2。

不做：数据位宽度、校验位、流控、驱动配置、时序测量。

---

## 2. 设计逻辑

- 封闭枚举：只列基线能命名的停止位；应用不能扩展。
- `OnePointFive` 是合法枚举成员，但不是所有 UART/平台都支持；通常与 5 数据位相关。
- `SerialOptions` 接受所有成员；具体硬件组合由 `SerialPort.open` 返回 `InvalidArgument`/`Unsupported`。
- 值语义；成员只允许追加，不允许改义/删除。

---

## 3. 表示与不变量

| 成员 | 含义 | 典型说明 |
| --- | --- | --- |
| `One` | 1 个停止位 | 基线常用 |
| `OnePointFive` | 1.5 个停止位 | 部分 UART/平台不支持 |
| `Two` | 2 个停止位 | 基线常用 |

不变量：成员固定；只允许追加；值语义；成员不携带数据位/校验位。

---

## 4. 生命周期

值类型；无构造器、无 close；可共享。

---

## 5. 构造契约

枚举项直接使用，无构造器。名称解析失败返回 null，不抛错。

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `serialStopBitsName` | 稳定小写名 | `SerialStopBits stopBits` | `String` | 无 |
| `serialStopBitsFromName` | 名称解析 | `String name` | `SerialStopBits?` | 无；未知返回 null |

说明：

- 稳定名用于日志/配置/诊断；不是驱动常量名。
- 解析做 `trim().toLower()` 归一；`one_point_five` 是唯一稳定拼写。
- 不提供数值 `1.0/1.5/2.0` 的公开换算；需要时由适配器映射。
- 不提供 `isSupported`；硬件支持由 `SerialPort.open` 的失败通道表达。

---

## 8. 使用的技术

- 简单枚举；
- 名称映射；
- 值语义比较。

---

## 9. 需要的支撑

- 语言：enum、String；
- 运行时：`trim()`、`toLower()`；
- 接口：`SerialOptions`、`SerialPort`。

---

## 10. 依赖的特性/接口/类

`SerialOptions`、`SerialParity`、`SerialPort`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。
相等：按枚举底层值比较；可作 `Map`/`Set` 键。

---

## 12. 示例与反例

正确：

```xnull
SerialOptions options = new SerialOptions(
    9600, 8, SerialParity.Even, SerialStopBits.Two, 500, 500)
```

反例：假设 `OnePointFive` 在所有平台可用；把 `OnePointFive` 当 `One`；用浮点数比较停止位；应用扩展枚举。

---

## 13. 测试/场景义务

每个成员名称/解析；大小写/空白归一；未知名称返回 null；`OnePointFive` 打开失败路径；与 `SerialOptions.equals`/`describe` 组合；跨平台差异。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
enum SerialStopBits {
    One,
    OnePointFive,
    Two,
}

String serialStopBitsName(SerialStopBits stopBits) {
    if stopBits == SerialStopBits.One { return "one" }
    if stopBits == SerialStopBits.OnePointFive { return "one_point_five" }
    return "two"
}

SerialStopBits? serialStopBitsFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "one" { return SerialStopBits.One }
    if normalized == "one_point_five" { return SerialStopBits.OnePointFive }
    if normalized == "two" { return SerialStopBits.Two }
    return null
}
```
