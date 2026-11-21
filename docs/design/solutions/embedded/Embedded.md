# `Embedded`

| 项 | 值 |
| --- | --- |
| 类型 | `class Embedded`（静态入口） |
| 包 | `xdk.embedded` |
| 层 |  |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Error`、`Board`、`BoardPin`、`AdcChannel`、`PwmChannel`、`UartPort`、`CanBus`、`Watchdog`、`Rtc`、`FlashRegion`、`PowerMode`、`SerialOptions` |

---

## 1. 定位

`xdk.embedded` 的**静态入口**：按板/引脚打开 ADC/PWM/UART/CAN/看门狗/RTC/Flash 区域，查询当前低功耗模式，切换低功耗模式，执行有界休眠。

不做：设备缓存、全局注册表、`closeAll`、板卡自动探测、GPIO/I2C/SPI 重复打开（用 `xdk.device.DeviceManager`）、OS 串口枚举（用 `xdk.serial.Serial`）、RTOS 任务创建、协议栈、驱动绑定、权限提升。

---

## 2. 设计逻辑

- 为什么是 class：提供稳定的包级命名空间与聚合方法；不是 protocol，因为没有多实现；不是单例，因为无实例状态。
- 静态无状态：所有方法都是便捷入口，不缓存 `Board`/`BoardPin`/句柄，不保存 `Context`，不跨调用保留电源状态。
- 所有 `open*` 直接委托对应类型的静态 `open`，参数与失败语义保持一致；不复制校验逻辑，不预打开、不探测。
- `openAdc` 需要分辨率与参考电压；`openPwm` 需要频率；`openUart`/`openCan` 需要 TX/RX 引脚与精确复用功能名；这些参数缺一不可，避免隐式默认值导致板级行为不确定。
- `openWatchdog`/`openRtc`/`openFlash` 以 `Board` 为单位；看门狗/RTC 是板级单实例，Flash 用显式区域名/偏移/长度界定。
- `powerMode` 查询当前模式；`setPowerMode` 切换模式；`sleepFor` 是“进入低功耗并在时长/唤醒源后返回”的便捷方法，只接受 `Sleep`/`DeepSleep`。
- 低功耗不自动关闭句柄：进入 `Sleep`/`DeepSleep`/`Off` 可能使句柄失效，调用方必须先 `close()` 或在唤醒后重新 `open()`；本入口不提供 `closeAll`，也不追踪已打开句柄。
- 不提供 `openGpio`/`openI2c`/`openSpi`：这些是 `xdk.device` 的职责；`Embedded` 不复制 `DeviceManager`。
- 不提供 `board()`/`detect()`/`load()`：板描述由应用/板级包显式构造；本入口只接受 `Board`/`BoardPin`。
- 无全局状态；静态方法可并发调用；返回的对象各自独立，仍需按各自并发规则使用。
- 所有 `Context` 首参方法在 `context == null` 时 panic；所有 `Result` 失败透传，不重试、不降级、不模拟。

---

## 3. 表示与不变量

无实例字段。

不变量：

- 不可实例化；所有方法静态；无全局可变状态。
- 不缓存 `Board`/`BoardPin`/设备句柄；不保存 `Context`；不跨调用保留电源状态。
- `open*` 返回调用方拥有的新句柄；失败不返回半初始化对象。
- `setPowerMode`/`sleepFor` 不自动关闭/重开任何句柄；不修改 `Board`/`BoardPin`。
- `powerMode` 返回当前模式；不缓存为全局值。
- 所有失败都是 `Result`，合同错误（null/禁止实例化）才 panic。

---

## 4. 生命周期

静态类；无实例；无 `close`；无全局资源；无 `deinit` 依赖。入口不延长任何句柄生命周期；句柄关闭后入口不感知，也不应被要求感知。电源模式切换是瞬时调用，不维持“当前模式”对象；当前模式只通过 `powerMode` 查询。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Embedded()` | 无 | 私有；禁止实例化 | 无 |

静态入口不提供工厂构造；所有能力通过静态方法获取。

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `openAdc` | 打开 ADC 通道 | `Context context, BoardPin boardPin, Int resolutionBits, Long referenceMillivolts` | `Result<AdcChannel, Error>` | 同 `AdcChannel.open` |
| `openPwm` | 打开 PWM 通道 | `Context context, BoardPin boardPin, Long frequencyHz` | `Result<PwmChannel, Error>` | 同 `PwmChannel.open` |
| `openUart` | 打开板级 UART | `Context context, BoardPin transmitPin, BoardPin receivePin, String transmitFunction, String receiveFunction, SerialOptions options` | `Result<UartPort, Error>` | 同 `UartPort.open` |
| `openCan` | 打开 CAN 控制器 | `Context context, BoardPin transmitPin, BoardPin receivePin, String transmitFunction, String receiveFunction, Long bitrateBitsPerSecond` | `Result<CanBus, Error>` | 同 `CanBus.open` |
| `openWatchdog` | 打开看门狗 | `Context context, Board board` | `Result<Watchdog, Error>` | 同 `Watchdog.open` |
| `openRtc` | 打开 RTC | `Context context, Board board` | `Result<Rtc, Error>` | 同 `Rtc.open` |
| `openFlash` | 打开 Flash 区域 | `Context context, Board board, String regionName, Long offsetBytes, Long lengthBytes` | `Result<FlashRegion, Error>` | 同 `FlashRegion.open` |
| `powerMode` | 查询当前模式 | `Context context, Board board` | `Result<PowerMode, Error>` | null → panic；`Unsupported`/`PermissionDenied`/`Io`/`Cancelled`/`Timeout` |
| `setPowerMode` | 切换模式 | `Context context, Board board, PowerMode powerMode` | `Result<Unit, Error>` | null → panic；不支持 → `Unsupported`；`Busy`/`PermissionDenied`/`Io`/`Cancelled`/`Timeout` |
| `sleepFor` | 有界低功耗休眠 | `Context context, Board board, PowerMode powerMode, Long durationMillis` | `Result<Unit, Error>` | null → panic；模式/时长非法 → `InvalidArgument`；不支持 → `Unsupported`；`Busy`/`PermissionDenied`/`Io`/`Cancelled`/`Timeout` |

说明：

- `openAdc`/`openPwm`/`openUart`/`openCan`/`openWatchdog`/`openRtc`/`openFlash` 是纯委托；null、范围、能力、权限、占用、I/O 错误语义完全由被委托类型定义；本入口不新增失败分类。
- `powerMode`：`context == null`/`board == null` panic；返回适配器报告的当前模式；平台不支持电源管理 → `Unsupported`；权限/容器限制 → `PermissionDenied`；查询可阻塞，取消/超时透传。
- `setPowerMode`：`context == null`/`board == null`/`powerMode == null` panic；`board.supportsPowerMode(powerMode)` 为 `false` → `Unsupported`；不自动关闭句柄；不等待句柄静默；调用方负责先 `close()` 不需要的设备。
- `sleepFor`：`context == null`/`board == null`/`powerMode == null` panic；`durationMillis <=0` → `InvalidArgument`；只接受 `PowerMode.Sleep`/`PowerMode.DeepSleep`，`Active`/`Idle`/`Off` → `InvalidArgument`；`board.supportsPowerMode(powerMode)` 为 `false` → `Unsupported`；休眠可能被外部唤醒源提前结束，返回 `Ok(unit)` 表示“已返回”，不保证睡满时长。
- `setPowerMode`/`sleepFor` 不保证 `powerMode` 切换后当前模式立即等于请求值（适配器可降级/拒绝）；需要确认时再调用 `powerMode`。
- 不提供 `closeAll`：入口不拥有句柄；每个句柄由调用方关闭。
- 不提供 `openGpio`/`openI2c`/`openSpi`/`serialPorts`/`board`/`detect`：职责属于 `xdk.device`/`xdk.serial`/应用板级包。
- 所有方法 O(1) 委托/校验；无隐藏全局状态。

---

## 8. 使用的技术

- 静态入口；
- 纯委托；
- 板能力校验；
- 显式低功耗模式；
- 有界休眠；
- `Context`/`Result`；
- 无状态聚合；
- 不缓存句柄。

---

## 9. 需要的支撑

- 语言：class、static、私有构造器、List、String、Long、Int、Result；
- 运行时/适配器：
  - `powerGetModeRaw(Context context, Board board) -> Result<PowerMode, Error>`；
  - `powerSetModeRaw(Context context, Board board, PowerMode powerMode) -> Result<Unit, Error>`；
  - `powerSleepForRaw(Context context, Board board, PowerMode powerMode, Long durationMillis) -> Result<Unit, Error>`；
  - 其余 `open*` 通过 `AdcChannel`/`PwmChannel`/`UartPort`/`CanBus`/`Watchdog`/`Rtc`/`FlashRegion` 的适配器，无直接原生调用；
- 接口：`Context`、`Error`、`BasicError`、`ErrorKind`、`Board`、`BoardPin`、`AdcChannel`、`PwmChannel`、`UartPort`、`CanBus`、`Watchdog`、`Rtc`、`FlashRegion`、`PowerMode`、`SerialOptions`。

---

## 10. 依赖的特性/接口/类

`Context`、`Error`、`Board`、`BoardPin`、`AdcChannel`、`PwmChannel`、`UartPort`、`CanBus`、`Watchdog`、`Rtc`、`FlashRegion`、`PowerMode`、`SerialOptions`。

相关但不同层：`xdk.device.DeviceManager`（GPIO/I2C/SPI/相机）、`xdk.serial.Serial`（OS 串口枚举）、`xdk.os`（系统电源/复位）、`xdk.core` 执行层（任务/取消）。本入口不复制这些 API。

---

## 11. 所有权与并发

静态无状态；无实例；无全局注册表；不拥有句柄；不缓存 `Board`/`BoardPin`/`Context`。
静态方法无共享状态，可并发调用；底层适配器可能串行化打开/电源切换，若适配器有全局设备表，调用方需串行化。并发 `open*` 可能打开同一引脚/控制器的多个句柄，由适配器返回 `Busy` 或由调用方去重/关闭；入口不做单例仲裁。
返回的 `AdcChannel`/`PwmChannel`/`UartPort`/`CanBus`/`Watchdog`/`Rtc`/`FlashRegion` 归调用方所有，按各自并发规则使用。
无 `equals`/`copy`；无实例；不适用作 `Map` 键。

---

## 12. 示例与反例

正确：

```xnull
Result<AdcChannel, Error> adc = Embedded.openAdc(
    context, board.findPin("PA5"), 12, 3300)
Result<PwmChannel, Error> pwm = Embedded.openPwm(
    context, board.findPin("PA8"), 1000)
Result<Watchdog, Error> watchdog = Embedded.openWatchdog(context, board)
Result<PowerMode, Error> current = Embedded.powerMode(context, board)
if current.isOk() && current.value() != PowerMode.Active {
    Result<Unit, Error> active = Embedded.setPowerMode(
        context, board, PowerMode.Active)
}
```

正确：进入 `Sleep`/`DeepSleep` 前先关闭 ADC/PWM/UART/CAN/Flash 句柄；`sleepFor` 只用于 `Sleep`/`DeepSleep`；唤醒后重新打开句柄。

反例：用 `Embedded` 打开 GPIO/I2C/SPI；期望 `Embedded` 自动探测板卡；进入低功耗后继续使用旧句柄；`sleepFor` 传 `Active` 或 `Off`；把 `setPowerMode` 当“保证进入该模式”（应再 `powerMode` 确认）；并发打开同一引脚却不处理 `Busy`；用 `Embedded` 保存全局句柄/`Context`；期望 `closeAll`。

---

## 13. 测试场景义务

每个 `open*` 委托的参数/失败语义；null context/board/pin/function/options；引脚能力/复用功能不匹配；位率/频率/分辨率/参考边界；`powerMode` 成功/不支持/权限/取消/超时；`setPowerMode` 支持/不支持/null/`Busy`/权限；`sleepFor` `Active`/`Idle`/`Off` 拒绝/`Sleep`/`DeepSleep` 成功/时长 0/负值/不支持/提前唤醒；不自动关闭句柄；无全局状态；并发调用各自独立；返回句柄由调用方关闭；`Embedded` 无 `close`/`closeAll`/`openGpio`/`openI2c`/`openSpi`/`board`/`detect`。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class Embedded {
    private Embedded() {}

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
        return powerGetModeRaw(context, board)
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
        return powerSetModeRaw(context, board, powerMode)
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
        return powerSleepForRaw(context, board, powerMode, durationMillis)
    }
}
```
