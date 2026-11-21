# `BoardPin`

| 项 | 值 |
| --- | --- |
| 类型 | `class BoardPin`（不可变值） |
| 包 | `xdk.embedded` |
| 层 |  |
| 稳定性 | `preview` |
| 依赖 | `PinCapability` |

---

## 1. 定位

一块板上的**单个引脚描述**：板级名称、板级编号、MCU 引脚名、端口名与端口内编号、能力集合、精确复用功能名、ADC/PWM 通道号。

不做：GPIO 读写、pinmux 写入、上下拉/驱动强度配置、边沿中断、模拟采样、PWM 输出、UART/CAN 收发、引脚仲裁、热插拔。

GPIO 控制仍用 [`GpioPin`](../../platform/device/GpioPin.md)；`BoardPin` 只是“这个引脚能做什么、对应哪个复用功能/通道”的只读契约。

---

## 2. 设计逻辑

- 为什么是 class：需要引用字段（能力列表、复用功能列表）与查询行为；不可变，可安全共享。
- 为什么不是 enum：引脚数量、名称、复用功能由板决定，不能枚举。
- `_boardPinNumber` 是板级逻辑编号（排针序号/板定义编号），不是 SoC 寄存器号；`_mcuPinName`/`_portName`/`_portPinNumber` 是 MCU 侧标识。适配器负责把二者映射到实际引脚。
- `_capabilities` 描述引脚可承担的角色；`_alternateFunctions` 描述可选的精确复用功能名（如 `USART3_TX`、`TIM2_CH1`、`CAN1_RX`、`ADC1_IN5`）。两者分开：能力用于快速筛选，复用功能名用于打开时的精确校验。
- `_adcChannelNumber`/`_pwmChannelNumber` 是 ADC/PWM 控制器通道号；没有该能力时必须为 `-1`，不得用 `0` 冒充“没有”。
- 能力与通道号严格一致：有 `AdcInput` 才允许非负 ADC 通道；有 `PwmOutput` 才允许非负 PWM 通道；反之通道号必须为 `-1`。构造期校验，避免运行期半真半假。
- 复用功能名大小写敏感、精确匹配；不做前缀推导、不做模糊匹配。`USART3_TX` 与 `usart2_tx` 不等价。复用功能只暴露精确名称，不暴露 STM32 AF0..AF15、ESP32 IOMUX 功能号或 SoC 寄存器值；这些编号映射由适配器完成。
- 不可变；列表返回副本；`equals` 值比较；无 `close`。
- 构造期校验：名称非空、编号非负、列表非 null、元素非 null/非空、能力与复用功能不重复、通道号与能力一致。非法输入 panic。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_name` | `String` | final | 非空；板级名称（如 `D13`、`LED`、`PA5`） |
| `_boardPinNumber` | `Int` | final | `>=0`；板级编号，板内唯一 |
| `_mcuPinName` | `String` | final | 非空；MCU 引脚名（如 `PA5`、`P0.05`） |
| `_portName` | `String` | final | 可为空；端口名（如 `GPIOA`、`P0`） |
| `_portPinNumber` | `Int` | final | `>=0`；端口内编号 |
| `_capabilities` | `List<PinCapability>` | final | 非 null；元素非 null；无重复 |
| `_alternateFunctions` | `List<String>` | final | 非 null；元素非空；无重复；精确名称 |
| `_adcChannelNumber` | `Int` | final | `>=-1`；`-1` 表示无 ADC 通道 |
| `_pwmChannelNumber` | `Int` | final | `>=-1`；`-1` 表示无 PWM 通道 |

不变量：

- 字符串非 null；`_name`、`_mcuPinName` 非空；`_portName` 可为空。
- `_boardPinNumber >= 0`；`_portPinNumber >= 0`。
- `_capabilities`/`_alternateFunctions` 非 null；构造时复制；外部修改不影响对象。
- `_capabilities` 无重复；`_alternateFunctions` 无重复且每个非空。
- `_adcChannelNumber >= -1`；`_pwmChannelNumber >= -1`。
- `_capabilities` 含 `PinCapability.AdcInput` ⇔ `_adcChannelNumber >= 0`。
- `_capabilities` 含 `PinCapability.PwmOutput` ⇔ `_pwmChannelNumber >= 0`。
- 不可变；`equals` 与全部字段及两个列表的顺序/内容一一对应。

---

## 4. 生命周期

由应用/板级包构造 `Board` 时创建；构造后不可变；无 `close`；可跨线程共享；可长期持有。引脚描述不拥有硬件；实际占用在 `AdcChannel`/`PwmChannel`/`UartPort`/`CanBus`/`GpioPin` 打开时由适配器仲裁。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `BoardPin(String name, Int boardPinNumber, String mcuPinName, String portName, Int portPinNumber, List<PinCapability> capabilities, List<String> alternateFunctions, Int adcChannelNumber, Int pwmChannelNumber)` | 9 个字段（见 §6） | 名称非空；编号≥0；列表非 null/元素非 null/非空/无重复；通道号≥-1；能力与通道一致 | 非法 → panic |

构造是合同边界：来自配置/代码生成的引脚表应先去重、校验，再构造；不要用 `-1` 以外的哨兵表示“无通道”，也不要用 `0` 表示“无能力”。

---

## 6. 字段表

见 §3；字段私有。`PinCapability` 是不可变枚举，复制引用；`String` 在 XDK 中按不可变值使用。构造时复制两个列表槽，避免调用方替换列表内容。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | 板级名称 | 无 | `String` | 无 |
| `boardPinNumber` | 板级编号 | 无 | `Int` | 无 |
| `mcuPinName` | MCU 引脚名 | 无 | `String` | 无 |
| `portName` | 端口名 | 无 | `String` | 无 |
| `portPinNumber` | 端口内编号 | 无 | `Int` | 无 |
| `capabilities` | 能力快照 | 无 | `List<PinCapability>` | 无 |
| `alternateFunctions` | 复用功能名快照 | 无 | `List<String>` | 无 |
| `supports` | 是否具备某能力 | `PinCapability capability` | `Bool` | 无 |
| `hasAlternateFunction` | 是否有某复用功能 | `String functionName` | `Bool` | 无 |
| `adcChannelNumber` | ADC 通道号 | 无 | `Int` | 无 |
| `pwmChannelNumber` | PWM 通道号 | 无 | `Int` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |
| `equals` | 值比较 | `BoardPin other` | `Bool` | null → false |

说明：

- 所有读取器纯读取；无 `Context`、无阻塞、无失败。
- `capabilities()`/`alternateFunctions()` 返回新列表；修改返回值不影响 `BoardPin`。
- `supports` 线性查找；`null` 返回 `false`。
- `hasAlternateFunction` 精确、大小写敏感匹配；`null` 或空串返回 `false`。
- `adcChannelNumber`/`pwmChannelNumber` 返回 `-1` 表示无该通道；调用方不得把 `-1` 当合法通道传给适配器。
- `equals` 比较全部字段、能力列表顺序与内容、复用功能列表顺序与内容；`==` 仍是引用身份。
- 不提供 `copy`：对象不可变，复制引用即可；需要独立列表时用 `capabilities()`/`alternateFunctions()`。
- 不提供 `configure`/`setFunction`/`setPull`：运行期 pinmux/电气配置不在本类型；当前基线在打开时固定复用功能。

---

## 8. 使用的技术

- 不可变值对象；
- 能力集合；
- 精确名称匹配；
- 列表复制与线性查找；
- 构造期一致性校验；
- 值相等；
- 单行描述。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Int、Bool、List、`?` 返回类型；
- 运行时：无原生调用；`BoardPin` 是纯值；
- 接口：`PinCapability`、`pinCapabilityDescribe`；
- 适配器：无；实际引脚映射/占用由打开控制句柄时的适配器负责。

---

## 10. 依赖的特性/接口/类

`PinCapability`、`pinCapabilityDescribe`、`Board`、`AdcChannel`、`PwmChannel`、`UartPort`、`CanBus`。

相关但不同层：`xdk.device.GpioPin`（GPIO 读写）、`xdk.device.GpioDirection`（方向）。本类型不复制 GPIO 控制 API。

---

## 11. 所有权与并发

不可变值；`capabilities`/`alternateFunctions` 返回副本；可跨线程共享，无锁、无取消点、无 `close`。
相等：`equals` 字段/列表比较；`==` 是引用身份；可作为 `Map` 键的前提是映射使用 `equals`，否则不推荐。无排序语义。

---

## 12. 示例与反例

正确：板级包构造 `BoardPin("PA5", 5, "PA5", "GPIOA", 5, [PinCapability.AdcInput], ["ADC1_IN5"], 5, -1)`；`AdcChannel.open` 校验 `supports(AdcInput)` 与 `adcChannelNumber() == 5`。

正确：UART 打开时调用 `transmitPin.hasAlternateFunction("USART3_TX")`，不满足返回 `Unsupported`，不尝试 `USART2_TX`。

反例：能力列表有 `AdcInput` 但通道号 `-1`；能力列表没有 `PwmOutput` 却把通道号设为 `0`；`name` 为空；`boardPinNumber` 重复；复用功能名写成 `usart2_tx` 却期望匹配 `USART3_TX`；把 `mcuPinName` 当板级唯一键；把 `BoardPin` 当 GPIO 句柄读写。

---

## 13. 测试场景义务

构造合法/非法：空名称、空 MCU 名、负编号、负端口编号、null 列表、null 元素、空复用功能名、重复能力、重复复用功能、ADC 能力与通道号不一致（两种方向）、PWM 能力与通道号不一致（两种方向）；`-1` 通道；列表复制独立性；`supports` 每个能力/null；`hasAlternateFunction` 命中/未命中/null/空串/大小写；`adcChannelNumber`/`pwmChannelNumber`；`equals` 全字段/列表顺序/列表内容/null；`describe` 不含秘密；不可变共享；无 `close`。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class BoardPin {
    final String _name
    final Int _boardPinNumber
    final String _mcuPinName
    final String _portName
    final Int _portPinNumber
    final List<PinCapability> _capabilities
    final List<String> _alternateFunctions
    final Int _adcChannelNumber
    final Int _pwmChannelNumber

    BoardPin(String name, Int boardPinNumber, String mcuPinName,
             String portName, Int portPinNumber,
             List<PinCapability> capabilities,
             List<String> alternateFunctions,
             Int adcChannelNumber, Int pwmChannelNumber) {
        if name == null || mcuPinName == null || portName == null {
            throw "BoardPin: null string"
        }
        if name.trim() == "" || mcuPinName.trim() == "" {
            throw "BoardPin: empty name"
        }
        if boardPinNumber < 0 || portPinNumber < 0 {
            throw "BoardPin: negative number"
        }
        if capabilities == null || alternateFunctions == null {
            throw "BoardPin: null list"
        }
        if adcChannelNumber < -1 || pwmChannelNumber < -1 {
            throw "BoardPin: invalid channel number"
        }

        Bool hasAdc = false
        Int capabilityIndex = 0
        while capabilityIndex < capabilities.length() {
            PinCapability capability = capabilities.get(capabilityIndex)
            if capability == null {
                throw "BoardPin: null capability"
            }
            if capability == PinCapability.AdcInput {
                hasAdc = true
            }
            Int capabilityScan = 0
            while capabilityScan < capabilityIndex {
                if capabilities.get(capabilityScan) == capability {
                    throw "BoardPin: duplicate capability"
                }
                capabilityScan = capabilityScan + 1
            }
            capabilityIndex = capabilityIndex + 1
        }

        Bool hasPwm = false
        Int functionIndex = 0
        while functionIndex < alternateFunctions.length() {
            String functionName = alternateFunctions.get(functionIndex)
            if functionName == null || functionName.trim() == "" {
                throw "BoardPin: empty alternate function"
            }
            Int functionScan = 0
            while functionScan < functionIndex {
                if alternateFunctions.get(functionScan) == functionName {
                    throw "BoardPin: duplicate alternate function"
                }
                functionScan = functionScan + 1
            }
            functionIndex = functionIndex + 1
        }

        capabilityIndex = 0
        while capabilityIndex < capabilities.length() {
            if capabilities.get(capabilityIndex) == PinCapability.PwmOutput {
                hasPwm = true
            }
            capabilityIndex = capabilityIndex + 1
        }

        if hasAdc != (adcChannelNumber >= 0) {
            throw "BoardPin: adc capability/channel mismatch"
        }
        if hasPwm != (pwmChannelNumber >= 0) {
            throw "BoardPin: pwm capability/channel mismatch"
        }

        _name = name
        _boardPinNumber = boardPinNumber
        _mcuPinName = mcuPinName
        _portName = portName
        _portPinNumber = portPinNumber
        _capabilities = capabilities.copy()
        _alternateFunctions = alternateFunctions.copy()
        _adcChannelNumber = adcChannelNumber
        _pwmChannelNumber = pwmChannelNumber
    }

    String name() { return _name }
    Int boardPinNumber() { return _boardPinNumber }
    String mcuPinName() { return _mcuPinName }
    String portName() { return _portName }
    Int portPinNumber() { return _portPinNumber }
    List<PinCapability> capabilities() { return _capabilities.copy() }
    List<String> alternateFunctions() { return _alternateFunctions.copy() }
    Int adcChannelNumber() { return _adcChannelNumber }
    Int pwmChannelNumber() { return _pwmChannelNumber }

    Bool supports(PinCapability capability) {
        if capability == null { return false }
        Int index = 0
        while index < _capabilities.length() {
            if _capabilities.get(index) == capability { return true }
            index = index + 1
        }
        return false
    }

    Bool hasAlternateFunction(String functionName) {
        if functionName == null || functionName == "" { return false }
        Int index = 0
        while index < _alternateFunctions.length() {
            if _alternateFunctions.get(index) == functionName { return true }
            index = index + 1
        }
        return false
    }

    String describe() {
        String capabilityText = ""
        Int index = 0
        while index < _capabilities.length() {
            if index > 0 { capabilityText = capabilityText + "," }
            capabilityText = capabilityText + pinCapabilityDescribe(_capabilities.get(index))
            index = index + 1
        }
        return "pin " + _name + " (" + _mcuPinName + ") board="
            + str(_boardPinNumber) + " port=" + _portName + "."
            + str(_portPinNumber) + " caps=" + capabilityText
            + " adc=" + str(_adcChannelNumber)
            + " pwm=" + str(_pwmChannelNumber)
    }

    Bool equals(BoardPin other) {
        if other == null { return false }
        if _name != other.name()
            || _boardPinNumber != other.boardPinNumber()
            || _mcuPinName != other.mcuPinName()
            || _portName != other.portName()
            || _portPinNumber != other.portPinNumber()
            || _adcChannelNumber != other.adcChannelNumber()
            || _pwmChannelNumber != other.pwmChannelNumber() {
            return false
        }
        List<PinCapability> otherCapabilities = other.capabilities()
        if _capabilities.length() != otherCapabilities.length() {
            return false
        }
        Int capabilityIndex = 0
        while capabilityIndex < _capabilities.length() {
            if _capabilities.get(capabilityIndex)
                != otherCapabilities.get(capabilityIndex) {
                return false
            }
            capabilityIndex = capabilityIndex + 1
        }
        List<String> otherFunctions = other.alternateFunctions()
        if _alternateFunctions.length() != otherFunctions.length() {
            return false
        }
        Int functionIndex = 0
        while functionIndex < _alternateFunctions.length() {
            if _alternateFunctions.get(functionIndex)
                != otherFunctions.get(functionIndex) {
                return false
            }
            functionIndex = functionIndex + 1
        }
        return true
    }
}
```
