# `xdk.os.memory` 物理内存与 NUMA

| 项 | 值 |
| --- | --- |
| 包 | `xdk.os.memory` |
| 层 | os / `xdk.os` |
| 依赖 | `xdk.core`、`xdk.os` |
| 能力 | `PhysicalMemory`、`Numa` |
| 稳定性 | `preview` |

---

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
