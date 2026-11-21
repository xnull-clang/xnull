# `Board`

| 项 | 值 |
| --- | --- |
| 类型 | `class Board`（不可变值） |
| 包 | `xdk.embedded` |
| 层 |  |
| 稳定性 | `preview` |
| 依赖 | `BoardPin`、`PinCapability`、`PowerMode` |

---

## 1. 定位

一块板/模块的**显式只读描述**：板名、厂商、MCU 名称/家族/架构、时钟频率、Flash/RAM 容量、引脚表、低功耗模式集合，以及 ADC/PWM/UART/CAN/看门狗/RTC 的能力计数。

不做：板卡自动探测、按名称自动加载、读取 SMBIOS/设备树、热插拔、引脚仲裁、驱动绑定、固件升级、序列号/MAC 导出。

`xdk.os.hardware` 的 [`BoardInfo`](../../platform/os/hardware/BoardInfo.md) 是 OS/DMI 可见的主板只读快照；`Board` 是应用为嵌入式目标显式提供的板级契约，两者不互相替代。CPU 运行态拓扑由 [`CpuTopology`](../../platform/os/cpu/CpuTopology.md) 提供，本类型不复制其字段。

---

## 2. 设计逻辑

- 为什么是 class 而不是 struct：需要引用字段（引脚列表、模式列表）与一组行为（查找、能力查询、相等），同时保持不可变；class 在 XDK 中可承载引用字段，构造后只读即可共享。
- 为什么不是 enum：板卡组合是开放的，不能把厂商/型号固化成枚举。
- 为什么不做自动探测：嵌入式目标经常没有可枚举的固件/设备树；自动探测会把“猜测”变成隐式全局状态。应用/板级包显式构造 `Board`，出错在构造期暴露。
- `_pins` 是板级引脚描述，不是 GPIO 控制器清单；GPIO 控制仍用 [`GpioPin`](../../platform/device/GpioPin.md)。
- `_powerModes` 是板支持的**候选模式集合**，不是当前模式；当前模式由 `Embedded.powerMode(context, board)` 查询。
- `_adcChannelCount`/`_pwmChannelCount`/`_uartPortCount`/`_canBusCount` 是板级能力上限，用于校验引脚通道号和快速判断能力；`0` 表示没有该能力。
- `_hasWatchdog`/`_hasRtc` 是板级布尔能力；具体打开仍可能因权限/占用失败。
- `_clockFrequencyHz`、`_flashBytes`、`_ramBytes` 是标称值；实际可运行频率/可用存储可能被引导器/容器裁剪，运行态以适配器查询为准。
- 不可变；`pins()`/`powerModes()` 返回副本；`equals` 做值比较；无 `close`。
- 构造期做完整一致性校验：名称非空、计数非负、`PowerMode.Active` 必须存在、引脚编号/名称唯一、引脚 ADC/PWM 通道号不超过板级计数。非法输入是合同错误（panic），不进入半初始化状态。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_name` | `String` | final | 非空；板/模块名 |
| `_vendor` | `String` | final | 可为空；厂商 |
| `_mcuName` | `String` | final | 非空；MCU 型号 |
| `_mcuFamily` | `String` | final | 可为空；MCU 家族 |
| `_cpuArchitecture` | `String` | final | 可为空；如 `ARM Cortex-M4` |
| `_clockFrequencyHz` | `Long` | final | `>0`；标称系统时钟 |
| `_flashBytes` | `Long` | final | `>=0`；标称片内/板载 Flash |
| `_ramBytes` | `Long` | final | `>=0`；标称 RAM |
| `_pins` | `List<BoardPin>` | final | 非 null；元素非 null；板级编号/名称唯一 |
| `_powerModes` | `List<PowerMode>` | final | 非 null、非空、唯一；必须包含 `Active` |
| `_adcChannelCount` | `Int` | final | `>=0` |
| `_pwmChannelCount` | `Int` | final | `>=0` |
| `_uartPortCount` | `Int` | final | `>=0` |
| `_canBusCount` | `Int` | final | `>=0` |
| `_hasWatchdog` | `Bool` | final | 板是否有看门狗 |
| `_hasRtc` | `Bool` | final | 板是否有 RTC |

不变量：

- 所有字符串非 null；`_name`、`_mcuName` 非空；其余字符串可为空。
- `_clockFrequencyHz > 0`；`_flashBytes >= 0`；`_ramBytes >= 0`。
- 四个能力计数 `>=0`。
- `_pins` 与 `_powerModes` 非 null；构造时复制，外部修改不影响对象。
- `_powerModes` 非空、无重复、包含 `PowerMode.Active`。
- `_pins` 中每个元素非 null；`boardPinNumber` 唯一；`name` 唯一。
- 每个引脚 `adcChannelNumber() == -1` 或 `< _adcChannelCount`；`pwmChannelNumber() == -1` 或 `< _pwmChannelCount`。
- 不可变；`equals` 与全部字段及列表内容一一对应。

---

## 4. 生命周期

由应用/板级包在启动期构造；构造后不可变；无 `close`；可跨线程共享；可长期持有。板描述不拥有任何设备句柄，不延长控制句柄生命周期。需要新板/新配置时构造新 `Board`，不提供原地修改。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Board(String name, String vendor, String mcuName, String mcuFamily, String cpuArchitecture, Long clockFrequencyHz, Long flashBytes, Long ramBytes, List<BoardPin> pins, List<PowerMode> powerModes, Int adcChannelCount, Int pwmChannelCount, Int uartPortCount, Int canBusCount, Bool hasWatchdog, Bool hasRtc)` | 16 个字段（见 §6） | 字符串非 null；`name`/`mcuName` 非空；时钟>0；容量/计数≥0；引脚/模式列表非 null；模式含 `Active`；引脚编号/名称唯一；通道号不越界 | 非法 → panic |

构造是合同边界：来自配置文件/外部输入的字段应先校验，再构造 `Board`；不要用 `null`/`0`/空串同时表示“缺失”和“合法值”。`vendor`/`mcuFamily`/`cpuArchitecture` 缺失用空串，不用 `null`。`pins` 可为空（只描述板级能力）；`powerModes` 不可为空且必须包含 `Active`。

---

## 6. 字段表

见 §3；字段私有。`BoardPin` 与 `PowerMode` 都是不可变值，复制引用即可；构造时仍复制列表槽，避免调用方后续替换列表内容。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | 板名 | 无 | `String` | 无 |
| `vendor` | 厂商 | 无 | `String` | 无 |
| `mcuName` | MCU 型号 | 无 | `String` | 无 |
| `mcuFamily` | MCU 家族 | 无 | `String` | 无 |
| `cpuArchitecture` | CPU 架构 | 无 | `String` | 无 |
| `clockFrequencyHz` | 标称时钟 | 无 | `Long` | 无 |
| `flashBytes` | 标称 Flash 容量 | 无 | `Long` | 无 |
| `ramBytes` | 标称 RAM 容量 | 无 | `Long` | 无 |
| `pins` | 引脚快照 | 无 | `List<BoardPin>` | 无 |
| `pinCount` | 引脚数 | 无 | `Int` | 无 |
| `findPin` | 按名称查引脚 | `String name` | `BoardPin?` | 无 |
| `findPinByNumber` | 按板级编号查引脚 | `Int boardPinNumber` | `BoardPin?` | 无 |
| `findPinByMcuName` | 按 MCU 引脚名查引脚 | `String mcuPinName` | `BoardPin?` | 无 |
| `powerModes` | 支持的低功耗模式 | 无 | `List<PowerMode>` | 无 |
| `supportsPowerMode` | 是否支持某模式 | `PowerMode powerMode` | `Bool` | 无 |
| `adcChannelCount` | ADC 通道数 | 无 | `Int` | 无 |
| `pwmChannelCount` | PWM 通道数 | 无 | `Int` | 无 |
| `uartPortCount` | UART 端口数 | 无 | `Int` | 无 |
| `canBusCount` | CAN 控制器数 | 无 | `Int` | 无 |
| `hasWatchdog` | 是否有看门狗 | 无 | `Bool` | 无 |
| `hasRtc` | 是否有 RTC | 无 | `Bool` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |
| `equals` | 值比较 | `Board other` | `Bool` | null → false |

说明：

- 所有读取器纯读取；无 `Context`、无阻塞、无失败。
- `pins()`/`powerModes()` 返回新列表；修改返回值不影响 `Board`。
- `findPin` 精确匹配 `BoardPin.name()`，大小写敏感；未找到或 `name == null` 返回 `null`；不模糊匹配、不转小写。
- `findPinByNumber` 精确匹配 `BoardPin.boardPinNumber()`；负编号或未找到返回 `null`。
- `findPinByMcuName` 精确匹配 `BoardPin.mcuPinName()`，大小写敏感；未找到或 `mcuPinName == null` 返回 `null`；若同一 MCU 引脚在板上出现多次，返回第一个匹配。
- `supportsPowerMode` 线性查找；`null` 返回 `false`。
- `equals` 比较全部字符串、数值、布尔、`powerModes` 顺序与内容、`pins` 顺序与内容；`==` 仍是引用身份。
- 不提供 `copy`：对象不可变，复制引用即可；需要独立列表时用 `pins()`/`powerModes()`。
- 不提供 `detect`/`current`/`load`：板描述必须显式构造。
- 不提供 `close`/`refresh`：无资源、无快照刷新。

---

## 8. 使用的技术

- 不可变值对象；
- 构造期一致性校验；
- 列表复制与线性查找；
- 唯一性检查；
- 能力计数；
- 值相等；
- 单行描述。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Long、Int、Bool、List、`?` 返回类型；
- 运行时：无原生调用；`Board` 是纯值；
- 接口：`BoardPin`、`PinCapability`、`PowerMode`、`powerModeDescribe`；
- 适配器：无；需要板级信息时由应用/板级包构造 `Board`，不查询硬件。

---

## 10. 依赖的特性/接口/类

`BoardPin`、`PinCapability`、`PowerMode`、`powerModeDescribe`、`List`。

相关但不同层：`xdk.os.hardware.BoardInfo`（OS 主板清单）、`xdk.os.cpu.CpuTopology`（运行态 CPU 拓扑）、`xdk.device.GpioPin`（GPIO 控制）。本类型不复制它们。

---

## 11. 所有权与并发

不可变值；引用字段是 `BoardPin`/`PowerMode` 不可变值；`pins()`/`powerModes()` 返回副本。可跨线程共享，无锁、无取消点、无 `close`。
相等：`equals` 字段/列表比较；`==` 是引用身份；可作为 `Map` 键的前提是映射使用 `equals`，否则不推荐。无排序语义。

---

## 12. 示例与反例

正确：应用在启动期用编译期常量构造 `Board`，把 `BoardPin` 传给 `AdcChannel.open`/`PwmChannel.open`；用 `board.supportsPowerMode(PowerMode.DeepSleep)` 决定是否暴露休眠功能。

正确：`board.findPin("PA5")` 找不到时返回 `null`，调用方回退到 `Unsupported`，不猜测其它引脚。

反例：期望 `Board` 自动识别当前板；把 `Board` 当设备句柄并 `close`；构造时传重复引脚编号导致后续查找不确定；用 `BoardInfo` 的厂商字段代替 MCU 型号；把 `flashBytes` 当可用文件系统空间；在日志中假设 `vendor` 非空；修改 `pins()` 返回值并期望影响板描述。

---

## 13. 测试场景义务

构造合法/非法：空名称、空 MCU、负时钟、负容量、负计数、空引脚列表、空模式列表、缺 `Active`、重复模式、重复引脚编号、重复引脚名称、引脚 ADC/PWM 通道越界；列表复制独立性；`pins`/`powerModes` 返回副本；`pinCount`；`findPin` 命中/未命中/null/大小写；`findPinByNumber` 命中/负值/未命中；`findPinByMcuName` 命中/重复 MCU 名/未命中/null/大小写；`supportsPowerMode` 每个成员/null；`equals` 全字段/列表顺序/列表内容/`null`；`describe` 不含秘密；不可变共享；无 `close`。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class Board {
    final String _name
    final String _vendor
    final String _mcuName
    final String _mcuFamily
    final String _cpuArchitecture
    final Long _clockFrequencyHz
    final Long _flashBytes
    final Long _ramBytes
    final List<BoardPin> _pins
    final List<PowerMode> _powerModes
    final Int _adcChannelCount
    final Int _pwmChannelCount
    final Int _uartPortCount
    final Int _canBusCount
    final Bool _hasWatchdog
    final Bool _hasRtc

    Board(String name, String vendor, String mcuName, String mcuFamily,
          String cpuArchitecture, Long clockFrequencyHz, Long flashBytes,
          Long ramBytes, List<BoardPin> pins, List<PowerMode> powerModes,
          Int adcChannelCount, Int pwmChannelCount, Int uartPortCount,
          Int canBusCount, Bool hasWatchdog, Bool hasRtc) {
        if name == null || vendor == null || mcuName == null
            || mcuFamily == null || cpuArchitecture == null {
            throw "Board: null string"
        }
        if name.trim() == "" || mcuName.trim() == "" {
            throw "Board: empty name"
        }
        if clockFrequencyHz <= 0 {
            throw "Board: non-positive clock"
        }
        if flashBytes < 0 || ramBytes < 0 {
            throw "Board: negative capacity"
        }
        if adcChannelCount < 0 || pwmChannelCount < 0
            || uartPortCount < 0 || canBusCount < 0 {
            throw "Board: negative capability count"
        }
        if pins == null || powerModes == null {
            throw "Board: null list"
        }
        if powerModes.length() == 0 {
            throw "Board: empty power mode list"
        }

        Bool hasActive = false
        Int modeIndex = 0
        while modeIndex < powerModes.length() {
            PowerMode mode = powerModes.get(modeIndex)
            if mode == null {
                throw "Board: null power mode"
            }
            if mode == PowerMode.Active {
                hasActive = true
            }
            Int modeScan = 0
            while modeScan < modeIndex {
                if powerModes.get(modeScan) == mode {
                    throw "Board: duplicate power mode"
                }
                modeScan = modeScan + 1
            }
            modeIndex = modeIndex + 1
        }
        if !hasActive {
            throw "Board: missing Active power mode"
        }

        Int pinIndex = 0
        while pinIndex < pins.length() {
            BoardPin pin = pins.get(pinIndex)
            if pin == null {
                throw "Board: null pin"
            }
            if pin.adcChannelNumber() >= adcChannelCount {
                throw "Board: adc channel out of range"
            }
            if pin.pwmChannelNumber() >= pwmChannelCount {
                throw "Board: pwm channel out of range"
            }
            Int pinScan = 0
            while pinScan < pinIndex {
                BoardPin prior = pins.get(pinScan)
                if prior.boardPinNumber() == pin.boardPinNumber() {
                    throw "Board: duplicate board pin number"
                }
                if prior.name() == pin.name() {
                    throw "Board: duplicate board pin name"
                }
                pinScan = pinScan + 1
            }
            pinIndex = pinIndex + 1
        }

        _name = name
        _vendor = vendor
        _mcuName = mcuName
        _mcuFamily = mcuFamily
        _cpuArchitecture = cpuArchitecture
        _clockFrequencyHz = clockFrequencyHz
        _flashBytes = flashBytes
        _ramBytes = ramBytes
        _pins = pins.copy()
        _powerModes = powerModes.copy()
        _adcChannelCount = adcChannelCount
        _pwmChannelCount = pwmChannelCount
        _uartPortCount = uartPortCount
        _canBusCount = canBusCount
        _hasWatchdog = hasWatchdog
        _hasRtc = hasRtc
    }

    String name() { return _name }
    String vendor() { return _vendor }
    String mcuName() { return _mcuName }
    String mcuFamily() { return _mcuFamily }
    String cpuArchitecture() { return _cpuArchitecture }
    Long clockFrequencyHz() { return _clockFrequencyHz }
    Long flashBytes() { return _flashBytes }
    Long ramBytes() { return _ramBytes }
    List<BoardPin> pins() { return _pins.copy() }
    Int pinCount() { return _pins.length() }
    List<PowerMode> powerModes() { return _powerModes.copy() }
    Int adcChannelCount() { return _adcChannelCount }
    Int pwmChannelCount() { return _pwmChannelCount }
    Int uartPortCount() { return _uartPortCount }
    Int canBusCount() { return _canBusCount }
    Bool hasWatchdog() { return _hasWatchdog }
    Bool hasRtc() { return _hasRtc }

    BoardPin? findPin(String name) {
        if name == null { return null }
        Int index = 0
        while index < _pins.length() {
            if _pins.get(index).name() == name {
                return _pins.get(index)
            }
            index = index + 1
        }
        return null
    }

    BoardPin? findPinByNumber(Int boardPinNumber) {
        if boardPinNumber < 0 { return null }
        Int index = 0
        while index < _pins.length() {
            if _pins.get(index).boardPinNumber() == boardPinNumber {
                return _pins.get(index)
            }
            index = index + 1
        }
        return null
    }

    BoardPin? findPinByMcuName(String mcuPinName) {
        if mcuPinName == null { return null }
        Int index = 0
        while index < _pins.length() {
            if _pins.get(index).mcuPinName() == mcuPinName {
                return _pins.get(index)
            }
            index = index + 1
        }
        return null
    }

    Bool supportsPowerMode(PowerMode powerMode) {
        if powerMode == null { return false }
        Int index = 0
        while index < _powerModes.length() {
            if _powerModes.get(index) == powerMode { return true }
            index = index + 1
        }
        return false
    }

    String describe() {
        String modes = ""
        Int index = 0
        while index < _powerModes.length() {
            if index > 0 { modes = modes + "," }
            modes = modes + powerModeDescribe(_powerModes.get(index))
            index = index + 1
        }
        return "board " + _name + " mcu=" + _mcuName
            + " arch=" + _cpuArchitecture
            + " clockHz=" + str(_clockFrequencyHz)
            + " flash=" + str(_flashBytes)
            + " ram=" + str(_ramBytes)
            + " pins=" + str(_pins.length())
            + " power=" + modes
    }

    Bool equals(Board other) {
        if other == null { return false }
        if _name != other.name() || _vendor != other.vendor()
            || _mcuName != other.mcuName()
            || _mcuFamily != other.mcuFamily()
            || _cpuArchitecture != other.cpuArchitecture()
            || _clockFrequencyHz != other.clockFrequencyHz()
            || _flashBytes != other.flashBytes()
            || _ramBytes != other.ramBytes()
            || _adcChannelCount != other.adcChannelCount()
            || _pwmChannelCount != other.pwmChannelCount()
            || _uartPortCount != other.uartPortCount()
            || _canBusCount != other.canBusCount()
            || _hasWatchdog != other.hasWatchdog()
            || _hasRtc != other.hasRtc() {
            return false
        }
        List<PowerMode> otherModes = other.powerModes()
        if _powerModes.length() != otherModes.length() {
            return false
        }
        Int modeIndex = 0
        while modeIndex < _powerModes.length() {
            if _powerModes.get(modeIndex) != otherModes.get(modeIndex) {
                return false
            }
            modeIndex = modeIndex + 1
        }
        List<BoardPin> otherPins = other.pins()
        if _pins.length() != otherPins.length() {
            return false
        }
        Int pinIndex = 0
        while pinIndex < _pins.length() {
            if !_pins.get(pinIndex).equals(otherPins.get(pinIndex)) {
                return false
            }
            pinIndex = pinIndex + 1
        }
        return true
    }
}
```
