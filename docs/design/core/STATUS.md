#  状态总表（Dashboard）

> **1.x 状态仪表盘**：本表记录旧 `01`–`16` 批次；2.x 包/阶段/状态以 [`../PACKAGE-MAP.md`](../PACKAGE-MAP.md) 为准，不把本表当 2.x 计划。

| 项 | 值 |
| --- | --- |
| 作用 | 把 `01`–`16` 的实现状态、源码路径、K/X 账本集中到一页； `annotations` 单列在 §2 |
| 权威 | API 形态以 `core/` 为准（ 以 `../annotations` 为准）；实现状态以本表、`AUDIT.md`、`src/xdk/PLAN.md` 为准 |
| 更新 | 只在实现/门禁变化时更新；纯 API 设计变化不更新本表 |
| 注意 | 本表是**状态仪表盘**，不是新的 API 规范；不复制类/方法契约 |

---

## 1. 包状态

| 包 | 类级设计 | 旧状态/源码账本 | 对应源码 | 当前状态 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `xdk.errors` | `core/errors/` | `01-errors.md` | `src/xdk/core/errors/Errors.x` | Verified（mini） | X：复杂方法调用返回推断 |
| `xdk.runtime` | `core/runtime/` | `02-runtime.md` | `src/xdk/core/runtime/Runtime.x` | Verified（mini） | 新增健康面为设计稿 |
| `xdk.meta` | `core/meta/` | `03-meta.md` | `src/xdk/core/meta/Meta.x` | Verified（mini） | 新增画像类型为设计稿 |
| `xdk.bytes` | `core/bytes/` | `04-bytes.md` | `src/xdk/core/bytes/Bytes.x` | Verified（mini） | X：ByteBuffer 等 |
| `xdk.text` | `core/text/` | `05-text.md` | `src/xdk/text/base/*.x`、`src/xdk/text/full/*.x` | Partial（mini） | 命名/Unicode/Regex 边界待补 |
| `xdk.collections` | `core/collections/` | `06-collections.md` | `src/xdk/core/collections/*.x` | Partial（mini） | 1.x `joinWith`/`Entry`/固定 `Pair` 已整合；见 README §9 |
| `xdk.math` | `core/math/` | `07-math.md` | `src/xdk/core/math/Math.x` | Verified（mini） | random 归  |
| `xdk.time` | `core/time/` | `08-time.md` | `src/xdk/core/time/*.x` | Verified（mini） | 时区库 X；`sleepContext`/layout 已整合 |
| `xdk.io` | `core/io/` | `09-io.md` | `src/xdk/io/IO.x`、`src/xdk/io/system/` | Partial（mini） | 完整文件/目录面在 system |
| `xdk.fs` | `core/fs/` | `10-fs.md` | `src/xdk/fs/FS.x`、`src/xdk/io/system/` | Partial（mini） | 1.x 完整 File/Dir/atomic/temp 已整合；`FileMode` 迁移 `OpenOptions` |
| `xdk.sys` | `core/sys/` | `11-sys.md` | `src/xdk/io/base/Sys.x`、`io/system`、`io/resource` | Partial（mini） | 1.x 完整 File/Dir/Process、进程组/stdio 兼容面已整合 |
| `xdk.tasks` | `core/execution/` | `12-tasks.md` | `src/xdk/concurrent/tasks/Tasks.x` | Verified（mini） | `xdk.tasks` 为兼容命名 |
| `xdk.sync` | `core/execution/` | `13-sync.md` | `src/xdk/concurrent/sync/Sync.x` | Verified（mini） | `xdk.sync` 为兼容命名 |
| `xdk.log` | `core/log/` | `14-log.md` | `src/xdk/log/Log.x` | Verified（mini） | 过滤/脱敏/采样已整合；见 README §9 |
| `xdk.config` | `core/config/` | `15-config.md` | `src/xdk/config/Config.x` | Verified（mini） | 内存/环境面；`setChecked`/`apply` 已整合 |
| `xdk.cli` | `core/cli/` | `16-cli.md` | `src/xdk/cli/Cli.x` | Verified（mini） | 子命令/`completionBash` 已整合；`Completion` 类型 X |

---

## 2. 设计稿（未实现）

以下类型是 `core/` 与 `annotations/` 的新增设计，**不计入**上面的 `Verified/Partial` 实现状态：

| 包 | 类型 | 文件 |
| --- | --- | --- |
|  `xdk.annotations` | 注解元模型/元注解/处理器合同（14 类型） | [`annotations/`](../annotations/README.md) |
| `xdk.meta` | `RuntimeRole`、`IoModel`、`ShutdownPolicy`、`CapabilitySet`、`ResourceLimits`、`CoreProfile`、`ProfileBuilder` | `core/meta/` |
| `xdk.config` | `ProfileSource`、`ConfigProfileSource` | `core/config/` |
| 执行层 | `Executor`、`Semaphore`、`RwLock<T>`、`WaitGroup`、`Once`、`Pool<T>`、`Future<T>`、`Promise<T>` | `core/execution/` |
| `xdk.runtime` | `HealthState`、`HealthReport`、`HealthCheck`、`HealthRegistry` | `core/runtime/` |

实现这些类型前，必须先补场景、运行时/编译器支撑和门禁；不得把“设计已写”当成“包已完成”。

---

## 3. 状态词

| 状态 | 含义 |
| --- | --- |
| `Verified` | 设计存在，场景/回归/门禁通过 |
| `Partial` | K 可用；存在已登记的 X 缺口 |
| `Draft` | 只有设计，未实现或未验证 |
| `Design` | 本表 §2 的新增设计稿；不参与包状态 |

规则：

- `Partial` 不得写成 `Verified`；
- 设计稿不得写成 `Verified`；
- 包状态变化时，同时更新 `AUDIT.md` 与 `src/xdk/PLAN.md`；
- API 变化只改 `core/`，不改本表的契约列（本表没有契约列）。

---

## 4. 为什么保留 `01`–`16`

- `src/toolchain/core-batches.sh` 仍按 `09-io.md`、`06-collections.md` 等路径驱动收口批次；
- 在允许修改工具脚本之前，移动/删除旧文件会直接破坏批次执行；
- 因此旧文件保留为**状态/源码账本**，本表只做集中展示；
- `00 annotations` 是新增首逻辑单元，没有对应的旧账本；其状态只在 §2 以 `Design` 记录；
- 等工具脚本改为引用本表后，再把旧文件归档到 `legacy/`。

---

## 5. 相关文档

- 类级设计：`core/`
- 注解包：`annotations/`（架构见 [`../ANNOTATION-SYSTEM.md`](../ANNOTATION-SYSTEM.md)）
- 客户端/服务器画像：`core/CORE-PROFILES.md`
- 平台/硬件边界：`core/PLATFORM-BOUNDARY.md`
- 审计：`AUDIT.md`
- 收口契约：`CORE-CLOSURE.md`
- 文档地图：`README.md`
