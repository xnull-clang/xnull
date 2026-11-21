# `xdk.os.cpu` CPU 拓扑与亲和性

| 项 | 值 |
| --- | --- |
| 包 | `xdk.os.cpu` |
| 层 | os / `xdk.os` |
| 依赖 | `xdk.core`、`xdk.os` |
| 能力 | `CpuTopology`、`CpuAffinity`、`CpuFeatures` |
| 稳定性 | `preview` |

---

## 1. 定位

CPU 拓扑、缓存、NUMA 归属、ISA 特性和亲和性控制。

不做：调度器、线程池、超频、微码更新、性能计数器、实时内核。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 快照优先 | 拓扑是只读快照；不随热插拔自动更新 |
| 只读默认 | 拓扑/缓存/特性只读；亲和性写操作显式 |
| 权限显式 | `CpuAffinity.set` 可能返回 `PermissionDenied` |
| 宽度 | 频率 `Int`；缓存 `Long`；CPU id `Int` |
| 无全局 | 由 `OsHost` 返回；调用方持有控制器 |

---

## 3. 类型索引

| 类型 | 种类 | 文件 |
| --- | --- | --- |
| `CpuTopology` | class | [`CpuTopology.md`](CpuTopology.md) |
| `CpuCore` | class | [`CpuCore.md`](CpuCore.md) |
| `CpuCache` | class | [`CpuCache.md`](CpuCache.md) |
| `CpuCacheKind` | enum | [`CpuCacheKind.md`](CpuCacheKind.md) |
| `CpuAffinity` | class | [`CpuAffinity.md`](CpuAffinity.md) |

---

## 4. 跨类型规则

- 先 `OsProfile.has(OsCapability.CpuTopology)`，再调用 `OsHost.cpuTopology`。
- 先 `OsProfile.has(OsCapability.CpuAffinity)`，再调用 `OsHost.cpuAffinity`。
- 拓扑/缓存/特性是快照；不自动刷新。
- 容器内返回可见 CPU，不承诺宿主全部。
- `CpuAffinity` 是控制器；必须 `close()`；关闭后 `Unavailable`。
- 亲和性写操作可能需要特权；`PermissionDenied` 不重试、不提权。

---

## 5. 场景

- 桌面：读取拓扑/缓存，决定 worker 数量；不修改亲和性。
- 服务器：读取 NUMA，绑定网络/工作线程；需要特权时显式失败。
- 容器：拓扑可能被 cpuset/cgroup 限制；实现返回可见 CPU。

---

## 6. 缺口

- 实时优先级/调度策略：X，需独立控制器。
- 热插拔/动态拓扑：X；当前快照不自动刷新。
- 性能计数器/PMU：ecosystem/FFI。
- 超频/微码：不做。
