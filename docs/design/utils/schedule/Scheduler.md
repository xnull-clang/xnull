# `Scheduler`

| 项 | 值 |
| --- | --- |
| 类型 | `class Scheduler` |
| 包 | `xdk.schedule` |
| 稳定性 | `preview` |
| 依赖 | `SchedulerOptions`、`Job`、`Schedule`、`JobHandle`、`Context`、`Error` |

---

## 1. 定位

调度器：创建、注册 Job/Schedule、取消、手动触发、列出作业、关闭。

不做：分布式调度、持久化、集群选主、动态改期、作业结果值。

---

## 2. 设计逻辑

- 包装运行时 `SchedulerRaw`；选项构造时复制。
- `schedule` 检查关闭/最大作业数，创建 JobHandle 并登记。
- 同一 Job 默认串行；worker 数量控制跨 Job 并发。
- `cancel` 移除活动登记并取消句柄；已取消返回 false。
- `trigger` 只入队一次立即运行，不改变 schedule。
- `shutdown` 停止接收、取消待执行、等待运行中；超时返回 `Timeout`。
- 关闭幂等；关闭后 schedule/trigger 返回 `Unavailable`。
- 无 close；使用 shutdown 结束。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_engine` | `SchedulerRaw` | 运行时引擎 |
| `_options` | `SchedulerOptions` | 选项副本 |
| `_monitor` | `RuntimeMonitor` | 登记保护 |
| `_jobs` | `Map<String,JobHandle>` | 活动句柄 |
| `_rawHandles` | `Map<String,JobHandleRaw>` | 运行时句柄 |
| `_closed` | `Bool` | 是否关闭 |

不变量：jobs 与 rawHandles 键一致；jobs.length ≤ maxPending；closed 后不再接收；句柄 id 唯一。

---

## 4. 生命周期

`create` 创建；`shutdown` 结束；shutdown 幂等；无资源句柄。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Scheduler(SchedulerRaw, SchedulerOptions)` | 内部 | 非 null | 私有；null → panic |

应用使用 `create`。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `create` | 创建 | `SchedulerOptions options` | `Result<Scheduler, Error>` | `Unavailable`/参数 |
| `schedule` | 注册作业 | `Job job, Schedule schedule` | `Result<JobHandle, Error>` | `Busy`/`Unavailable` |
| `cancel` | 取消 | `JobHandle handle` | `Bool` | null → panic |
| `trigger` | 立即触发 | `JobHandle handle` | `Result<Unit, Error>` | `NotFound`/`Unavailable` |
| `jobs` | 活动作业 | 无 | `List<JobHandle>` | 无 |
| `shutdown` | 关闭 | `Context context` | `Result<Unit, Error>` | `Timeout`/`Cancelled` |
| `isShutdown` | 是否关闭 | 无 | `Bool` | 无 |
| `options` | 选项副本 | 无 | `SchedulerOptions` | 无 |

说明：

- `schedule` 在监视器内调用 engine；engine 必须快速返回，不得同步执行 Job。
- `trigger` 只保证入队，不等待 Job 完成。
- `cancel` 对未知/已完成句柄返回 false。
- `shutdown` 超时后引擎可能仍有运行中 Job；返回 `Timeout`，调用方决定是否继续等待。
- `jobs` 返回快照，不包含已取消/已完成移除的作业。

---

## 8. 使用的技术

- 运行时调度引擎；
- 作业登记；
- 监视器同步；
- 取消/关闭；
- misfire 由引擎按 options 处理。

---

## 9. 需要的支撑

- 语言：class、Map、List、String、Bool、Result、Unit；
- 运行时：`SchedulerRaw`、`JobHandleRaw`、`schedulerCreateRaw`、`schedulerScheduleRaw`、`schedulerTriggerRaw`、`schedulerShutdownRaw`、`RuntimeMonitor`；
- 接口：`SchedulerOptions`、`Job`、`Schedule`、`JobHandle`、`Context`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`SchedulerOptions`、`Job`、`Schedule`、`JobHandle`、`Context`、`Error`、调度运行时原语。

---

## 11. 所有权与并发

引用语义；线程安全；可跨任务共享；shutdown 与 schedule 并发安全；无资源。

---

## 12. 示例与反例

正确：`Scheduler.create(opts)`；`schedule(job, Schedule.cron("0 3 * * *"))`；`shutdown(ctx)`。  
反例：关闭后 schedule；在 Job 内 shutdown 自身等待死锁；把 trigger 当同步执行；忽略 shutdown Timeout。

---

## 13. 测试/场景义务

create 成功/失败；schedule 正常/上限/关闭；cancel；trigger；jobs；shutdown 正常/超时/取消/幂等；同 Job 不重叠；misfire 三策略；cron 时区；多 worker。

---

## 14. XNull 伪代码

```xnull
class Scheduler {
    final SchedulerRaw _engine
    final SchedulerOptions _options
    final RuntimeMonitor _monitor
    final Map<String, JobHandle> _jobs
    final Map<String, JobHandleRaw> _rawHandles
    Bool _closed = false

    private Scheduler(SchedulerRaw engine, SchedulerOptions options) {
        if engine == null || options == null {
            throw "Scheduler: null argument"
        }
        _engine = engine
        _options = options
        _monitor = new RuntimeMonitor()
        _jobs = new Map<String, JobHandle>()
        _rawHandles = new Map<String, JobHandleRaw>()
    }

    static Result<Scheduler, Error> create(SchedulerOptions options) {
        if options == null { throw "Scheduler.create: null options" }
        SchedulerOptions copied = options.copy()
        Result<SchedulerRaw, Error> engine = schedulerCreateRaw(copied)
        if engine.isErr() { return Err(engine.error()) }
        return Ok(new Scheduler(engine.value(), copied))
    }

    Result<JobHandle, Error> schedule(Job job, Schedule schedule) {
        if job == null || schedule == null {
            throw "Scheduler.schedule: null argument"
        }
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable, "scheduler is closed"))
        }
        if _jobs.length() >= _options.getMaxPending() {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Busy, "too many scheduled jobs"))
        }
        Result<JobHandleRaw, Error> created = schedulerScheduleRaw(_engine, job, schedule, _options)
        if created.isErr() {
            _monitor.exit()
            return Err(created.error())
        }
        JobHandleRaw raw = created.value()
        JobHandle handle = new JobHandle(raw, raw.id(), job.name(), schedule)
        _jobs.put(handle.id(), handle)
        _rawHandles.put(handle.id(), raw)
        _monitor.exit()
        return Ok(handle)
    }

    Bool cancel(JobHandle handle) {
        if handle == null { throw "Scheduler.cancel: null handle" }
        _monitor.enter()
        if !_jobs.has(handle.id()) {
            _monitor.exit()
            return false
        }
        Bool cancelled = handle.cancel()
        if cancelled {
            _jobs.remove(handle.id())
            _rawHandles.remove(handle.id())
        }
        _monitor.exit()
        return cancelled
    }

    Result<Unit, Error> trigger(JobHandle handle) {
        if handle == null { throw "Scheduler.trigger: null handle" }
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable, "scheduler is closed"))
        }
        if !_rawHandles.has(handle.id()) {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.NotFound, "job is not active"))
        }
        JobHandleRaw raw = _rawHandles.get(handle.id())
        Result<Unit, Error> result = schedulerTriggerRaw(_engine, raw, _options)
        _monitor.exit()
        return result
    }

    List<JobHandle> jobs() {
        _monitor.enter()
        List<JobHandle> values = _jobs.values()
        List<JobHandle> result = []
        Int index = 0
        while index < values.length() {
            result.push(values.get(index))
            index = index + 1
        }
        _monitor.exit()
        return result
    }

    Result<Unit, Error> shutdown(Context context) {
        if context == null { throw "Scheduler.shutdown: null context" }
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return Ok(unit)
        }
        _closed = true
        _monitor.exit()
        Result<Unit, Error> result = schedulerShutdownRaw(_engine, context,
            _options.getShutdownTimeoutMillis())
        _monitor.enter()
        _jobs.clear()
        _rawHandles.clear()
        _monitor.exit()
        return result
    }

    Bool isShutdown() {
        _monitor.enter()
        Bool result = _closed
        _monitor.exit()
        return result
    }

    SchedulerOptions options() { return _options.copy() }
}
```

> `SchedulerRaw`、`JobHandleRaw` 与 `scheduler*Raw` 是运行时调度原语；不是 XDK 公共类型。
