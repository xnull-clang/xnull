# core 文档地图

| 项 | 值 |
| --- | --- |
| 作用 | 说明 core 文档里哪些是权威、哪些是历史、哪些是状态账本，避免把两代文档当成两套 API |
| 统计 | 2026-11-22：core 目录共 228 个文件（`core/` 201、根目录 27）；core 共 15 包 / 186 类型 |
| 结论 | `core/` 是类级设计权威；`annotations/` 独立；`01`–`16` 是实现/状态账本；`XDK-CORE-API.md`、`XDK-SCENARIOS.md` 是 v1 历史快照 |


> 全量能力覆盖审计见 [`COVERAGE.md`](../COVERAGE.md)。
> core 的 API 广度与方法面见 [`API-SURFACE.md`](API-SURFACE.md)；跨域场景与能力分析见 [`SCENARIOS.md`](../SCENARIOS.md)、[`CAPABILITY.md`](../CAPABILITY.md)。

> 注解包（元模型/元注解/处理器合同，14 类型）见 [`../annotations/README.md`](../annotations/README.md)；架构与 XDK 对接矩阵见 [`ANNOTATION-SYSTEM.md`](../ANNOTATION-SYSTEM.md)。
> 旧计划 [`ANNOTATION-PLAN.md`](../ANNOTATION-PLAN.md) 保留为历史；与 `ANNOTATION-SYSTEM.md` 冲突时以后者为准。

---

## 1. 为什么文件多

`core/` 采用“一个公开类型一个文件”：

```text
core/
  errors/       16 个类型文件 + README
  bytes/         7 个类型文件 + README
  io/           22 个类型文件 + README
  ...
```

196 个文件不是 196 份重复设计，而是：

- 每个 class / enum / protocol 单独一份 12/14 项契约；
- 包 README 只放索引、顶层函数、场景、缺口；
- 这样评审时可以逐类型冻结，不用在一个大文件里翻几千行。

真正重复的是**两代文档之间**，不是 `core/` 内部。

### 1.1 交叉检查

- `core/` 共 186 个类型文件，跨包**没有重名类型**；`annotations/` 14 个类型文件（设计基线）；core + annotations 合计 200 类型（16 包）；
- `core/` 15 个包 README + 3 个总纲/跨包文档 = 196；`annotations/` 另计 14 类型 + README；
- `errors/`、`runtime/` 的早期类型文档使用紧凑 7 段格式，其余包使用 14 段格式；
- 旧 `01`–`16` 与 `core/` 有 API 重叠，但 `01`–`16` 仍保留实现状态/源码映射；
- `XDK-CORE-API.md`、`XDK-SCENARIOS.md` 是 v1 历史快照，不再作为权威。

---

## 2. 权威顺序

发生冲突时按以下顺序：

1. **语言规范 S0–S10**：语法、对象模型、错误/并发/资源合同；
2. **`../annotations/README.md` + `ANNOTATION-SYSTEM.md`**： 注解语法、元模型、处理器合同与 XDK 对接矩阵；
3. **`core/` 类级设计**：公开类型、方法、失败、生命周期、并发、XNull 伪代码；
4. **`STATUS.md` + `01`–`16` + `AUDIT.md` + `src/xdk/PLAN.md`**：实现状态、源码映射、`当前状态`、K/X 账本；
5. **`CORE-CLOSURE.md`**：收口批次范围、门禁、终态；
6. **`XDK-CORE-API.md` / `XDK-SCENARIOS.md`**：v1 历史快照，只作参考，不作 API 权威。

规则：

- 注解冲突：以 `ANNOTATION-SYSTEM.md` 为准，`ANNOTATION-PLAN.md` 只作历史；
- API 形态冲突：以 `core/` 为准；
- 实现是否完成：以 `STATUS.md` / `AUDIT.md` / `01`–`16` 的 `当前状态` / `PLAN.md` 为准；
- 批次范围冲突：以 `CORE-CLOSURE.md` 为准；
- 历史文档不得反向覆盖 `core/`。

---

## 3. 文件分类

| 文件/目录 | 角色 | 是否重复 | 处理 |
| --- | --- | --- | --- |
| `CORE-PROFILES.md`（在 `core/`） | 客户端/服务器画像、资源上限、健康/执行原语 | 否 | 新增权威 |
| `PLATFORM-BOUNDARY.md`（在 `core/`） | 硬件/OS/GPU/防火墙/平台服务归属 | 否 | 新增权威 |
| `core/README.md` | 类级设计标准、包顺序、目录规范 | 否 | 权威 |
| `core/<pkg>/README.md` | 包索引、顶层函数、场景、缺口 | 否 | 权威 |
| `core/<pkg>/<Type>.md` | 单类型完整契约 | 否 | 权威 |
| `../annotations/README.md` + `../annotations<Type>.md` |  注解元模型/元注解/处理器合同（14 类型） | 否 | 新增权威；不计入 `core/` 186 类型 |
| `00-overview.md` |  旧总览、K/X、评审标准 | 部分重复 | 保留为流程/历史入口，并指向 `core/` |
| `01-errors.md` … `16-cli.md` | v1 包级设计 + 实现状态 + 源码映射 | **与 `core/` 部分重复** | 保留为状态/实现账本；API 以 `core/` 为准 |
| `12-tasks.md` + `13-sync.md` | 旧 tasks/sync 包 | 与 `core/execution/` 部分重复 | 同上；执行层以 `core/execution/` 为准 |
| `XDK-CORE-API.md` | v1 扁平 API 清单 | **整份被 `core/` 取代** | 标记历史，不再更新 |
| `XDK-SCENARIOS.md` | v1 场景设计 | **部分被 `core/*/README` 场景取代** | 标记历史，不再作为验收依据 |
| `STATUS.md` | 包状态/源码/K/X 仪表盘 | 否 | 权威状态入口 |
| `AUDIT.md` | 实现/门禁/Int 审计 | 否 | 权威状态 |
| `CORE-CLOSURE.md` | 收口范围/终态/验收 | 否 | 权威门禁 |

---

## 4. 旧文件与 `core/` 的对应

| 旧文件 | 新位置 | 说明 |
| --- | --- | --- |
| —（无旧文件） | `../annotations` | 新增 ；逻辑首单元，无 `01`–`16` 账本 |
| `00-overview.md` | `core/README.md` + `AUDIT.md` + `CORE-CLOSURE.md` | 流程/状态拆开 |
| `01-errors.md` | `core/errors/` | API 以新位置为准 |
| `02-runtime.md` | `core/runtime/` | 含新增健康面 |
| `03-meta.md` | `core/meta/` | 含画像类型 |
| `04-bytes.md` | `core/bytes/` | |
| `05-text.md` | `core/text/` | |
| `06-collections.md` | `core/collections/` | |
| `07-math.md` | `core/math/` | |
| `08-time.md` | `core/time/` | |
| `09-io.md` | `core/io/` | |
| `10-fs.md` | `core/fs/` | |
| `11-sys.md` | `core/sys/` | |
| `12-tasks.md` + `13-sync.md` | `core/execution/` | 合并为执行层 |
| `14-log.md` | `core/log/` | |
| `15-config.md` | `core/config/` | 含画像来源 |
| `16-cli.md` | `core/cli/` | |
| `XDK-CORE-API.md` | `core/` 全部包 | 扁平清单不再维护 |
| `XDK-SCENARIOS.md` | `core/*/README.md` + `CORE-PROFILES.md` | 场景不再维护 |

---

## 5. 为什么暂时不删旧文件

旧文件仍有两类不可替代的信息：

1. **实现状态**：`当前状态 Verified/Partial`、源码路径、K/X 账本；
2. **工具引用**：`src/toolchain/core-batches.sh` 仍按 `09-io.md`、`06-collections.md` 等路径驱动收口；
   `CORE-CLOSURE.md` 也引用这些文件的 `当前状态`。

在把状态迁移到 `STATUS.md` / `AUDIT.md` / `PLAN.md` 并更新工具脚本之前，直接删除会破坏门禁。
因此当前处理是：

- 保留旧文件；
- 在旧文件顶部加状态横幅；
- 用本 README 明确权威顺序；
- 等状态账本迁移完成后，再统一归档到 `legacy/` 或删除。

---

## 6. 维护规则

- 新增/修改公开类型：`core/` 类型只改 `core/`； 注解类型只改 `annotations/`；不要回写 `01`–`16` 的 API 段；
- 包实现状态：更新 `STATUS.md` / `AUDIT.md` / `PLAN.md`，不要改 `core/` 的契约；
- 实现状态变化：改 `AUDIT.md` / `01`–`16` 的 `当前状态` / `PLAN.md`，不要改 `core/` 的 API 契约；
- 场景验收：以 `core/*/README.md` 和实际测试脚本为准，不以 `XDK-SCENARIOS.md` 为准；
- 发现旧文件与新设计冲突：先改 `core/`，再在旧文件加注“已由 core 取代”，不得反向覆盖。