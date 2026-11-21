# `MemoryLimiterProcessor`

| 项 | 值 |
| --- | --- |
| 类型 | `class MemoryLimiterProcessor implements Processor` |
| 包 | `xdk.agent` |
| 稳定性 | `preview` |
| 依赖 | `Processor`、`TelemetryKind`、`TelemetryBatch`、`MemoryStats`、`SystemInfo`、`Timer`、`Context`、`Error` |

---

## 1. 定位

内存限制处理器：周期检查进程堆使用，超过软/硬限制时拒绝新批次或按显式策略丢弃，向接收器
施加背压，避免 Agent 因数据量过大而 OOM。

它对齐 OTel `memory_limiter` 的软/硬限制语义；XNull 不做强制 GC（没有公开 GC 原语）。

不做：强制 GC、操作系统 OOM 保护、进程外内存限制、容器内存配额读取、持久化队列、采样。

---

## 2. 设计逻辑

- 实现 `Processor`；`kind()` 由构造器固定；
- 硬限制 = `limitBytes`（优先）或 `limitPercentage × 主机总内存`；
- 尖峰限制 = `spikeLimitBytes`（优先）或 `spikeLimitPercentage × 硬限制`；默认硬限制的 20%；
- 软限制 = 硬限制 − 尖峰限制；软限制必须 >0；
- 每 `checkIntervalMillis` 检查一次 `memoryStats().heapUsed()`；`process` 也会在到期时检查；
- 使用中 ≥ 软限制进入 limited 状态；< 软限制恢复正常；
- limited 时：
  - `dropWhenLimited == false`（默认）：返回 `Busy`，让接收器重试/降速；
  - `dropWhenLimited == true`：不转发，累加丢弃记录数，返回 `Ok(unit)`；
- 不做 GC；文档明确“拒绝/丢弃”是唯一手段；
- 建议放在管线第一个处理器（与 OTel 建议一致），使背压尽早传到接收器；
- `isHealthy` 在 limited 时为 false，Agent 健康面可反映降级/不可用；
- `drain` 无缓冲；`close` 停止定时器；幂等。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | 非空、单行 |
| `_kind` | `TelemetryKind` | 非 null |
| `_checkIntervalMillis` | `Long` | >0 |
| `_limitBytes` | `Long` | ≥0；0 表示未配置 |
| `_limitPercentage` | `Int` | 0..100；0 表示未配置 |
| `_spikeLimitBytes` | `Long` | ≥0；0 表示未配置 |
| `_spikeLimitPercentage` | `Int` | 0..100；0 表示未配置 |
| `_dropWhenLimited` | `Bool` | 默认 false |
| `_hostTotalBytes` | `Long` | ≥0；百分比基准 |
| `_hardLimitBytes` | `Long` | >0；构造时解析 |
| `_softLimitBytes` | `Long` | >0；构造时解析 |
| `_lastCheckMono` | `Long` | ≥0 |
| `_limited` | `Bool` | 当前是否受限 |
| `_started` | `Bool` | start 后 true |
| `_closed` | `Bool` | 只从 false 变 true |
| `_downstream` | `Result<Unit, Error>(TelemetryBatch)?` | start 后非 null |
| `_refusedBatches` | `Int` | ≥0 |
| `_droppedBatches` | `Int` | ≥0 |
| `_droppedRecords` | `Int` | ≥0 |
| `_timer` | `Timer` | 处理器拥有 |
| `_timerHandle` | `Long` | ≥0 |
| `_monitor` | `RuntimeMonitor` | 状态保护 |

不变量：软限制 >0 且 < 硬限制；一次只配置一种基准（bytes 或 percentage）时必须能解析；
limited 状态只由检查更新；close 后不再检查/转发；拒绝/丢弃计数可读；不调用 GC。

---

## 4. 生命周期

```text
构造（解析限制）→ start（绑定下游/启动检查定时器）→ process（检查/转发/拒绝）→ close
```

- `start`：保存 downstream；执行一次检查；启动周期检查；重复 start 返回 `Ok(unit)`；
- `process`：到期检查；受限则拒绝/丢弃；否则转发；
- `checkNow`：手动检查，返回当前是否受限；
- `drain`：无缓冲，返回 `Ok(unit)`；
- `close`：停止定时器；幂等；关闭后 `process` 返回 `Unavailable`；
- 无 `stop`；管线先停止喂入，再 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `MemoryLimiterProcessor` | `String name, TelemetryKind kind, Long checkIntervalMillis, Long limitBytes, Int limitPercentage, Long spikeLimitBytes, Int spikeLimitPercentage, Bool dropWhenLimited` | name 非空；kind 非 null；interval >0；limitBytes >0 或 percentage 1..100；spike 合法且 < 硬限制 | 非法 → panic |

说明：

- `limitBytes >0` 优先于 `limitPercentage`；两者都为 0 时 panic；
- `limitPercentage` 1..100；用 `SystemInfo.snapshot().memoryTotal()` 作为基准；总内存为 0 时 panic；
- `spikeLimitBytes >0` 优先；否则 `spikeLimitPercentage` 1..100；都为 0 时默认 20%；
- 尖峰必须 < 硬限制；软限制 = 硬 − 尖峰，必须 >0；
- `dropWhenLimited` 为 true 时是显式丢弃；默认 false 表示背压；
- `name` 同一 Agent 内唯一，通常为 `"memory_limiter"`。

---

## 6. 字段表

见 §3；配置/解析后的限制为 `final`；运行状态由监视器保护。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `kind` | 遥测种类 | 无 | `TelemetryKind` | 无 |
| `name` | 处理器名 | 无 | `String` | 无 |
| `start` | 绑定下游/启动检查 | `Context context, Result<Unit, Error>(TelemetryBatch) downstream` | `Result<Unit, Error>` | `Unavailable`/`InvalidArgument`/`Cancelled` |
| `process` | 检查并转发/拒绝 | `Context context, TelemetryBatch batch` | `Result<Unit, Error>` | `Busy`/`Cancelled`/`Unavailable`/下游错误 |
| `drain` | 无缓冲 | `Context context` | `Result<Unit, Error>` | `Cancelled`/`Unavailable` |
| `close` | 停止检查 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isHealthy` | 是否健康 | 无 | `Bool` | 无 |
| `checkNow` | 手动检查 | 无 | `Bool` | 无 |
| `isLimited` | 是否受限 | 无 | `Bool` | 无 |
| `currentUsageBytes` | 当前堆使用 | 无 | `Long` | 无 |
| `hardLimitBytes` | 硬限制 | 无 | `Long` | 无 |
| `softLimitBytes` | 软限制 | 无 | `Long` | 无 |
| `refusedBatches` | 拒绝批次数 | 无 | `Int` | 无 |
| `droppedBatches` | 丢弃批次数 | 无 | `Int` | 无 |
| `droppedRecords` | 丢弃记录数 | 无 | `Int` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |

说明：

- `start` 对 null context/downstream → panic；已关闭 → `Unavailable`；重复 start → `Ok(unit)`；
- `process` 对 null context/batch → panic；kind 不匹配 → panic；未启动/关闭 → `Unavailable`；
- `process` 到期检查：`nowMono() - _lastCheckMono >= _checkIntervalMillis`；
- limited 且 `dropWhenLimited == false`：`_refusedBatches++`，返回 `Busy`；
- limited 且 `dropWhenLimited == true`：`_droppedBatches++`、`_droppedRecords += batch.recordCount()`，
  返回 `Ok(unit)`，不调用 downstream；
- 未受限：调用 downstream；下游错误原样返回；
- `checkNow` 无参数；条件竞争由监视器保护；返回 `_limited`；
- `isHealthy` 未启动/关闭/受限时为 false；正常为 true；
- `drain` 无缓冲，返回 `Ok(unit)`；关闭后 `Unavailable`；
- `close` 幂等；停止定时器；不调用 GC。

---

## 8. 使用的技术

- 软/硬限制；
- 周期内存快照；
- 背压/显式丢弃；
- 有界计数；
- 定时器；
- 幂等关闭；
- 健康降级。

---

## 9. 需要的支撑

- 语言：class、String、Int、Long、Bool、Result；
- 运行时：`memoryStats`、`SystemInfo.snapshot`、`Timer.after/every/cancel/shutdown`、
  `Context.withCancel`、`RuntimeMonitor`、`nowMono`；
- 接口：`Processor`、`TelemetryKind`、`TelemetryBatch`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Processor`、`TelemetryKind`、`TelemetryBatch`、`MemoryStats`、`memoryStats`、`SystemInfo`、`Timer`、`Duration`、
`Context`、`RuntimeMonitor`、`Error`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

- 处理器拥有 Timer、检查状态、计数；不拥有 downstream；
- `start`/`process`/`checkNow`/`close` 可并发调用；状态由监视器保护；
- `process` 调用 downstream 时不持有监视器；
- `isLimited`/计数/限制值可并发读取；
- 同一实例不跨管线共享；每条管线独立实例。

---

## 12. 示例与反例

正确：

```xnull
MemoryLimiterProcessor limiter = new MemoryLimiterProcessor(
    "memory_limiter",
    TelemetryKind.Metrics,
    1000,
    0,
    80,
    0,
    0,
    false
)
```

反例：把 memory_limiter 放在 batch 之后导致背压太晚；超过限制仍无限缓冲；默认丢弃但无计数；
在有硬限制时假设会强制 GC；用主机内存百分比但容器配额更小却不设固定值；`limitBytes` 与
`limitPercentage` 都为 0。

---

## 13. 测试/场景义务

构造校验（bytes/percentage/spike/软限制）；百分比基准；软/硬边界；limited 进入/退出；
timeout 检查；`dropWhenLimited` false/true；拒绝/丢弃计数；downstream 错误；
checkNow；drain；close 后 process；重复 start/close；并发 process；isHealthy；describe。

---

## 14. XNull 伪代码

```xnull
class MemoryLimiterProcessor implements Processor {
    final String _name
    final TelemetryKind _kind
    final Long _checkIntervalMillis
    final Long _limitBytes
    final Int _limitPercentage
    final Long _spikeLimitBytes
    final Int _spikeLimitPercentage
    final Bool _dropWhenLimited
    final Long _hostTotalBytes
    final Long _hardLimitBytes
    final Long _softLimitBytes
    final Timer _timer
    Long _timerHandle = 0
    Context? _context
    Result<Unit, Error>(TelemetryBatch)? _downstream
    Long _lastCheckMono = 0
    Bool _limited = false
    Bool _started = false
    Bool _closed = false
    Int _refusedBatches = 0
    Int _droppedBatches = 0
    Int _droppedRecords = 0
    final RuntimeMonitor _monitor

    MemoryLimiterProcessor(String name, TelemetryKind kind,
                           Long checkIntervalMillis, Long limitBytes,
                           Int limitPercentage, Long spikeLimitBytes,
                           Int spikeLimitPercentage, Bool dropWhenLimited) {
        if name == null || name == "" {
            throw "MemoryLimiterProcessor: empty name"
        }
        if kind == null { throw "MemoryLimiterProcessor: null kind" }
        if checkIntervalMillis <= 0 {
            throw "MemoryLimiterProcessor: interval <= 0"
        }
        if limitBytes < 0 || limitPercentage < 0 || limitPercentage > 100 {
            throw "MemoryLimiterProcessor: invalid limit"
        }
        if limitBytes == 0 && limitPercentage == 0 {
            throw "MemoryLimiterProcessor: no limit"
        }
        if spikeLimitBytes < 0 || spikeLimitPercentage < 0
            || spikeLimitPercentage > 100 {
            throw "MemoryLimiterProcessor: invalid spike"
        }
        Long hostTotal = SystemInfo.snapshot().memoryTotal()
        Long hard = limitBytes
        if hard == 0 {
            if hostTotal == 0 {
                throw "MemoryLimiterProcessor: no host memory"
            }
            hard = hostTotal * limitPercentage / 100
        }
        Long spike = spikeLimitBytes
        if spike == 0 && spikeLimitPercentage > 0 {
            spike = hard * spikeLimitPercentage / 100
        }
        if spike == 0 { spike = hard / 5 }
        if spike >= hard {
            throw "MemoryLimiterProcessor: spike >= hard"
        }
        _name = name
        _kind = kind
        _checkIntervalMillis = checkIntervalMillis
        _limitBytes = limitBytes
        _limitPercentage = limitPercentage
        _spikeLimitBytes = spikeLimitBytes
        _spikeLimitPercentage = spikeLimitPercentage
        _dropWhenLimited = dropWhenLimited
        _hostTotalBytes = hostTotal
        _hardLimitBytes = hard
        _softLimitBytes = hard - spike
        _timer = new Timer()
        _monitor = new RuntimeMonitor()
    }

    TelemetryKind kind() { return _kind }
    String name() { return _name }
    Bool isHealthy() { return _started && !_closed && !_limited }
    Bool isLimited() { return _limited }
    Long currentUsageBytes() { return memoryStats().heapUsed() }
    Long hardLimitBytes() { return _hardLimitBytes }
    Long softLimitBytes() { return _softLimitBytes }
    Int refusedBatches() { return _refusedBatches }
    Int droppedBatches() { return _droppedBatches }
    Int droppedRecords() { return _droppedRecords }

    Result<Unit, Error> start(Context context,
        Result<Unit, Error>(TelemetryBatch) downstream) {
        if context == null || downstream == null {
            throw "MemoryLimiterProcessor.start: null argument"
        }
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable, "closed"))
        }
        if _started {
            _monitor.exit()
            return Ok(unit)
        }
        _started = true
        _downstream = downstream
        _context = Context.withCancel(context)
        _monitor.exit()
        self.checkNow()
        Result<Long, Error> periodic = _timer.every(_context,
            Duration.ofMillis(_checkIntervalMillis),
            () -> self.checkScheduled())
        if periodic.isErr() {
            _monitor.enter()
            _started = false
            _monitor.exit()
            return Err(periodic.error())
        }
        _monitor.enter()
        _timerHandle = periodic.value()
        _monitor.exit()
        return Ok(unit)
    }

    Result<Unit, Error> process(Context context, TelemetryBatch batch) {
        if context == null { throw "MemoryLimiterProcessor.process: null context" }
        if batch == null { throw "MemoryLimiterProcessor.process: null batch" }
        if batch.kind() != _kind {
            throw "MemoryLimiterProcessor.process: kind mismatch"
        }
        _monitor.enter()
        if !_started || _closed {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable, "not running"))
        }
        _monitor.exit()
        self.checkIfDue()
        _monitor.enter()
        Bool limited = _limited
        if limited && _dropWhenLimited {
            _droppedBatches = _droppedBatches + 1
            _droppedRecords = _droppedRecords + batch.recordCount()
            _monitor.exit()
            return Ok(unit)
        }
        if limited {
            _refusedBatches = _refusedBatches + 1
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Busy, "memory limit exceeded"))
        }
        _monitor.exit()
        if _downstream == null {
            return Err(new BasicError(ErrorKind.Unavailable, "no downstream"))
        }
        return _downstream(context, batch)
    }

    Result<Unit, Error> drain(Context context) {
        if context == null { throw "MemoryLimiterProcessor.drain: null context" }
        if !_started || _closed {
            return Err(new BasicError(ErrorKind.Unavailable, "not running"))
        }
        return Ok(unit)
    }

    Result<Unit, Error> close() {
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return Ok(unit)
        }
        _closed = true
        _started = false
        if _timerHandle != 0 { _timer.cancel(_timerHandle) }
        _timerHandle = 0
        if _context != null { _context.cancel() }
        _monitor.exit()
        _timer.shutdown()
        return Ok(unit)
    }

    Bool checkNow() {
        Long usage = memoryStats().heapUsed()
        _monitor.enter()
        _lastCheckMono = nowMono()
        _limited = usage >= _softLimitBytes
        Bool limited = _limited
        _monitor.exit()
        return limited
    }

    void checkIfDue() {
        if nowMono() - _lastCheckMono >= _checkIntervalMillis {
            self.checkNow()
        }
    }

    void checkScheduled() {
        if _context == null || _context.isCancelled() { return }
        self.checkNow()
    }

    String describe() {
        return "memory_limiter " + _name
            + " hard=" + str(_hardLimitBytes)
            + " soft=" + str(_softLimitBytes)
            + " limited=" + str(_limited)
    }
}
```
