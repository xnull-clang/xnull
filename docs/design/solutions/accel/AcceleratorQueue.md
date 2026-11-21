# `AcceleratorQueue`

| 项 | 值 |
| --- | --- |
| 类型 | `class AcceleratorQueue` |
| 包 | `xdk.accel` |
| 稳定性 | `preview` |
| 依赖 | `Error` |

---

## 1. 定位

已创建的加速器队列不透明句柄：队列句柄、创建时优先级提示、关闭、是否可用。

只表示一个有序提交目标的生命周期；真正的命令录制与提交在 [`AcceleratorCommandBuffer`](AcceleratorCommandBuffer.md)，完成同步在 [`AcceleratorFence`](AcceleratorFence.md)。

不做：

- 命令提交/同步/栅栏；
- 调度、抢占、负载均衡、亲和性；
- 队列族/队列类型/传输队列；
- 多队列协同/跨队列屏障；
- 队列数量策略/单例假设；
- 设备发现/打开。

---

## 2. 设计逻辑

- 由 [`AcceleratorDevice.createQueue`](AcceleratorDevice.md) 创建；构造器主要供宿主/测试使用。
- `_handle` 是 `Long` 不透明句柄；不暴露后端队列指针、队列族索引或驱动句柄。
- 队列是**有序**提交目标：同一队列上的提交按提交顺序执行；跨队列不保证顺序，需要 fence 显式同步。
- 基线没有队列类型枚举：所有队列接受计算命令缓冲；没有独立传输队列、图形队列或显示队列。
- 一个设备可创建多个队列，是否支持由后端决定；不支持时 `createQueue` 返回 `Unsupported`。NPU/DSP/MCU 常见单队列。
- `_priority` 是创建时的提示（-100..100），不是调度合同；后端不支持非零优先级时必须在创建时返回 `Unsupported`，不能静默按 0 处理。
- 队列 kind 不可变；没有“提升优先级”“改变用途”的入口。
- 队列由设备持有；设备 `close()` 先关闭所有队列；队列也可独立 `close()`；关闭幂等。
- 队列不拥有命令缓冲、内核、程序、内存或 fence。
- 关闭后纯元数据（句柄、优先级、isOpen）仍可读；提交返回 `Unavailable`。
- 无 `equals`/`copy`/`describe`；队列是资源，不是值对象。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_handle` | `Long` | final | >0；不透明句柄 |
| `_priority` | `Int` | final | -100..100；创建后固定 |
| `_open` | `Bool` | 内部 | 构造后 true；close 后 false |

不变量：

- `handle > 0`；`priority` 在 -100..100。
- 队列只属于创建它的设备；不跨设备使用。
- 队列按提交顺序执行；不承诺跨队列顺序。
- 构造后 `open = true`；`close()` 后 `open = false`；close 幂等。
- 关闭后不再调用任何原生队列原语。
- 队列不持有命令缓冲/内核/程序/内存/fence 的强引用。
- 设备关闭会关闭全部队列；队列关闭不关闭设备。

---

## 4. 生命周期

由 `AcceleratorDevice.createQueue` 创建；调用方可以独立 `close()`；设备 close 也会关闭队列；close 幂等；无 `deinit` 依赖。

顺序：

- 设备创建 → 队列创建 → 命令缓冲创建 → 录制/提交 → 等 fence → 关闭命令缓冲 → 关闭队列 → 关闭设备；
- 队列可以先于命令缓冲关闭；此时录制可继续（若命令缓冲只持有队列引用），但 `submit` 返回 `Unavailable`；
- 设备关闭后队列已由设备关闭；再次 `close()` 返回 `Ok(unit)`；
- 已提交未完成的命令缓冲仍引用队列时，调用方必须等 fence signaled 再关闭队列（设备/后端可能已持有原生队列）。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `AcceleratorQueue(Long handle, Int priority)` | handle、priority | handle >0；priority ∈ [-100, 100] | 非法 → panic |

构造器主要供宿主/测试使用；业务代码通过 `AcceleratorDevice.createQueue` 获取。工厂对已关闭设备返回 `Unavailable`；不支持多队列/优先级返回 `Unsupported`。

---

## 6. 字段表

见 §3；字段私有。不暴露原生队列、队列族索引、门铃/寄存器或驱动句柄。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `queueHandle` | 不透明句柄 | 无 | `Long` | 无 |
| `priority` | 创建优先级提示 | 无 | `Int` | 无 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 |

说明：

- `queueHandle()` 返回不透明 `Long`；关闭后仍返回原值；不得当作跨进程/持久 ID。
- `priority()` 返回创建时请求的优先级；关闭后仍可读；不代表实际调度优先级。
- `close`：第一次调用标记关闭并调用原生关闭；后续返回 `Ok(unit)`，不再触碰原生句柄。关闭失败只作为诊断返回 `Io`。
- 设备 close 会调用队列 `close`；因此设备 close 后 `isOpen()` 为 false。
- 不提供 `submit`/`wait`/`kind`/`device`/`describe`/`equals`/`copy`；提交在命令缓冲，设备关联由创建路径保证。

---

## 8. 使用的技术

- 不透明 `Long` 句柄；
- 有序队列生命周期；
- 优先级提示；
- 幂等关闭；
- 原生队列错误映射。

---

## 9. 需要的支撑

- 语言：class、final 字段、Long、Int、Bool、Result；
- 辅助：`unit` 值；
- 运行时/适配器：
  - `acceleratorQueueCreateRaw(Context context, Long deviceHandle, Int priority) -> Result<Long, Error>`；
  - `acceleratorQueueCloseRaw(Long queueHandle) -> Result<Unit, Error>`；
- 原生队列句柄必须 >0；0/负数视为适配器内部错误（工厂返回 `Internal`，构造器 panic）；
- 适配器必须检查 `Context` 取消；不支持多队列/优先级时返回 `Unsupported`；
- 接口：`Context`、`Error`、`BasicError`、`ErrorKind`、`AcceleratorDevice`、`AcceleratorOptions`、`AcceleratorCommandBuffer`。

---

## 10. 依赖的特性/接口/类

[`AcceleratorDevice`](AcceleratorDevice.md)、[`AcceleratorOptions`](AcceleratorOptions.md)、[`AcceleratorCommandBuffer`](AcceleratorCommandBuffer.md)、[`AcceleratorFence`](AcceleratorFence.md)、`Context`、`Error`。

---

## 11. 所有权与并发

引用语义；队列由设备持有并在设备 close 时关闭；调用方也可以提前 close。队列不反向持有设备。

非线程安全：`close` 与提交/查询不得并发；调用方必须串行化。`close()` 幂等指重复调用安全，不承诺并发 close 安全。

多队列之间无隐式顺序；需要同步时由调用方用 fence 显式等待。队列不提供跨队列屏障。

无 `equals`/`copy`；`==` 是引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：

- 每个设备创建一个队列，所有命令缓冲串行提交；完成后关闭命令缓冲、队列、设备。
- NPU 单队列场景显式传 `queuePriority = 0`；不支持优先级时不传非零值。
- 需要两个并发流时创建两个队列，并用各自的 fence 管理完成；不假设跨队列顺序。
- 排队列时保留队列句柄直到所有提交完成。

反例：

- 在队列上找 `submit`/`wait` 方法。
- 假设同一设备的所有队列按全局顺序执行。
- 队列关闭后继续 `submit`。
- 设备 close 后继续使用队列句柄。
- 把 `priority` 当实时优先级或延迟保证。
- 假设所有后端都支持多队列。
- 把队列当传输队列/图形队列。

---

## 13. 测试/场景义务

构造非法 handle/priority panic；创建/关闭；close 幂等；关闭后 `isOpen` false；
设备 close 关闭全部队列；队列先 close 再设备 close；设备 close 后队列 close `Ok(unit)`；
多队列/单队列后端；非零优先级支持/不支持；关闭后提交 `Unavailable`；
`priority` 元数据；无提交/同步方法；队列与命令缓冲/fence 生命周期；
取消/`Unsupported`/`Io`。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class AcceleratorQueue {
    final Long _handle
    final Int _priority
    Bool _open

    AcceleratorQueue(Long handle, Int priority) {
        if handle <= 0 {
            throw "AcceleratorQueue: invalid handle"
        }
        if priority < -100 || priority > 100 {
            throw "AcceleratorQueue: priority out of range"
        }
        _handle = handle
        _priority = priority
        _open = true
    }

    Long queueHandle() { return _handle }
    Int priority() { return _priority }
    Bool isOpen() { return _open }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        return acceleratorQueueCloseRaw(_handle)
    }
}
```
