# `SerialParity`

| 项 | 值 |
| --- | --- |
| 类型 | `enum SerialParity` |
| 包 | `xdk.serial` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

串口校验位模式：无、偶、奇、Mark、Space。

不做：数据位宽度、停止位、流控、错误统计、驱动配置。

---

## 2. 设计逻辑

- 封闭枚举：只列基线能命名的校验模式；应用不能扩展。
- `None` 表示不校验；`Mark`/`Space` 固定校验位电平，不是所有 UART/平台都支持。
- `SerialOptions` 只校验成员非 null；具体硬件组合由 `SerialPort.open` 返回 `InvalidArgument`/`Unsupported`，不静默降级。
- 值语义；成员只允许追加，不允许改义/删除。

---

## 3. 表示与不变量

| 成员 | 含义 | 典型说明 |
| --- | --- | --- |
| `None` | 无校验 | 基线默认可用 |
| `Even` | 偶校验 | 校验位使 1 的个数为偶数 |
| `Odd` | 奇校验 | 校验位使 1 的个数为奇数 |
| `Mark` | 校验位固定 1 | 部分硬件/平台不支持 |
| `Space` | 校验位固定 0 | 部分硬件/平台不支持 |

不变量：成员固定；只允许追加；值语义；成员不携带数据位/停止位。

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
| `serialParityName` | 稳定小写名 | `SerialParity parity` | `String` | 无 |
| `serialParityFromName` | 名称解析 | `String name` | `SerialParity?` | 无；未知返回 null |

说明：

- 稳定名用于日志/配置/诊断；不是驱动常量名。
- 解析做 `trim().toLower()` 归一；未知名称返回 null。
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

`SerialOptions`、`SerialStopBits`、`SerialPort`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。
相等：按枚举底层值比较；可作 `Map`/`Set` 键。

---

## 12. 示例与反例

正确：

```xnull
SerialOptions options = new SerialOptions(
    115200, 8, SerialParity.None, SerialStopBits.One, 1000, 1000)
```

反例：把 `Mark` 当所有平台都支持；用字符串拼接代替枚举；在 `None` 下期望校验错误检测；应用扩展枚举。

---

## 13. 测试/场景义务

每个成员名称/解析；大小写/空白归一；未知名称返回 null；与 `SerialOptions.equals`/`describe` 组合；`Mark`/`Space` 打开失败路径；跨平台差异。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
enum SerialParity {
    None,
    Even,
    Odd,
    Mark,
    Space,
}

String serialParityName(SerialParity parity) {
    if parity == SerialParity.None { return "none" }
    if parity == SerialParity.Even { return "even" }
    if parity == SerialParity.Odd { return "odd" }
    if parity == SerialParity.Mark { return "mark" }
    return "space"
}

SerialParity? serialParityFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "none" { return SerialParity.None }
    if normalized == "even" { return SerialParity.Even }
    if normalized == "odd" { return SerialParity.Odd }
    if normalized == "mark" { return SerialParity.Mark }
    if normalized == "space" { return SerialParity.Space }
    return null
}
```
