// xdk.embedded —— 嵌入式板级支持（A8 派生实现）
//
// 本文件实现合同中的 12 个类型：Board / BoardPin / PinCapability /
// AdcChannel / PwmChannel / UartPort / CanBus / Watchdog / Rtc /
// FlashRegion / PowerMode / Embedded。
//
// 当前宿主（macOS/桌面）没有 /dev/gpiochipN、spidev、i2c-dev、MTD 等
// 嵌入式控制面。描述/值类型与句柄生命周期/校验完整实现；需要真实硬件的
// 采样、PWM、串口、CAN、看门狗、RTC、Flash 擦写与电源切换返回
// ErrorKind.Unsupported，不伪造硬件执行。
package xdk.embedded
import xdk.errors
import xdk.execution
import xdk.bytes
import xdk.time

// ---------- 支持类型：xdk.serial 缺失时的本地串口参数 ----------
// 合同要求 UartPort 复用 xdk.serial.SerialOptions；当前仓库没有该包。
// 这里按 docs/design/platform/serial/SerialOptions.md 的字段与校验提供
// 同名兼容值对象；xdk.serial 落地后应替换为跨包引用。

enum SerialParity {
    Unknown,
    None,
    Even,
    Odd,
    Mark,
    Space,
}

enum SerialStopBits {
    Unknown,
    One,
    OnePointFive,
    Two,
}

String serialParityName(SerialParity? parity) {
    if parity == null { return "unknown" }
    if parity == SerialParity.Unknown { return "unknown" }
    if parity == SerialParity.None { return "none" }
    if parity == SerialParity.Even { return "even" }
    if parity == SerialParity.Odd { return "odd" }
    if parity == SerialParity.Mark { return "mark" }
    return "space"
}

String serialStopBitsName(SerialStopBits? stopBits) {
    if stopBits == null { return "unknown" }
    if stopBits == SerialStopBits.Unknown { return "unknown" }
    if stopBits == SerialStopBits.One { return "one" }
    if stopBits == SerialStopBits.OnePointFive { return "one_point_five" }
    return "two"
}

class SerialOptions {
    final Int _baudRate
    final Int _dataBits
    final SerialParity _parity
    final SerialStopBits _stopBits
    final Long _readTimeoutMillis
    final Long _writeTimeoutMillis

    SerialOptions(Int baudRate, Int dataBits, SerialParity parity,
                  SerialStopBits stopBits, Long readTimeoutMillis,
                  Long writeTimeoutMillis) {
        if baudRate <= 0 { throw "SerialOptions: baud rate must be positive" }
        if dataBits < 5 || dataBits > 8 {
            throw "SerialOptions: data bits out of range"
        }
        if parity == null || stopBits == null {
            throw "SerialOptions: null parity/stop bits"
        }
        if readTimeoutMillis < 0 || writeTimeoutMillis < 0 {
            throw "SerialOptions: negative timeout"
        }
        self._baudRate = baudRate
        self._dataBits = dataBits
        self._parity = parity
        self._stopBits = stopBits
        self._readTimeoutMillis = readTimeoutMillis
        self._writeTimeoutMillis = writeTimeoutMillis
    }

    Int baudRate() { return self._baudRate }
    Int dataBits() { return self._dataBits }
    SerialParity parity() { return self._parity }
    SerialStopBits stopBits() { return self._stopBits }
    Long readTimeoutMillis() { return self._readTimeoutMillis }
    Long writeTimeoutMillis() { return self._writeTimeoutMillis }

    Bool equals(SerialOptions other) {
        if other == null { return false }
        return self._baudRate == other.baudRate() &&
            self._dataBits == other.dataBits() &&
            self._parity == other.parity() &&
            self._stopBits == other.stopBits() &&
            self._readTimeoutMillis == other.readTimeoutMillis() &&
            self._writeTimeoutMillis == other.writeTimeoutMillis()
    }

    String describe() {
        return "serial " + str(self._baudRate) + " " + str(self._dataBits)
            + " parity=" + serialParityName(self._parity)
            + " stop=" + serialStopBitsName(self._stopBits)
            + " readTimeout=" + str(self._readTimeoutMillis)
            + " writeTimeout=" + str(self._writeTimeoutMillis)
    }
}

// ---------- 通用错误 ----------

static Error embeddedUnsupported(String operation) {
    return new BasicError(ErrorKind.Unsupported,
        operation + ": not supported on this platform")
}

static Error embeddedUnavailable(String resource) {
    return new BasicError(ErrorKind.Unavailable, resource + " is closed")
}

// 可空 String 参数在编译器中不能直接与字符串字面量比较；先解包再比较。
static Bool embeddedStringEquals(String? value, String expected) {
    if value == null { return false }
    String actual = value as String
    return actual == expected
}

// ---------- PinCapability ----------

enum PinCapability {
    // 编译器把枚举零值当作 null；合同码 0..17 因此整体后移 1，
    // Unknown 占 0，Gpio 从 1 开始。Unknown 不是合同成员。
    Unknown,
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

Bool pinCapabilityIsInput(PinCapability? capability) {
    if capability == null { return false }
    if capability == PinCapability.Unknown { return false }
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

Bool pinCapabilityIsOutput(PinCapability? capability) {
    if capability == null { return false }
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

Bool pinCapabilityIsBusSignal(PinCapability? capability) {
    if capability == null { return false }
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

Bool pinCapabilityIsAnalog(PinCapability? capability) {
    return capability == PinCapability.AdcInput
}

String pinCapabilityDescribe(PinCapability? capability) {
    if capability == null { return "Unknown" }
    if capability == PinCapability.Unknown { return "Unknown" }
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

// 显式名称解析；未知名称返回 Unknown，不静默当成 Other。
PinCapability pinCapabilityFromName(String? name) {
    if name == null { return PinCapability.Unknown }
    if embeddedStringEquals(name, "Gpio") { return PinCapability.Gpio }
    if embeddedStringEquals(name, "AdcInput") { return PinCapability.AdcInput }
    if embeddedStringEquals(name, "PwmOutput") { return PinCapability.PwmOutput }
    if embeddedStringEquals(name, "UartTransmit") {
        return PinCapability.UartTransmit
    }
    if embeddedStringEquals(name, "UartReceive") {
        return PinCapability.UartReceive
    }
    if embeddedStringEquals(name, "CanTransmit") {
        return PinCapability.CanTransmit
    }
    if embeddedStringEquals(name, "CanReceive") {
        return PinCapability.CanReceive
    }
    if embeddedStringEquals(name, "I2cClock") { return PinCapability.I2cClock }
    if embeddedStringEquals(name, "I2cData") { return PinCapability.I2cData }
    if embeddedStringEquals(name, "SpiClock") { return PinCapability.SpiClock }
    if embeddedStringEquals(name, "SpiMosi") { return PinCapability.SpiMosi }
    if embeddedStringEquals(name, "SpiMiso") { return PinCapability.SpiMiso }
    if embeddedStringEquals(name, "SpiSelect") { return PinCapability.SpiSelect }
    if embeddedStringEquals(name, "ClockOutput") {
        return PinCapability.ClockOutput
    }
    if embeddedStringEquals(name, "Wakeup") { return PinCapability.Wakeup }
    if embeddedStringEquals(name, "Debug") { return PinCapability.Debug }
    if embeddedStringEquals(name, "PowerEnable") {
        return PinCapability.PowerEnable
    }
    if embeddedStringEquals(name, "Other") { return PinCapability.Other }
    return PinCapability.Unknown
}

// ---------- PowerMode ----------

enum PowerMode {
    // 同上：Unknown 占编译器零值，合同模式码整体后移 1。
    Unknown,
    Active,
    Idle,
    Sleep,
    DeepSleep,
    Off,
}

Bool powerModeIsRunning(PowerMode? powerMode) {
    if powerMode == null { return false }
    if powerMode == PowerMode.Active { return true }
    if powerMode == PowerMode.Idle { return true }
    return false
}

Bool powerModeIsLowPower(PowerMode? powerMode) {
    if powerMode == null { return false }
    if powerMode == PowerMode.Idle { return true }
    if powerMode == PowerMode.Sleep { return true }
    if powerMode == PowerMode.DeepSleep { return true }
    if powerMode == PowerMode.Off { return true }
    return false
}

Bool powerModeInvalidatesHandles(PowerMode? powerMode) {
    if powerMode == null { return false }
    if powerMode == PowerMode.Sleep { return true }
    if powerMode == PowerMode.DeepSleep { return true }
    if powerMode == PowerMode.Off { return true }
    return false
}

Bool powerModeRequiresWakeSource(PowerMode? powerMode) {
    if powerMode == null { return false }
    if powerMode == PowerMode.Sleep { return true }
    if powerMode == PowerMode.DeepSleep { return true }
    if powerMode == PowerMode.Off { return true }
    return false
}

String powerModeDescribe(PowerMode? powerMode) {
    if powerMode == null { return "Unknown" }
    if powerMode == PowerMode.Unknown { return "Unknown" }
    if powerMode == PowerMode.Active { return "Active" }
    if powerMode == PowerMode.Idle { return "Idle" }
    if powerMode == PowerMode.Sleep { return "Sleep" }
    if powerMode == PowerMode.DeepSleep { return "DeepSleep" }
    return "Off"
}

PowerMode powerModeFromName(String? name) {
    if name == null { return PowerMode.Unknown }
    if embeddedStringEquals(name, "Active") { return PowerMode.Active }
    if embeddedStringEquals(name, "Idle") { return PowerMode.Idle }
    if embeddedStringEquals(name, "Sleep") { return PowerMode.Sleep }
    if embeddedStringEquals(name, "DeepSleep") { return PowerMode.DeepSleep }
    if embeddedStringEquals(name, "Off") { return PowerMode.Off }
    return PowerMode.Unknown
}

// 转换表：同模式是无操作；Off -> Active 只经外部复位/上电。
Bool powerModeCanTransition(PowerMode? from, PowerMode? to) {
    if from == null || to == null { return false }
    if from == PowerMode.Unknown || to == PowerMode.Unknown { return false }
    if from == to { return true }
    if from == PowerMode.Active {
        return to == PowerMode.Idle || to == PowerMode.Sleep ||
            to == PowerMode.DeepSleep || to == PowerMode.Off
    }
    if from == PowerMode.Idle {
        return to == PowerMode.Active || to == PowerMode.Sleep ||
            to == PowerMode.DeepSleep || to == PowerMode.Off
    }
    if from == PowerMode.Sleep {
        return to == PowerMode.Active || to == PowerMode.DeepSleep ||
            to == PowerMode.Off
    }
    if from == PowerMode.DeepSleep {
        return to == PowerMode.Active
    }
    return to == PowerMode.Active
}

// ---------- BoardPin ----------

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
        Bool hasPwm = false
        Int capabilityIndex = 0
        while capabilityIndex < capabilities.length() {
            PinCapability capability = capabilities.get(capabilityIndex)
            if capability == null {
                throw "BoardPin: null capability"
            }
            if capability == PinCapability.AdcInput { hasAdc = true }
            if capability == PinCapability.PwmOutput { hasPwm = true }
            Int capabilityScan = 0
            while capabilityScan < capabilityIndex {
                if capabilities.get(capabilityScan) == capability {
                    throw "BoardPin: duplicate capability"
                }
                capabilityScan = capabilityScan + 1
            }
            capabilityIndex = capabilityIndex + 1
        }

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

        if hasAdc != (adcChannelNumber >= 0) {
            throw "BoardPin: adc capability/channel mismatch"
        }
        if hasPwm != (pwmChannelNumber >= 0) {
            throw "BoardPin: pwm capability/channel mismatch"
        }

        self._name = name
        self._boardPinNumber = boardPinNumber
        self._mcuPinName = mcuPinName
        self._portName = portName
        self._portPinNumber = portPinNumber
        self._capabilities = capabilities.copy()
        self._alternateFunctions = alternateFunctions.copy()
        self._adcChannelNumber = adcChannelNumber
        self._pwmChannelNumber = pwmChannelNumber
    }

    String name() { return self._name }
    Int boardPinNumber() { return self._boardPinNumber }
    String mcuPinName() { return self._mcuPinName }
    String portName() { return self._portName }
    Int portPinNumber() { return self._portPinNumber }
    List<PinCapability> capabilities() { return self._capabilities.copy() }
    List<String> alternateFunctions() { return self._alternateFunctions.copy() }
    Int adcChannelNumber() { return self._adcChannelNumber }
    Int pwmChannelNumber() { return self._pwmChannelNumber }

    Bool supports(PinCapability? capability) {
        if capability == null { return false }
        Int index = 0
        while index < self._capabilities.length() {
            if self._capabilities.get(index) == capability { return true }
            index = index + 1
        }
        return false
    }

    Bool hasAlternateFunction(String? functionName) {
        if functionName == null || embeddedStringEquals(functionName, "") {
            return false
        }
        Int index = 0
        while index < self._alternateFunctions.length() {
            if embeddedStringEquals(functionName,
                self._alternateFunctions.get(index)) {
                return true
            }
            index = index + 1
        }
        return false
    }

    String describe() {
        String capabilityText = ""
        Int index = 0
        while index < self._capabilities.length() {
            if index > 0 { capabilityText = capabilityText + "," }
            capabilityText = capabilityText
                + pinCapabilityDescribe(self._capabilities.get(index))
            index = index + 1
        }
        return "pin " + self._name + " (" + self._mcuPinName + ") board="
            + str(self._boardPinNumber) + " port=" + self._portName + "."
            + str(self._portPinNumber) + " caps=" + capabilityText
            + " adc=" + str(self._adcChannelNumber)
            + " pwm=" + str(self._pwmChannelNumber)
    }

    Bool equals(BoardPin other) {
        if other == null { return false }
        if self._name != other.name()
            || self._boardPinNumber != other.boardPinNumber()
            || self._mcuPinName != other.mcuPinName()
            || self._portName != other.portName()
            || self._portPinNumber != other.portPinNumber()
            || self._adcChannelNumber != other.adcChannelNumber()
            || self._pwmChannelNumber != other.pwmChannelNumber() {
            return false
        }
        List<PinCapability> otherCapabilities = other.capabilities()
        if self._capabilities.length() != otherCapabilities.length() {
            return false
        }
        Int capabilityIndex = 0
        while capabilityIndex < self._capabilities.length() {
            if self._capabilities.get(capabilityIndex)
                != otherCapabilities.get(capabilityIndex) {
                return false
            }
            capabilityIndex = capabilityIndex + 1
        }
        List<String> otherFunctions = other.alternateFunctions()
        if self._alternateFunctions.length() != otherFunctions.length() {
            return false
        }
        Int functionIndex = 0
        while functionIndex < self._alternateFunctions.length() {
            if self._alternateFunctions.get(functionIndex)
                != otherFunctions.get(functionIndex) {
                return false
            }
            functionIndex = functionIndex + 1
        }
        return true
    }
}

// ---------- Board ----------

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
            if mode == PowerMode.Active { hasActive = true }
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

        self._name = name
        self._vendor = vendor
        self._mcuName = mcuName
        self._mcuFamily = mcuFamily
        self._cpuArchitecture = cpuArchitecture
        self._clockFrequencyHz = clockFrequencyHz
        self._flashBytes = flashBytes
        self._ramBytes = ramBytes
        self._pins = pins.copy()
        self._powerModes = powerModes.copy()
        self._adcChannelCount = adcChannelCount
        self._pwmChannelCount = pwmChannelCount
        self._uartPortCount = uartPortCount
        self._canBusCount = canBusCount
        self._hasWatchdog = hasWatchdog
        self._hasRtc = hasRtc
    }

    String name() { return self._name }
    String vendor() { return self._vendor }
    String mcuName() { return self._mcuName }
    String mcuFamily() { return self._mcuFamily }
    String cpuArchitecture() { return self._cpuArchitecture }
    Long clockFrequencyHz() { return self._clockFrequencyHz }
    Long flashBytes() { return self._flashBytes }
    Long ramBytes() { return self._ramBytes }
    List<BoardPin> pins() { return self._pins.copy() }
    Int pinCount() { return self._pins.length() }
    List<PowerMode> powerModes() { return self._powerModes.copy() }
    Int adcChannelCount() { return self._adcChannelCount }
    Int pwmChannelCount() { return self._pwmChannelCount }
    Int uartPortCount() { return self._uartPortCount }
    Int canBusCount() { return self._canBusCount }
    Bool hasWatchdog() { return self._hasWatchdog }
    Bool hasRtc() { return self._hasRtc }

    BoardPin? findPin(String? name) {
        if name == null { return null }
        Int index = 0
        while index < self._pins.length() {
            if embeddedStringEquals(name, self._pins.get(index).name()) {
                return self._pins.get(index)
            }
            index = index + 1
        }
        return null
    }

    BoardPin? findPinByNumber(Int boardPinNumber) {
        if boardPinNumber < 0 { return null }
        Int index = 0
        while index < self._pins.length() {
            if self._pins.get(index).boardPinNumber() == boardPinNumber {
                return self._pins.get(index)
            }
            index = index + 1
        }
        return null
    }

    BoardPin? findPinByMcuName(String? mcuPinName) {
        if mcuPinName == null { return null }
        Int index = 0
        while index < self._pins.length() {
            if embeddedStringEquals(mcuPinName,
                self._pins.get(index).mcuPinName()) {
                return self._pins.get(index)
            }
            index = index + 1
        }
        return null
    }

    Bool supportsPowerMode(PowerMode? powerMode) {
        if powerMode == null { return false }
        Int index = 0
        while index < self._powerModes.length() {
            if self._powerModes.get(index) == powerMode { return true }
            index = index + 1
        }
        return false
    }

    String describe() {
        String modes = ""
        Int index = 0
        while index < self._powerModes.length() {
            if index > 0 { modes = modes + "," }
            modes = modes + powerModeDescribe(self._powerModes.get(index))
            index = index + 1
        }
        return "board " + self._name + " mcu=" + self._mcuName
            + " arch=" + self._cpuArchitecture
            + " clockHz=" + str(self._clockFrequencyHz)
            + " flash=" + str(self._flashBytes)
            + " ram=" + str(self._ramBytes)
            + " pins=" + str(self._pins.length())
            + " power=" + modes
    }

    Bool equals(Board other) {
        if other == null { return false }
        if self._name != other.name() || self._vendor != other.vendor()
            || self._mcuName != other.mcuName()
            || self._mcuFamily != other.mcuFamily()
            || self._cpuArchitecture != other.cpuArchitecture()
            || self._clockFrequencyHz != other.clockFrequencyHz()
            || self._flashBytes != other.flashBytes()
            || self._ramBytes != other.ramBytes()
            || self._adcChannelCount != other.adcChannelCount()
            || self._pwmChannelCount != other.pwmChannelCount()
            || self._uartPortCount != other.uartPortCount()
            || self._canBusCount != other.canBusCount()
            || self._hasWatchdog != other.hasWatchdog()
            || self._hasRtc != other.hasRtc() {
            return false
        }
        List<PowerMode> otherModes = other.powerModes()
        if self._powerModes.length() != otherModes.length() {
            return false
        }
        Int modeIndex = 0
        while modeIndex < self._powerModes.length() {
            if self._powerModes.get(modeIndex) != otherModes.get(modeIndex) {
                return false
            }
            modeIndex = modeIndex + 1
        }
        List<BoardPin> otherPins = other.pins()
        if self._pins.length() != otherPins.length() {
            return false
        }
        Int pinIndex = 0
        while pinIndex < self._pins.length() {
            if !self._pins.get(pinIndex).equals(otherPins.get(pinIndex)) {
                return false
            }
            pinIndex = pinIndex + 1
        }
        return true
    }
}

// ---------- AdcChannel ----------

class AdcChannel {
    final Long _handle
    final BoardPin _boardPin
    final Int _channelNumber
    final Int _resolutionBits
    final Long _referenceMillivolts
    Bool _open

    AdcChannel(Long handle, BoardPin boardPin, Int channelNumber,
               Int resolutionBits, Long referenceMillivolts) {
        if handle == null || handle <= 0 {
            throw "AdcChannel: invalid handle"
        }
        if boardPin == null || !boardPin.supports(PinCapability.AdcInput) {
            throw "AdcChannel: pin has no adc capability"
        }
        if channelNumber < 0 || channelNumber != boardPin.adcChannelNumber() {
            throw "AdcChannel: channel mismatch"
        }
        if resolutionBits < 1 || resolutionBits > 24 {
            throw "AdcChannel: invalid resolution"
        }
        if referenceMillivolts <= 0 {
            throw "AdcChannel: invalid reference"
        }
        self._handle = handle
        self._boardPin = boardPin
        self._channelNumber = channelNumber
        self._resolutionBits = resolutionBits
        self._referenceMillivolts = referenceMillivolts
        self._open = true
    }

    static Result<AdcChannel, Error> open(Context context, BoardPin boardPin,
                                          Int resolutionBits,
                                          Long referenceMillivolts) {
        if context == null || boardPin == null {
            throw "AdcChannel.open: null argument"
        }
        if resolutionBits < 1 || resolutionBits > 24 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "invalid adc resolution"))
        }
        if referenceMillivolts <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "invalid adc reference"))
        }
        if !boardPin.supports(PinCapability.AdcInput) {
            return Err(new BasicError(ErrorKind.Unsupported,
                "pin has no adc capability"))
        }
        if boardPin.adcChannelNumber() < 0 {
            return Err(new BasicError(ErrorKind.Unsupported,
                "pin has no adc channel"))
        }
        return Err(embeddedUnsupported("AdcChannel.open"))
    }

    BoardPin boardPin() { return self._boardPin }
    Int channelNumber() { return self._channelNumber }
    Int resolutionBits() { return self._resolutionBits }
    Long referenceMillivolts() { return self._referenceMillivolts }
    Bool isOpen() { return self._open }

    Result<Int, Error> read(Context context) {
        if context == null { throw "AdcChannel.read: null context" }
        if !self._open { return Err(embeddedUnavailable("adc channel")) }
        return Err(embeddedUnsupported("AdcChannel.read"))
    }

    Result<Long, Error> readMillivolts(Context context) {
        if context == null {
            throw "AdcChannel.readMillivolts: null context"
        }
        if !self._open { return Err(embeddedUnavailable("adc channel")) }
        return Err(embeddedUnsupported("AdcChannel.readMillivolts"))
    }

    Result<Unit, Error> close() {
        if !self._open { return Ok() }
        self._open = false
        return Ok()
    }
}

// ---------- PwmChannel ----------

class PwmChannel {
    final Long _handle
    final BoardPin _boardPin
    final Int _channelNumber
    Long _frequencyHz
    Int _dutyPermille
    Bool _enabled
    Bool _open

    PwmChannel(Long handle, BoardPin boardPin, Int channelNumber,
               Long frequencyHz) {
        if handle == null || handle <= 0 {
            throw "PwmChannel: invalid handle"
        }
        if boardPin == null || !boardPin.supports(PinCapability.PwmOutput) {
            throw "PwmChannel: pin has no pwm capability"
        }
        if channelNumber < 0 || channelNumber != boardPin.pwmChannelNumber() {
            throw "PwmChannel: channel mismatch"
        }
        if frequencyHz <= 0 {
            throw "PwmChannel: invalid frequency"
        }
        self._handle = handle
        self._boardPin = boardPin
        self._channelNumber = channelNumber
        self._frequencyHz = frequencyHz
        self._dutyPermille = 0
        self._enabled = false
        self._open = true
    }

    static Result<PwmChannel, Error> open(Context context, BoardPin boardPin,
                                          Long frequencyHz) {
        if context == null || boardPin == null {
            throw "PwmChannel.open: null argument"
        }
        if frequencyHz <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "invalid pwm frequency"))
        }
        if !boardPin.supports(PinCapability.PwmOutput) {
            return Err(new BasicError(ErrorKind.Unsupported,
                "pin has no pwm capability"))
        }
        if boardPin.pwmChannelNumber() < 0 {
            return Err(new BasicError(ErrorKind.Unsupported,
                "pin has no pwm channel"))
        }
        return Err(embeddedUnsupported("PwmChannel.open"))
    }

    BoardPin boardPin() { return self._boardPin }
    Int channelNumber() { return self._channelNumber }
    Long frequencyHz() { return self._frequencyHz }
    Int dutyPermille() { return self._dutyPermille }
    Bool isEnabled() { return self._enabled }
    Bool isOpen() { return self._open }

    Result<Unit, Error> setFrequency(Context context, Long frequencyHz) {
        if context == null { throw "PwmChannel.setFrequency: null context" }
        if !self._open { return Err(embeddedUnavailable("pwm channel")) }
        if frequencyHz <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "invalid pwm frequency"))
        }
        return Err(embeddedUnsupported("PwmChannel.setFrequency"))
    }

    Result<Unit, Error> setDutyCycle(Context context, Int dutyPermille) {
        if context == null { throw "PwmChannel.setDutyCycle: null context" }
        if !self._open { return Err(embeddedUnavailable("pwm channel")) }
        if dutyPermille < 0 || dutyPermille > 1000 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "duty permille out of range"))
        }
        return Err(embeddedUnsupported("PwmChannel.setDutyCycle"))
    }

    Result<Unit, Error> enable(Context context) {
        if context == null { throw "PwmChannel.enable: null context" }
        if !self._open { return Err(embeddedUnavailable("pwm channel")) }
        if self._enabled { return Ok() }
        return Err(embeddedUnsupported("PwmChannel.enable"))
    }

    Result<Unit, Error> disable(Context context) {
        if context == null { throw "PwmChannel.disable: null context" }
        if !self._open { return Err(embeddedUnavailable("pwm channel")) }
        if !self._enabled { return Ok() }
        return Err(embeddedUnsupported("PwmChannel.disable"))
    }

    Result<Unit, Error> close() {
        if !self._open { return Ok() }
        self._open = false
        self._enabled = false
        return Ok()
    }
}

// ---------- UartPort ----------

class UartPort {
    final Long _handle
    final BoardPin _transmitPin
    final BoardPin _receivePin
    final String _transmitFunction
    final String _receiveFunction
    final SerialOptions _options
    Bool _open

    UartPort(Long handle, BoardPin transmitPin, BoardPin receivePin,
             String transmitFunction, String receiveFunction,
             SerialOptions options) {
        if handle == null || handle <= 0 {
            throw "UartPort: invalid handle"
        }
        if transmitPin == null
            || !transmitPin.supports(PinCapability.UartTransmit) {
            throw "UartPort: invalid transmit pin"
        }
        if receivePin == null
            || !receivePin.supports(PinCapability.UartReceive) {
            throw "UartPort: invalid receive pin"
        }
        if transmitFunction == null || transmitFunction.trim() == "" {
            throw "UartPort: empty transmit function"
        }
        if receiveFunction == null || receiveFunction.trim() == "" {
            throw "UartPort: empty receive function"
        }
        if !transmitPin.hasAlternateFunction(transmitFunction) {
            throw "UartPort: transmit function not on pin"
        }
        if !receivePin.hasAlternateFunction(receiveFunction) {
            throw "UartPort: receive function not on pin"
        }
        if options == null {
            throw "UartPort: null options"
        }
        self._handle = handle
        self._transmitPin = transmitPin
        self._receivePin = receivePin
        self._transmitFunction = transmitFunction
        self._receiveFunction = receiveFunction
        self._options = options
        self._open = true
    }

    static Result<UartPort, Error> open(Context context, BoardPin transmitPin,
                                        BoardPin receivePin,
                                        String transmitFunction,
                                        String receiveFunction,
                                        SerialOptions options) {
        if context == null || transmitPin == null || receivePin == null
            || transmitFunction == null || receiveFunction == null
            || options == null {
            throw "UartPort.open: null argument"
        }
        if transmitFunction.trim() == "" || receiveFunction.trim() == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "empty uart function"))
        }
        if !transmitPin.supports(PinCapability.UartTransmit) {
            return Err(new BasicError(ErrorKind.Unsupported,
                "pin has no uart transmit capability"))
        }
        if !receivePin.supports(PinCapability.UartReceive) {
            return Err(new BasicError(ErrorKind.Unsupported,
                "pin has no uart receive capability"))
        }
        if !transmitPin.hasAlternateFunction(transmitFunction) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "transmit function not on pin"))
        }
        if !receivePin.hasAlternateFunction(receiveFunction) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "receive function not on pin"))
        }
        return Err(embeddedUnsupported("UartPort.open"))
    }

    BoardPin transmitPin() { return self._transmitPin }
    BoardPin receivePin() { return self._receivePin }
    String transmitFunction() { return self._transmitFunction }
    String receiveFunction() { return self._receiveFunction }
    SerialOptions options() { return self._options }
    Bool isOpen() { return self._open }

    Result<Int, Error> read(Context context, Bytes buffer) {
        if context == null || buffer == null {
            throw "UartPort.read: null argument"
        }
        if !self._open { return Err(embeddedUnavailable("uart port")) }
        if buffer.length() == 0 { return Ok(0) }
        return Err(embeddedUnsupported("UartPort.read"))
    }

    Result<Int, Error> write(Context context, Bytes buffer) {
        if context == null || buffer == null {
            throw "UartPort.write: null argument"
        }
        if !self._open { return Err(embeddedUnavailable("uart port")) }
        if buffer.length() == 0 { return Ok(0) }
        return Err(embeddedUnsupported("UartPort.write"))
    }

    Result<Unit, Error> flush(Context context) {
        if context == null { throw "UartPort.flush: null context" }
        if !self._open { return Err(embeddedUnavailable("uart port")) }
        return Err(embeddedUnsupported("UartPort.flush"))
    }

    Result<Unit, Error> close() {
        if !self._open { return Ok() }
        self._open = false
        return Ok()
    }
}

// ---------- CanBus ----------

class CanBus {
    final Long _handle
    final BoardPin _transmitPin
    final BoardPin _receivePin
    final String _transmitFunction
    final String _receiveFunction
    Long _bitrateBitsPerSecond
    Bool _started
    Bool _open

    CanBus(Long handle, BoardPin transmitPin, BoardPin receivePin,
           String transmitFunction, String receiveFunction,
           Long bitrateBitsPerSecond) {
        if handle == null || handle <= 0 {
            throw "CanBus: invalid handle"
        }
        if transmitPin == null
            || !transmitPin.supports(PinCapability.CanTransmit) {
            throw "CanBus: invalid transmit pin"
        }
        if receivePin == null
            || !receivePin.supports(PinCapability.CanReceive) {
            throw "CanBus: invalid receive pin"
        }
        if transmitFunction == null || transmitFunction.trim() == "" {
            throw "CanBus: empty transmit function"
        }
        if receiveFunction == null || receiveFunction.trim() == "" {
            throw "CanBus: empty receive function"
        }
        if !transmitPin.hasAlternateFunction(transmitFunction) {
            throw "CanBus: transmit function not on pin"
        }
        if !receivePin.hasAlternateFunction(receiveFunction) {
            throw "CanBus: receive function not on pin"
        }
        if bitrateBitsPerSecond <= 0 {
            throw "CanBus: invalid bitrate"
        }
        self._handle = handle
        self._transmitPin = transmitPin
        self._receivePin = receivePin
        self._transmitFunction = transmitFunction
        self._receiveFunction = receiveFunction
        self._bitrateBitsPerSecond = bitrateBitsPerSecond
        self._started = false
        self._open = true
    }

    static Result<CanBus, Error> open(Context context, BoardPin transmitPin,
                                      BoardPin receivePin,
                                      String transmitFunction,
                                      String receiveFunction,
                                      Long bitrateBitsPerSecond) {
        if context == null || transmitPin == null || receivePin == null
            || transmitFunction == null || receiveFunction == null {
            throw "CanBus.open: null argument"
        }
        if transmitFunction.trim() == "" || receiveFunction.trim() == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "empty can function"))
        }
        if bitrateBitsPerSecond <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "invalid can bitrate"))
        }
        if !transmitPin.supports(PinCapability.CanTransmit) {
            return Err(new BasicError(ErrorKind.Unsupported,
                "pin has no can transmit capability"))
        }
        if !receivePin.supports(PinCapability.CanReceive) {
            return Err(new BasicError(ErrorKind.Unsupported,
                "pin has no can receive capability"))
        }
        if !transmitPin.hasAlternateFunction(transmitFunction) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "transmit function not on pin"))
        }
        if !receivePin.hasAlternateFunction(receiveFunction) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "receive function not on pin"))
        }
        return Err(embeddedUnsupported("CanBus.open"))
    }

    BoardPin transmitPin() { return self._transmitPin }
    BoardPin receivePin() { return self._receivePin }
    String transmitFunction() { return self._transmitFunction }
    String receiveFunction() { return self._receiveFunction }
    Long bitrateBitsPerSecond() { return self._bitrateBitsPerSecond }
    Bool isStarted() { return self._started }
    Bool isOpen() { return self._open }

    Result<Unit, Error> start(Context context) {
        if context == null { throw "CanBus.start: null context" }
        if !self._open { return Err(embeddedUnavailable("can bus")) }
        if self._started { return Ok() }
        return Err(embeddedUnsupported("CanBus.start"))
    }

    Result<Unit, Error> stop(Context context) {
        if context == null { throw "CanBus.stop: null context" }
        if !self._open { return Err(embeddedUnavailable("can bus")) }
        if !self._started { return Ok() }
        return Err(embeddedUnsupported("CanBus.stop"))
    }

    Result<Unit, Error> setBitrate(Context context,
                                   Long bitrateBitsPerSecond) {
        if context == null { throw "CanBus.setBitrate: null context" }
        if !self._open { return Err(embeddedUnavailable("can bus")) }
        if self._started {
            return Err(new BasicError(ErrorKind.Busy, "can bus is started"))
        }
        if bitrateBitsPerSecond <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "invalid can bitrate"))
        }
        return Err(embeddedUnsupported("CanBus.setBitrate"))
    }

    Result<Int, Error> addFilter(Context context, Int identifier, Int mask,
                                 Bool isExtended) {
        if context == null { throw "CanBus.addFilter: null context" }
        if !self._open { return Err(embeddedUnavailable("can bus")) }
        Long identifierValue = identifier as Long
        Long maskValue = mask as Long
        Long maximumIdentifier = 0x7FF
        if isExtended { maximumIdentifier = 0x1FFFFFFF }
        if identifierValue < 0 || identifierValue > maximumIdentifier {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "can identifier out of range"))
        }
        if maskValue < 0 || maskValue > maximumIdentifier {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "can mask out of range"))
        }
        return Err(embeddedUnsupported("CanBus.addFilter"))
    }

    Result<Unit, Error> removeFilter(Context context, Int filterIdentifier) {
        if context == null { throw "CanBus.removeFilter: null context" }
        if !self._open { return Err(embeddedUnavailable("can bus")) }
        if filterIdentifier < 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "negative can filter identifier"))
        }
        return Err(embeddedUnsupported("CanBus.removeFilter"))
    }

    Result<Unit, Error> send(Context context, Int identifier,
                             Bool isExtended, Bool isRemoteRequest,
                             Int dataLengthCode, Bytes payload,
                             Long timeoutMillis) {
        if context == null || payload == null {
            throw "CanBus.send: null argument"
        }
        if !self._open || !self._started {
            return Err(embeddedUnavailable("can bus"))
        }
        Long identifierValue = identifier as Long
        Long maximumIdentifier = 0x7FF
        if isExtended { maximumIdentifier = 0x1FFFFFFF }
        if identifierValue < 0 || identifierValue > maximumIdentifier {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "can identifier out of range"))
        }
        if dataLengthCode < 0 || dataLengthCode > 8 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "can data length code out of range"))
        }
        if isRemoteRequest {
            if payload.length() != 0 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "remote frame with payload"))
            }
        } else {
            if payload.length() != dataLengthCode {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "can payload length does not match dlc"))
            }
        }
        if timeoutMillis < 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "negative can timeout"))
        }
        return Err(embeddedUnsupported("CanBus.send"))
    }

    Result<List<Int>, Error> receive(Context context, Long timeoutMillis,
                                     Bytes payloadBuffer) {
        if context == null || payloadBuffer == null {
            throw "CanBus.receive: null argument"
        }
        if !self._open || !self._started {
            return Err(embeddedUnavailable("can bus"))
        }
        if timeoutMillis < 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "negative can timeout"))
        }
        if payloadBuffer.length() < 8 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "can payload buffer too small"))
        }
        return Err(embeddedUnsupported("CanBus.receive"))
    }

    Result<Bool, Error> busOff(Context context) {
        if context == null { throw "CanBus.busOff: null context" }
        if !self._open { return Err(embeddedUnavailable("can bus")) }
        return Err(embeddedUnsupported("CanBus.busOff"))
    }

    Result<Int, Error> receiveErrorCount(Context context) {
        if context == null {
            throw "CanBus.receiveErrorCount: null context"
        }
        if !self._open { return Err(embeddedUnavailable("can bus")) }
        return Err(embeddedUnsupported("CanBus.receiveErrorCount"))
    }

    Result<Int, Error> transmitErrorCount(Context context) {
        if context == null {
            throw "CanBus.transmitErrorCount: null context"
        }
        if !self._open { return Err(embeddedUnavailable("can bus")) }
        return Err(embeddedUnsupported("CanBus.transmitErrorCount"))
    }

    Result<Unit, Error> recover(Context context) {
        if context == null { throw "CanBus.recover: null context" }
        if !self._open { return Err(embeddedUnavailable("can bus")) }
        return Err(embeddedUnsupported("CanBus.recover"))
    }

    Result<Unit, Error> close() {
        if !self._open { return Ok() }
        self._open = false
        self._started = false
        return Ok()
    }
}

// ---------- Watchdog ----------

class Watchdog {
    final Long _handle
    Bool _open
    Bool _started
    Long _minimumFeedMillis
    Long _maximumFeedMillis

    Watchdog(Long handle) {
        if handle == null || handle <= 0 {
            throw "Watchdog: invalid handle"
        }
        self._handle = handle
        self._open = true
        self._started = false
        self._minimumFeedMillis = 0
        self._maximumFeedMillis = 0
    }

    static Result<Watchdog, Error> open(Context context, Board board) {
        if context == null || board == null {
            throw "Watchdog.open: null argument"
        }
        if !board.hasWatchdog() {
            return Err(new BasicError(ErrorKind.Unsupported,
                "board has no watchdog"))
        }
        return Err(embeddedUnsupported("Watchdog.open"))
    }

    Long minimumFeedMillis() { return self._minimumFeedMillis }
    Long maximumFeedMillis() { return self._maximumFeedMillis }
    Bool isStarted() { return self._started }
    Bool isOpen() { return self._open }

    Result<Unit, Error> start(Context context, Long timeoutMillis) {
        if context == null { throw "Watchdog.start: null context" }
        if !self._open { return Err(embeddedUnavailable("watchdog")) }
        if self._started {
            return Err(new BasicError(ErrorKind.Busy,
                "watchdog already started"))
        }
        if timeoutMillis <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "invalid watchdog timeout"))
        }
        return Err(embeddedUnsupported("Watchdog.start"))
    }

    Result<Unit, Error> startWindowed(Context context,
                                      Long minimumFeedMillis,
                                      Long maximumFeedMillis) {
        if context == null {
            throw "Watchdog.startWindowed: null context"
        }
        if !self._open { return Err(embeddedUnavailable("watchdog")) }
        if self._started {
            return Err(new BasicError(ErrorKind.Busy,
                "watchdog already started"))
        }
        if minimumFeedMillis < 0
            || maximumFeedMillis <= minimumFeedMillis {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "invalid watchdog window"))
        }
        return Err(embeddedUnsupported("Watchdog.startWindowed"))
    }

    Result<Unit, Error> feed(Context context) {
        if context == null { throw "Watchdog.feed: null context" }
        if !self._open || !self._started {
            return Err(embeddedUnavailable("watchdog"))
        }
        return Err(embeddedUnsupported("Watchdog.feed"))
    }

    Result<Unit, Error> stop(Context context) {
        if context == null { throw "Watchdog.stop: null context" }
        if !self._open { return Err(embeddedUnavailable("watchdog")) }
        if !self._started { return Ok() }
        return Err(embeddedUnsupported("Watchdog.stop"))
    }

    Result<Unit, Error> close() {
        if !self._open { return Ok() }
        self._open = false
        return Ok()
    }
}

// ---------- Rtc ----------

class Rtc {
    final Long _handle
    Int _calibrationPpm
    Bool _open

    Rtc(Long handle) {
        if handle == null || handle <= 0 {
            throw "Rtc: invalid handle"
        }
        self._handle = handle
        self._calibrationPpm = 0
        self._open = true
    }

    static Result<Rtc, Error> open(Context context, Board board) {
        if context == null || board == null {
            throw "Rtc.open: null argument"
        }
        if !board.hasRtc() {
            return Err(new BasicError(ErrorKind.Unsupported,
                "board has no rtc"))
        }
        return Err(embeddedUnsupported("Rtc.open"))
    }

    Int calibrationPpm() { return self._calibrationPpm }
    Bool isOpen() { return self._open }

    Result<Instant, Error> now(Context context) {
        if context == null { throw "Rtc.now: null context" }
        if !self._open { return Err(embeddedUnavailable("rtc")) }
        return Err(embeddedUnsupported("Rtc.now"))
    }

    Result<Unit, Error> setTime(Context context, Instant instant) {
        if context == null || instant == null {
            throw "Rtc.setTime: null argument"
        }
        if !self._open { return Err(embeddedUnavailable("rtc")) }
        return Err(embeddedUnsupported("Rtc.setTime"))
    }

    Result<Unit, Error> setAlarm(Context context, Instant instant) {
        if context == null || instant == null {
            throw "Rtc.setAlarm: null argument"
        }
        if !self._open { return Err(embeddedUnavailable("rtc")) }
        return Err(embeddedUnsupported("Rtc.setAlarm"))
    }

    Result<Unit, Error> clearAlarm(Context context) {
        if context == null { throw "Rtc.clearAlarm: null context" }
        if !self._open { return Err(embeddedUnavailable("rtc")) }
        return Err(embeddedUnsupported("Rtc.clearAlarm"))
    }

    Result<Instant, Error> alarm(Context context) {
        if context == null { throw "Rtc.alarm: null context" }
        if !self._open { return Err(embeddedUnavailable("rtc")) }
        return Err(embeddedUnsupported("Rtc.alarm"))
    }

    Result<Bool, Error> isAlarmPending(Context context) {
        if context == null {
            throw "Rtc.isAlarmPending: null context"
        }
        if !self._open { return Err(embeddedUnavailable("rtc")) }
        return Err(embeddedUnsupported("Rtc.isAlarmPending"))
    }

    Result<Unit, Error> calibrate(Context context, Int partsPerMillion) {
        if context == null { throw "Rtc.calibrate: null context" }
        if !self._open { return Err(embeddedUnavailable("rtc")) }
        if partsPerMillion < -1000 || partsPerMillion > 1000 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "rtc calibration out of range"))
        }
        return Err(embeddedUnsupported("Rtc.calibrate"))
    }

    Result<Unit, Error> close() {
        if !self._open { return Ok() }
        self._open = false
        return Ok()
    }
}

// ---------- FlashRegion ----------

class FlashRegion {
    final Long _handle
    final String _name
    final Long _offsetBytes
    final Long _lengthBytes
    final Long _pageSizeBytes
    final Long _eraseSizeBytes
    final Long _writeSizeBytes
    Bool _open

    FlashRegion(Long handle, String name, Long offsetBytes, Long lengthBytes,
                Long pageSizeBytes, Long eraseSizeBytes,
                Long writeSizeBytes) {
        if handle == null || handle <= 0 {
            throw "FlashRegion: invalid handle"
        }
        if name == null || name.trim() == "" {
            throw "FlashRegion: empty name"
        }
        if offsetBytes < 0 || lengthBytes <= 0 {
            throw "FlashRegion: invalid region"
        }
        if pageSizeBytes <= 0 || eraseSizeBytes <= 0
            || writeSizeBytes <= 0 {
            throw "FlashRegion: invalid geometry"
        }
        if offsetBytes % eraseSizeBytes != 0
            || lengthBytes % eraseSizeBytes != 0 {
            throw "FlashRegion: unaligned region"
        }
        self._handle = handle
        self._name = name
        self._offsetBytes = offsetBytes
        self._lengthBytes = lengthBytes
        self._pageSizeBytes = pageSizeBytes
        self._eraseSizeBytes = eraseSizeBytes
        self._writeSizeBytes = writeSizeBytes
        self._open = true
    }

    static Result<FlashRegion, Error> open(Context context, Board board,
                                           String regionName,
                                           Long offsetBytes,
                                           Long lengthBytes) {
        if context == null || board == null || regionName == null {
            throw "FlashRegion.open: null argument"
        }
        if regionName.trim() == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "empty flash region name"))
        }
        if offsetBytes < 0 || lengthBytes <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "invalid flash region"))
        }
        if board.flashBytes() == 0 {
            return Err(new BasicError(ErrorKind.Unsupported,
                "board has no flash"))
        }
        if lengthBytes > board.flashBytes()
            || offsetBytes > board.flashBytes() - lengthBytes {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "flash region out of bounds"))
        }
        return Err(embeddedUnsupported("FlashRegion.open"))
    }

    String name() { return self._name }
    Long offsetBytes() { return self._offsetBytes }
    Long lengthBytes() { return self._lengthBytes }
    Long pageSizeBytes() { return self._pageSizeBytes }
    Long eraseSizeBytes() { return self._eraseSizeBytes }
    Long writeSizeBytes() { return self._writeSizeBytes }
    Bool isOpen() { return self._open }

    Bool _checkRange(Long offsetBytes, Long lengthBytes) {
        if offsetBytes < 0 || lengthBytes < 0 { return false }
        if offsetBytes > self._lengthBytes { return false }
        if lengthBytes > self._lengthBytes - offsetBytes { return false }
        return true
    }

    Result<Int, Error> read(Context context, Long offsetBytes, Bytes buffer) {
        if context == null || buffer == null {
            throw "FlashRegion.read: null argument"
        }
        if !self._open { return Err(embeddedUnavailable("flash region")) }
        if buffer.length() == 0 { return Ok(0) }
        if !self._checkRange(offsetBytes, buffer.length() as Long) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "flash read out of range"))
        }
        return Err(embeddedUnsupported("FlashRegion.read"))
    }

    Result<Unit, Error> write(Context context, Long offsetBytes,
                              Bytes payload) {
        if context == null || payload == null {
            throw "FlashRegion.write: null argument"
        }
        if !self._open { return Err(embeddedUnavailable("flash region")) }
        if payload.length() == 0 { return Ok() }
        Long payloadLength = payload.length() as Long
        if offsetBytes < 0 || offsetBytes % self._writeSizeBytes != 0
            || payloadLength % self._writeSizeBytes != 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "flash write not aligned"))
        }
        if !self._checkRange(offsetBytes, payloadLength) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "flash write out of range"))
        }
        return Err(embeddedUnsupported("FlashRegion.write"))
    }

    Result<Unit, Error> erase(Context context, Long offsetBytes,
                              Long lengthBytes) {
        if context == null {
            throw "FlashRegion.erase: null context"
        }
        if !self._open { return Err(embeddedUnavailable("flash region")) }
        if lengthBytes <= 0 || offsetBytes < 0
            || offsetBytes % self._eraseSizeBytes != 0
            || lengthBytes % self._eraseSizeBytes != 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "flash erase not aligned"))
        }
        if !self._checkRange(offsetBytes, lengthBytes) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "flash erase out of range"))
        }
        return Err(embeddedUnsupported("FlashRegion.erase"))
    }

    Result<Bool, Error> isErased(Context context, Long offsetBytes,
                                 Long lengthBytes) {
        if context == null {
            throw "FlashRegion.isErased: null context"
        }
        if !self._open { return Err(embeddedUnavailable("flash region")) }
        if lengthBytes < 0 || !self._checkRange(offsetBytes, lengthBytes) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "flash range out of range"))
        }
        if lengthBytes == 0 { return Ok(true) }
        return Err(embeddedUnsupported("FlashRegion.isErased"))
    }

    String describe() {
        return "flash " + self._name + " offset=" + str(self._offsetBytes)
            + " length=" + str(self._lengthBytes)
            + " page=" + str(self._pageSizeBytes)
            + " erase=" + str(self._eraseSizeBytes)
            + " write=" + str(self._writeSizeBytes)
    }

    Result<Unit, Error> close() {
        if !self._open { return Ok() }
        self._open = false
        return Ok()
    }
}

// ---------- Embedded ----------

class Embedded {
    private Embedded() { }

    static Result<AdcChannel, Error> openAdc(Context context,
                                             BoardPin boardPin,
                                             Int resolutionBits,
                                             Long referenceMillivolts) {
        return AdcChannel.open(context, boardPin, resolutionBits,
            referenceMillivolts)
    }

    static Result<PwmChannel, Error> openPwm(Context context,
                                             BoardPin boardPin,
                                             Long frequencyHz) {
        return PwmChannel.open(context, boardPin, frequencyHz)
    }

    static Result<UartPort, Error> openUart(Context context,
                                            BoardPin transmitPin,
                                            BoardPin receivePin,
                                            String transmitFunction,
                                            String receiveFunction,
                                            SerialOptions options) {
        return UartPort.open(context, transmitPin, receivePin,
            transmitFunction, receiveFunction, options)
    }

    static Result<CanBus, Error> openCan(Context context,
                                         BoardPin transmitPin,
                                         BoardPin receivePin,
                                         String transmitFunction,
                                         String receiveFunction,
                                         Long bitrateBitsPerSecond) {
        return CanBus.open(context, transmitPin, receivePin,
            transmitFunction, receiveFunction, bitrateBitsPerSecond)
    }

    static Result<Watchdog, Error> openWatchdog(Context context,
                                                Board board) {
        return Watchdog.open(context, board)
    }

    static Result<Rtc, Error> openRtc(Context context, Board board) {
        return Rtc.open(context, board)
    }

    static Result<FlashRegion, Error> openFlash(Context context, Board board,
                                                String regionName,
                                                Long offsetBytes,
                                                Long lengthBytes) {
        return FlashRegion.open(context, board, regionName, offsetBytes,
            lengthBytes)
    }

    static Result<PowerMode, Error> powerMode(Context context, Board board) {
        if context == null || board == null {
            throw "Embedded.powerMode: null argument"
        }
        return Err(embeddedUnsupported("Embedded.powerMode"))
    }

    static Result<Unit, Error> setPowerMode(Context context, Board board,
                                            PowerMode powerMode) {
        if context == null || board == null || powerMode == null {
            throw "Embedded.setPowerMode: null argument"
        }
        if !board.supportsPowerMode(powerMode) {
            return Err(new BasicError(ErrorKind.Unsupported,
                "board does not support power mode"))
        }
        return Err(embeddedUnsupported("Embedded.setPowerMode"))
    }

    static Result<Unit, Error> sleepFor(Context context, Board board,
                                        PowerMode powerMode,
                                        Long durationMillis) {
        if context == null || board == null || powerMode == null {
            throw "Embedded.sleepFor: null argument"
        }
        if durationMillis <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "invalid sleep duration"))
        }
        if powerMode != PowerMode.Sleep
            && powerMode != PowerMode.DeepSleep {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "sleepFor requires Sleep or DeepSleep"))
        }
        if !board.supportsPowerMode(powerMode) {
            return Err(new BasicError(ErrorKind.Unsupported,
                "board does not support power mode"))
        }
        return Err(embeddedUnsupported("Embedded.sleepFor"))
    }
}
