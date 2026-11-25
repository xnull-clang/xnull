# `xdk.os.cpu` CPU 拓扑与亲和性

| 项 | 值 |
| --- | --- |
| 包 | `xdk.os.cpu` |
| 层 | os / `xdk.os` |
| 依赖 | `xdk.core`、`xdk.os` |
| 能力 | `CpuTopology`、`CpuAffinity`、`CpuFeatures` |
| 稳定性 | `preview` |

---

## 0.5 实现状态（M20.2）

已实现 `CpuCacheKind`、`CpuCore`、`CpuCache`、`CpuTopology`、`CpuAffinity`（5/5）。

- `CpuTopology.detect()`：`hw.logicalcpu`/`hw.ncpu`、`hw.physicalcpu`、缓存 sysctl、
  `machdep.cpu.features`/`leaf7_features`；缺失项跳过，频率未知为 0；
- `socketCount=1`（多 socket 识别留后续）；Darwin `numaNodeCount=0`，Linux 读
  `/sys/devices/system/node/online`；
- `CpuAffinity` 仅保留句柄/生命周期：`get/set/reset` 返回 `Unsupported`，
  本批不做跨平台绑核；
- 深度拓扑、SMT 精确映射与容器 cpuset 留后续。

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

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | 无领域注解 |
| 本包消费 | `@Value` |
| 处理器 | 标准 A8 |
| 生成物 | CPU 拓扑/核心/缓存值语义；Affinity 是句柄 |
| 状态 | 无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `CpuTopology`/`CpuCore`/`CpuCache` | `@Value` | 值语义成员 |
| `CpuAffinity` | — | 资源/句柄，保持显式 class |

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../../ANNOTATION-CATALOG.md)。
