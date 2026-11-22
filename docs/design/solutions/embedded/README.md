# `xdk.embedded` 嵌入式板级支持

| 项 | 值 |
| --- | --- |
| 包 | `xdk.embedded` |
| 层 | L8 solutions |
| 依赖 | `xdk.core`、`xdk.device`、`xdk.serial`、`xdk.os` |
| 被依赖 | 应用、板级支持包、嵌入式产品、边缘设备服务 |
| 稳定性 | `preview`；不进入 1.0 公共承诺 |
| 状态 | 设计基线；不含实现 |

---

## 1. 定位

`xdk.embedded` 是**板级支持与控制面**：应用显式描述一块板（MCU、引脚、复用功能、能力），再按引脚打开 ADC/PWM/UART/CAN，按板打开看门狗/RTC/Flash 区域，并显式进入低功耗模式。

本包是 [`t4`](../README.md) 工作流 -1 的产物；驱动、协议栈、文件系统仍在 ecosystem。

它只做：

- 板级描述：MCU 名称/家族/架构、时钟、Flash/RAM 容量、引脚表、复用功能、能力计数；
- 引脚能力查询：GPIO、模拟输入、PWM 输出、UART/CAN/I2C/SPI 信号、唤醒、调试、电源使能；
- 控制句柄：ADC 采样、PWM 输出、UART 字节流、CAN 经典帧、看门狗、RTC、Flash 区域；
- 低功耗模式：`Active`/`Idle`/`Sleep`/`DeepSleep`/`Off` 的显式切换与有界休眠；
- 显式失败：不支持、无权限、占用、I/O、取消、超时。

它不做：

- GPIO/I2C/SPI 的重复实现；这些仍由 `xdk.device` 的 [`GpioPin`](../../platform/device/GpioPin.md)、[`I2cBus`](../../platform/device/I2cBus.md)、[`SpiBus`](../../platform/device/SpiBus.md) 提供；
- 通用串口设备枚举/路径打开；OS 可见串口仍由 [`xdk.serial`](../../platform/serial/README.md) 的 [`SerialPort`](../../platform/serial/SerialPort.md) 提供；
- RTOS 调度器、任务创建、抢占、优先级、时间片；执行模型归 `xdk.core` 执行层；
- BLE、LoRa、Zigbee、Wi-Fi 协议栈；归 ecosystem；
- 驱动绑定、内核模块、厂商 SDK、裸寄存器、裸 `ioctl`、设备树/overlay；
- 板卡自动探测、自动选择引脚、自动识别 MCU；板描述必须由应用/板级包显式提供；
- Flash 文件系统、磨损均衡、OTA、安全启动、密钥存储；归 ecosystem 或安全产品；
- 引脚热插拔、运行时动态 pinmux 重排；当前基线是打开时固定复用功能。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 显式板级描述 | `Board`/`BoardPin` 是调用方构造的不可变值；不做自动探测，不读取隐藏全局注册表 |
| 复用  | GPIO/I2C/SPI 用 `xdk.device`；OS 可见串口用 `xdk.serial`；本包不复制这些类型 |
| 引脚即契约 | 打开 ADC/PWM/UART/CAN 必须给出 `BoardPin` 与（串行/CAN）精确复用功能名；引脚能力不足返回 `Unsupported` |
| 不透明句柄 | 所有控制句柄只暴露 `Long`；不暴露 fd、指针、寄存器地址、内核对象、厂商句柄 |
| 显式生命周期 | 调用方持有并 `close()`；`close()` 幂等；无 finalizer 依赖；关闭后只允许纯读取器 |
| 可失败 | 打开/读/写/擦除/启动/休眠返回 `Result`；无权限 `PermissionDenied`，占用 `Busy`，I/O `Io`，平台无能力 `Unsupported` |
| 可取消 | 可阻塞方法首参 `Context`；取消 `Cancelled`，超时 `Timeout`；合同错误 panic |
| 危险操作显式 | Flash `erase`/`write` 是独立方法，不隐式擦除；看门狗 `stop` 是独立方法，`close` 不偷偷停表 |
| 低功耗显式 | 进入低功耗前由调用方决定关闭/保留哪些句柄；本包不自动关闭，也不承诺句柄跨模式有效 |
| 字节所有权 | 输入字节借用；输出字节写入调用方缓冲区；对象不保留调用方缓冲区 |
| 无全局状态 | 静态入口 `Embedded` 只做校验/委托；不缓存设备，不提供 `closeAll` |
| 单一职责 | 一个类型只解决一个控制面；协议（Modbus/CANopen/J1939）、文件系统、OTA 不在本包 |
| 行业语义对齐 | ADC 通道配置/原始值/参考电压对齐 Zephyr ADC；PWM `0`/`1000` 千分比对齐 Zephyr `pulse=0/period` 与 embedded-hal fully-off/on；看门狗窗口对齐 Zephyr `wdt_window` 与 STM32 IWDG/WWDG；RTC 单闹钟/挂起查询对齐 Zephyr `rtc_*`；Flash 页/擦除/写粒度对齐 Zephyr `flash_*` 与 STM32 HAL；电源模式对齐 ESP-IDF light/deep sleep 分层；CAN 经典标识符/掩码/错误计数对齐 Zephyr CAN 与 embedded-can |

---

## 3. 类型索引

| 类型 | 种类 | 文件 | 说明 |
| --- | --- | --- | --- |
| `Board` | class（不可变值） | [`Board.md`](Board.md) | 板级描述：MCU、时钟、存储、引脚、能力 |
| `BoardPin` | class（不可变值） | [`BoardPin.md`](BoardPin.md) | 单个引脚：编号、名称、能力、复用功能、ADC/PWM 通道 |
| `PinCapability` | enum | [`PinCapability.md`](PinCapability.md) | 引脚能力分类 |
| `AdcChannel` | class（控制句柄） | [`AdcChannel.md`](AdcChannel.md) | 单通道 ADC 采样 |
| `PwmChannel` | class（控制句柄） | [`PwmChannel.md`](PwmChannel.md) | 单通道 PWM 输出 |
| `UartPort` | class（控制句柄） | [`UartPort.md`](UartPort.md) | 绑定板级引脚的 MCU UART |
| `CanBus` | class（控制句柄） | [`CanBus.md`](CanBus.md) | 经典 CAN 控制器 |
| `Watchdog` | class（控制句柄） | [`Watchdog.md`](Watchdog.md) | 看门狗启动/喂狗/停止 |
| `Rtc` | class（控制句柄） | [`Rtc.md`](Rtc.md) | 实时时钟与单闹钟 |
| `FlashRegion` | class（控制句柄） | [`FlashRegion.md`](FlashRegion.md) | 有界 Flash 区域读写擦 |
| `PowerMode` | enum | [`PowerMode.md`](PowerMode.md) | 低功耗模式 |
| `Embedded` | class（静态入口） | [`Embedded.md`](Embedded.md) | 打开控制句柄、查询/切换低功耗 |

类型索引 12 项 = 12 个类型文件；README 不含类型方法表或伪代码。

---

## 4. 跨类型规则

- `Board`/`BoardPin`/`PinCapability`/`PowerMode` 是不可变值；可共享、可复制引用、无 `close`。控制句柄是引用语义资源，由调用方关闭。
- 先有板描述，再打开句柄。`BoardPin` 应由应用从 `Board` 取得；`BoardPin` 自身携带 MCU 引脚/复用功能信息，本包不做全局板校验，也不自动探测。
- `BoardPin` 的能力与通道号必须一致：有 `PinCapability.AdcInput` 才能有非负 `adcChannelNumber`；有 `PinCapability.PwmOutput` 才能有非负 `pwmChannelNumber`；否则为 `-1`。
- `BoardPin.alternateFunctions()` 返回精确、大小写敏感的复用功能名（如 `USART3_TX`、`TIM2_CH1`、`CAN1_RX`）。串行/CAN 打开时传精确名字；不做前缀猜测、不做模糊匹配。
- 打开 ADC/PWM/UART/CAN 前先检查 `BoardPin` 的能力（`supports`）与复用功能名；不满足返回 `Unsupported`/`InvalidArgument`，不尝试其它引脚。
- 所有控制句柄的 `open` 返回 `Result`；句柄值为 `Long`，`<=0` 视为适配器内部错误（`Internal`），不构造对象。
- 所有 `close()` 幂等：第一次释放原生句柄，后续 `Ok(unit)`；关闭失败返回 `Io`/`Unsupported` 仅作诊断，对象仍视为关闭；关闭后除纯读取器与 `close` 外返回 `Unavailable`。
- 所有可阻塞方法首参 `Context`；`context == null` 是合同错误（panic）；取消 `Cancelled`；有界等待超时 `Timeout`。纯读取器（`boardPin`/`channelNumber`/`resolutionBits`/`bitrateBitsPerSecond`/`isOpen` 等）无 `Context`。
- `UartPort` 与 `SerialPort` 分工：`UartPort` 是 MCU 片上 UART，绑定 TX/RX 引脚与复用功能，适合无 OS 串口设备的裸机/RTOS 场景；`SerialPort` 是 OS 可见串口设备（`/dev/tty*`、`COM*`）。不要用 `UartPort` 枚举端口，也不要用 `SerialPort` 配置引脚复用。
- `CanBus` 基线是经典 CAN 2.0A/2.0B：标准 11 位/扩展 29 位标识符、0..8 字节数据、可选远程请求；不做 CAN FD、ISO-TP、CANopen、J1939。`receive` 返回紧凑帧头 `[identifier, flags, payloadLength]`，`flags` 位 0 = 扩展帧、位 1 = 远程请求；空列表表示超时无帧。
- `Watchdog.close()` 不停止已启动的看门狗；需要停表必须显式 `stop(context)`。这是安全默认：关闭句柄不等于解除复位保护。
- `Rtc` 在低功耗与主电源关闭时通常继续运行；`close()` 不停止时钟、不清除闹钟；`now` 在时间未设置时返回 `NotFound`。
- `FlashRegion` 的 `write` 不隐式擦除；调用方必须先 `erase`，或用 `isErased` 验证。`erase`/`write` 必须显式给出相对区域偏移与长度；越界/未对齐返回 `InvalidArgument`；适配器必须在执行前写审计日志。
- `PowerMode` 进入 `Sleep`/`DeepSleep`/`Off` 可能使已打开句柄失效；本包不自动关闭句柄，也不承诺唤醒后句柄仍有效。调用方应先 `close()`，唤醒后重新 `open()`。`Idle` 不承诺句柄失效，但也不保证平台不会关闭个别外设。
- 并发：`Board`/`BoardPin`/枚举可并发共享；控制句柄非线程安全，同一句柄的读/写/启动/停止/关闭必须由调用方串行化。不同句柄可并行，前提是适配器支持。
- 无 RTOS 调度器、无 BLE/LoRa 协议栈、无板卡自动探测；这些是明确的非目标，不是遗漏。

---

## 5. 场景

### S1：板级点亮与调光

应用构造 `Board`/`BoardPin`，用 `GpioPin` 点亮 LED；需要调光时按 PWM 引脚打开 `PwmChannel`，设置频率与占空比，`enable`，退出前 `disable`/`close`。GPIO 与 PWM 不重复实现。

### S2：模拟采样

按 `PinCapability.AdcInput` 的引脚打开 `AdcChannel`，读取原始值或用参考电压换算毫伏；校准/滤波由应用完成。多通道扫描/DMA 是 X。

### S3：板载串口控制台

按 UART TX/RX 引脚与精确复用功能名打开 `UartPort`，用 `SerialOptions` 设置波特率/数据位/校验/停止位/超时；读写字节、刷新、关闭。OS 可见串口设备改用 `SerialPort`。

### S4：CAN 节点

按 CAN TX/RX 引脚打开 `CanBus`，设置位率，启动，添加过滤器，发送经典帧，轮询接收；总线关闭时读错误计数并 `recover`。协议解析归 ecosystem。

### S5：看门狗守护

按板打开 `Watchdog`，`start` 或 `startWindowed`，主循环周期 `feed`；需要停表时显式 `stop`；`close` 只释放句柄，不解除复位保护。

### S6：RTC 时间与闹钟

按板打开 `Rtc`，`now` 读取时间，`setTime` 校准，`setAlarm` 设置单闹钟，`isAlarmPending` 查询；`close` 后时钟继续运行。

### S7：配置区 Flash

按板打开 `FlashRegion`，先用 `isErased` 检查，必要时 `erase`，再按写粒度 `write`；读取用 `read`。擦写前适配器写审计日志。文件系统/OTA 不在本包。

### S8：低功耗采集

关闭不需要的句柄，`Embedded.setPowerMode(context, board, PowerMode.Sleep)` 或有界 `sleepFor`；唤醒后重新打开句柄。`Off` 表示受控关机，进程不假设还能继续执行。

### S9：失败与权限

平台无 ADC → `Unsupported`；无权限访问 Flash → `PermissionDenied`；引脚已被其它外设占用 → `Busy`；I/O 错误 → `Io`；`Context` 取消 → `Cancelled`；超时 → `Timeout`；关闭后 → `Unavailable`。不 panic 运行时失败。

---

## 6. 缺口

| 项 | 决策 |
| --- | --- |
| 板卡自动探测/自动加载板描述 | 明确不做；由应用/板级包显式构造 `Board` |
| 运行时动态 pinmux/引脚重映射 | X；当前打开时固定复用功能 |
| ADC 连续采样、DMA、多通道扫描、差分、增益、过采样 | X |
| PWM 捕获、互补输出、死区、相位、刹车 | X |
| UART 硬件流控、RS-485/LIN、9 位、DMA、半双工 | X |
| CAN FD、ISO-TP、CANopen、J1939、时间触发 CAN | ecosystem/X |
| 看门狗多阶段、回调、独立/窗口双看门狗组合 | X |
| RTC 备份域、篡改检测、温度补偿、多闹钟 | X |
| Flash 磨损均衡、文件系统、OTA、安全启动、密钥存储 | ecosystem |
| 低功耗唤醒源配置（GPIO/RTC/UART/CAN）、ULP、电源域 | X |
| BLE/LoRa/Zigbee/Wi-Fi 协议栈 | ecosystem |
| RTOS 调度器、任务/优先级/时间片 | `xdk.core` 执行层；不在本包 |
| 设备热插拔/引脚冲突事件 | X；当前打开冲突返回 `Busy` |
| 通用 CAN 帧对象类型 | 当前用 `[identifier, flags, payloadLength]` 紧凑帧头；帧对象是 X |

---

## 7. 安全

- **Flash 是危险面**：`erase`/`write` 只接受有界 `FlashRegion` 内的相对偏移；打开时校验 `offset + length` 不越过 `Board.flashBytes()`；越界/未对齐返回 `InvalidArgument`。适配器必须在擦写前记录区域名、偏移、长度、操作类型；不得记录写入内容中的密钥/凭据。
- **不隐式擦除**：`write` 不自动擦除，避免“写配置”意外清空整页；调用方必须先 `erase` 或用 `isErased` 验证。
- **看门狗不被静默解除**：`close()` 不停止已启动的看门狗；只有显式 `stop(context)` 才能停表。`stop` 可能因硬件/权限返回 `Unsupported`/`PermissionDenied`，此时看门狗继续保护系统。
- **低功耗不等于安全状态**：进入 `Sleep`/`DeepSleep`/`Off` 可能关闭调试口、时钟、外设与安全监控；调用方必须先完成安全状态保存、关闭不需要的句柄，并确认唤醒源。`Off` 不承诺进程继续执行。
- **权限与能力门控**：打开/擦写/停表受 OS/引导器/熔丝/能力门控；失败返回 `PermissionDenied`/`Unsupported`，不重试提权、不绕过保护。
- **无裸寄存器/ioctl**：公开 API 不暴露寄存器地址、fd、指针、厂商句柄；适配器负责把错误映射为 `ErrorKind`，不把内核/厂商错误码直接泄漏给调用方。
- **引脚冲突**：同一引脚被 GPIO/ADC/PWM/UART/CAN 同时占用时，适配器应返回 `Busy`；本包不提供全局引脚仲裁器，调用方负责规划。
- **CAN 不是安全边界**：过滤器只做接收筛选，不提供认证/加密；总线上的帧不可信，协议层必须自行校验。
- **RTC 不是可信时间源**：RTC 可被设置/校准，不能作为安全审计的唯一时间依据；需要可信时间时使用安全元件/签名时间源。
- **ADC 不是安全联锁**：采样值仅用于测量/控制，不满足功能安全认证；安全联锁必须由独立硬件/认证组件实现。
- **日志脱敏**：`Board`/`BoardPin` 不含序列号、MAC、密钥；`FlashRegion.name()` 由调用方提供，禁止放入秘密；错误消息不得包含写入内容或 CAN 载荷。

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | 无领域注解 |
| 本包消费 | `@Builder`、`@Device`、`@Gpio`、`@I2cAddress`、`@SerialBinding`、`@Packed`、`@Align` |
| 处理器 | 无自有处理器；消费 Device/Serial/FFI 生成物 |
| 生成物 | 板级/引脚描述、设备目录、布局校验；设备句柄不套 `@Value` |
| 状态 | 无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 板级类型 | `@Device` | 复用 Device 处理器 |
| 引脚/地址字段 | `@Gpio`/`@I2cAddress` | 复用 Device 处理器 |
| 串口字段 | `@SerialBinding` | 复用 Serial 处理器 |
| 原生布局类型 | `@Packed`/`@Align` | 复用 FFI 布局处理器 |

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
