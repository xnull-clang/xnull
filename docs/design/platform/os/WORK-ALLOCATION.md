# `xdk.os` 工作分配与执行分析

| 项 | 值 |
| --- | --- |
| 目的 | 把剩余 `xdk.os` 类型文档一次并行做完，而不是逐批停留 |
| 方法 | 盘点 → 依赖/冲突分析 → 不相交工作流 → 并行执行 → 统一集成校验 |
| 范围 | B3 GPU、B5 firewall、B6 container/virt/service |
| 约束 | 只写设计文档；不改代码/测试/脚本；共享文件只由集成者修改 |

---

## 1. 盘点

剩余类型 25 个：

| Domain | 类型数 | 类型 |
| --- | --- | --- |
| GPU | 6 | `GpuBackend`、`GpuAdapter`、`GpuDevice`、`GpuMemoryInfo`、`GpuQueueKind`、`GpuQueue` |
| Firewall | 6 | `FirewallAction`、`FirewallDirection`、`FirewallProtocol`、`FirewallRule`、`FirewallStatus`、`FirewallController` |
| Container | 5 | `NamespaceKind`、`Namespace`、`Cgroup`、`ContainerInfo`、`ContainerHost` |
| Virt | 5 | `HypervisorKind`、`Hypervisor`、`VirtualMachineState`、`VirtualMachine`、`VirtualizationHost` |
| Service | 3 | `ServiceState`、`ServiceInfo`、`ServiceManager` |

---

## 2. 依赖与冲突分析

- 所有 domain 只依赖 `xdk.os` 基础类型与 core；彼此不依赖。
- 每个 domain 的 README 与类型文件只在自己的目录内，互不覆盖。
- 共享文件：
  - `docs/design/PLAN.md`
  - `docs/design/README.md`
  - `docs/design/platform/README.md`
  由集成者最后统一修改，工作流不得改。
- 同一 domain 的 README 与类型文件由同一个工作流负责，避免并行写同一文件。

---

## 3. 工作流

| 流 | 范围 | 产物 | 状态 |
| --- | --- | --- | --- |
| W1 | GPU | 6 个类型文件 + `gpu/README.md` 索引化 | 已完成 |
| W3 | Firewall | 6 个类型文件 + `firewall/README.md` 索引化 | 已完成 |
| W4 | Container + Virt | 10 个类型文件 + 两个 README 索引化 | 已完成 |
| W5 | Service | 3 个类型文件 + `service/README.md` 索引化 | 已完成 |

并行规则：

- 每个流只写自己的目录；
- 不新建共享类型；
- 不修改 `PLAN.md`、`t2` 总 README、core/t1 文档；
- 类型名/字段/方法与现有 domain README 一致；
- 所有类型 14 段；README 只留索引/规则/场景/缺口。

---

## 4. 集成校验

并行完成后由集成者统一做（已完成）：

1. 统计预期文件是否齐全（25 个类型文件）；
2. 每个类型文件检查 14 段标题；
3. `check_doc_naming.py docs/design/platform/os docs/design/core`；
4. 相对链接检查 0 broken；
5. 扫描非 XNull 写法：`self(...)`、`self._private`、`new T()`、`// ...`、Python 式 `if` 表达式；
6. 更新 `PLAN.md` 批次状态为全部完成；
7. 更新 `README.md` 与 `../README.md`（只在需要时）；
8. 不提交代码；提交由用户决定。

---

## 5. 验收结果

```text
本轮类型文件：25/25
xdk.os 总计：52 个类型文件（基础 7 + domain 45）
14 段检查：全部通过
命名检查：PASS
相对链接：0 broken
domain README：全部 index-only（0 代码围栏）
代码/脚本改动：无
```

## 6. 验收谓词

- 25 个类型文件全部存在，文件名与类型名一致；
- 每个类型 14 段齐全；
- domain README 只含索引/规则/场景/缺口，不含类伪代码；
- 所有链接可达；
- 参数命名检查 PASS；
- 无代码/脚本改动；
- `PLAN.md` 不再有“待做”状态。
