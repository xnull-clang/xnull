# `xdk.queue` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.queue` |
| 层 | L7 应用服务（文档分组 `utils/`） |
| 依赖 | `xdk.errors`、`xdk.execution`、`xdk.runtime` |
| 被依赖 | 应用、日志/指标缓冲、批处理 |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 0.5 实现状态（M21.1）

已实现 `DropPolicy`、`QueueStats`、`BoundedQueue<T>`、`BatchQueue<T>`、`DelayQueue<T>`（5/5）。

- `BoundedQueue`：Error/DropNewest/DropOldest 三策略、统计、clear/close；
- `BatchQueue`：达到批量后 `add=false`（任务合同），`flush` 返回副本并清空；
- `DelayQueue`：按 `nowMono()+delay` 排序，`take` 用 `RuntimeMonitor.waitDeadline`
  等待最早就绪（5ms 取消轮询，无忙等）；`tryTake` 只取已就绪；
- `RuntimeMonitor` 新增 `waitDeadline(Context, Long)` 加法 API；
- 不做无界队列、持久化、优先级；泛型元素不强制 null 检查，以支持 Int 等值类型。

## 1. 包定位

并发队列补充：有界丢弃策略、批处理、延迟出队、统计。

不重复 core：
- 阻塞单值通道用 `xdk.execution.Channel`；
- 普通容器用 `xdk.collections.Queue/Deque/PriorityQueue/RingBuffer`；
- 本包只补策略、批处理、延迟和统计。

不做：持久化队列、分布式队列、优先级堆（用 `PriorityQueue`）、事务。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 不阻塞 | `BoundedQueue`/`BatchQueue` 非阻塞；阻塞语义用 Channel |
| 策略显式 | full 时 Error/DropNewest/DropOldest 由调用方选择 |
| 计数可见 | pushed/popped/dropped/rejected 可观测 |
| 延迟可取消 | `DelayQueue.take` 接受 Context |
| 关闭明确 | close 清空并计数丢弃；之后拒绝写入 |
| 无全局 | 无全局队列注册表 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `DropPolicy` | enum | 满队列策略 | [`DropPolicy.md`](DropPolicy.md) |
| `QueueStats` | class | 队列统计快照 | [`QueueStats.md`](QueueStats.md) |
| `BoundedQueue` | class | 非阻塞有界队列 | [`BoundedQueue.md`](BoundedQueue.md) |
| `BatchQueue` | class | 批处理缓冲 | [`BatchQueue.md`](BatchQueue.md) |
| `DelayQueue` | class | 延迟出队 | [`DelayQueue.md`](DelayQueue.md) |

X：持久化、分布式、优先级延迟、批量超时自动 flush、无锁队列。

---

## 4. 顶层函数

无。

---

## 5. 技术/支撑/依赖

- 技术：监视器保护、丢弃策略、批处理、单调截止、延迟堆/线性扫描。
- 支撑：`RuntimeMonitor`、`nowMono`、`cancelledError`、`unavailableError`。
- 依赖：`errors`、`execution`、`runtime`。

---

## 6. 场景

### Q1：遥测缓冲

`BoundedQueue(1024, DropPolicy.DropOldest)`；满时丢最旧，保留最新。

### Q2：批量写入

`BatchQueue(128)`；`add` 后检查 `isFull()`，再 `flush()`。

### Q3：延迟重试

`DelayQueue`；`put(task, 30000)`；`take(ctx)` 在到期后返回。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 阻塞队列 | 使用 `Channel`，不重复 |
| 有界丢弃 |  支持三种策略 |
| 延迟队列 | 无界；`take` 可取消 |
| 批量自动 flush | X； 显式 flush |
| 公平性 | 不承诺 |
| 持久化/分布式 | 不做 |

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | 无领域注解 |
| 本包消费 | `@Value` |
| 处理器 | 标准 A8 |
| 生成物 | 队列统计值语义；队列本身是状态资源 |
| 状态 | 无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `QueueStats` | `@Value` | 值语义成员 |
| `BoundedQueue`/`BatchQueue`/`DelayQueue` | — | 状态资源，保持显式 class/close |

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
