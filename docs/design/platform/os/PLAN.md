# `xdk.os` 类型文档批次计划

| 项 | 值 |
| --- | --- |
| 目的 | 把 `xdk.os` 的 domain README 索引展开为“一类型一文件”的完整契约 |
| 规则 | 只写设计文档；不写代码；不改 core/net；每批只收尾一次 |
| 当前基线 | 基础类型 7 份、domain README 9 份、domain 类型 45 份全部完成；desktop 已移除 |
| 标准 | 每个类型 14 段；domain README 只保留索引、跨类型规则、场景、缺口 |

---

## 1. 批次

| 批次 | 范围 | 类型数 | 状态 |
| --- | --- | --- | --- |
| B1 | `xdk.os.cpu` + `xdk.os.memory` | 8 | 已完成 |
| B2 | `xdk.os.hardware` + `xdk.os.storage` | 12 | 已完成 |
| B3 | `xdk.os.gpu` | 6 | 已完成 |
| B5 | `xdk.os.firewall` | 6 | 已完成 |
| B6 | `xdk.os.container` + `xdk.os.virt` + `xdk.os.service` | 13 | 已完成 |

说明：

- 基础类型（`OsKind`/`OsFamily`/`OsCapability`/`OsInfo`/`OsProfile`/`OsHost`/`Os`）已在 `os/` 与 `os/host/` 完成。
- 每个批次只展开一个/两个 domain，避免一次改太多文件。
- domain README 在批次结束后只保留索引与跨类型规则；类/方法/伪代码进类型文件。

---

## 2. 每批收尾

1. 类型文件齐全，README 索引链接指向文件；
2. 运行 `check_doc_naming.py`；
3. 相对链接检查 0 broken；
4. 更新本表状态；
5. 不提交代码；提交由用户决定。

---

## 3. B1 范围

| 类型 | 文件 |
| --- | --- |
| `CpuCacheKind` | `cpu/CpuCacheKind.md` |
| `CpuCore` | `cpu/CpuCore.md` |
| `CpuCache` | `cpu/CpuCache.md` |
| `CpuTopology` | `cpu/CpuTopology.md` |
| `CpuAffinity` | `cpu/CpuAffinity.md` |
| `MemoryModule` | `memory/MemoryModule.md` |
| `NumaNode` | `memory/NumaNode.md` |
| `PhysicalMemory` | `memory/PhysicalMemory.md` |
