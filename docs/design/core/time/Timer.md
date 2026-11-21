# `Timer`

| 项 | 值 |
| --- | --- |
| 类型 | `class Timer` |
| 包 | `xdk.time` |
| 稳定性 | `preview`（X） |
| 依赖 | `Duration`、`tasks.Context`、`errors` |

---

## 1. 定位

延迟/周期任务定时器；返回可取消的句柄。

不做：cron、日历调度、实时保证、任务持久化。

---

## 2. 设计逻辑

- `after` 延迟一次；`every` 周期执行。
- 句柄是 `Long`，由 Timer 内部表管理；`cancel` 幂等。
- `every` 不保证不重叠；应用可选择跳过/串行。
- `shutdown` 取消全部并停止接收新任务。
- 需要执行层调度支撑； 标 X。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_nextHandle` | `Long` | 下一个句柄 |
| `_jobs` | `Map<Long, TimerJob>` | 内部任务表 |
| `_shutdown` | `Bool` | 是否停止 |

不变量：handle 唯一；shutdown 后不再接受。

---

## 4. 生命周期

构造后使用；`shutdown` 后可 close；无 OS 资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Timer()` | 无 | 空 | 无 |

---

## 6. 字段表

见 §3；字段私有；`TimerJob` 是内部类型。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `after` | 延迟一次 | `Context context, Duration delay, void() callback` | `Result<Long, Error>` | 已 shutdown/取消 |
| `every` | 周期 | `Context context, Duration period, void() callback` | `Result<Long, Error>` | 已 shutdown/取消 |
| `cancel` | 取消 | `Long handle` | `Bool` | 无 |
| `shutdown` | 停止全部 | 无 | `void` | 无 |
| `isShutdown` | 是否停止 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 延迟队列/调度器；
- 句柄表；
- 取消；
- 周期任务。

---

## 9. 需要的支撑

- 语言：class、Long、Bool、void 函数；
- 运行时/执行层：定时调度、Context；
- 接口：`Duration`、`Context`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Duration`、`Context`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

Timer 持有任务表；非线程安全由实现声明；`shutdown` 取消全部。

---

## 12. 示例与反例

正确：`timer.after(ctx, Duration.ofSeconds(1), callback)`；`cancel(handle)`。  
反例：期望周期任务严格不漂移；shutdown 后继续 after；回调重入 Timer 修改表。

---

## 13. 测试/场景义务

after 一次；every 周期；cancel 幂等；shutdown 后拒绝；Context 取消；回调异常隔离。

---

## 14. XNull 伪代码

```xnull
class Timer {
    Long _nextHandle
    Map<Long, TimerJob> _jobs
    Bool _shutdown

    Timer() {
        _nextHandle = 1
        _jobs = new Map<Long, TimerJob>()
        _shutdown = false
    }

    Result<Long, Error> after(Context context, Duration delay, void() callback) {
        if _shutdown {
            return Err(new BasicError(ErrorKind.Unavailable, "timer shutdown"))
        }
        if context == null || delay == null || callback == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "null timer argument"))
        }
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "cancelled"))
        }
        Long handle = _nextHandle
        _nextHandle = _nextHandle + 1
        TimerJob job = new TimerJob(handle, delay.millis(), false, callback)
        _jobs.put(handle, job)
        scheduleOnce(job)
        return Ok(handle)
    }

    Result<Long, Error> every(Context context, Duration period, void() callback) {
        if _shutdown {
            return Err(new BasicError(ErrorKind.Unavailable, "timer shutdown"))
        }
        if context == null || period == null || callback == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "null timer argument"))
        }
        if period.millis() <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "non-positive period"))
        }
        Long handle = _nextHandle
        _nextHandle = _nextHandle + 1
        TimerJob job = new TimerJob(handle, period.millis(), true, callback)
        _jobs.put(handle, job)
        schedulePeriodic(job)
        return Ok(handle)
    }

    Bool cancel(Long handle) {
        if !_jobs.has(handle) {
            return false
        }
        _jobs.remove(handle)
        cancelScheduled(handle)
        return true
    }

    void shutdown() {
        _shutdown = true
        List<Long> handles = _jobs.keys()
        Int index = 0
        while index < handles.length() {
            self.cancel(handles.get(index))
            index = index + 1
        }
    }

    Bool isShutdown() { return _shutdown }
}
```

> `TimerJob`、`scheduleOnce/schedulePeriodic/cancelScheduled` 是执行层内部支撑，不属于 XDK 公共类型。
