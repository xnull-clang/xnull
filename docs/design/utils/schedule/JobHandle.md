# `JobHandle`

| 项 | 值 |
| --- | --- |
| 类型 | `class JobHandle` |
| 包 | `xdk.schedule` |
| 稳定性 | `preview` |
| 依赖 | `Schedule`、`Error`、`JobHandleRaw` |

---

## 1. 定位

已调度作业的句柄：id/name/schedule、取消、状态、下次/上次运行、最后错误。

不做：执行、修改调度、持久化、结果值。

---

## 2. 设计逻辑

- 句柄包装运行时 `JobHandleRaw`；状态由调度器更新。
- `cancel` 幂等；取消后 `isCancelled=true`。
- `isDone` 表示作业不再有未来运行（一次性完成/取消/关闭）。
- `nextRunMillis`/`lastRunMillis` 为 epoch 毫秒；0 表示无。
- `lastError` 为最近一次 `Err`，成功不自动清除？ 成功清除；文档明确。
- 线程安全由 raw 句柄保证；无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_handle` | `JobHandleRaw` | 运行时句柄 |
| `_id` | `String` | 稳定 id |
| `_name` | `String` | 作业名 |
| `_schedule` | `Schedule` | 调度规格 |

不变量：字段非 null；id/name 非空；schedule 不可变。

---

## 4. 生命周期

`Scheduler.schedule` 创建；`cancel`/完成/关闭后仍可查询；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `JobHandle(JobHandleRaw, String jobId, String name, Schedule)` | 内部 | 非 null | 私有；null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `id` | 作业 id | 无 | `String` | 无 |
| `name` | 作业名 | 无 | `String` | 无 |
| `schedule` | 调度规格 | 无 | `Schedule` | 无 |
| `cancel` | 取消 | 无 | `Bool` | 无 |
| `isCancelled` | 是否取消 | 无 | `Bool` | 无 |
| `isDone` | 是否结束 | 无 | `Bool` | 无 |
| `nextRunMillis` | 下次运行 | 无 | `Long` | 无 |
| `lastRunMillis` | 上次运行 | 无 | `Long` | 无 |
| `lastError` | 最后错误/无 | 无 | `Error?` | 无 |

说明：

- `cancel` 返回 false 表示已取消/已完成。
- 成功运行会清除 `lastError`；失败保留最近错误。
- `nextRunMillis` 在无未来运行时为 0。

---

## 8. 使用的技术

- 运行时段句柄；
- 状态查询；
- 取消；
- 不可变元数据。

---

## 9. 需要的支撑

- 语言：class、String、Long、Bool、可空；
- 运行时：`JobHandleRaw`；
- 接口：`Schedule`、`Error`。

---

## 10. 依赖的特性/接口/类

`Schedule`、`Error`、`JobHandleRaw`。

---

## 11. 所有权与并发

引用语义；线程安全由 raw 保证；可跨任务查询；无资源。

---

## 12. 示例与反例

正确：`handle.cancel()`；`handle.nextRunMillis()`。  
反例：取消后期望 lastError 清空；重复 cancel 期望 true；把 handle 当结果容器。

---

## 13. 测试/场景义务

取消/重复取消；完成；next/last；lastError 成功清除/失败保留；id/name/schedule；并发查询。

---

## 14. XNull 伪代码

```xnull
class JobHandle {
    final JobHandleRaw _handle
    final String _id
    final String _name
    final Schedule _schedule

    JobHandle(JobHandleRaw handle, String jobId, String name, Schedule schedule) {
        if handle == null || jobId == null || name == null || schedule == null {
            throw "JobHandle: null argument"
        }
        if jobId == "" || name == "" { throw "JobHandle: empty id/name" }
        _handle = handle
        _id = jobId
        _name = name
        _schedule = schedule
    }

    String id() { return _id }
    String name() { return _name }
    Schedule schedule() { return _schedule }
    Bool cancel() { return jobHandleCancelRaw(_handle) }
    Bool isCancelled() { return jobHandleIsCancelledRaw(_handle) }
    Bool isDone() { return jobHandleIsDoneRaw(_handle) }
    Long nextRunMillis() { return jobHandleNextRunRaw(_handle) }
    Long lastRunMillis() { return jobHandleLastRunRaw(_handle) }
    Error? lastError() { return jobHandleLastErrorRaw(_handle) }
}
```

> `JobHandleRaw` 与 `jobHandle*Raw` 是运行时调度原语；不是 XDK 公共类型。
