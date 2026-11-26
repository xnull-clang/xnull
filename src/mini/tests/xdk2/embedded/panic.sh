#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/embedded-panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
package xdk2.embedded
import xdk.embedded
import xdk.errors
import xdk.execution
import xdk.bytes
import xdk.time

static BoardPin pAdcPin() {
    List<PinCapability> caps = [PinCapability.AdcInput]
    List<String> functions = ["ADC1_IN5"]
    return new BoardPin("PA5", 5, "PA5", "GPIOA", 5, caps, functions, 0, -1)
}

static BoardPin pPwmPin() {
    List<PinCapability> caps = [PinCapability.PwmOutput]
    List<String> functions = ["TIM1_CH1"]
    return new BoardPin("PA8", 8, "PA8", "GPIOA", 8, caps, functions, -1, 0)
}

static BoardPin pGpioPin() {
    List<PinCapability> caps = [PinCapability.Gpio]
    List<String> functions = []
    return new BoardPin("LED", 13, "PC13", "GPIOC", 13, caps, functions, -1, -1)
}

static BoardPin pUartTxPin() {
    List<PinCapability> caps = [PinCapability.UartTransmit]
    List<String> functions = ["USART2_TX"]
    return new BoardPin("PA2", 2, "PA2", "GPIOA", 2, caps, functions, -1, -1)
}

static BoardPin pUartRxPin() {
    List<PinCapability> caps = [PinCapability.UartReceive]
    List<String> functions = ["USART2_RX"]
    return new BoardPin("PA3", 3, "PA3", "GPIOA", 3, caps, functions, -1, -1)
}

static BoardPin pCanTxPin() {
    List<PinCapability> caps = [PinCapability.CanTransmit]
    List<String> functions = ["CAN1_TX"]
    return new BoardPin("PA11", 11, "PA11", "GPIOA", 11, caps, functions, -1, -1)
}

static BoardPin pCanRxPin() {
    List<PinCapability> caps = [PinCapability.CanReceive]
    List<String> functions = ["CAN1_RX"]
    return new BoardPin("PA12", 12, "PA12", "GPIOA", 12, caps, functions, -1, -1)
}

static SerialOptions pOptions() {
    return new SerialOptions(115200, 8, SerialParity.None,
        SerialStopBits.One, 1000 as Long, 1000 as Long)
}

static Board pBoard() {
    List<BoardPin> pins = [pAdcPin()]
    List<PowerMode> modes = [PowerMode.Active]
    return new Board("Demo", "", "STM32F407", "", "ARM Cortex-M4",
        168000000 as Long, 1048576 as Long, 262144 as Long, pins, modes,
        1, 1, 1, 1, true, true)
}

static Int main(String[] args) {
    String name = args.get(0)
    if name == "pinName" {
        List<PinCapability> caps = []
        List<String> functions = []
        BoardPin value = new BoardPin("", 0, "PA0", "", 0, caps, functions, -1, -1)
    } else if name == "pinMcu" {
        List<PinCapability> caps = []
        List<String> functions = []
        BoardPin value = new BoardPin("P", 0, "", "", 0, caps, functions, -1, -1)
    } else if name == "pinNumber" {
        List<PinCapability> caps = []
        List<String> functions = []
        BoardPin value = new BoardPin("P", -1, "PA0", "", 0, caps, functions, -1, -1)
    } else if name == "pinPort" {
        List<PinCapability> caps = []
        List<String> functions = []
        BoardPin value = new BoardPin("P", 0, "PA0", "", -1, caps, functions, -1, -1)
    } else if name == "pinNullCaps" {
        List<String> functions = []
        BoardPin value = new BoardPin("P", 0, "PA0", "", 0, null, functions, -1, -1)
    } else if name == "pinNullFunctions" {
        List<PinCapability> caps = []
        BoardPin value = new BoardPin("P", 0, "PA0", "", 0, caps, null, -1, -1)
    } else if name == "pinEmptyFunction" {
        List<PinCapability> caps = []
        List<String> functions = [""]
        BoardPin value = new BoardPin("P", 0, "PA0", "", 0, caps, functions, -1, -1)
    } else if name == "pinDuplicateCap" {
        List<PinCapability> caps = [PinCapability.Gpio, PinCapability.Gpio]
        List<String> functions = []
        BoardPin value = new BoardPin("P", 0, "PA0", "", 0, caps, functions, -1, -1)
    } else if name == "pinDuplicateFunction" {
        List<PinCapability> caps = []
        List<String> functions = ["AF1", "AF1"]
        BoardPin value = new BoardPin("P", 0, "PA0", "", 0, caps, functions, -1, -1)
    } else if name == "pinAdcMismatch" {
        List<PinCapability> caps = [PinCapability.AdcInput]
        List<String> functions = []
        BoardPin value = new BoardPin("P", 0, "PA0", "", 0, caps, functions, -1, -1)
    } else if name == "pinAdcChannel" {
        List<PinCapability> caps = []
        List<String> functions = []
        BoardPin value = new BoardPin("P", 0, "PA0", "", 0, caps, functions, 0, -1)
    } else if name == "pinPwmMismatch" {
        List<PinCapability> caps = [PinCapability.PwmOutput]
        List<String> functions = []
        BoardPin value = new BoardPin("P", 0, "PA0", "", 0, caps, functions, -1, -1)
    } else if name == "pinPwmChannel" {
        List<PinCapability> caps = []
        List<String> functions = []
        BoardPin value = new BoardPin("P", 0, "PA0", "", 0, caps, functions, -1, 0)
    } else if name == "pinChannelNegative" {
        List<PinCapability> caps = []
        List<String> functions = []
        BoardPin value = new BoardPin("P", 0, "PA0", "", 0, caps, functions, -2, -1)
    } else if name == "pinNullCapability" {
        List<PinCapability> caps = [PinCapability.Gpio, PinCapability.Unknown]
        List<String> functions = []
        BoardPin value = new BoardPin("P", 0, "PA0", "", 0, caps, functions, -1, -1)
    } else if name == "boardNullString" {
        List<BoardPin> pins = []
        List<PowerMode> modes = [PowerMode.Active]
        Board value = new Board("B", null, "MCU", "", "", 1 as Long, 0 as Long,
            0 as Long, pins, modes, 0, 0, 0, 0, false, false)
    } else if name == "boardEmptyName" {
        List<BoardPin> pins = []
        List<PowerMode> modes = [PowerMode.Active]
        Board value = new Board("", "", "MCU", "", "", 1 as Long, 0 as Long,
            0 as Long, pins, modes, 0, 0, 0, 0, false, false)
    } else if name == "boardClock" {
        List<BoardPin> pins = []
        List<PowerMode> modes = [PowerMode.Active]
        Board value = new Board("B", "", "MCU", "", "", 0 as Long, 0 as Long,
            0 as Long, pins, modes, 0, 0, 0, 0, false, false)
    } else if name == "boardFlash" {
        List<BoardPin> pins = []
        List<PowerMode> modes = [PowerMode.Active]
        Board value = new Board("B", "", "MCU", "", "", 1 as Long, -1 as Long,
            0 as Long, pins, modes, 0, 0, 0, 0, false, false)
    } else if name == "boardRam" {
        List<BoardPin> pins = []
        List<PowerMode> modes = [PowerMode.Active]
        Board value = new Board("B", "", "MCU", "", "", 1 as Long, 0 as Long,
            -1 as Long, pins, modes, 0, 0, 0, 0, false, false)
    } else if name == "boardCounts" {
        List<BoardPin> pins = []
        List<PowerMode> modes = [PowerMode.Active]
        Board value = new Board("B", "", "MCU", "", "", 1 as Long, 0 as Long,
            0 as Long, pins, modes, -1, 0, 0, 0, false, false)
    } else if name == "boardNullPins" {
        List<PowerMode> modes = [PowerMode.Active]
        Board value = new Board("B", "", "MCU", "", "", 1 as Long, 0 as Long,
            0 as Long, null, modes, 0, 0, 0, 0, false, false)
    } else if name == "boardNullModes" {
        List<BoardPin> pins = []
        Board value = new Board("B", "", "MCU", "", "", 1 as Long, 0 as Long,
            0 as Long, pins, null, 0, 0, 0, 0, false, false)
    } else if name == "boardEmptyModes" {
        List<BoardPin> pins = []
        List<PowerMode> modes = []
        Board value = new Board("B", "", "MCU", "", "", 1 as Long, 0 as Long,
            0 as Long, pins, modes, 0, 0, 0, 0, false, false)
    } else if name == "boardMissingActive" {
        List<BoardPin> pins = []
        List<PowerMode> modes = [PowerMode.Idle]
        Board value = new Board("B", "", "MCU", "", "", 1 as Long, 0 as Long,
            0 as Long, pins, modes, 0, 0, 0, 0, false, false)
    } else if name == "boardDuplicateMode" {
        List<BoardPin> pins = []
        List<PowerMode> modes = [PowerMode.Active, PowerMode.Active]
        Board value = new Board("B", "", "MCU", "", "", 1 as Long, 0 as Long,
            0 as Long, pins, modes, 0, 0, 0, 0, false, false)
    } else if name == "boardNullMode" {
        List<BoardPin> pins = []
        List<PowerMode> modes = [PowerMode.Active, PowerMode.Unknown]
        Board value = new Board("B", "", "MCU", "", "", 1 as Long, 0 as Long,
            0 as Long, pins, modes, 0, 0, 0, 0, false, false)
    } else if name == "boardDuplicatePinNumber" {
        List<PinCapability> caps = []
        List<String> functions = []
        BoardPin one = new BoardPin("A", 1, "PA1", "", 1, caps, functions, -1, -1)
        BoardPin two = new BoardPin("B", 1, "PA2", "", 2, caps, functions, -1, -1)
        List<BoardPin> pins = [one, two]
        List<PowerMode> modes = [PowerMode.Active]
        Board value = new Board("B", "", "MCU", "", "", 1 as Long, 0 as Long,
            0 as Long, pins, modes, 0, 0, 0, 0, false, false)
    } else if name == "boardDuplicatePinName" {
        List<PinCapability> caps = []
        List<String> functions = []
        BoardPin one = new BoardPin("P", 1, "PA1", "", 1, caps, functions, -1, -1)
        BoardPin two = new BoardPin("P", 2, "PA2", "", 2, caps, functions, -1, -1)
        List<BoardPin> pins = [one, two]
        List<PowerMode> modes = [PowerMode.Active]
        Board value = new Board("B", "", "MCU", "", "", 1 as Long, 0 as Long,
            0 as Long, pins, modes, 0, 0, 0, 0, false, false)
    } else if name == "boardAdcRange" {
        List<PinCapability> caps = [PinCapability.AdcInput]
        List<String> functions = []
        BoardPin pin = new BoardPin("P", 1, "PA1", "", 1, caps, functions, 2, -1)
        List<BoardPin> pins = [pin]
        List<PowerMode> modes = [PowerMode.Active]
        Board value = new Board("B", "", "MCU", "", "", 1 as Long, 0 as Long,
            0 as Long, pins, modes, 1, 1, 0, 0, false, false)
    } else if name == "boardPwmRange" {
        List<PinCapability> caps = [PinCapability.PwmOutput]
        List<String> functions = []
        BoardPin pin = new BoardPin("P", 1, "PA1", "", 1, caps, functions, -1, 2)
        List<BoardPin> pins = [pin]
        List<PowerMode> modes = [PowerMode.Active]
        Board value = new Board("B", "", "MCU", "", "", 1 as Long, 0 as Long,
            0 as Long, pins, modes, 1, 1, 0, 0, false, false)
    } else if name == "adcHandle" {
        AdcChannel value = new AdcChannel(0 as Long, pAdcPin(), 0, 12, 3300 as Long)
    } else if name == "adcCapability" {
        AdcChannel value = new AdcChannel(1 as Long, pGpioPin(), 0, 12, 3300 as Long)
    } else if name == "adcChannel" {
        AdcChannel value = new AdcChannel(1 as Long, pAdcPin(), 1, 12, 3300 as Long)
    } else if name == "adcResolution0" {
        AdcChannel value = new AdcChannel(1 as Long, pAdcPin(), 0, 0, 3300 as Long)
    } else if name == "adcResolution25" {
        AdcChannel value = new AdcChannel(1 as Long, pAdcPin(), 0, 25, 3300 as Long)
    } else if name == "adcReference" {
        AdcChannel value = new AdcChannel(1 as Long, pAdcPin(), 0, 12, 0 as Long)
    } else if name == "pwmHandle" {
        PwmChannel value = new PwmChannel(0 as Long, pPwmPin(), 0, 1000 as Long)
    } else if name == "pwmCapability" {
        PwmChannel value = new PwmChannel(1 as Long, pGpioPin(), 0, 1000 as Long)
    } else if name == "pwmChannel" {
        PwmChannel value = new PwmChannel(1 as Long, pPwmPin(), 1, 1000 as Long)
    } else if name == "pwmFrequency" {
        PwmChannel value = new PwmChannel(1 as Long, pPwmPin(), 0, 0 as Long)
    } else if name == "uartHandle" {
        UartPort value = new UartPort(0 as Long, pUartTxPin(), pUartRxPin(),
            "USART2_TX", "USART2_RX", pOptions())
    } else if name == "uartTxCap" {
        UartPort value = new UartPort(1 as Long, pUartRxPin(), pUartRxPin(),
            "USART2_RX", "USART2_RX", pOptions())
    } else if name == "uartRxCap" {
        UartPort value = new UartPort(1 as Long, pUartTxPin(), pUartTxPin(),
            "USART2_TX", "USART2_TX", pOptions())
    } else if name == "uartEmptyTx" {
        UartPort value = new UartPort(1 as Long, pUartTxPin(), pUartRxPin(),
            "", "USART2_RX", pOptions())
    } else if name == "uartMissingTx" {
        UartPort value = new UartPort(1 as Long, pUartTxPin(), pUartRxPin(),
            "USART3_TX", "USART2_RX", pOptions())
    } else if name == "uartNullOptions" {
        UartPort value = new UartPort(1 as Long, pUartTxPin(), pUartRxPin(),
            "USART2_TX", "USART2_RX", null)
    } else if name == "canHandle" {
        CanBus value = new CanBus(0 as Long, pCanTxPin(), pCanRxPin(),
            "CAN1_TX", "CAN1_RX", 500000 as Long)
    } else if name == "canTxCap" {
        CanBus value = new CanBus(1 as Long, pCanRxPin(), pCanRxPin(),
            "CAN1_RX", "CAN1_RX", 500000 as Long)
    } else if name == "canRxCap" {
        CanBus value = new CanBus(1 as Long, pCanTxPin(), pCanTxPin(),
            "CAN1_TX", "CAN1_TX", 500000 as Long)
    } else if name == "canEmptyTx" {
        CanBus value = new CanBus(1 as Long, pCanTxPin(), pCanRxPin(),
            "", "CAN1_RX", 500000 as Long)
    } else if name == "canMissingTx" {
        CanBus value = new CanBus(1 as Long, pCanTxPin(), pCanRxPin(),
            "CAN2_TX", "CAN1_RX", 500000 as Long)
    } else if name == "canBitrate" {
        CanBus value = new CanBus(1 as Long, pCanTxPin(), pCanRxPin(),
            "CAN1_TX", "CAN1_RX", 0 as Long)
    } else if name == "watchdogHandle" {
        Watchdog value = new Watchdog(0 as Long)
    } else if name == "rtcHandle" {
        Rtc value = new Rtc(-1 as Long)
    } else if name == "flashHandle" {
        FlashRegion value = new FlashRegion(0 as Long, "config", 0 as Long,
            4096 as Long, 4096 as Long, 4096 as Long, 256 as Long)
    } else if name == "flashName" {
        FlashRegion value = new FlashRegion(1 as Long, "", 0 as Long,
            4096 as Long, 4096 as Long, 4096 as Long, 256 as Long)
    } else if name == "flashOffset" {
        FlashRegion value = new FlashRegion(1 as Long, "config", -1 as Long,
            4096 as Long, 4096 as Long, 4096 as Long, 256 as Long)
    } else if name == "flashLength" {
        FlashRegion value = new FlashRegion(1 as Long, "config", 0 as Long,
            0 as Long, 4096 as Long, 4096 as Long, 256 as Long)
    } else if name == "flashPage" {
        FlashRegion value = new FlashRegion(1 as Long, "config", 0 as Long,
            4096 as Long, 0 as Long, 4096 as Long, 256 as Long)
    } else if name == "flashUnaligned" {
        FlashRegion value = new FlashRegion(1 as Long, "config", 0 as Long,
            100 as Long, 4096 as Long, 4096 as Long, 256 as Long)
    } else if name == "powerNullContext" {
        Result<PowerMode, Error> value = Embedded.powerMode(null, pBoard())
    } else if name == "setNullBoard" {
        Result<Unit, Error> value = Embedded.setPowerMode(Context.background(),
            null, PowerMode.Active)
    } else if name == "sleepNullMode" {
        Result<Unit, Error> value = Embedded.sleepFor(Context.background(),
            pBoard(), PowerMode.Unknown, 10 as Long)
    } else if name == "adcReadNull" {
        AdcChannel channel = new AdcChannel(1 as Long, pAdcPin(), 0, 12,
            3300 as Long)
        Result<Int, Error> value = channel.read(null)
    } else if name == "pwmDutyNull" {
        PwmChannel channel = new PwmChannel(1 as Long, pPwmPin(), 0, 1000 as Long)
        Result<Unit, Error> value = channel.setDutyCycle(null, 100)
    } else if name == "uartReadNull" {
        UartPort port = new UartPort(1 as Long, pUartTxPin(), pUartRxPin(),
            "USART2_TX", "USART2_RX", pOptions())
        Result<Int, Error> value = port.read(Context.background(), null)
    } else if name == "canSendNull" {
        CanBus bus = new CanBus(1 as Long, pCanTxPin(), pCanRxPin(),
            "CAN1_TX", "CAN1_RX", 500000 as Long)
        Result<Unit, Error> value = bus.send(Context.background(), 0x123, false,
            false, 0, null, 0 as Long)
    } else if name == "flashReadNull" {
        FlashRegion region = new FlashRegion(1 as Long, "config", 0 as Long,
            4096 as Long, 4096 as Long, 4096 as Long, 256 as Long)
        Result<Int, Error> value = region.read(Context.background(), 0 as Long,
            null)
    } else if name == "rtcSetTimeNull" {
        Rtc rtc = new Rtc(1 as Long)
        Result<Unit, Error> value = rtc.setTime(Context.background(), null)
    } else if name == "watchdogStartNull" {
        Watchdog watchdog = new Watchdog(1 as Long)
        Result<Unit, Error> value = watchdog.start(null, 1000 as Long)
    } else if name == "serialBaud" {
        SerialOptions value = new SerialOptions(0, 8, SerialParity.None,
            SerialStopBits.One, 0 as Long, 0 as Long)
    } else if name == "serialDataBits" {
        SerialOptions value = new SerialOptions(115200, 9, SerialParity.None,
            SerialStopBits.One, 0 as Long, 0 as Long)
    } else if name == "serialParity" {
        SerialOptions value = new SerialOptions(115200, 8, SerialParity.Unknown,
            SerialStopBits.One, 0 as Long, 0 as Long)
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || { cat "$TMP/build.err" >&2; exit 1; }
check_panic() {
    name=$1; marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && { echo "embedded panic: $name did not fail" >&2; exit 1; }
    grep -Fq "$marker" "$TMP/$name.err" || { echo "embedded panic: $name missing '$marker'" >&2; cat "$TMP/$name.err" >&2; exit 1; }
}
check_panic pinName "BoardPin: empty name"
check_panic pinMcu "BoardPin: empty name"
check_panic pinNumber "BoardPin: negative number"
check_panic pinPort "BoardPin: negative number"
check_panic pinNullCaps "BoardPin: null list"
check_panic pinNullFunctions "BoardPin: null list"
check_panic pinEmptyFunction "BoardPin: empty alternate function"
check_panic pinDuplicateCap "BoardPin: duplicate capability"
check_panic pinDuplicateFunction "BoardPin: duplicate alternate function"
check_panic pinAdcMismatch "BoardPin: adc capability/channel mismatch"
check_panic pinAdcChannel "BoardPin: adc capability/channel mismatch"
check_panic pinPwmMismatch "BoardPin: pwm capability/channel mismatch"
check_panic pinPwmChannel "BoardPin: pwm capability/channel mismatch"
check_panic pinChannelNegative "BoardPin: invalid channel number"
check_panic pinNullCapability "BoardPin: null capability"
check_panic boardNullString "Board: null string"
check_panic boardEmptyName "Board: empty name"
check_panic boardClock "Board: non-positive clock"
check_panic boardFlash "Board: negative capacity"
check_panic boardRam "Board: negative capacity"
check_panic boardCounts "Board: negative capability count"
check_panic boardNullPins "Board: null list"
check_panic boardNullModes "Board: null list"
check_panic boardEmptyModes "Board: empty power mode list"
check_panic boardMissingActive "Board: missing Active power mode"
check_panic boardDuplicateMode "Board: duplicate power mode"
check_panic boardNullMode "Board: null power mode"
check_panic boardDuplicatePinNumber "Board: duplicate board pin number"
check_panic boardDuplicatePinName "Board: duplicate board pin name"
check_panic boardAdcRange "Board: adc channel out of range"
check_panic boardPwmRange "Board: pwm channel out of range"
check_panic adcHandle "AdcChannel: invalid handle"
check_panic adcCapability "AdcChannel: pin has no adc capability"
check_panic adcChannel "AdcChannel: channel mismatch"
check_panic adcResolution0 "AdcChannel: invalid resolution"
check_panic adcResolution25 "AdcChannel: invalid resolution"
check_panic adcReference "AdcChannel: invalid reference"
check_panic pwmHandle "PwmChannel: invalid handle"
check_panic pwmCapability "PwmChannel: pin has no pwm capability"
check_panic pwmChannel "PwmChannel: channel mismatch"
check_panic pwmFrequency "PwmChannel: invalid frequency"
check_panic uartHandle "UartPort: invalid handle"
check_panic uartTxCap "UartPort: invalid transmit pin"
check_panic uartRxCap "UartPort: invalid receive pin"
check_panic uartEmptyTx "UartPort: empty transmit function"
check_panic uartMissingTx "UartPort: transmit function not on pin"
check_panic uartNullOptions "UartPort: null options"
check_panic canHandle "CanBus: invalid handle"
check_panic canTxCap "CanBus: invalid transmit pin"
check_panic canRxCap "CanBus: invalid receive pin"
check_panic canEmptyTx "CanBus: empty transmit function"
check_panic canMissingTx "CanBus: transmit function not on pin"
check_panic canBitrate "CanBus: invalid bitrate"
check_panic watchdogHandle "Watchdog: invalid handle"
check_panic rtcHandle "Rtc: invalid handle"
check_panic flashHandle "FlashRegion: invalid handle"
check_panic flashName "FlashRegion: empty name"
check_panic flashOffset "FlashRegion: invalid region"
check_panic flashLength "FlashRegion: invalid region"
check_panic flashPage "FlashRegion: invalid geometry"
check_panic flashUnaligned "FlashRegion: unaligned region"
check_panic powerNullContext "Embedded.powerMode: null argument"
check_panic setNullBoard "Embedded.setPowerMode: null argument"
check_panic sleepNullMode "Embedded.sleepFor: null argument"
check_panic adcReadNull "AdcChannel.read: null context"
check_panic pwmDutyNull "PwmChannel.setDutyCycle: null context"
check_panic uartReadNull "UartPort.read: null argument"
check_panic canSendNull "CanBus.send: null argument"
check_panic flashReadNull "FlashRegion.read: null argument"
check_panic rtcSetTimeNull "Rtc.setTime: null argument"
check_panic watchdogStartNull "Watchdog.start: null context"
check_panic serialBaud "SerialOptions: baud rate must be positive"
check_panic serialDataBits "SerialOptions: data bits out of range"
check_panic serialParity "SerialOptions: null parity/stop bits"
echo "embedded_panic: PASS"
