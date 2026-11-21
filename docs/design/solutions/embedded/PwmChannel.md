# `PwmChannel`

| 项 | 值 |
| --- | --- |
| 类型 | `class PwmChannel`（控制句柄） |
| 包 | `xdk.embedded` |
| 层 |  |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Error`、`BoardPin`、`PinCapability` |

---

## 1. 定位

已打开的**单通道 PWM 输出句柄**：设置频率、设置占空比、使能/禁用输出、关闭、是否打开。

不做：PWM 捕获/输入测量、互补输出、死区、相位偏移、刹车/故障输入、中心对齐/边沿对齐选择、DMA 更新、裸寄存器/`ioctl`。电机控制级 PWM（死区/互补/刹车）是 X 或专用驱动。

---

## 2. 设计逻辑

- 为什么是 class：持有不透明句柄、输出状态与配置缓存，生命周期需要显式 `close`；不是值对象。
- 由静态 `PwmChannel.open(context, boardPin, frequencyHz)` 创建；构造器主要供宿主/测试使用。
- `boardPin` 必须具备 `PinCapability.PwmOutput` 与非负 `pwmChannelNumber`；打开时再次校验。
- 频率单位 Hz，`Long`；`>0`。适配器可因定时器/时钟限制返回 `Unsupported`/`InvalidArgument`。
- 占空比单位 **permille**（千分比），`Int`，`0..1000`；`0` = 恒定无效电平，`1000` = 恒定有效电平。这与 Zephyr 的 `pulse=0`/`pulse=period`、embedded-hal 的 fully-off/fully-on 语义一致，同时避免浮点。
- `open` 后输出默认**禁用**，占空比缓存为 `0`；`setDutyCycle` 只更新配置，不自动使能；必须显式 `enable`。这样不会在配置过程中意外驱动执行器。
- `setFrequency` 只改周期；占空比按 permille 保持，因此绝对脉宽随频率变化。需要固定脉宽时由调用方按 `dutyPermille = pulseNanoseconds * frequencyHz / 1e9` 计算。
- `enable`/`disable` 幂等：已处于目标状态返回 `Ok(unit)`，不重复写硬件。
- `close()` 先尽力 `disable`，再释放句柄；`disable` 失败仍继续关闭，返回第一个错误（诊断），避免输出悬空。
- 非线程安全；同一句柄的 `setFrequency`/`setDutyCycle`/`enable`/`disable`/`close` 必须由调用方串行化。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_handle` | `Long` | final | `>0`；不透明句柄 |
| `_boardPin` | `BoardPin` | final | 非 null；具备 `PwmOutput` |
| `_channelNumber` | `Int` | final | `>=0`；等于 `boardPin.pwmChannelNumber()` |
| `_frequencyHz` | `Long` | 内部 | `>0`；当前配置频率 |
| `_dutyPermille` | `Int` | 内部 | `0..1000`；当前配置占空比 |
| `_enabled` | `Bool` | 内部 | 输出是否使能 |
| `_open` | `Bool` | 内部 | 是否打开 |

不变量：

- `_handle > 0`；`_boardPin` 非 null 且 `supports(PinCapability.PwmOutput)`；`_channelNumber == _boardPin.pwmChannelNumber()` 且 `>=0`。
- `_frequencyHz > 0`；`_dutyPermille` 在 `0..1000`。
- 构造后 `_open = true`、`_enabled = false`、`_dutyPermille = 0`；`enable` 成功后才 `_enabled = true`。
- `close` 后 `_open = false`、`_enabled = false`；`close` 幂等；关闭后不再调用原生 PWM 原语。
- 配置缓存只在适配器成功后更新；失败不改变缓存，避免“以为改了实际没改”。

---

## 4. 生命周期

由 `PwmChannel.open` 创建；构造器主要供宿主/测试使用。调用方持有；调用方 `close()`；无 `deinit`/finalizer 依赖。关闭后对象终止，不提供重新打开；需要新频率/引脚/会话时重新 `open`。关闭后只允许纯读取器与 `close`；`setFrequency`/`setDutyCycle`/`enable`/`disable` 返回 `Unavailable`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `PwmChannel(Long handle, BoardPin boardPin, Int channelNumber, Long frequencyHz)` | handle、boardPin、channelNumber、frequencyHz | handle>0；boardPin 非 null 且支持 `PwmOutput`；channelNumber≥0 且等于引脚通道；frequencyHz>0 | 非法 → panic |
| `PwmChannel.open(Context context, BoardPin boardPin, Long frequencyHz)` | context、boardPin、frequencyHz | 同构造；适配器可拒绝硬件不支持的频率 | null → panic；频率≤0 → `InvalidArgument`；无 PWM 能力 → `Unsupported`；适配器失败透传 |

`open` 成功后返回打开对象，输出默认禁用；适配器返回句柄 `<=0` 视为内部错误，返回 `Internal`，不构造对象。

---

## 6. 字段表

见 §3；字段私有。`BoardPin` 是不可变值，复制引用；`_frequencyHz`/`_dutyPermille`/`_enabled`/`_open` 是句柄状态，不作为值对象共享。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `open`（static） | 打开 PWM 通道 | `Context context, BoardPin boardPin, Long frequencyHz` | `Result<PwmChannel, Error>` | null → panic；`InvalidArgument`/`Unsupported`/`PermissionDenied`/`Busy`/`Io`/`Cancelled`/`Timeout` |
| `boardPin` | 绑定引脚 | 无 | `BoardPin` | 无 |
| `channelNumber` | PWM 通道号 | 无 | `Int` | 无 |
| `frequencyHz` | 当前频率 | 无 | `Long` | 无 |
| `dutyPermille` | 当前占空比 | 无 | `Int` | 无 |
| `isEnabled` | 输出是否使能 | 无 | `Bool` | 无 |
| `setFrequency` | 设置频率 | `Context context, Long frequencyHz` | `Result<Unit, Error>` | null → panic；关闭 → `Unavailable`；频率≤0 → `InvalidArgument`；`Unsupported`/`Busy`/`Io`/`Cancelled`/`Timeout` |
| `setDutyCycle` | 设置占空比 | `Context context, Int dutyPermille` | `Result<Unit, Error>` | null → panic；关闭 → `Unavailable`；越界 → `InvalidArgument`；`Unsupported`/`Busy`/`Io`/`Cancelled`/`Timeout` |
| `enable` | 使能输出 | `Context context` | `Result<Unit, Error>` | null → panic；关闭 → `Unavailable`；`Unsupported`/`Busy`/`Io`/`Cancelled`/`Timeout` |
| `disable` | 禁用输出 | `Context context` | `Result<Unit, Error>` | null → panic；关闭 → `Unavailable`；`Unsupported`/`Busy`/`Io`/`Cancelled`/`Timeout` |
| `close` | 禁用并关闭 | 无 | `Result<Unit, Error>` | `Io`/`Unsupported`（诊断） |
| `isOpen` | 是否打开 | 无 | `Bool` | 无 |

说明：

- `open`：`context == null`/`boardPin == null` panic；`frequencyHz <=0` → `InvalidArgument`；引脚无 `PwmOutput` 或通道号 `<0` → `Unsupported`；适配器可因频率/分辨率返回 `Unsupported`/`InvalidArgument`。
- `setFrequency`：关闭后 `Unavailable`；`frequencyHz <=0` → `InvalidArgument`；成功后更新 `_frequencyHz`；不改变 `_dutyPermille`、不自动 `enable`；可阻塞，取消 `Cancelled`，超时 `Timeout`。
- `setDutyCycle`：关闭后 `Unavailable`；`dutyPermille <0` 或 `>1000` → `InvalidArgument`；成功后更新 `_dutyPermille`；不自动 `enable`；0/1000 是恒定无效/有效电平，不是“关闭输出”。
- `enable`：关闭后 `Unavailable`；已使能返回 `Ok(unit)`；成功后 `_enabled = true`；使用当前频率/占空比。
- `disable`：关闭后 `Unavailable`；已禁用返回 `Ok(unit)`；成功后 `_enabled = false`；不改变频率/占空比缓存。
- `close`：第一次置 `_open = false`、`_enabled = false`；若之前使能，先调用原生 `pwmDisableOnCloseRaw`，再 `pwmCloseRaw`；`disable` 失败仍继续关闭，返回第一个错误（可能是 `Io`/`Unsupported`）；后续 `Ok(unit)`；关闭失败返回 `Io`/`Unsupported`，状态仍视为关闭。
- 纯读取器关闭后仍返回最后配置值；`isEnabled` 关闭后为 `false`。
- 不提供 `setPulseNanoseconds`/`setPeriodNanoseconds`/`setPolarity`/`setDeadTime`/`capture`：X。
- 不提供 `describe`/`equals`/`copy`：通道是资源，不是值对象。

---

## 8. 使用的技术

- 不透明 `Long` 句柄；
- 引脚能力/通道号双重校验；
- 频率 + 千分比占空比；
- 配置缓存与成功后提交；
- 显式 enable/disable；
- 关闭时尽力禁用；
- `Context`/`Result`；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、final/内部字段、Long、Int、Bool、Result；
- 运行时/适配器：
  - `pwmOpenRaw(Context context, Int channelNumber, Long frequencyHz) -> Result<Long, Error>`；
  - `pwmSetFrequencyRaw(Context context, Long handle, Long frequencyHz) -> Result<Unit, Error>`；
  - `pwmSetDutyRaw(Context context, Long handle, Int dutyPermille) -> Result<Unit, Error>`；
  - `pwmEnableRaw(Context context, Long handle) -> Result<Unit, Error>`；
  - `pwmDisableRaw(Context context, Long handle) -> Result<Unit, Error>`；
  - `pwmDisableOnCloseRaw(Long handle) -> Result<Unit, Error>`；`close` 专用、无 `Context`、不得阻塞；
  - `pwmCloseRaw(Long handle) -> Result<Unit, Error>`；
- 适配器负责：
  - 把 `channelNumber` 映射到定时器/比较通道；
  - 频率与占空比的分辨率/范围校验；
  - 保证 `dutyPermille` 0/1000 对应恒定无效/有效电平；
  - 拒绝不支持的频率/通道，返回 `Unsupported`/`InvalidArgument`；
- 原生句柄必须 `>0`；`0`/负数在 `open` 中转为 `Internal`，构造器 panic；
- 接口：`Context`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`、`BoardPin`、`PinCapability`。

---

## 10. 依赖的特性/接口/类

`Context`、`Error`、`BasicError`、`ErrorKind`、`BoardPin`、`PinCapability`、`Board`、`Embedded`。

相关但不同层：`xdk.device.GpioPin`（数字输出）、`xdk.embedded.AdcChannel`（采样）。本类型不提供 PWM 捕获；需要测量外部 PWM 时用定时器输入捕获（X）或外部器件。

---

## 11. 所有权与并发

引用语义；通道由调用方持有并关闭；无全局注册表；无循环引用。`BoardPin` 是借用/共享的不可变值。
非线程安全：`setFrequency`/`setDutyCycle`/`enable`/`disable`/`close` 不得并发；调用方需串行化，或确保关闭时没有其它调用。`close` 幂等指重复调用安全，不承诺并发 close 安全。
纯读取器可并发读取，但不要依赖与并发 `close` 的时序。
无 `equals`/`copy`；不推荐作 `Map` 键；关闭后不得再用通道。

---

## 12. 示例与反例

正确：

```xnull
Result<PwmChannel, Error> opened = PwmChannel.open(
    context, board.findPin("PA8"), 1000)
if opened.isOk() {
    PwmChannel channel = opened.value()
    Result<Unit, Error> duty = channel.setDutyCycle(context, 250)
    if duty.isOk() {
        Result<Unit, Error> started = channel.enable(context)
    }
    Result<Unit, Error> stopped = channel.disable(context)
    Result<Unit, Error> closed = channel.close()
}
```

正确：`setDutyCycle(context, 0)` 输出恒定无效电平；`setDutyCycle(context, 1000)` 输出恒定有效电平；两者都不等于 `disable`。

反例：`open` 后假设输出已使能；`setDutyCycle` 后不 `enable` 就期望波形；把 `dutyPermille` 当百分比（100 实际是 10%）；频率 `0`；`setFrequency` 后假设脉宽不变；在 `disable` 失败后忽略错误并继续使用通道；close 后继续 `setDutyCycle`；多任务并发改同一通道；用 PWM 捕获 API（本类型没有）。

---

## 13. 测试场景义务

打开成功/无 PWM 能力/通道号 `-1`/频率 `0`/负值/无权限/占用/取消/超时；`setFrequency` 成功/失败不更新缓存/关闭后/取消；`setDutyCycle` `0`/`1`/`500`/`999`/`1000`/`-1`/`1001`/关闭后；`enable`/`disable` 幂等/失败状态不变/关闭后；`close` 使能时先禁用/禁用失败仍关闭/幂等/关闭后纯读取器；`frequencyHz`/`dutyPermille`/`isEnabled` 缓存语义；多通道独立；桌面/无 PWM 平台 `Unsupported`；原生句柄 `<=0` → `Internal`。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
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
        _handle = handle
        _boardPin = boardPin
        _channelNumber = channelNumber
        _frequencyHz = frequencyHz
        _dutyPermille = 0
        _enabled = false
        _open = true
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
        Int channelNumber = boardPin.pwmChannelNumber()
        if channelNumber < 0 {
            return Err(new BasicError(ErrorKind.Unsupported,
                "pin has no pwm channel"))
        }
        Result<Long, Error> opened = pwmOpenRaw(
            context, channelNumber, frequencyHz)
        if opened.isErr() { return Err(opened.error()) }
        if opened.value() <= 0 {
            return Err(new BasicError(ErrorKind.Internal,
                "invalid pwm handle"))
        }
        return Ok(new PwmChannel(opened.value(), boardPin, channelNumber,
            frequencyHz))
    }

    BoardPin boardPin() { return _boardPin }
    Int channelNumber() { return _channelNumber }
    Long frequencyHz() { return _frequencyHz }
    Int dutyPermille() { return _dutyPermille }
    Bool isEnabled() { return _enabled }
    Bool isOpen() { return _open }

    Result<Unit, Error> setFrequency(Context context, Long frequencyHz) {
        if context == null { throw "PwmChannel.setFrequency: null context" }
        if !_open { return Err(unavailableError("pwm channel")) }
        if frequencyHz <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "invalid pwm frequency"))
        }
        Result<Unit, Error> changed = pwmSetFrequencyRaw(
            context, _handle, frequencyHz)
        if changed.isErr() { return Err(changed.error()) }
        _frequencyHz = frequencyHz
        return Ok(unit)
    }

    Result<Unit, Error> setDutyCycle(Context context, Int dutyPermille) {
        if context == null { throw "PwmChannel.setDutyCycle: null context" }
        if !_open { return Err(unavailableError("pwm channel")) }
        if dutyPermille < 0 || dutyPermille > 1000 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "duty permille out of range"))
        }
        Result<Unit, Error> changed = pwmSetDutyRaw(
            context, _handle, dutyPermille)
        if changed.isErr() { return Err(changed.error()) }
        _dutyPermille = dutyPermille
        return Ok(unit)
    }

    Result<Unit, Error> enable(Context context) {
        if context == null { throw "PwmChannel.enable: null context" }
        if !_open { return Err(unavailableError("pwm channel")) }
        if _enabled { return Ok(unit) }
        Result<Unit, Error> started = pwmEnableRaw(context, _handle)
        if started.isErr() { return Err(started.error()) }
        _enabled = true
        return Ok(unit)
    }

    Result<Unit, Error> disable(Context context) {
        if context == null { throw "PwmChannel.disable: null context" }
        if !_open { return Err(unavailableError("pwm channel")) }
        if !_enabled { return Ok(unit) }
        Result<Unit, Error> stopped = pwmDisableRaw(context, _handle)
        if stopped.isErr() { return Err(stopped.error()) }
        _enabled = false
        return Ok(unit)
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        Bool wasEnabled = _enabled
        _open = false
        _enabled = false
        Result<Unit, Error> disableResult = Ok(unit)
        if wasEnabled {
            disableResult = pwmDisableOnCloseRaw(_handle)
        }
        Result<Unit, Error> closeResult = pwmCloseRaw(_handle)
        if disableResult.isErr() { return disableResult }
        return closeResult
    }
}
```
