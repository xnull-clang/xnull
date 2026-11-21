# `Watchdog`

| 项 | 值 |
| --- | --- |
| 类型 | `class Watchdog`（控制句柄） |
| 包 | `xdk.embedded` |
| 层 |  |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Error`、`Board` |

---

## 1. 定位

已打开的**看门狗控制句柄**：启动（简单超时或窗口超时）、喂狗、停止、查询窗口/状态、关闭。

不做：多阶段看门狗链、复位原因解析、独立看门狗 + 窗口看门狗组合编排、喂狗线程/定时器、调试器暂停策略、裸寄存器/`ioctl`。喂狗调度由应用/执行层负责。

---

## 2. 设计逻辑

- 为什么是 class：看门狗是有状态硬件资源，需要显式启动/喂狗/停止/关闭；不是值对象。
- 由静态 `Watchdog.open(context, board)` 创建；构造器主要供宿主/测试使用。`Board.hasWatchdog()` 为 `false` 时返回 `Unsupported`；板只暴露一个看门狗句柄，不支持多实例索引。
- 打开后看门狗处于**停止**状态；必须显式 `start`/`startWindowed`。这样调用方可以先决定超时/窗口，再启用保护。
- `start(context, timeoutMillis)` 是简单超时：喂狗窗口 `[0, timeoutMillis]`；`startWindowed(context, minimumFeedMillis, maximumFeedMillis)` 是窗口看门狗：早于 `minimumFeedMillis` 喂狗应被拒绝，晚于 `maximumFeedMillis` 触发复位。
- 窗口看门狗是安全特性：`feed` 在窗口未打开时返回 `Busy`，且**不得**因为一次被拒绝的喂狗而复位。适配器必须先检查窗口再写硬件；无法原子检查的平台应返回 `Unsupported`，而不是冒险复位。
- `stop(context)` 是独立显式操作；不是所有硬件都允许停表，可能返回 `Unsupported`/`PermissionDenied`。`close()` **不停止**已启动的看门狗：关闭句柄不等于解除复位保护，这是安全默认。
- `close()` 幂等；关闭后 `minimumFeedMillis`/`maximumFeedMillis`/`isStarted`/`isOpen`/`close` 可用；`start`/`startWindowed`/`feed`/`stop` 返回 `Unavailable`。`isStarted()` 在关闭后仍报告看门狗是否处于已启动保护状态（可能继续复位系统）。
- 启动后再次 `start`/`startWindowed` 返回 `Busy`；停止后可重新启动（若硬件允许）。
- 非线程安全；同一句柄的 `start`/`startWindowed`/`feed`/`stop`/`close` 必须由调用方串行化。多任务喂狗应由唯一负责人串行化。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_handle` | `Long` | final | `>0`；不透明句柄 |
| `_open` | `Bool` | 内部 | 是否打开 |
| `_started` | `Bool` | 内部 | 看门狗是否已启动/保护中 |
| `_minimumFeedMillis` | `Long` | 内部 | `>=0`；窗口下界；简单超时为 0 |
| `_maximumFeedMillis` | `Long` | 内部 | `>0`；窗口上界/超时 |

不变量：

- `_handle > 0`；构造后 `_open = true`、`_started = false`、两个窗口值均为 `0`。
- 启动成功后 `_started = true`；`_minimumFeedMillis >= 0`；`_maximumFeedMillis > _minimumFeedMillis`。
- 简单超时启动后 `_minimumFeedMillis = 0`、`_maximumFeedMillis = timeoutMillis`。
- `stop` 成功后 `_started = false`；窗口值保留最后配置（诊断用）。
- `close` 后 `_open = false`；`_started` 不因 `close` 改变；`close` 幂等。
- 关闭后不再调用原生启动/喂狗/停止/关闭原语；`_handle` 不复用、不持久化、不跨进程。
- `feed` 只在 `_open && _started` 时执行；被窗口拒绝时不改变 `_started`、不复位。

---

## 4. 生命周期

由 `Watchdog.open` 创建，初始停止；调用方 `start`/`startWindowed` 后周期 `feed`；需要停表时显式 `stop`；最后 `close` 释放句柄。关闭不停止看门狗；若已启动，关闭后看门狗继续运行并可能复位系统。无 `deinit`/finalizer 依赖。关闭后只允许纯读取器与 `close`；其余操作 `Unavailable`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Watchdog(Long handle)` | handle | handle>0 | 非法 → panic |
| `Watchdog.open(Context context, Board board)` | context、board | context/board 非 null；board 必须有看门狗 | null → panic；无看门狗 → `Unsupported`；无权限/占用/IO → 适配器错误 |

`open` 成功后返回停止状态的对象；适配器返回句柄 `<=0` 视为内部错误，返回 `Internal`，不构造对象。

---

## 6. 字段表

见 §3；字段私有。`Watchdog` 不持有 `Board` 引用；板信息只在 `open` 时用于选择看门狗，避免长期持有板描述。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `open`（static） | 打开看门狗 | `Context context, Board board` | `Result<Watchdog, Error>` | null → panic；`Unsupported`/`PermissionDenied`/`Busy`/`Io`/`Cancelled`/`Timeout` |
| `start` | 启动简单超时 | `Context context, Long timeoutMillis` | `Result<Unit, Error>` | null → panic；关闭 → `Unavailable`；已启动 → `Busy`；超时≤0 → `InvalidArgument`；`Unsupported`/`PermissionDenied`/`Io`/`Cancelled`/`Timeout` |
| `startWindowed` | 启动窗口看门狗 | `Context context, Long minimumFeedMillis, Long maximumFeedMillis` | `Result<Unit, Error>` | null → panic；关闭 → `Unavailable`；已启动 → `Busy`；窗口非法 → `InvalidArgument`；`Unsupported`/`PermissionDenied`/`Io`/`Cancelled`/`Timeout` |
| `feed` | 喂狗 | `Context context` | `Result<Unit, Error>` | null → panic；关闭/未启动 → `Unavailable`；窗口未开 → `Busy`；`Unsupported`/`Io`/`Cancelled`/`Timeout` |
| `stop` | 停止看门狗 | `Context context` | `Result<Unit, Error>` | null → panic；关闭 → `Unavailable`；未启动 → `Ok(unit)`；`Unsupported`/`PermissionDenied`/`Io`/`Cancelled`/`Timeout` |
| `minimumFeedMillis` | 窗口下界 | 无 | `Long` | 无 |
| `maximumFeedMillis` | 窗口上界/超时 | 无 | `Long` | 无 |
| `isStarted` | 是否已启动/保护中 | 无 | `Bool` | 无 |
| `isOpen` | 是否打开 | 无 | `Bool` | 无 |
| `close` | 释放句柄（不停止） | 无 | `Result<Unit, Error>` | `Io`（诊断） |

说明：

- `open`：`context == null`/`board == null` panic；`board.hasWatchdog()` 为 `false` → `Unsupported`；适配器可选择板载看门狗；无权限 `PermissionDenied`，已被占用 `Busy`。
- `start`：关闭后 `Unavailable`；已启动 `Busy`；`timeoutMillis <=0` → `InvalidArgument`；成功后窗口 `[0, timeoutMillis]`；适配器可向上取整到硬件粒度，但不得低于请求值；无法精确支持返回 `Unsupported`/`InvalidArgument`。
- `startWindowed`：关闭后 `Unavailable`；已启动 `Busy`；`minimumFeedMillis <0` 或 `maximumFeedMillis <= minimumFeedMillis` → `InvalidArgument`；成功后窗口 `[minimum, maximum]`；硬件不支持窗口 → `Unsupported`。
- `feed`：关闭/未启动 `Unavailable`；当前时间早于窗口下界 → `Busy`，且不得复位；超过上界由硬件复位，API 不保证还能返回；取消/超时透传。
- `stop`：关闭后 `Unavailable`；未启动 `Ok(unit)`；硬件不可停表 → `Unsupported`/`PermissionDenied`；成功后 `_started = false`；不改变窗口缓存。
- `close`：第一次 `_open = false` 并调用原生关闭；`_started` 保持不变；后续 `Ok(unit)`；关闭失败返回 `Io`，状态仍视为关闭。**关闭已启动的看门狗后，系统仍可能被复位**。
- `minimumFeedMillis`/`maximumFeedMillis`/`isStarted`/`isOpen` 是纯读取；关闭后仍可读最后配置/保护状态。
- 不提供 `feedAsync`/`setCallback`/`resetCause`/`multiStage`：X 或系统层。
- 不提供 `describe`/`equals`/`copy`：看门狗是资源，不是值对象。

---

## 8. 使用的技术

- 不透明 `Long` 句柄；
- 简单超时 + 窗口看门狗；
- 显式启动/喂狗/停止；
- 关闭不停止的安全默认；
- 窗口拒绝不复位；
- `Context`/`Result`；
- 幂等关闭；
- 非线程安全句柄。

---

## 9. 需要的支撑

- 语言：class、final/内部字段、Long、Bool、Result；
- 运行时/适配器：
  - `wdtOpenRaw(Context context, Board board) -> Result<Long, Error>`；
  - `wdtStartRaw(Context context, Long handle, Long minimumFeedMillis, Long maximumFeedMillis) -> Result<Unit, Error>`；
  - `wdtFeedRaw(Context context, Long handle) -> Result<Unit, Error>`；
  - `wdtStopRaw(Context context, Long handle) -> Result<Unit, Error>`；
  - `wdtCloseRaw(Long handle) -> Result<Unit, Error>`；
- 适配器负责：
  - 选择板载看门狗；
  - 把毫秒窗口映射到硬件计数器/预分频；
  - 窗口未开时拒绝喂狗且不复位；
  - 不可停表时返回 `Unsupported`/`PermissionDenied`；
  - 关闭句柄时**不**停表；
- 原生句柄必须 `>0`；`0`/负数在 `open` 中转为 `Internal`，构造器 panic；
- 接口：`Context`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`、`Board`。

---

## 10. 依赖的特性/接口/类

`Context`、`Error`、`Board`、`Embedded`。

相关但不同层：`xdk.os` 的复位/电源管理（若存在）、`xdk.log`（启动/喂狗诊断日志）。本类型不解析复位原因，也不创建喂狗任务；调度归应用/`xdk.core` 执行层。

---

## 11. 所有权与并发

引用语义；看门狗由调用方持有并关闭；无全局注册表；无循环引用。`Board` 只在 `open` 时借用，不长期持有。
非线程安全：`start`/`startWindowed`/`feed`/`stop`/`close` 不得并发；调用方需串行化，或确保关闭时没有其它调用。`close` 幂等指重复调用安全，不承诺并发 close 安全。
多任务喂狗必须由唯一负责人 或外部互斥串行化；不要多个任务同时 `feed`。
无 `equals`/`copy`；不推荐作 `Map` 键；关闭后不得再启动/喂狗/停止。

---

## 12. 示例与反例

正确：

```xnull
Result<Watchdog, Error> opened = Watchdog.open(context, board)
if opened.isOk() {
    Watchdog watchdog = opened.value()
    Result<Unit, Error> started = watchdog.start(context, 1000)
    if started.isOk() {
        Int cycle = 0
        while cycle < 10 {
            Result<Unit, Error> fed = watchdog.feed(context)
            cycle = cycle + 1
        }
    }
    Result<Unit, Error> closed = watchdog.close()
}
```

正确：窗口看门狗 `startWindowed(context, 100, 500)`；在 100 ms 前喂狗返回 `Busy`，不触发复位；在 500 ms 前必须喂狗。

反例：`close` 后假设看门狗已停止；启动后再次 `start` 并期望重置超时；在窗口未开时循环 `feed` 并期望安全；用 `stop` 作为正常关机路径却不处理 `Unsupported`；多任务并发喂狗；把看门狗当定时器；用 `Board.hasWatchdog()` 代替打开结果；关闭已启动看门狗后继续运行长任务。

---

## 13. 测试场景义务

打开成功/板无看门狗/无权限/占用/取消/超时；`start` 成功/超时 0/负值/已启动 `Busy`/关闭后/取消；`startWindowed` 窗口 `[0,0]`/负下界/上界≤下界/成功/不支持/已启动；`feed` 未启动/关闭后/窗口未开 `Busy` 且不复位/成功/取消；`stop` 未启动/成功/不可停表/关闭后；`close` 停止状态/已启动状态不停止/幂等/关闭失败仍关闭/`isStarted` 保持已启动；`minimumFeedMillis`/`maximumFeedMillis` 简单/窗口/关闭后；多任务串行化；桌面/无看门狗平台 `Unsupported`；原生句柄 `<=0` → `Internal`。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
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
        _handle = handle
        _open = true
        _started = false
        _minimumFeedMillis = 0
        _maximumFeedMillis = 0
    }

    static Result<Watchdog, Error> open(Context context, Board board) {
        if context == null || board == null {
            throw "Watchdog.open: null argument"
        }
        if !board.hasWatchdog() {
            return Err(new BasicError(ErrorKind.Unsupported,
                "board has no watchdog"))
        }
        Result<Long, Error> opened = wdtOpenRaw(context, board)
        if opened.isErr() { return Err(opened.error()) }
        if opened.value() <= 0 {
            return Err(new BasicError(ErrorKind.Internal,
                "invalid watchdog handle"))
        }
        return Ok(new Watchdog(opened.value()))
    }

    Long minimumFeedMillis() { return _minimumFeedMillis }
    Long maximumFeedMillis() { return _maximumFeedMillis }
    Bool isStarted() { return _started }
    Bool isOpen() { return _open }

    Result<Unit, Error> start(Context context, Long timeoutMillis) {
        if context == null { throw "Watchdog.start: null context" }
        if !_open { return Err(unavailableError("watchdog")) }
        if _started {
            return Err(new BasicError(ErrorKind.Busy,
                "watchdog already started"))
        }
        if timeoutMillis <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "invalid watchdog timeout"))
        }
        Result<Unit, Error> started = wdtStartRaw(
            context, _handle, 0, timeoutMillis)
        if started.isErr() { return Err(started.error()) }
        _started = true
        _minimumFeedMillis = 0
        _maximumFeedMillis = timeoutMillis
        return Ok(unit)
    }

    Result<Unit, Error> startWindowed(Context context,
                                      Long minimumFeedMillis,
                                      Long maximumFeedMillis) {
        if context == null {
            throw "Watchdog.startWindowed: null context"
        }
        if !_open { return Err(unavailableError("watchdog")) }
        if _started {
            return Err(new BasicError(ErrorKind.Busy,
                "watchdog already started"))
        }
        if minimumFeedMillis < 0
            || maximumFeedMillis <= minimumFeedMillis {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "invalid watchdog window"))
        }
        Result<Unit, Error> started = wdtStartRaw(
            context, _handle, minimumFeedMillis, maximumFeedMillis)
        if started.isErr() { return Err(started.error()) }
        _started = true
        _minimumFeedMillis = minimumFeedMillis
        _maximumFeedMillis = maximumFeedMillis
        return Ok(unit)
    }

    Result<Unit, Error> feed(Context context) {
        if context == null { throw "Watchdog.feed: null context" }
        if !_open || !_started {
            return Err(unavailableError("watchdog"))
        }
        return wdtFeedRaw(context, _handle)
    }

    Result<Unit, Error> stop(Context context) {
        if context == null { throw "Watchdog.stop: null context" }
        if !_open { return Err(unavailableError("watchdog")) }
        if !_started { return Ok(unit) }
        Result<Unit, Error> stopped = wdtStopRaw(context, _handle)
        if stopped.isErr() { return Err(stopped.error()) }
        _started = false
        return Ok(unit)
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        return wdtCloseRaw(_handle)
    }
}
```
