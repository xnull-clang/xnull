# `AdcChannel`

| 项 | 值 |
| --- | --- |
| 类型 | `class AdcChannel`（控制句柄） |
| 包 | `xdk.embedded` |
| 层 |  |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Error`、`BoardPin`、`PinCapability` |

---

## 1. 定位

已打开的**单通道 ADC 控制句柄**：读取原始采样值、按参考电压换算毫伏、关闭、是否打开。

不做：多通道扫描、连续采样、DMA、差分输入、可编程增益、过采样/滤波、比较器/阈值中断、校准、温度传感器、裸寄存器/`ioctl`。采样调度、滤波和校准由应用或 X 负责。

---

## 2. 设计逻辑

- 为什么是 class：持有不透明句柄与打开状态，生命周期需要显式 `close`；不是值对象，因为句柄不能被复制。
- 由静态 `AdcChannel.open(context, boardPin, resolutionBits, referenceMillivolts)` 创建；构造器主要供宿主/测试使用。
- `boardPin` 必须是 `BoardPin`，且具备 `PinCapability.AdcInput` 与非负 `adcChannelNumber`；打开时再次校验，防止构造后被错误复用。
- `resolutionBits` 是本次会话的采样分辨率，范围 `1..24`；超过 24 位在基线不支持（`Unsupported`/`InvalidArgument`），避免 `Int` 原始值溢出。
- `referenceMillivolts` 是换算参考电压，`>0`；具体可用参考（内部/外部/VDD）由适配器解释。`readMillivolts` 只做线性换算，不做校准/温度补偿。
- `read` 返回原始码值 `0..(2^resolutionBits - 1)`；适配器返回越界值视为 `DataCorrupted`，不静默截断。
- `readMillivolts` 使用 `raw * referenceMillivolts / maxRaw` 的 Long 算术，避免 Int 溢出；结果向下取整。
- 打开受 OS/适配器能力/权限门控：无 ADC `Unsupported`，无权限 `PermissionDenied`，通道被占用 `Busy`，I/O `Io`。
- `close()` 幂等；关闭后 `boardPin`/`channelNumber`/`resolutionBits`/`referenceMillivolts`/`isOpen`/`close` 可用，`read`/`readMillivolts` 返回 `Unavailable`。
- 非线程安全；同一句柄的 `read`/`readMillivolts`/`close` 必须由调用方串行化。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_handle` | `Long` | final | `>0`；不透明句柄 |
| `_boardPin` | `BoardPin` | final | 非 null；具备 `AdcInput` |
| `_channelNumber` | `Int` | final | `>=0`；等于 `boardPin.adcChannelNumber()` |
| `_resolutionBits` | `Int` | final | `1..24` |
| `_referenceMillivolts` | `Long` | final | `>0` |
| `_open` | `Bool` | 内部 | 是否打开 |

不变量：

- `_handle > 0`；`_boardPin` 非 null 且 `supports(PinCapability.AdcInput)`；`_channelNumber == _boardPin.adcChannelNumber()` 且 `>=0`。
- `_resolutionBits` 在 `1..24`；`_referenceMillivolts > 0`。
- 构造后 `_open = true`；`close` 后 `_open = false`；`close` 幂等。
- 关闭后不再调用原生采样/关闭原语；`_handle` 不复用、不持久化、不跨进程。
- 采样值域 `0..(2^_resolutionBits - 1)`；越界是适配器错误（`DataCorrupted`），不是合法值。

---

## 4. 生命周期

由 `AdcChannel.open` 创建；构造器主要供宿主/测试使用。调用方持有；调用方 `close()` 释放句柄；无 `deinit`/finalizer 依赖。关闭后对象终止，不提供重新打开；需要新分辨率/参考电压/会话时重新 `open`。关闭后只允许纯读取器与 `close`；`read`/`readMillivolts` 返回 `Unavailable`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `AdcChannel(Long handle, BoardPin boardPin, Int channelNumber, Int resolutionBits, Long referenceMillivolts)` | handle、boardPin、channelNumber、resolutionBits、referenceMillivolts | handle>0；boardPin 非 null 且支持 `AdcInput`；channelNumber≥0 且等于引脚通道；resolutionBits 1..24；referenceMillivolts>0 | 非法 → panic |
| `AdcChannel.open(Context context, BoardPin boardPin, Int resolutionBits, Long referenceMillivolts)` | context、boardPin、resolutionBits、referenceMillivolts | 同构造；适配器可拒绝硬件不支持的组合 | null → panic；参数越界 → `InvalidArgument`；无 ADC 能力 → `Unsupported`；适配器失败透传 |

`open` 成功后返回打开对象；适配器返回句柄 `<=0` 视为内部错误，返回 `Internal`，不构造对象。

---

## 6. 字段表

见 §3；字段私有。`BoardPin` 是不可变值，复制引用；构造器不复制 `BoardPin` 的内部列表。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `open`（static） | 打开 ADC 通道 | `Context context, BoardPin boardPin, Int resolutionBits, Long referenceMillivolts` | `Result<AdcChannel, Error>` | null → panic；`InvalidArgument`/`Unsupported`/`PermissionDenied`/`Busy`/`Io`/`Cancelled`/`Timeout` |
| `boardPin` | 绑定引脚 | 无 | `BoardPin` | 无 |
| `channelNumber` | ADC 通道号 | 无 | `Int` | 无 |
| `resolutionBits` | 采样分辨率 | 无 | `Int` | 无 |
| `referenceMillivolts` | 参考电压 | 无 | `Long` | 无 |
| `read` | 读取原始采样 | `Context context` | `Result<Int, Error>` | null → panic；关闭 → `Unavailable`；`Cancelled`/`Timeout`/`Io`/`DataCorrupted` |
| `readMillivolts` | 读取并换算毫伏 | `Context context` | `Result<Long, Error>` | 同 `read`；换算不引入新失败 |
| `close` | 关闭通道 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isOpen` | 是否打开 | 无 | `Bool` | 无 |

说明：

- `open`：`context == null`/`boardPin == null` panic；`resolutionBits` 不在 `1..24` → `InvalidArgument`；`referenceMillivolts <=0` → `InvalidArgument`；引脚无 `AdcInput` 或通道号 `<0` → `Unsupported`；适配器可因硬件不支持该分辨率/参考返回 `Unsupported`/`InvalidArgument`。
- `read`：`context == null` panic；关闭后 `Unavailable`；可阻塞，取消 `Cancelled`，超时 `Timeout`；原始值越界 `DataCorrupted`；不返回“上一次采样”缓存。
- `readMillivolts`：先调用 `self.read(context)`；成功后用 Long 算术换算；失败透传；不做校准、不做单位自动缩放（mV 是唯一单位）。
- `close`：第一次置 `_open = false`，再调用原生关闭；后续 `Ok(unit)`；关闭失败返回 `Io`，状态仍视为关闭，避免重复释放。
- `boardPin`/`channelNumber`/`resolutionBits`/`referenceMillivolts`/`isOpen` 是纯读取；关闭后仍返回打开时的值。
- 不提供 `readAverage`/`readRaw`/`startContinuous`/`stop`/`calibrate`/`setGain`：这些是 X 或应用层。
- 不提供 `describe`/`equals`/`copy`：通道是资源，不是值对象。

---

## 8. 使用的技术

- 不透明 `Long` 句柄；
- 引脚能力/通道号双重校验；
- 分辨率与参考电压；
- Long 算术换算；
- `Context`/`Result`；
- 幂等关闭；
- 原生错误映射。

---

## 9. 需要的支撑

- 语言：class、final 字段、Long、Int、Bool、Result；
- 运行时/适配器：
  - `adcOpenRaw(Context context, Int channelNumber, Int resolutionBits, Long referenceMillivolts) -> Result<Long, Error>`；
  - `adcReadRaw(Context context, Long handle) -> Result<Int, Error>`；
  - `adcCloseRaw(Long handle) -> Result<Unit, Error>`；
- 适配器负责：
  - 把 `channelNumber` 映射到平台 ADC 通道；
  - 校验分辨率/参考电压是否支持；
  - 保证原始值在 `0..(2^resolutionBits - 1)`；越界由本类型转 `DataCorrupted`；
  - 拒绝不支持的通道/模式，返回 `Unsupported`/`InvalidArgument`；
- 原生句柄必须 `>0`；`0`/负数在 `open` 中转为 `Internal`，构造器 panic；
- 接口：`Context`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`、`BoardPin`、`PinCapability`。

---

## 10. 依赖的特性/接口/类

`Context`、`Error`、`BasicError`、`ErrorKind`、`BoardPin`、`PinCapability`、`Board`、`Embedded`。

相关但不同层：`xdk.device.GpioPin`（数字 GPIO）、`xdk.device.I2cBus`/`SpiBus`（外部 ADC 总线）。本类型不复制总线控制 API；外部 ADC 通过 I2C/SPI 读取，不在 `AdcChannel` 内实现。

---

## 11. 所有权与并发

引用语义；通道由调用方持有并关闭；无全局注册表；无循环引用。`BoardPin` 是借用/共享的不可变值，通道不拥有它。
非线程安全：`read`/`readMillivolts`/`close` 不得并发；调用方需串行化，或确保关闭时没有其它调用。`close` 幂等指重复调用安全，不承诺并发 close 安全。
纯读取器可并发读取，但不要依赖与并发 `close` 的时序。
无 `equals`/`copy`；不推荐作 `Map` 键；关闭后不得再用通道。

---

## 12. 示例与反例

正确：

```xnull
Result<AdcChannel, Error> opened = AdcChannel.open(
    context, board.findPin("PA5"), 12, 3300)
if opened.isOk() {
    AdcChannel channel = opened.value()
    Result<Int, Error> raw = channel.read(context)
    if raw.isOk() {
        Result<Long, Error> millivolts = channel.readMillivolts(context)
    }
    Result<Unit, Error> closed = channel.close()
}
```

正确：12 位、3.3 V 参考时，原始值 `4095` 换算约 `3300 mV`；调用方按传感器分压/增益再换算。

反例：引脚没有 `AdcInput` 却强行打开；`resolutionBits` 传 `32` 并期望 `Int` 原始值；`referenceMillivolts` 传 `0`；把 `read` 当连续采样/滤波；假设 `read` 一定返回满量程；close 后继续 `read`；多任务并发读同一通道；用 `AdcChannel` 读取外部 I2C ADC；把原始值当毫伏直接上报。

---

## 13. 测试场景义务

打开成功/无 ADC 能力/通道号 `-1`/分辨率 `0`/`1`/`24`/`25`/参考电压 `0`/负值/无权限/占用/取消/超时；`read` 边界 `0`/最大值/越界/关闭后/取消/超时/I/O；`readMillivolts` 0/满量程/中间值/溢出安全/失败透传；`close` 幂等/关闭失败仍关闭/关闭后纯读取器；`boardPin`/`channelNumber`/`resolutionBits`/`referenceMillivolts` 关闭后可读；多通道独立；桌面/无 ADC 平台返回 `Unsupported`；原生句柄 `<=0` → `Internal`；`read` 无缓冲区参数，因此不存在空 buffer 原生调用。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
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
        _handle = handle
        _boardPin = boardPin
        _channelNumber = channelNumber
        _resolutionBits = resolutionBits
        _referenceMillivolts = referenceMillivolts
        _open = true
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
        Int channelNumber = boardPin.adcChannelNumber()
        if channelNumber < 0 {
            return Err(new BasicError(ErrorKind.Unsupported,
                "pin has no adc channel"))
        }
        Result<Long, Error> opened = adcOpenRaw(
            context, channelNumber, resolutionBits, referenceMillivolts)
        if opened.isErr() { return Err(opened.error()) }
        if opened.value() <= 0 {
            return Err(new BasicError(ErrorKind.Internal,
                "invalid adc handle"))
        }
        return Ok(new AdcChannel(opened.value(), boardPin, channelNumber,
            resolutionBits, referenceMillivolts))
    }

    BoardPin boardPin() { return _boardPin }
    Int channelNumber() { return _channelNumber }
    Int resolutionBits() { return _resolutionBits }
    Long referenceMillivolts() { return _referenceMillivolts }
    Bool isOpen() { return _open }

    Int _maximumRawValue() {
        Int maximum = 1
        Int index = 0
        while index < _resolutionBits {
            maximum = maximum * 2
            index = index + 1
        }
        return maximum - 1
    }

    Result<Int, Error> read(Context context) {
        if context == null { throw "AdcChannel.read: null context" }
        if !_open { return Err(unavailableError("adc channel")) }
        Result<Int, Error> sampled = adcReadRaw(context, _handle)
        if sampled.isErr() { return Err(sampled.error()) }
        Int value = sampled.value()
        Int maximum = _maximumRawValue()
        if value < 0 || value > maximum {
            return Err(new BasicError(ErrorKind.DataCorrupted,
                "adc sample out of range"))
        }
        return Ok(value)
    }

    Result<Long, Error> readMillivolts(Context context) {
        if context == null { throw "AdcChannel.readMillivolts: null context" }
        Result<Int, Error> sampled = self.read(context)
        if sampled.isErr() { return Err(sampled.error()) }
        Long sampleValue = sampled.value() as Long
        Long maximumValue = _maximumRawValue() as Long
        Long millivolts = (sampleValue * _referenceMillivolts) / maximumValue
        return Ok(millivolts)
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        return adcCloseRaw(_handle)
    }
}
```
