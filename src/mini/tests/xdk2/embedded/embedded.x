package xdk2.embedded
import xdk.embedded
import xdk.errors
import xdk.execution
import xdk.bytes
import xdk.time

static String embPinName(BoardPin? pin) {
    if pin == null { return "null" }
    BoardPin actual = pin as BoardPin
    return actual.name()
}

static String embCapabilityRow(PinCapability? capability) {
    return pinCapabilityDescribe(capability) + ":"
        + str(pinCapabilityIsInput(capability)) + ","
        + str(pinCapabilityIsOutput(capability)) + ","
        + str(pinCapabilityIsBusSignal(capability)) + ","
        + str(pinCapabilityIsAnalog(capability))
}

static String embPowerRow(PowerMode? powerMode) {
    return powerModeDescribe(powerMode) + ":"
        + str(powerModeIsRunning(powerMode)) + ","
        + str(powerModeIsLowPower(powerMode)) + ","
        + str(powerModeInvalidatesHandles(powerMode)) + ","
        + str(powerModeRequiresWakeSource(powerMode))
}

static String embTransitionRow(PowerMode? from) {
    String row = ""
    if powerModeCanTransition(from, PowerMode.Active) { row = row + "1" }
    else { row = row + "0" }
    if powerModeCanTransition(from, PowerMode.Idle) { row = row + "1" }
    else { row = row + "0" }
    if powerModeCanTransition(from, PowerMode.Sleep) { row = row + "1" }
    else { row = row + "0" }
    if powerModeCanTransition(from, PowerMode.DeepSleep) { row = row + "1" }
    else { row = row + "0" }
    if powerModeCanTransition(from, PowerMode.Off) { row = row + "1" }
    else { row = row + "0" }
    return row
}

static BoardPin embPin(String name, Int number, String mcuName, String port,
                       Int portNumber, List<PinCapability> capabilities,
                       List<String> functions, Int adc, Int pwm) {
    return new BoardPin(name, number, mcuName, port, portNumber, capabilities,
        functions, adc, pwm)
}

static Board embBoard() {
    List<PinCapability> adcCaps = [PinCapability.AdcInput]
    List<String> adcFunctions = ["ADC1_IN5"]
    BoardPin pa5 = embPin("PA5", 5, "PA5", "GPIOA", 5, adcCaps,
        adcFunctions, 0, -1)

    List<PinCapability> pwmCaps = [PinCapability.PwmOutput]
    List<String> pwmFunctions = ["TIM1_CH1"]
    BoardPin pa8 = embPin("PA8", 8, "PA8", "GPIOA", 8, pwmCaps,
        pwmFunctions, -1, 0)

    List<PinCapability> txCaps = [PinCapability.UartTransmit]
    List<String> txFunctions = ["USART2_TX"]
    BoardPin pa2 = embPin("PA2", 2, "PA2", "GPIOA", 2, txCaps,
        txFunctions, -1, -1)

    List<PinCapability> rxCaps = [PinCapability.UartReceive]
    List<String> rxFunctions = ["USART2_RX"]
    BoardPin pa3 = embPin("PA3", 3, "PA3", "GPIOA", 3, rxCaps,
        rxFunctions, -1, -1)

    List<PinCapability> canTxCaps = [PinCapability.CanTransmit]
    List<String> canTxFunctions = ["CAN1_TX"]
    BoardPin pa11 = embPin("PA11", 11, "PA11", "GPIOA", 11, canTxCaps,
        canTxFunctions, -1, -1)

    List<PinCapability> canRxCaps = [PinCapability.CanReceive]
    List<String> canRxFunctions = ["CAN1_RX"]
    BoardPin pa12 = embPin("PA12", 12, "PA12", "GPIOA", 12, canRxCaps,
        canRxFunctions, -1, -1)

    List<PinCapability> gpioCaps = [PinCapability.Gpio]
    List<String> noFunctions = []
    BoardPin led = embPin("LED", 13, "PC13", "GPIOC", 13, gpioCaps,
        noFunctions, -1, -1)

    List<PinCapability> mixedCaps = [PinCapability.Gpio,
        PinCapability.AdcInput, PinCapability.PwmOutput]
    List<String> mixedFunctions = ["ADC1_IN6", "TIM3_CH1"]
    BoardPin pa6 = embPin("PA6", 6, "PA6", "GPIOA", 6, mixedCaps,
        mixedFunctions, 1, 1)

    List<BoardPin> pins = [pa5, pa8, pa2, pa3, pa11, pa12, led, pa6]
    List<PowerMode> modes = [PowerMode.Active, PowerMode.Idle,
        PowerMode.Sleep, PowerMode.DeepSleep, PowerMode.Off]
    return new Board("Demo", "XNull", "STM32F407", "STM32F4",
        "ARM Cortex-M4", 168000000 as Long, 1048576 as Long,
        262144 as Long, pins, modes, 2, 2, 1, 1, true, true)
}

static Board embMinimalBoard() {
    List<BoardPin> pins = []
    List<PowerMode> modes = [PowerMode.Active]
    return new Board("Minimal", "", "RV32", "", "RISC-V", 1000000 as Long,
        0, 65536, pins, modes, 0, 0, 0, 0, false, false)
}

static Int main() {
    print("caps="
        + embCapabilityRow(PinCapability.Unknown) + "|"
        + embCapabilityRow(PinCapability.Gpio) + "|"
        + embCapabilityRow(PinCapability.AdcInput) + "|"
        + embCapabilityRow(PinCapability.PwmOutput) + "|"
        + embCapabilityRow(PinCapability.UartTransmit) + "|"
        + embCapabilityRow(PinCapability.UartReceive) + "|"
        + embCapabilityRow(PinCapability.CanTransmit) + "|"
        + embCapabilityRow(PinCapability.CanReceive) + "|"
        + embCapabilityRow(PinCapability.I2cClock) + "|"
        + embCapabilityRow(PinCapability.I2cData) + "|"
        + embCapabilityRow(PinCapability.SpiClock) + "|"
        + embCapabilityRow(PinCapability.SpiMosi) + "|"
        + embCapabilityRow(PinCapability.SpiMiso) + "|"
        + embCapabilityRow(PinCapability.SpiSelect) + "|"
        + embCapabilityRow(PinCapability.ClockOutput) + "|"
        + embCapabilityRow(PinCapability.Wakeup) + "|"
        + embCapabilityRow(PinCapability.Debug) + "|"
        + embCapabilityRow(PinCapability.PowerEnable) + "|"
        + embCapabilityRow(PinCapability.Other))
    print("caps-null=" + embCapabilityRow(null))
    PinCapability fromName = pinCapabilityFromName("AdcInput")
    print("caps-from=" + pinCapabilityDescribe(fromName) + ","
        + pinCapabilityDescribe(pinCapabilityFromName("Other")) + ","
        + str(pinCapabilityFromName("bogus") == PinCapability.Unknown) + ","
        + str(pinCapabilityFromName(null) == PinCapability.Unknown))

    print("power="
        + embPowerRow(PowerMode.Unknown) + "|"
        + embPowerRow(PowerMode.Active) + "|"
        + embPowerRow(PowerMode.Idle) + "|"
        + embPowerRow(PowerMode.Sleep) + "|"
        + embPowerRow(PowerMode.DeepSleep) + "|"
        + embPowerRow(PowerMode.Off))
    print("power-null=" + embPowerRow(null))
    print("power-from=" + powerModeDescribe(powerModeFromName("DeepSleep"))
        + "," + str(powerModeFromName("bogus") == PowerMode.Unknown) + ","
        + str(powerModeFromName(null) == PowerMode.Unknown))
    print("transitions=" + embTransitionRow(PowerMode.Active) + ","
        + embTransitionRow(PowerMode.Idle) + ","
        + embTransitionRow(PowerMode.Sleep) + ","
        + embTransitionRow(PowerMode.DeepSleep) + ","
        + embTransitionRow(PowerMode.Off) + ","
        + str(powerModeCanTransition(null, PowerMode.Active)) + ","
        + str(powerModeCanTransition(PowerMode.Active, null)))

    List<PinCapability> adcCaps = [PinCapability.AdcInput]
    List<String> adcFunctions = ["ADC1_IN5"]
    BoardPin pa5 = embPin("PA5", 5, "PA5", "GPIOA", 5, adcCaps,
        adcFunctions, 0, -1)
    print("pin=" + pa5.name() + "," + str(pa5.boardPinNumber()) + ","
        + pa5.mcuPinName() + "," + pa5.portName() + ","
        + str(pa5.portPinNumber()) + "," + str(pa5.supports(PinCapability.AdcInput))
        + "," + str(pa5.supports(PinCapability.PwmOutput)) + ","
        + str(pa5.supports(null)) + "," + str(pa5.adcChannelNumber()) + ","
        + str(pa5.pwmChannelNumber()))
    print("pin-caps=" + pinCapabilityDescribe(pa5.capabilities().get(0)) + ","
        + str(pa5.capabilities().length()) + ","
        + str(pa5.hasAlternateFunction("ADC1_IN5")) + ","
        + str(pa5.hasAlternateFunction("adc1_in5")) + ","
        + str(pa5.hasAlternateFunction("")) + ","
        + str(pa5.hasAlternateFunction(null)))
    print("pin-copy=" + str(pa5.capabilities().length()) + ","
        + str(pa5.alternateFunctions().length()))
    pa5.capabilities().push(PinCapability.Gpio)
    pa5.alternateFunctions().push("EXTRA")
    print("pin-copy-after=" + str(pa5.capabilities().length()) + ","
        + str(pa5.alternateFunctions().length()))
    print("pin-desc=" + pa5.describe())
    print("pin-eq=" + str(pa5.equals(new BoardPin("PA5", 5, "PA5", "GPIOA", 5,
        adcCaps, adcFunctions, 0, -1))) + "," + str(pa5.equals(null)))

    Board board = embBoard()
    Board sameBoard = embBoard()
    Board minimal = embMinimalBoard()
    print("board=" + board.name() + "," + board.vendor() + ","
        + board.mcuName() + "," + board.mcuFamily() + ","
        + board.cpuArchitecture() + "," + str(board.clockFrequencyHz()) + ","
        + str(board.flashBytes()) + "," + str(board.ramBytes()) + ","
        + str(board.pinCount()) + "," + str(board.adcChannelCount()) + ","
        + str(board.pwmChannelCount()) + "," + str(board.uartPortCount()) + ","
        + str(board.canBusCount()) + "," + str(board.hasWatchdog()) + ","
        + str(board.hasRtc()))
    print("board-find=" + embPinName(board.findPin("PA5")) + ","
        + embPinName(board.findPinByNumber(8)) + ","
        + embPinName(board.findPinByMcuName("PC13")) + ","
        + embPinName(board.findPin("missing")) + ","
        + embPinName(board.findPinByNumber(-1)) + ","
        + embPinName(board.findPinByMcuName(null)) + ","
        + embPinName(board.findPin(null)))
    print("board-power=" + str(board.supportsPowerMode(PowerMode.Active)) + ","
        + str(board.supportsPowerMode(PowerMode.Sleep)) + ","
        + str(board.supportsPowerMode(PowerMode.Off)) + ","
        + str(board.supportsPowerMode(null)) + ","
        + str(board.powerModes().length()) + ","
        + str(board.equals(sameBoard)) + "," + str(board.equals(minimal)) + ","
        + str(board.equals(null)))
    board.pins().push(pa5)
    board.powerModes().push(PowerMode.Active)
    print("board-copy=" + str(board.pinCount()) + ","
        + str(board.powerModes().length()))
    print("board-desc=" + board.describe())

    Result<AdcChannel, Error> adcOpen = Embedded.openAdc(Context.background(),
        pa5, 12, 3300 as Long)
    print("adc-open=" + errorKindName(adcOpen.error().kind()) + ","
        + str(Embedded.openAdc(Context.background(), pa5, 0,
            3300 as Long).error().kind() == ErrorKind.InvalidArgument) + ","
        + str(AdcChannel.open(Context.background(), pa5, 12,
            0 as Long).error().kind() == ErrorKind.InvalidArgument))
    AdcChannel adc = new AdcChannel(1 as Long, pa5, 0, 12, 3300 as Long)
    print("adc=" + adc.boardPin().name() + "," + str(adc.channelNumber()) + ","
        + str(adc.resolutionBits()) + "," + str(adc.referenceMillivolts()) + ","
        + str(adc.isOpen()))
    print("adc-read=" + errorKindName(adc.read(Context.background()).error().kind())
        + "," + errorKindName(adc.readMillivolts(Context.background()).error().kind()))
    Result<Unit, Error> adcClose = adc.close()
    Result<Unit, Error> adcCloseAgain = adc.close()
    print("adc-close=" + str(adcClose.isOk()) + "," + str(adcCloseAgain.isOk())
        + "," + str(adc.isOpen()) + ","
        + errorKindName(adc.read(Context.background()).error().kind()))
    print("adc-after=" + adc.boardPin().name() + ","
        + str(adc.channelNumber()) + "," + str(adc.resolutionBits()) + ","
        + str(adc.referenceMillivolts()))

    BoardPin pa8 = board.findPinByNumber(8) as BoardPin
    Result<PwmChannel, Error> pwmOpen = Embedded.openPwm(Context.background(),
        pa8, 1000 as Long)
    print("pwm-open=" + errorKindName(pwmOpen.error().kind()) + ","
        + str(PwmChannel.open(Context.background(), pa8, 0 as Long).error().kind()
            == ErrorKind.InvalidArgument))
    PwmChannel pwm = new PwmChannel(2 as Long, pa8, 0, 1000 as Long)
    print("pwm=" + pwm.boardPin().name() + "," + str(pwm.channelNumber()) + ","
        + str(pwm.frequencyHz()) + "," + str(pwm.dutyPermille()) + ","
        + str(pwm.isEnabled()) + "," + str(pwm.isOpen()))
    print("pwm-duty=" + errorKindName(pwm.setDutyCycle(Context.background(), 1001)
        .error().kind()) + ","
        + errorKindName(pwm.setDutyCycle(Context.background(), 250)
            .error().kind()) + "," + str(pwm.dutyPermille()))
    print("pwm-frequency="
        + errorKindName(pwm.setFrequency(Context.background(), 2000 as Long)
            .error().kind()) + "," + str(pwm.frequencyHz()))
    print("pwm-enable=" + errorKindName(pwm.enable(Context.background())
        .error().kind()) + "," + str(pwm.isEnabled()) + ","
        + str(pwm.disable(Context.background()).isOk()))
    Result<Unit, Error> pwmClose = pwm.close()
    Result<Unit, Error> pwmCloseAgain = pwm.close()
    print("pwm-close=" + str(pwmClose.isOk()) + "," + str(pwmCloseAgain.isOk())
        + "," + str(pwm.isOpen()) + "," + str(pwm.isEnabled()) + ","
        + errorKindName(pwm.setDutyCycle(Context.background(), 100)
            .error().kind()) + "," + str(pwm.frequencyHz()) + ","
        + str(pwm.dutyPermille()))

    BoardPin pa2 = board.findPinByNumber(2) as BoardPin
    BoardPin pa3 = board.findPinByNumber(3) as BoardPin
    SerialOptions options = new SerialOptions(115200, 8, SerialParity.None,
        SerialStopBits.One, 1000 as Long, 1000 as Long)
    Result<UartPort, Error> uartOpen = Embedded.openUart(Context.background(),
        pa2, pa3, "USART2_TX", "USART2_RX", options)
    print("uart-open=" + errorKindName(uartOpen.error().kind()) + ","
        + str(UartPort.open(Context.background(), pa2, pa3, "", "USART2_RX",
            options).error().kind() == ErrorKind.InvalidArgument) + ","
        + str(UartPort.open(Context.background(), pa2, pa3, "USART2_TX",
            "WRONG_RX", options).error().kind() == ErrorKind.InvalidArgument))
    UartPort uart = new UartPort(3 as Long, pa2, pa3, "USART2_TX",
        "USART2_RX", options)
    Bytes empty = Bytes.alloc(0)
    Bytes data = Bytes.alloc(4)
    print("uart=" + uart.transmitPin().name() + ","
        + uart.receivePin().name() + "," + uart.transmitFunction() + ","
        + uart.receiveFunction() + "," + str(uart.options().baudRate()) + ","
        + str(uart.isOpen()))
    print("uart-options=" + uart.options().describe())
    print("uart-empty=" + str(uart.read(Context.background(), empty).value()) + ","
        + str(uart.write(Context.background(), empty).value()))
    print("uart-io=" + errorKindName(uart.read(Context.background(), data)
        .error().kind()) + ","
        + errorKindName(uart.write(Context.background(), data).error().kind()) + ","
        + errorKindName(uart.flush(Context.background()).error().kind()))
    Result<Unit, Error> uartClose = uart.close()
    Result<Unit, Error> uartCloseAgain = uart.close()
    print("uart-close=" + str(uartClose.isOk()) + ","
        + str(uartCloseAgain.isOk()) + "," + str(uart.isOpen()) + ","
        + errorKindName(uart.read(Context.background(), data).error().kind()))

    BoardPin pa11 = board.findPinByNumber(11) as BoardPin
    BoardPin pa12 = board.findPinByNumber(12) as BoardPin
    print("can-pin-check=" + pa11.name() + ","
        + str(pa11.supports(PinCapability.CanTransmit)) + ","
        + str(pa11.hasAlternateFunction("CAN1_TX")) + "," + pa12.name() + ","
        + str(pa12.supports(PinCapability.CanReceive)) + ","
        + str(pa12.hasAlternateFunction("CAN1_RX")))
    Result<CanBus, Error> canOpen = Embedded.openCan(Context.background(), pa11,
        pa12, "CAN1_TX", "CAN1_RX", 500000 as Long)
    print("can-open=" + errorKindName(canOpen.error().kind()) + ","
        + str(CanBus.open(Context.background(), pa11, pa12, "CAN1_TX",
            "CAN1_RX", 0 as Long).error().kind() == ErrorKind.InvalidArgument))
    CanBus can = new CanBus(4 as Long, pa11, pa12, "CAN1_TX", "CAN1_RX",
        500000 as Long)
    print("can=" + can.transmitPin().name() + "," + can.receivePin().name()
        + "," + str(can.bitrateBitsPerSecond()) + ","
        + str(can.isStarted()) + "," + str(can.isOpen()))
    print("can-start=" + errorKindName(can.start(Context.background())
        .error().kind()) + "," + str(can.isStarted()) + ","
        + str(can.stop(Context.background()).isOk()))
    print("can-bitrate="
        + errorKindName(can.setBitrate(Context.background(), 250000 as Long)
            .error().kind()) + "," + str(can.bitrateBitsPerSecond()) + ","
        + errorKindName(can.setBitrate(Context.background(), 0 as Long)
            .error().kind()))
    print("can-filter="
        + errorKindName(can.addFilter(Context.background(), 0x800, 0x7FF, false)
            .error().kind()) + ","
        + errorKindName(can.addFilter(Context.background(), 0x123, 0x7FF, false)
            .error().kind()) + ","
        + errorKindName(can.removeFilter(Context.background(), -1).error().kind())
        + "," + errorKindName(can.removeFilter(Context.background(), 7)
            .error().kind()))
    Bytes canPayload = Bytes.alloc(2)
    Bytes canBuffer = Bytes.alloc(8)
    print("can-unstarted="
        + errorKindName(can.send(Context.background(), 0x123, false, false, 2,
            canPayload, 0 as Long).error().kind()) + ","
        + errorKindName(can.receive(Context.background(), 0 as Long, canBuffer)
            .error().kind()))
    print("can-diagnostics="
        + errorKindName(can.busOff(Context.background()).error().kind()) + ","
        + errorKindName(can.receiveErrorCount(Context.background()).error().kind())
        + "," + errorKindName(can.transmitErrorCount(Context.background())
            .error().kind()) + ","
        + errorKindName(can.recover(Context.background()).error().kind()))
    Result<Unit, Error> canClose = can.close()
    Result<Unit, Error> canCloseAgain = can.close()
    print("can-close=" + str(canClose.isOk()) + "," + str(canCloseAgain.isOk())
        + "," + str(can.isOpen()) + "," + str(can.isStarted()) + ","
        + errorKindName(can.start(Context.background()).error().kind()))

    Result<Watchdog, Error> wdtMissing = Embedded.openWatchdog(
        Context.background(), minimal)
    Result<Watchdog, Error> wdtOpen = Embedded.openWatchdog(Context.background(),
        board)
    print("wdt-open=" + errorKindName(wdtMissing.error().kind()) + ","
        + errorKindName(wdtOpen.error().kind()))
    Watchdog wdt = new Watchdog(5 as Long)
    print("wdt=" + str(wdt.minimumFeedMillis()) + ","
        + str(wdt.maximumFeedMillis()) + "," + str(wdt.isStarted()) + ","
        + str(wdt.isOpen()))
    print("wdt-start="
        + errorKindName(wdt.start(Context.background(), 0 as Long).error().kind())
        + "," + errorKindName(wdt.start(Context.background(), 1000 as Long)
            .error().kind()) + "," + str(wdt.isStarted()))
    print("wdt-window="
        + errorKindName(wdt.startWindowed(Context.background(), -1 as Long,
            100 as Long).error().kind()) + ","
        + errorKindName(wdt.startWindowed(Context.background(), 100 as Long,
            100 as Long).error().kind()) + ","
        + errorKindName(wdt.startWindowed(Context.background(), 100 as Long,
            500 as Long).error().kind()))
    print("wdt-feed=" + errorKindName(wdt.feed(Context.background())
        .error().kind()) + "," + str(wdt.stop(Context.background()).isOk()))
    Result<Unit, Error> wdtClose = wdt.close()
    Result<Unit, Error> wdtCloseAgain = wdt.close()
    print("wdt-close=" + str(wdtClose.isOk()) + ","
        + str(wdtCloseAgain.isOk()) + "," + str(wdt.isOpen()) + ","
        + str(wdt.isStarted()) + ","
        + errorKindName(wdt.start(Context.background(), 1000 as Long)
            .error().kind()))

    Result<Rtc, Error> rtcMissing = Embedded.openRtc(Context.background(),
        minimal)
    Result<Rtc, Error> rtcOpen = Embedded.openRtc(Context.background(), board)
    print("rtc-open=" + errorKindName(rtcMissing.error().kind()) + ","
        + errorKindName(rtcOpen.error().kind()))
    Rtc rtc = new Rtc(6 as Long)
    Instant instant = Instant.ofEpochMillis(1000 as Long)
    print("rtc=" + str(rtc.calibrationPpm()) + "," + str(rtc.isOpen()))
    print("rtc-now=" + errorKindName(rtc.now(Context.background())
        .error().kind()) + ","
        + errorKindName(rtc.setTime(Context.background(), instant)
            .error().kind()) + ","
        + errorKindName(rtc.setAlarm(Context.background(), instant)
            .error().kind()) + ","
        + errorKindName(rtc.alarm(Context.background()).error().kind()) + ","
        + errorKindName(rtc.isAlarmPending(Context.background())
            .error().kind()) + ","
        + errorKindName(rtc.clearAlarm(Context.background()).error().kind()))
    print("rtc-calibrate="
        + errorKindName(rtc.calibrate(Context.background(), 1001)
            .error().kind()) + ","
        + errorKindName(rtc.calibrate(Context.background(), 0).error().kind())
        + "," + str(rtc.calibrationPpm()))
    Result<Unit, Error> rtcClose = rtc.close()
    Result<Unit, Error> rtcCloseAgain = rtc.close()
    print("rtc-close=" + str(rtcClose.isOk()) + "," + str(rtcCloseAgain.isOk())
        + "," + str(rtc.isOpen()) + ","
        + errorKindName(rtc.now(Context.background()).error().kind()))

    Result<FlashRegion, Error> flashNo = Embedded.openFlash(
        Context.background(), minimal, "config", 0 as Long, 4096 as Long)
    Result<FlashRegion, Error> flashOpen = Embedded.openFlash(
        Context.background(), board, "config", 0 as Long, 65536 as Long)
    print("flash-open=" + errorKindName(flashNo.error().kind()) + ","
        + errorKindName(flashOpen.error().kind()) + ","
        + errorKindName(FlashRegion.open(Context.background(), board, "",
            0 as Long, 4096 as Long).error().kind()) + ","
        + errorKindName(FlashRegion.open(Context.background(), board, "config",
            1048576 as Long, 4096 as Long).error().kind()))
    FlashRegion flash = new FlashRegion(7 as Long, "config", 0 as Long,
        65536 as Long, 4096 as Long, 4096 as Long, 256 as Long)
    Bytes flashEmpty = Bytes.alloc(0)
    Bytes flashData = Bytes.alloc(256)
    Bytes flashRead = Bytes.alloc(16)
    print("flash=" + flash.name() + "," + str(flash.offsetBytes()) + ","
        + str(flash.lengthBytes()) + "," + str(flash.pageSizeBytes()) + ","
        + str(flash.eraseSizeBytes()) + "," + str(flash.writeSizeBytes()) + ","
        + str(flash.isOpen()))
    print("flash-read=" + str(flash.read(Context.background(), 0 as Long,
        flashEmpty).value()) + ","
        + errorKindName(flash.read(Context.background(), 0 as Long, flashRead)
            .error().kind()) + ","
        + errorKindName(flash.read(Context.background(), 65530 as Long,
            flashRead).error().kind()))
    print("flash-write=" + str(flash.write(Context.background(), 0 as Long,
        flashEmpty).isOk()) + ","
        + errorKindName(flash.write(Context.background(), 1 as Long, flashData)
            .error().kind()) + ","
        + errorKindName(flash.write(Context.background(), 0 as Long, flashData)
            .error().kind()))
    print("flash-erase="
        + errorKindName(flash.erase(Context.background(), 0 as Long, 256 as Long)
            .error().kind()) + ","
        + errorKindName(flash.erase(Context.background(), 0 as Long, 4096 as Long)
            .error().kind()) + ","
        + str(flash.isErased(Context.background(), 0 as Long, 0 as Long).value())
        + "," + errorKindName(flash.isErased(Context.background(), 0 as Long,
            512 as Long).error().kind()))
    print("flash-desc=" + flash.describe())
    Result<Unit, Error> flashClose = flash.close()
    Result<Unit, Error> flashCloseAgain = flash.close()
    print("flash-close=" + str(flashClose.isOk()) + ","
        + str(flashCloseAgain.isOk()) + "," + str(flash.isOpen()) + ","
        + errorKindName(flash.read(Context.background(), 0 as Long, flashRead)
            .error().kind()))

    Result<PowerMode, Error> power = Embedded.powerMode(Context.background(),
        board)
    Result<Unit, Error> powerSet = Embedded.setPowerMode(Context.background(),
        board, PowerMode.Sleep)
    Result<Unit, Error> powerUnsupported = Embedded.setPowerMode(
        Context.background(), minimal, PowerMode.DeepSleep)
    Result<Unit, Error> sleepZero = Embedded.sleepFor(Context.background(),
        board, PowerMode.Sleep, 0 as Long)
    Result<Unit, Error> sleepActive = Embedded.sleepFor(Context.background(),
        board, PowerMode.Active, 10 as Long)
    Result<Unit, Error> sleepMissing = Embedded.sleepFor(Context.background(),
        minimal, PowerMode.Sleep, 10 as Long)
    Result<Unit, Error> sleepOk = Embedded.sleepFor(Context.background(),
        board, PowerMode.Sleep, 10 as Long)
    print("embedded-power=" + errorKindName(power.error().kind()) + ","
        + errorKindName(powerSet.error().kind()) + ","
        + errorKindName(powerUnsupported.error().kind()))
    print("embedded-sleep=" + errorKindName(sleepZero.error().kind()) + ","
        + errorKindName(sleepActive.error().kind()) + ","
        + errorKindName(sleepMissing.error().kind()) + ","
        + errorKindName(sleepOk.error().kind()))
    print("embedded-open="
        + errorKindName(Embedded.openAdc(Context.background(), pa5, 12,
            3300 as Long).error().kind()) + ","
        + errorKindName(Embedded.openPwm(Context.background(), pa8, 1000 as Long)
            .error().kind()) + ","
        + errorKindName(Embedded.openUart(Context.background(), pa2, pa3,
            "USART2_TX", "USART2_RX", options).error().kind()) + ","
        + errorKindName(Embedded.openCan(Context.background(), pa11, pa12,
            "CAN1_TX", "CAN1_RX", 500000 as Long).error().kind()) + ","
        + errorKindName(Embedded.openWatchdog(Context.background(), board)
            .error().kind()) + ","
        + errorKindName(Embedded.openRtc(Context.background(), board)
            .error().kind()) + ","
        + errorKindName(Embedded.openFlash(Context.background(), board, "config",
            0 as Long, 65536 as Long).error().kind()))
    return 0
}
