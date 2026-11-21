# `BatchProcessor`

| 项 | 值 |
| --- | --- |
| 类型 | `class BatchProcessor implements Processor` |
| 包 | `xdk.agent` |
| 稳定性 | `preview` |
| 依赖 | `Processor`、`TelemetryKind`、`TelemetryBatch`、`Timer`、`Context`、`Error` |

---

## 1. 定位

批处理器：把上游批次聚合到条数/时间阈值，按最大批次拆分，再交给下游。

它减少导出请求数与压缩开销；位于 `MemoryLimiterProcessor` 之后、采样/过滤之后（与 OTel
建议一致：先丢数据，再批处理）。

不做：采样、过滤、重试、持久化、跨资源合并、无损磁盘缓冲。

---

## 2. 设计逻辑

- 实现 `Processor`；`kind()` 由构造器固定；
- `process` 把批次加入 pending；当 pending 条数达到 `sendBatchSize` 或 `timeoutMillis == 0`
  时立即 flush；
- `timeoutMillis > 0` 时由 `Timer.every` 周期触发 flush；定时器用 start 时创建的子上下文；
- pending 有界：`maximumPendingRecords`；满时按 `overflowPolicy` 返回 `Busy`、丢最旧或丢最新；
- flush 先按资源合并同 kind 批次（`TelemetryBatch.merge`），再按 `sendBatchMaxSize` 拆分；
- `sendBatchMaxSize == 0` 表示不限制；非 0 时必须 ≥ `sendBatchSize`；
- flush 调用下游失败时，未发送的批次保留在 pending，返回错误；已发送部分可能重复（at-least-once）；
- `drain` 强制 flush 全部；`close` 停止定时器，未 flush 的 pending 丢弃并计数；
- 定时器 flush 与 `process` flush 通过 `_flushing` 互斥，避免并发 downstream；
- `isHealthy` 在关闭/未启动时为 false；pending 接近上限时可降级（实现可选，基线只按错误）。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | 非空、单行 |
| `_kind` | `TelemetryKind` | 非 null |
| `_sendBatchSize` | `Int` | >0；触发条数 |
| `_timeoutMillis` | `Long` | ≥0；0 表示立即 |
| `_sendBatchMaxSize` | `Int` | 0 或 ≥sendBatchSize |
| `_maximumPendingRecords` | `Int` | ≥sendBatchSize |
| `_overflowPolicy` | `String` | `reject`/`drop_oldest`/`drop_newest` |
| `_timer` | `Timer` | 非 null；处理器拥有 |
| `_timerHandle` | `Long` | ≥0 |
| `_context` | `Context?` | start 后子上下文 |
| `_downstream` | `Result<Unit, Error>(TelemetryBatch)?` | start 后非 null |
| `_pending` | `List<TelemetryBatch>` | 非 null；有界 |
| `_pendingRecords` | `Int` | ≥0 |
| `_started` | `Bool` | start 后 true |
| `_flushing` | `Bool` | 防止并发 flush |
| `_closed` | `Bool` | 只从 false 变 true |
| `_droppedRecords` | `Int` | ≥0 |
| `_sentBatches` | `Int` | ≥0 |
| `_monitor` | `RuntimeMonitor` | 状态/pending 保护 |

不变量：pending 记录数 ≤ maximumPendingRecords；所有 pending 批次 kind 等于 `_kind`；
`sendBatchMaxSize == 0` 或 ≥ `sendBatchSize`；flush 不并发；close 后不再 flush；
丢弃有计数；start 最多一次。

---

## 4. 生命周期

```text
构造 → start（可选定时器）→ process（多次）→ flush（阈值/定时）→ drain → close
```

- `start`：保存 downstream；timeout >0 时启动周期定时器；重复 start 返回 `Ok(unit)`；
- `process`：加入 pending；必要时 flush；下游错误原样返回；
- `drain`：flush 全部；可重复；取消返回 `Cancelled`；
- `close`：取消定时器；丢弃 pending 并计数；幂等；关闭后 `process`/`drain` 返回 `Unavailable`；
- 无 `stop`；管线停止喂入后调用 `drain`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `BatchProcessor` | `String name, TelemetryKind kind, Int sendBatchSize, Long timeoutMillis, Int sendBatchMaxSize, Int maximumPendingRecords, String overflowPolicy` | name 非空；kind 非 null；sendBatchSize >0；timeout ≥0；maxSize 为 0 或 ≥sendBatchSize；maxPending ≥sendBatchSize；policy 合法 | 非法 → panic |

说明：

- `sendBatchSize` 是触发阈值，不强制单批大小；单批大小由 `sendBatchMaxSize` 控制；
- `timeoutMillis == 0` 时忽略定时器，每次 process 立即 flush；
- `maximumPendingRecords` 是硬上限；达到上限时按策略处理；
- `overflowPolicy` 固定三种；大小写敏感；
- `name` 同一 Agent 内唯一，通常为 `"batch"`。

---

## 6. 字段表

见 §3；配置字段为 `final`；pending/状态由监视器保护。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `kind` | 遥测种类 | 无 | `TelemetryKind` | 无 |
| `name` | 处理器名 | 无 | `String` | 无 |
| `start` | 绑定下游/启动定时器 | `Context context, Result<Unit, Error>(TelemetryBatch) downstream` | `Result<Unit, Error>` | `Unavailable`/`InvalidArgument`/`Cancelled` |
| `process` | 加入批次 | `Context context, TelemetryBatch batch` | `Result<Unit, Error>` | `Busy`/`Cancelled`/`Unavailable`/下游错误 |
| `drain` | 强制 flush | `Context context` | `Result<Unit, Error>` | `Busy`/`Cancelled`/`Unavailable`/下游错误 |
| `close` | 停止/丢弃 pending | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isHealthy` | 是否健康 | 无 | `Bool` | 无 |
| `pendingRecords` | pending 条数 | 无 | `Int` | 无 |
| `droppedRecords` | 丢弃条数 | 无 | `Int` | 无 |
| `sentBatches` | 已发送批次数 | 无 | `Int` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |

说明：

- `start` 对 null context/downstream → panic；已关闭 → `Unavailable`；重复 start → `Ok(unit)`；
- `process` 对 null context/batch → panic；kind 不匹配 → panic；未启动/关闭 → `Unavailable`；
- process 加入后 pending 超过上限：`reject` 返回 `Busy`（不加入）；`drop_oldest` 移除最旧；
  `drop_newest` 丢弃新批次；丢弃记录数累加；
- 达到 `sendBatchSize` 或 timeout==0 时 flush；flush 错误时返回错误，未发送 pending 保留；
- `drain` 对 null context → panic；未启动/关闭 → `Unavailable`；flush 全部；取消返回 `Cancelled`；
- `close` 幂等；已关闭返回 `Ok(unit)`；丢弃 pending 并累加 `_droppedRecords`；
- `isHealthy` 未启动/关闭为 false；运行中且最近 flush 无错误为 true；
- `pendingRecords`/`droppedRecords`/`sentBatches` 可并发读取。

---

## 8. 使用的技术

- 有界 pending 列表；
- 条数/时间双阈值；
- 同资源合并；
- 最大批次拆分；
- 定时器；
- 并发 flush 互斥；
- at-least-once；
- 显式丢弃计数。

---

## 9. 需要的支撑

- 语言：class、String、Int、Long、Bool、List、Result；
- 运行时：`Timer.after/every/cancel/shutdown`、`Context.withCancel`、`RuntimeMonitor`、`nowMono`；
- 接口：`TelemetryKind`、`TelemetryBatch`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Processor`、`TelemetryKind`、`TelemetryBatch`、`Timer`、`Duration`、`Context`、`RuntimeMonitor`、
`Error`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

- 处理器拥有 Timer、pending 列表、定时器句柄；不拥有 downstream；
- `process`/`drain`/`close` 可并发调用；pending 与状态由监视器保护；
- 同一时刻最多一个 flush（`_flushing`）；flush 调用 downstream 时不持有监视器；
- `pendingRecords`/计数/健康可并发读取；
- 同一实例不跨管线共享；每条管线独立实例，符合 OTel processor 实例语义。

---

## 12. 示例与反例

正确：

```xnull
BatchProcessor processor = new BatchProcessor(
    "batch", TelemetryKind.Metrics, 8192, 200, 16384, 32768, "reject")
Result<Unit, Error> started = processor.start(context, downstream)
if started.isErr() { return started }
Result<Unit, Error> processed = processor.process(context, batch)
if processed.isErr() { return processed }
```

反例：无界 pending；定时器与 process 并发 flush 导致下游并发；flush 失败却清空 pending；
`sendBatchMaxSize` 小于 `sendBatchSize`；timeout=0 仍启动定时器；close 不计数丢弃；
pending 跨资源合并失败却强行拼接。

---

## 13. 测试/场景义务

构造校验（阈值/上限/策略）；条数触发/时间触发/timeout=0；最大批次拆分；同资源合并/不同资源不合并；
pending 上限三种策略/计数；flush 失败保留未发送；drain 全部/取消；close 丢弃计数；
重复 start/close；未启动 process/drain；并发 process/flush；kind 不匹配；计数/健康；describe。

---

## 14. XNull 伪代码

```xnull
class BatchProcessor implements Processor {
    final String _name
    final TelemetryKind _kind
    final Int _sendBatchSize
    final Long _timeoutMillis
    final Int _sendBatchMaxSize
    final Int _maximumPendingRecords
    final String _overflowPolicy
    final Timer _timer
    Long _timerHandle = 0
    Context? _context
    Result<Unit, Error>(TelemetryBatch)? _downstream
    List<TelemetryBatch> _pending = []
    Int _pendingRecords = 0
    Bool _started = false
    Bool _flushing = false
    Bool _closed = false
    Bool _healthy = false
    Int _droppedRecords = 0
    Int _sentBatches = 0
    final RuntimeMonitor _monitor

    BatchProcessor(String name, TelemetryKind kind, Int sendBatchSize,
                   Long timeoutMillis, Int sendBatchMaxSize,
                   Int maximumPendingRecords, String overflowPolicy) {
        if name == null || name == "" {
            throw "BatchProcessor: empty name"
        }
        if kind == null { throw "BatchProcessor: null kind" }
        if sendBatchSize <= 0 {
            throw "BatchProcessor: sendBatchSize <= 0"
        }
        if timeoutMillis < 0 {
            throw "BatchProcessor: negative timeout"
        }
        if sendBatchMaxSize != 0 && sendBatchMaxSize < sendBatchSize {
            throw "BatchProcessor: sendBatchMaxSize < sendBatchSize"
        }
        if maximumPendingRecords < sendBatchSize {
            throw "BatchProcessor: maxPending < sendBatchSize"
        }
        if overflowPolicy != "reject" && overflowPolicy != "drop_oldest"
            && overflowPolicy != "drop_newest" {
            throw "BatchProcessor: invalid overflow policy"
        }
        _name = name
        _kind = kind
        _sendBatchSize = sendBatchSize
        _timeoutMillis = timeoutMillis
        _sendBatchMaxSize = sendBatchMaxSize
        _maximumPendingRecords = maximumPendingRecords
        _overflowPolicy = overflowPolicy
        _timer = new Timer()
        _monitor = new RuntimeMonitor()
    }

    TelemetryKind kind() { return _kind }
    String name() { return _name }
    Int pendingRecords() { return _pendingRecords }
    Int droppedRecords() { return _droppedRecords }
    Int sentBatches() { return _sentBatches }
    Bool isHealthy() { return _started && !_closed && _healthy }

    Result<Unit, Error> start(Context context,
        Result<Unit, Error>(TelemetryBatch) downstream) {
        if context == null || downstream == null {
            throw "BatchProcessor.start: null argument"
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
        _healthy = true
        _downstream = downstream
        _context = Context.withCancel(context)
        _monitor.exit()
        if _timeoutMillis > 0 {
            Result<Long, Error> periodic = _timer.every(_context,
                Duration.ofMillis(_timeoutMillis),
                () -> self.flushTick())
            if periodic.isErr() {
                _monitor.enter()
                _started = false
                _monitor.exit()
                return Err(periodic.error())
            }
            _monitor.enter()
            _timerHandle = periodic.value()
            _monitor.exit()
        }
        return Ok(unit)
    }

    Result<Unit, Error> process(Context context, TelemetryBatch batch) {
        if context == null { throw "BatchProcessor.process: null context" }
        if batch == null { throw "BatchProcessor.process: null batch" }
        if batch.kind() != _kind {
            throw "BatchProcessor.process: batch kind mismatch"
        }
        _monitor.enter()
        if !_started || _closed {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable,
                "not running"))
        }
        if _pendingRecords + batch.recordCount() > _maximumPendingRecords {
            if _overflowPolicy == "reject" {
                _monitor.exit()
                return Err(new BasicError(ErrorKind.Busy, "batch pending full"))
            }
            if _overflowPolicy == "drop_newest" {
                _droppedRecords = _droppedRecords + batch.recordCount()
                _monitor.exit()
                return Ok(unit)
            }
            TelemetryBatch oldest = _pending.get(0)
            _pending.removeAt(0)
            _pendingRecords = _pendingRecords - oldest.recordCount()
            _droppedRecords = _droppedRecords + oldest.recordCount()
        }
        _pending.push(batch)
        _pendingRecords = _pendingRecords + batch.recordCount()
        Bool shouldFlush = _pendingRecords >= _sendBatchSize
            || _timeoutMillis == 0
        _monitor.exit()
        if shouldFlush { return self.flush(context) }
        return Ok(unit)
    }

    Result<Unit, Error> drain(Context context) {
        if context == null { throw "BatchProcessor.drain: null context" }
        _monitor.enter()
        if !_started || _closed {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable,
                "not running"))
        }
        _monitor.exit()
        return self.flush(context)
    }

    void flushTick() {
        self.flushScheduled()
    }

    Result<Unit, Error> flushScheduled() {
        Context context = _context
        if context == null { return Ok(unit) }
        if context.isCancelled() { return Ok(unit) }
        return self.flush(context)
    }

    Result<Unit, Error> flush(Context context) {
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable, "closed"))
        }
        if _flushing {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Busy, "already flushing"))
        }
        if _downstream == null {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable, "no downstream"))
        }
        _flushing = true
        List<TelemetryBatch> batches = self.mergePending()
        _pending = []
        _pendingRecords = 0
        _monitor.exit()
        Int index = 0
        Result<Unit, Error> first = Ok(unit)
        while index < batches.length() {
            List<TelemetryBatch> parts = []
            if batches.get(index).recordCount() == 0 {
                parts.push(batches.get(index))
            } else {
                parts = batches.get(index).split(
                    self.maximumRecordsPerBatch(batches.get(index)))
            }
            Int partIndex = 0
            while partIndex < parts.length() {
                Result<Unit, Error> exported =
                    _downstream(context, parts.get(partIndex))
                if exported.isErr() {
                    if first.isOk() { first = exported }
                    break
                }
                _monitor.enter()
                _sentBatches = _sentBatches + 1
                _monitor.exit()
                partIndex = partIndex + 1
            }
            if first.isErr() {
                _monitor.enter()
                Int restore = index
                while restore < batches.length() {
                    _pending.push(batches.get(restore))
                    _pendingRecords = _pendingRecords
                        + batches.get(restore).recordCount()
                    restore = restore + 1
                }
                _flushing = false
                _healthy = false
                _monitor.exit()
                return first
            }
            index = index + 1
        }
        _monitor.enter()
        _flushing = false
        _healthy = true
        _monitor.exit()
        return Ok(unit)
    }

    List<TelemetryBatch> mergePending() {
        List<TelemetryBatch> merged = []
        Int index = 0
        while index < _pending.length() {
            TelemetryBatch batch = _pending.get(index)
            Bool placed = false
            Int scan = 0
            while scan < merged.length() {
                Result<TelemetryBatch, Error> combined =
                    merged.get(scan).merge(batch)
                if combined.isOk() {
                    merged.set(scan, combined.value())
                    placed = true
                    break
                }
                scan = scan + 1
            }
            if !placed { merged.push(batch) }
            index = index + 1
        }
        return merged
    }

    Int maximumRecordsPerBatch(TelemetryBatch batch) {
        if _sendBatchMaxSize == 0 { return batch.recordCount() }
        return _sendBatchMaxSize
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
        Int index = 0
        while index < _pending.length() {
            _droppedRecords = _droppedRecords + _pending.get(index).recordCount()
            index = index + 1
        }
        _pending = []
        _pendingRecords = 0
        _monitor.exit()
        _timer.shutdown()
        return Ok(unit)
    }

    String describe() {
        return "batch " + _name + " pending=" + str(_pendingRecords)
            + " sent=" + str(_sentBatches)
            + " dropped=" + str(_droppedRecords)
    }
}
```
