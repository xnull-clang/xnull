# `Rtc`

| 项 | 值 |
| --- | --- |
| 类型 | `class Rtc`（控制句柄） |
| 包 | `xdk.embedded` |
| 层 |  |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Error`、`Instant`、`Board` |

---

## 1. 定位

已打开的**实时时钟控制句柄**：读取当前时间、设置时间、设置/清除单闹钟、查询闹钟、校准、关闭、是否打开。

不做：多闹钟、周期闹钟、备份域/篡改检测、温度补偿、闰秒/时区/日历格式化、可信时间/安全审计时间、RTC 中断回调、裸寄存器/`ioctl`。时区/格式化用 `xdk.time`；可信时间用安全元件/签名时间源。

---

## 2. 设计逻辑

- 为什么是 class：RTC 是有状态、可能被独占的硬件资源，需要显式打开/关闭；不是值对象。
- 由静态 `Rtc.open(context, board)` 创建；构造器主要供宿主/测试使用。`Board.hasRtc()` 为 `false` 时返回 `Unsupported`；板只暴露一个 RTC 句柄。
- `now` 返回 `Instant`（epoch 毫秒），不是日历字段；时区/格式化由 `xdk.time` 处理。RTC 未设置时间时返回 `NotFound`，不返回 epoch 0 或当前墙钟。
- `setTime` 设置 RTC 并启动走时；适配器可因硬件范围/写保护返回 `InvalidArgument`/`PermissionDenied`。
- 单闹钟：`setAlarm` 替换已有闹钟；`clearAlarm` 幂等；`alarm` 在无闹钟时返回 `NotFound`，不是 `null`；`isAlarmPending` 查询并**清除**挂起锁存（与 Zephyr `rtc_alarm_is_pending` 语义一致），避免同一事件无限重复触发。
- `calibrate` 输入 ppm（百万分率），范围 `-1000..1000`；正数提高频率、负数降低频率；适配器可因不支持返回 `Unsupported`，或因超出硬件范围返回 `InvalidArgument`。`calibrationPpm()` 返回最近一次成功配置值（初值 0），不是硬件实际寄存器读数。
- RTC 通常由 VBAT/备份域供电，主电源关闭/低功耗时继续运行；`close()` 不停止时钟、不清除闹钟。关闭后 `now`/`setTime`/`setAlarm`/`clearAlarm`/`alarm`/`isAlarmPending`/`calibrate` 返回 `Unavailable`；`calibrationPpm`/`isOpen`/`close` 可用。
- 打开可能独占 RTC；已被占用返回 `Busy`。RTC 是系统级共享资源时，适配器可选择允许多个只读句柄；本类型不承诺共享。
- 非线程安全；同一句柄的 `now`/`setTime`/`setAlarm`/`clearAlarm`/`alarm`/`isAlarmPending`/`calibrate`/`close` 必须由调用方串行化。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_handle` | `Long` | final | `>0`；不透明句柄 |
| `_calibrationPpm` | `Int` | 内部 | `-1000..1000`；最近成功配置值 |
| `_open` | `Bool` | 内部 | 是否打开 |

不变量：

- `_handle > 0`；构造后 `_open = true`、`_calibrationPpm = 0`。
- `_calibrationPpm` 在 `-1000..1000`；只在 `calibrate` 成功后更新。
- `close` 后 `_open = false`；`close` 幂等；关闭后不再调用原生 RTC 原语。
- `_handle` 不复用、不持久化、不跨进程。
- RTC 时间/闹钟状态由硬件持有，不在对象内缓存；`alarm()`/`isAlarmPending()` 每次查询适配器。
- `now` 的 `Instant` 由适配器从 RTC 日历换算；未设置时间必须返回 `NotFound`。

---

## 4. 生命周期

由 `Rtc.open` 创建；调用方持有；调用方 `close()` 释放句柄；无 `deinit`/finalizer 依赖。关闭后对象终止，不提供重新打开；需要新会话时重新 `open`。RTC 时钟与闹钟在 `close` 后继续运行；需要停闹钟必须显式 `clearAlarm`（在关闭前）。关闭后只允许 `calibrationPpm`/`isOpen`/`close`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Rtc(Long handle)` | handle | handle>0 | 非法 → panic |
| `Rtc.open(Context context, Board board)` | context、board | context/board 非 null；board 必须有 RTC | null → panic；无 RTC → `Unsupported`；无权限/占用/IO → 适配器错误 |

`open` 成功后返回打开对象；适配器返回句柄 `<=0` 视为内部错误，返回 `Internal`，不构造对象。RTC 时间是否已设置不由 `open` 决定；`now` 用 `NotFound` 表达未设置。

---

## 6. 字段表

见 §3；字段私有。`Rtc` 不持有 `Board` 引用；板信息只在 `open` 时用于选择 RTC。时间/闹钟不在对象内缓存，避免与硬件/其它句柄不一致。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `open`（static） | 打开 RTC | `Context context, Board board` | `Result<Rtc, Error>` | null → panic；`Unsupported`/`PermissionDenied`/`Busy`/`Io`/`Cancelled`/`Timeout` |
| `now` | 读取当前时间 | `Context context` | `Result<Instant, Error>` | null → panic；关闭 → `Unavailable`；未设置 → `NotFound`；`Io`/`Cancelled`/`Timeout` |
| `setTime` | 设置当前时间 | `Context context, Instant instant` | `Result<Unit, Error>` | null → panic；关闭 → `Unavailable`；`InvalidArgument`/`PermissionDenied`/`Unsupported`/`Io`/`Cancelled`/`Timeout` |
| `setAlarm` | 设置/替换闹钟 | `Context context, Instant instant` | `Result<Unit, Error>` | null → panic；关闭 → `Unavailable`；`InvalidArgument`/`PermissionDenied`/`Unsupported`/`Io`/`Cancelled`/`Timeout` |
| `clearAlarm` | 清除闹钟 | `Context context` | `Result<Unit, Error>` | null → panic；关闭 → `Unavailable`；`Unsupported`/`PermissionDenied`/`Io`/`Cancelled`/`Timeout` |
| `alarm` | 查询闹钟 | `Context context` | `Result<Instant, Error>` | null → panic；关闭 → `Unavailable`；无闹钟 → `NotFound`；`Unsupported`/`Io`/`Cancelled` |
| `isAlarmPending` | 查询并清除挂起 | `Context context` | `Result<Bool, Error>` | null → panic；关闭 → `Unavailable`；`Unsupported`/`Io`/`Cancelled` |
| `calibrate` | 设置校准 | `Context context, Int partsPerMillion` | `Result<Unit, Error>` | null → panic；关闭 → `Unavailable`；越界 → `InvalidArgument`；`Unsupported`/`PermissionDenied`/`Io`/`Cancelled` |
| `calibrationPpm` | 最近校准值 | 无 | `Int` | 无 |
| `isOpen` | 是否打开 | 无 | `Bool` | 无 |
| `close` | 关闭句柄 | 无 | `Result<Unit, Error>` | `Io`（诊断） |

说明：

- `open`：`context == null`/`board == null` panic；`board.hasRtc()` 为 `false` → `Unsupported`；无权限 `PermissionDenied`；已被占用 `Busy`。
- `now`：关闭后 `Unavailable`；RTC 时间未设置 → `NotFound`；适配器读数失败 → `Io`；可阻塞，取消 `Cancelled`，超时 `Timeout`；返回 `Instant` 借用/新值，调用方拥有。
- `setTime`：关闭后 `Unavailable`；`instant == null` panic；适配器可因硬件范围/写保护返回 `InvalidArgument`/`PermissionDenied`/`Unsupported`；成功后 RTC 开始走时。
- `setAlarm`：关闭后 `Unavailable`；`instant == null` panic；单闹钟，替换旧闹钟；硬件不支持闹钟 → `Unsupported`；时间已过去的行为由适配器决定（可立即挂起或 `InvalidArgument`），文档必须明确平台行为。
- `clearAlarm`：关闭后 `Unavailable`；没有闹钟时 `Ok(unit)`（幂等）；硬件不支持闹钟 → `Unsupported`。
- `alarm`：关闭后 `Unavailable`；无闹钟 → `NotFound`；硬件不支持闹钟 → `Unsupported`；返回 `Instant` 新值。
- `isAlarmPending`：关闭后 `Unavailable`；查询会清除挂起锁存；硬件不支持闹钟 → `Unsupported`；返回值只表示调用瞬间状态。
- `calibrate`：关闭后 `Unavailable`；`partsPerMillion < -1000` 或 `> 1000` → `InvalidArgument`；硬件不支持/超范围 → `Unsupported`/`InvalidArgument`；成功后更新 `_calibrationPpm`。
- `calibrationPpm`/`isOpen` 纯读取；关闭后仍可读最近配置值。
- `close`：第一次 `_open = false` 并调用原生关闭；后续 `Ok(unit)`；关闭失败返回 `Io`，状态仍视为关闭。**RTC 继续走时，闹钟仍可能触发**；需要停闹钟应在 close 前 `clearAlarm`。
- 不提供 `setDateTime`/`format`/`parse`/`timeZone`/`multiAlarm`/`setCallback`：`xdk.time` 或 X。
- 不提供 `describe`/`equals`/`copy`：RTC 是资源，不是值对象。

---

## 8. 使用的技术

- 不透明 `Long` 句柄；
- epoch 毫秒 `Instant`；
- 单闹钟设置/查询/清除；
- 挂起锁存查询并清除；
- ppm 校准；
- `Context`/`Result`；
- 幂等关闭；
- 非线程安全句柄。

---

## 9. 需要的支撑

- 语言：class、final/内部字段、Long、Int、Bool、Result；
- 运行时/适配器：
  - `rtcOpenRaw(Context context, Board board) -> Result<Long, Error>`；
  - `rtcNowRaw(Context context, Long handle) -> Result<Instant, Error>`；未设置时间 → `NotFound`；
  - `rtcSetTimeRaw(Context context, Long handle, Instant instant) -> Result<Unit, Error>`；
  - `rtcSetAlarmRaw(Context context, Long handle, Instant instant) -> Result<Unit, Error>`；
  - `rtcClearAlarmRaw(Context context, Long handle) -> Result<Unit, Error>`；
  - `rtcAlarmRaw(Context context, Long handle) -> Result<Instant, Error>`；无闹钟 → `NotFound`；
  - `rtcAlarmPendingRaw(Context context, Long handle) -> Result<Bool, Error>`；读取并清除挂起；
  - `rtcCalibrateRaw(Context context, Long handle, Int partsPerMillion) -> Result<Unit, Error>`；
  - `rtcCloseRaw(Long handle) -> Result<Unit, Error>`；
- 适配器负责：
  - 选择板载 RTC；
  - 日历 ↔ epoch 毫秒换算；
  - 单闹钟映射；
  - 挂起锁存语义；
  - 校准范围/寄存器映射；
  - 关闭句柄时**不**停止 RTC；
- 原生句柄必须 `>0`；`0`/负数在 `open` 中转为 `Internal`，构造器 panic；
- 接口：`Context`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`、`Instant`、`Board`。

---

## 10. 依赖的特性/接口/类

`Context`、`Error`、`Instant`、`Board`、`Embedded`。

相关但不同层：`xdk.time.DateTime`/`TimeZone`（日历/时区）、`xdk.time.Duration`（时间差）、`xdk.os`（系统时间）。本类型不复制时间格式化/时区 API，也不提供可信时间。

---

## 11. 所有权与并发

引用语义；RTC 由调用方持有并关闭；无全局注册表；无循环引用。`Board` 只在 `open` 时借用，不长期持有。
非线程安全：`now`/`setTime`/`setAlarm`/`clearAlarm`/`alarm`/`isAlarmPending`/`calibrate`/`close` 不得并发；调用方需串行化，或确保关闭时没有其它调用。`close` 幂等指重复调用安全，不承诺并发 close 安全。
`Instant` 是不可变值，返回新值/共享值；调用方拥有。
无 `equals`/`copy`；不推荐作 `Map` 键；关闭后不得再读写 RTC。

---

## 12. 示例与反例

正确：

```xnull
Result<Rtc, Error> opened = Rtc.open(context, board)
if opened.isOk() {
    Rtc rtc = opened.value()
    Result<Instant, Error> current = rtc.now(context)
    if current.isErr() && current.error().kind() == ErrorKind.NotFound {
        Result<Unit, Error> set = rtc.setTime(context, Instant.now())
    }
    Result<Unit, Error> alarmSet = rtc.setAlarm(
        context, Instant.now().plus(Duration.ofMinutes(5)))
    Result<Bool, Error> pending = rtc.isAlarmPending(context)
    Result<Unit, Error> cleared = rtc.clearAlarm(context)
    Result<Unit, Error> closed = rtc.close()
}
```

正确：`close` 前 `clearAlarm`，避免关闭后闹钟继续触发；`now` 的 `NotFound` 表示“时间未设置”，不是 I/O 失败。

反例：把 `now` 的 `NotFound` 当 epoch 0；用 RTC 作为安全审计可信时间；`setAlarm` 设置过去时间并假设一定报错（平台相关）；`isAlarmPending` 轮询却不理解它会清除锁存；`close` 后假设闹钟已取消；多任务并发写 RTC；用 `Rtc` 做定时器/延时；把 `calibrationPpm` 当硬件实际校准读数。

---

## 13. 测试场景义务

打开成功/板无 RTC/无权限/占用/取消/超时；`now` 未设置 `NotFound`/已设置/关闭后/取消/超时；`setTime` 成功/非法范围/写保护/关闭后；`setAlarm` 成功/替换/过去时间/不支持/关闭后；`clearAlarm` 有/无闹钟/幂等/关闭后；`alarm` 有/无 `NotFound`/不支持/关闭后；`isAlarmPending` 挂起/清除锁存/不支持/关闭后；`calibrate` 边界 `-1000`/`0`/`1000`/`-1001`/`1001`/不支持/成功后缓存；`calibrationPpm` 初值/更新/关闭后；`close` 幂等/关闭失败仍关闭/RTC 继续走时/闹钟仍触发；`Instant` 换算边界；桌面/无 RTC 平台 `Unsupported`；原生句柄 `<=0` → `Internal`。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class Rtc {
    final Long _handle
    Int _calibrationPpm
    Bool _open

    Rtc(Long handle) {
        if handle == null || handle <= 0 {
            throw "Rtc: invalid handle"
        }
        _handle = handle
        _calibrationPpm = 0
        _open = true
    }

    static Result<Rtc, Error> open(Context context, Board board) {
        if context == null || board == null {
            throw "Rtc.open: null argument"
        }
        if !board.hasRtc() {
            return Err(new BasicError(ErrorKind.Unsupported,
                "board has no rtc"))
        }
        Result<Long, Error> opened = rtcOpenRaw(context, board)
        if opened.isErr() { return Err(opened.error()) }
        if opened.value() <= 0 {
            return Err(new BasicError(ErrorKind.Internal,
                "invalid rtc handle"))
        }
        return Ok(new Rtc(opened.value()))
    }

    Int calibrationPpm() { return _calibrationPpm }
    Bool isOpen() { return _open }

    Result<Instant, Error> now(Context context) {
        if context == null { throw "Rtc.now: null context" }
        if !_open { return Err(unavailableError("rtc")) }
        return rtcNowRaw(context, _handle)
    }

    Result<Unit, Error> setTime(Context context, Instant instant) {
        if context == null || instant == null {
            throw "Rtc.setTime: null argument"
        }
        if !_open { return Err(unavailableError("rtc")) }
        return rtcSetTimeRaw(context, _handle, instant)
    }

    Result<Unit, Error> setAlarm(Context context, Instant instant) {
        if context == null || instant == null {
            throw "Rtc.setAlarm: null argument"
        }
        if !_open { return Err(unavailableError("rtc")) }
        return rtcSetAlarmRaw(context, _handle, instant)
    }

    Result<Unit, Error> clearAlarm(Context context) {
        if context == null { throw "Rtc.clearAlarm: null context" }
        if !_open { return Err(unavailableError("rtc")) }
        return rtcClearAlarmRaw(context, _handle)
    }

    Result<Instant, Error> alarm(Context context) {
        if context == null { throw "Rtc.alarm: null context" }
        if !_open { return Err(unavailableError("rtc")) }
        return rtcAlarmRaw(context, _handle)
    }

    Result<Bool, Error> isAlarmPending(Context context) {
        if context == null {
            throw "Rtc.isAlarmPending: null context"
        }
        if !_open { return Err(unavailableError("rtc")) }
        return rtcAlarmPendingRaw(context, _handle)
    }

    Result<Unit, Error> calibrate(Context context, Int partsPerMillion) {
        if context == null { throw "Rtc.calibrate: null context" }
        if !_open { return Err(unavailableError("rtc")) }
        if partsPerMillion < -1000 || partsPerMillion > 1000 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "rtc calibration out of range"))
        }
        Result<Unit, Error> calibrated = rtcCalibrateRaw(
            context, _handle, partsPerMillion)
        if calibrated.isErr() { return Err(calibrated.error()) }
        _calibrationPpm = partsPerMillion
        return Ok(unit)
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        return rtcCloseRaw(_handle)
    }
}
```
