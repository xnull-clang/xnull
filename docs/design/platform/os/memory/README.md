# `xdk.os.memory` 物理内存与 NUMA

| 项 | 值 |
| --- | --- |
| 包 | `xdk.os.memory` |
| 层 | os / `xdk.os` |
| 依赖 | `xdk.core`、`xdk.os` |
| 能力 | `PhysicalMemory`、`Numa` |
| 稳定性 | `preview` |

---

## 0.5 实现状态（M20.2）

已实现 `NumaNode`、`MemoryModule`、`PhysicalMemory`（3/3）。

- `PhysicalMemory.detect()`：`hw.memsize` 总量，`xdkc_memory_free_bytes` 空闲/可用
  （二者同值）；检测失败返回 0/空，不 panic；
- DIMM/SMBIOS 未采集（无 IOKit/特权路径），`modules` 为空；
- Darwin `numaNodes` 为空；Linux NUMA 节点计数由 cpu 包读取；
- 深度 NUMA/DIMM 槽位/厂商型号留后续。

## 1. 定位

物理内存快照、内存条（DIMM）信息、NUMA 节点；不涉及语言堆/GC。

不做：分配器、GC、mmap/共享内存（X）、页表、内存热插拔、ECC 注入。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 只读 | 物理内存清单默认只读；不提供分配/释放 |
| 单位 | 所有字节数用 `Long` |
| 脱敏 | 不暴露序列号；厂商/型号可选 |
| 容器/虚拟化 | 返回当前可见内存，不承诺宿主全部 |
| 快照 | 不自动刷新；需要新值重新调用 |

---

## 3. 类型索引

| 类型 | 种类 | 文件 |
| --- | --- | --- |
| `PhysicalMemory` | class | [`PhysicalMemory.md`](PhysicalMemory.md) |
| `MemoryModule` | class | [`MemoryModule.md`](MemoryModule.md) |
| `NumaNode` | class | [`NumaNode.md`](NumaNode.md) |
| `MappedRegion`（X） | class | X；本批不冻结 |

---

## 4. 跨类型规则

- 先 `OsProfile.has(OsCapability.PhysicalMemory)`，再调用 `OsHost.physicalMemory`。
- 物理内存 ≠ 语言堆：堆/GC 见 `runtime.MemoryStats`。
- 容器内只返回 cgroup/namespace 可见内存。
- `modules`/`numaNodes` 为空表示不支持/不可见，不 panic。
- 不提供分配/释放/mmap；`MappedRegion` 是后续独立设计。

---

## 5. 场景

- 服务器启动：记录内存/NUMA 摘要；按 NUMA 绑定 worker。
- 桌面：显示内存条/容量；不做分配。
- 容器：只显示 namespace/cgroup 可见内存。

---

## 6. 缺口

- mmap/共享内存：X `MappedRegion`，需要显式 `close()`。
- ECC 错误/内存热插拔：ecosystem/FFI。
- 精确内存带宽/PMU：X。
- 分配器/GC：runtime，不在 `xdk.os`。

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | 无领域注解 |
| 本包消费 | `@Value` |
| 处理器 | 标准 A8 |
| 生成物 | 内存/模组/NUMA 值语义 |
| 状态 | 无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `PhysicalMemory`/`MemoryModule`/`NumaNode` | `@Value` | 值语义成员 |

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../../ANNOTATION-CATALOG.md)。
