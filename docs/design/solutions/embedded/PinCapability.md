# `PinCapability`

| 项 | 值 |
| --- | --- |
| 类型 | `enum PinCapability` |
| 包 | `xdk.embedded` |
| 层 |  |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

引脚**能力分类**：描述一个 `BoardPin` 能承担的角色，用于打开 ADC/PWM/UART/CAN 前的快速筛选和诊断。

不做：引脚电气配置（上下拉、开漏、驱动强度、压摆率）、复用功能号、AF 编号、引脚仲裁、运行时切换。具体复用功能名由 `BoardPin.alternateFunctions()` 提供；本枚举只回答“能做什么类别的事”。

---

## 2. 设计逻辑

- 为什么是 enum：能力集合是封闭、跨板稳定的分类；新增能力必须显式追加，不能由字符串自由发挥。
- 为什么区分方向：UART/CAN 的 TX/RX、SPI 的 MOSI/MISO/SCK/CS 在引脚复用与冲突检测上方向不同；只用一个 `Uart` 会让打开逻辑无法判断 TX 还是 RX。
- 为什么 I2C 同时是输入/输出：I2C 是开漏双向总线，SCL/SDA 都既驱动又采样；`pinCapabilityIsInput` 与 `pinCapabilityIsOutput` 都返回 `true`。
- 为什么保留 `Other`：厂商私有/板级特殊功能需要分类占位；`Other` 不承诺任何方向或总线语义，打开具体控制句柄时仍需精确复用功能名。
- 稳定序号：成员码 0..17 固定，只允许追加；不得重排/复用旧码，避免配置/日志/持久化错位。
- 值语义；无实例字段；可作 `Map`/`Set` 键；无 `close`。

---

## 3. 表示与不变量

| 成员 | 码 | 方向 | 说明 |
| --- | ---: | --- | --- |
| `Gpio` | 0 | 双向 | 通用 GPIO，可输入或输出 |
| `AdcInput` | 1 | 输入 | 模拟输入，可接 ADC 通道 |
| `PwmOutput` | 2 | 输出 | 定时器 PWM 输出 |
| `UartTransmit` | 3 | 输出 | UART TX |
| `UartReceive` | 4 | 输入 | UART RX |
| `CanTransmit` | 5 | 输出 | CAN TX |
| `CanReceive` | 6 | 输入 | CAN RX |
| `I2cClock` | 7 | 双向 | I2C SCL，开漏双向 |
| `I2cData` | 8 | 双向 | I2C SDA，开漏双向 |
| `SpiClock` | 9 | 输出 | SPI SCK |
| `SpiMosi` | 10 | 输出 | SPI MOSI |
| `SpiMiso` | 11 | 输入 | SPI MISO |
| `SpiSelect` | 12 | 输出 | SPI 片选 |
| `ClockOutput` | 13 | 输出 | 时钟输出/MCO |
| `Wakeup` | 14 | 输入 | 低功耗唤醒输入 |
| `Debug` | 15 | 双向 | SWD/JTAG/跟踪等调试信号 |
| `PowerEnable` | 16 | 输出 | 外设电源/使能控制 |
| `Other` | 17 | 未定义 | 厂商私有/板级特殊功能 |

不变量：18 项固定；码 0..17 固定；成员非 null；值语义；`pinCapabilityIsInput`/`pinCapabilityIsOutput` 对 `Other` 均为 `false`；`pinCapabilityIsAnalog` 仅 `AdcInput` 为 `true`。

---

## 4. 生命周期

编译期/加载期固定；无实例；无 `close`；可跨线程共享；可长期持有。能力分类不随运行时引脚状态变化；运行时是否被占用由控制句柄打开结果表达。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| 无公开构造 | 无 | 仅枚举成员 | 禁止实例化 |

枚举成员由语言/宿主固定；来自配置/日志的名称应通过显式映射表转换，未知名称由调用方决定回退到 `Other` 还是报 `InvalidArgument`。不得用整数码直接构造未知成员。

---

## 6. 字段表

无实例字段；成员即值。不要在 `BoardPin` 之外维护一份平行的“能力字符串表”；需要持久化时使用稳定码或稳定成员名。

---

## 7. 方法总表 / 详表

| 成员/函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `Gpio` | 通用 GPIO | 无 | 成员 | 无 |
| `AdcInput` | 模拟输入 | 无 | 成员 | 无 |
| `PwmOutput` | PWM 输出 | 无 | 成员 | 无 |
| `UartTransmit` | UART TX | 无 | 成员 | 无 |
| `UartReceive` | UART RX | 无 | 成员 | 无 |
| `CanTransmit` | CAN TX | 无 | 成员 | 无 |
| `CanReceive` | CAN RX | 无 | 成员 | 无 |
| `I2cClock` | I2C SCL | 无 | 成员 | 无 |
| `I2cData` | I2C SDA | 无 | 成员 | 无 |
| `SpiClock` | SPI SCK | 无 | 成员 | 无 |
| `SpiMosi` | SPI MOSI | 无 | 成员 | 无 |
| `SpiMiso` | SPI MISO | 无 | 成员 | 无 |
| `SpiSelect` | SPI CS | 无 | 成员 | 无 |
| `ClockOutput` | 时钟输出 | 无 | 成员 | 无 |
| `Wakeup` | 唤醒输入 | 无 | 成员 | 无 |
| `Debug` | 调试信号 | 无 | 成员 | 无 |
| `PowerEnable` | 电源/使能输出 | 无 | 成员 | 无 |
| `Other` | 其它/私有 | 无 | 成员 | 无 |
| `pinCapabilityIsInput` | 是否可作输入 | `PinCapability capability` | `Bool` | 无 |
| `pinCapabilityIsOutput` | 是否可作输出 | `PinCapability capability` | `Bool` | 无 |
| `pinCapabilityIsBusSignal` | 是否总线信号 | `PinCapability capability` | `Bool` | 无 |
| `pinCapabilityIsAnalog` | 是否模拟输入 | `PinCapability capability` | `Bool` | 无 |
| `pinCapabilityDescribe` | 稳定描述名 | `PinCapability capability` | `String` | 无 |

说明：

- `pinCapabilityIsInput`：`Gpio`、`AdcInput`、`UartReceive`、`CanReceive`、`I2cClock`、`I2cData`、`SpiMiso`、`Wakeup`、`Debug` 为 `true`；`null` 为 `false`。
- `pinCapabilityIsOutput`：`Gpio`、`PwmOutput`、`UartTransmit`、`CanTransmit`、`I2cClock`、`I2cData`、`SpiClock`、`SpiMosi`、`SpiSelect`、`ClockOutput`、`PowerEnable`、`Debug` 为 `true`；`null` 为 `false`。
- `pinCapabilityIsBusSignal`：UART/CAN/I2C/SPI 的成员为 `true`；`ClockOutput`、`Wakeup`、`PowerEnable`、`Debug`、`Other` 及 `null` 为 `false`。
- `pinCapabilityIsAnalog`：仅 `AdcInput` 为 `true`。
- `pinCapabilityDescribe` 返回稳定成员名（如 `"AdcInput"`），用于日志；`null` 返回 `"Unknown"` 作为诊断兜底，`"Unknown"` 不是枚举成员。
- 不提供 `fromCode`/`fromName`：需要解析时由板级包维护显式映射，避免把未知码静默当成 `Other`。

---

## 8. 使用的技术

- 稳定枚举码；
- 能力分类表；
- 方向谓词；
- 值语义；
- 稳定名称描述。

---

## 9. 需要的支撑

- 语言：enum、Int、Bool、String；
- 运行时：无；
- 接口：无；被 `BoardPin`、`Board` 使用。

---

## 10. 依赖的特性/接口/类

无。`PinCapability` 是 `xdk.embedded` 最底层的分类类型；被 `BoardPin`（能力集合）、`Board`（引脚一致性校验）、`AdcChannel`/`PwmChannel`/`UartPort`/`CanBus`（打开前筛选）使用。

---

## 11. 所有权与并发

值语义；不可变；可跨线程共享；无资源；无取消点；无 `close`。
相等：成员身份；可作 `Map`/`Set` 键；排序按稳定码（仅诊断用，不承诺业务排序）。

---

## 12. 示例与反例

正确：`boardPin.supports(PinCapability.AdcInput)` 决定是否调用 `AdcChannel.open`；`boardPin.hasAlternateFunction("ADC1_IN5")` 做精确复用功能校验。

正确：日志输出 `pinCapabilityDescribe(capability)`，不输出整数码作为唯一标识。

反例：用 `PinCapability.Gpio` 表示“任意引脚功能”；把 `I2cClock` 当纯输出；把 `Other` 当“支持所有功能”；把整数码持久化后重排成员；用 `pinCapabilityIsAnalog` 判断 PWM；用能力分类代替精确复用功能名。

---

## 13. 测试场景义务

18 个成员的 `pinCapabilityIsInput`/`pinCapabilityIsOutput`/`pinCapabilityIsBusSignal`/`pinCapabilityIsAnalog` 真值表；`pinCapabilityDescribe` 稳定名；值相等；可作 `Set`/`Map` 键；追加成员不改变旧码；`Other` 方向为 false；I2C 双向；Debug 双向；Gpio 双向；枚举 switch/if 覆盖全部成员（无默认吞掉新成员）。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
enum PinCapability {
    Gpio,
    AdcInput,
    PwmOutput,
    UartTransmit,
    UartReceive,
    CanTransmit,
    CanReceive,
    I2cClock,
    I2cData,
    SpiClock,
    SpiMosi,
    SpiMiso,
    SpiSelect,
    ClockOutput,
    Wakeup,
    Debug,
    PowerEnable,
    Other,
}

Bool pinCapabilityIsInput(PinCapability capability) {
    if capability == PinCapability.Gpio { return true }
    if capability == PinCapability.AdcInput { return true }
    if capability == PinCapability.UartReceive { return true }
    if capability == PinCapability.CanReceive { return true }
    if capability == PinCapability.I2cClock { return true }
    if capability == PinCapability.I2cData { return true }
    if capability == PinCapability.SpiMiso { return true }
    if capability == PinCapability.Wakeup { return true }
    if capability == PinCapability.Debug { return true }
    return false
}

Bool pinCapabilityIsOutput(PinCapability capability) {
    if capability == PinCapability.Gpio { return true }
    if capability == PinCapability.PwmOutput { return true }
    if capability == PinCapability.UartTransmit { return true }
    if capability == PinCapability.CanTransmit { return true }
    if capability == PinCapability.I2cClock { return true }
    if capability == PinCapability.I2cData { return true }
    if capability == PinCapability.SpiClock { return true }
    if capability == PinCapability.SpiMosi { return true }
    if capability == PinCapability.SpiSelect { return true }
    if capability == PinCapability.ClockOutput { return true }
    if capability == PinCapability.PowerEnable { return true }
    if capability == PinCapability.Debug { return true }
    return false
}

Bool pinCapabilityIsBusSignal(PinCapability capability) {
    if capability == PinCapability.UartTransmit { return true }
    if capability == PinCapability.UartReceive { return true }
    if capability == PinCapability.CanTransmit { return true }
    if capability == PinCapability.CanReceive { return true }
    if capability == PinCapability.I2cClock { return true }
    if capability == PinCapability.I2cData { return true }
    if capability == PinCapability.SpiClock { return true }
    if capability == PinCapability.SpiMosi { return true }
    if capability == PinCapability.SpiMiso { return true }
    if capability == PinCapability.SpiSelect { return true }
    return false
}

Bool pinCapabilityIsAnalog(PinCapability capability) {
    return capability == PinCapability.AdcInput
}

String pinCapabilityDescribe(PinCapability capability) {
    if capability == null { return "Unknown" }
    if capability == PinCapability.Gpio { return "Gpio" }
    if capability == PinCapability.AdcInput { return "AdcInput" }
    if capability == PinCapability.PwmOutput { return "PwmOutput" }
    if capability == PinCapability.UartTransmit { return "UartTransmit" }
    if capability == PinCapability.UartReceive { return "UartReceive" }
    if capability == PinCapability.CanTransmit { return "CanTransmit" }
    if capability == PinCapability.CanReceive { return "CanReceive" }
    if capability == PinCapability.I2cClock { return "I2cClock" }
    if capability == PinCapability.I2cData { return "I2cData" }
    if capability == PinCapability.SpiClock { return "SpiClock" }
    if capability == PinCapability.SpiMosi { return "SpiMosi" }
    if capability == PinCapability.SpiMiso { return "SpiMiso" }
    if capability == PinCapability.SpiSelect { return "SpiSelect" }
    if capability == PinCapability.ClockOutput { return "ClockOutput" }
    if capability == PinCapability.Wakeup { return "Wakeup" }
    if capability == PinCapability.Debug { return "Debug" }
    if capability == PinCapability.PowerEnable { return "PowerEnable" }
    return "Other"
}
```
