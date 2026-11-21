# `GpioDirection`

| 项 | 值 |
| --- | --- |
| 类型 | `enum GpioDirection` |
| 包 | `xdk.device` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

GPIO 引脚在打开时声明的方向：输入、输出。

不做：上拉/下拉、开漏/推挽、pinmux、边沿触发、PWM、双向模式、运行时切换方向。

---

## 2. 设计逻辑

- 为什么是 enum：方向只有两种，值语义、可穷举；比 `Bool` 或 `Int` 更难误用。
- 方向在 `GpioPin.open` 时固定；baseline 不支持运行时切换。要换方向，关闭后按新方向重新打开。
- `Input` 只允许 `read`；`Output` 只允许 `write`；反向操作返回 `InvalidArgument`，不是 panic。
- 方向是软件意图，不是电气配置；上拉/下拉/驱动强度是 X。
- 不提供 `Unknown`：打开必须显式选择；未知/缺失配置由调用方处理。
- 成员固定，只允许追加；名称映射稳定小写。

---

## 3. 表示与不变量

| 成员 | 含义 | 允许操作 |
| --- | --- | --- |
| `Input` | 输入引脚 | `read` |
| `Output` | 输出引脚 | `write` |

不变量：成员固定；只允许追加；值语义；`GpioPin.direction()` 返回打开时选择的值，关闭后仍可读。

---

## 4. 生命周期

值类型；无构造器、无 `close`；可共享；无资源；无取消点。

---

## 5. 构造契约

枚举项直接使用，无构造器。`GpioPin.open` 要求非 null；null 是合同错误（panic），不是 `InvalidArgument`。

---

## 6. 字段表

无实例字段；成员表见 §3。

---

## 7. 方法总表 / 详表

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `gpioDirectionName` | 稳定小写名 | `GpioDirection direction` | `String` | 无；null 返回 `"unknown"` |
| `gpioDirectionFromName` | 名称解析 | `String name` | `GpioDirection?` | 无；未知/null 返回 null |

说明：

- `gpioDirectionName` 对 `Input`/`Output` 返回 `"input"`/`"output"`；null 返回 `"unknown"` 作为诊断兜底，`"unknown"` 不是枚举成员。
- `gpioDirectionFromName` 先 `trim()` 再 `toLower()`；只接受 `"input"`/`"output"`。
- 不接受 `"in"`/`"out"`/`"0"`/`"1"` 等缩写；不做本地化。
- 两个函数都是纯函数、O(1)、无锁、可并发调用。

---

## 8. 使用的技术

- 简单枚举；
- 稳定名称映射；
- 大小写归一；
- 值语义。

---

## 9. 需要的支撑

- 语言：enum、String；
- 运行时：无；
- 接口：`GpioPin` 的 `direction()` 返回本枚举。

---

## 10. 依赖的特性/接口/类

`GpioPin`、`DeviceManager`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。
相等：按枚举底层值比较；可作 `Map`/`Set` 键；排序按 `Input`、`Output` 声明顺序。

---

## 12. 示例与反例

正确：`GpioPin.open(context, 17, GpioDirection.Output)`；`pin.direction() == GpioDirection.Input`。  
反例：打开后试图把 `Input` 改成 `Output`；用 `write` 写输入；用 `read` 读输出；用 `Bool` 表示方向；把 `"in"` 当配置值；用 null 表示默认方向。

---

## 13. 测试/场景义务

两个成员名称/解析往返；大小写与空白；未知名称；null；`GpioPin` 方向固定；Input/Output 反向操作返回 `InvalidArgument`；关闭后 `direction()` 仍可读；枚举作 `Map` 键。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
enum GpioDirection {
    Input,
    Output,
}

String gpioDirectionName(GpioDirection direction) {
    if direction == null { return "unknown" }
    if direction == GpioDirection.Input { return "input" }
    return "output"
}

GpioDirection? gpioDirectionFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "input" { return GpioDirection.Input }
    if normalized == "output" { return GpioDirection.Output }
    return null
}
```
