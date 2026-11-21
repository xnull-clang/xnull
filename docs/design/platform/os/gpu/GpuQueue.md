# `GpuQueue`

| 项 | 值 |
| --- | --- |
| 类型 | `class GpuQueue` |
| 包 | `xdk.os.gpu` |
| 稳定性 | `preview` |
| 依赖 | `GpuQueueKind`、`Error` |

---

## 1. 定位

已创建的 GPU 队列不透明句柄：队列 ID、用途、关闭、是否可用。

不做：命令提交、同步/栅栏、优先级/抢占、内存分配、命令缓冲。队列只表示一个已创建的生命周期句柄，真正的提交/同步属于 X。

---

## 2. 设计逻辑

- 由 `GpuDevice.createQueue(context, kind)` 创建；构造器主要供宿主/测试使用。
- `_queueId` 是 `Long` 不透明句柄；不暴露后端队列指针/队列族索引。
- kind 在创建时固定；同一队列不能改变用途。
- close 幂等；关闭后 `id`/`kind` 仍可读，`isOpen` 为 false。
- 设备持有已创建队列的引用；`GpuDevice.close()` 会先关闭所有队列，再关闭设备。
- 队列可以独立 `close()`；设备 close 后队列已关闭，再次 `close()` 返回 `Ok(unit)`。
- 不提供提交/同步；队列关闭失败只作为诊断返回 `Io`。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_queueId` | `Long` | final | >0；不透明句柄 |
| `_kind` | `GpuQueueKind` | final | 非 null；创建后不变 |
| `_open` | `Bool` | 内部 | 是否可用 |

不变量：queueId>0；kind 非 null；构造后 open=true；close 后 open=false；close 幂等；关闭后不再调用原生队列原语。

---

## 4. 生命周期

由 `GpuDevice.createQueue` 创建；调用方可以独立 `close()`；设备 close 也会关闭队列；close 幂等；无 `deinit` 依赖。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `GpuQueue(Long queueId, GpuQueueKind kind)` | queueId、kind | queueId>0；kind 非 null | 非法 → panic |

构造器主要供宿主/测试使用；业务代码通过 `GpuDevice.createQueue(context, kind)` 获取。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `id` | 队列 ID | 无 | `Long` | 无 |
| `kind` | 队列用途 | 无 | `GpuQueueKind` | 无 |
| `close` | 关闭队列 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 |

说明：

- `id`/`kind` 是纯读取；关闭后仍返回原值。
- `close` 第一次调用标记关闭并调用 `gpuQueueCloseRaw`；后续调用返回 `Ok(unit)`，不再触碰原生句柄。
- 设备 close 会调用队列的 `close`；因此设备 close 后 `isOpen()` 为 false。
- 不提供 `describe`/`equals`/`copy`；队列是资源，不是值对象。

---

## 8. 使用的技术

- 不透明 `Long` 句柄；
- 状态标记；
- 幂等关闭；
- 原生队列原语错误映射。

---

## 9. 需要的支撑

- 语言：class、final 字段、Long、Bool、Result；
- 运行时/适配器：`gpuQueueCloseRaw(Long queueId) -> Result<Unit, Error>`；
- 接口：`GpuQueueKind`、`GpuDevice`、`Error`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`GpuQueueKind`、`GpuDevice`、`GpuBackend`、`Error`、`ErrorKind`。

---

## 11. 所有权与并发

引用语义；队列由 `GpuDevice` 持有并在设备 close 时关闭；调用方也可以提前 close。队列不反向持有设备。
不可跨任务并发使用；`close` 与其它队列操作不得并发。`close` 幂等指重复调用安全，不承诺并发 close 安全。无 `equals`/`copy`；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：`GpuQueue queue = device.createQueue(context, GpuQueueKind.Compute)`；用完 `queue.close()`；设备 close 后不再使用队列。  
反例：试图在队列上提交命令；close 后继续使用；假设队列在设备 close 后仍可用；假设 kind 可变；把 queueId 当跨进程持久 ID；close 后重试原生关闭。

---

## 13. 测试/场景义务

构造非法 queueId/kind panic；三种 kind 创建；close 幂等；close 后 `isOpen` false；
设备 close 关闭全部队列；队列先 close 再设备 close；设备 close 后队列 close 返回 `Ok(unit)`；
不支持的 kind；close 失败只诊断；关闭后不调用原生原语。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class GpuQueue {
    final Long _queueId
    final GpuQueueKind _kind
    Bool _open

    GpuQueue(Long queueId, GpuQueueKind kind) {
        if queueId <= 0 || kind == null {
            throw "GpuQueue: invalid field"
        }
        _queueId = queueId
        _kind = kind
        _open = true
    }

    Long id() { return _queueId }
    GpuQueueKind kind() { return _kind }
    Bool isOpen() { return _open }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        return gpuQueueCloseRaw(_queueId)
    }
}
```
