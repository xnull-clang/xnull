# 注解平台实施计划（mini 1.0）

| 项 | 值 |
| --- | --- |
| 状态 | **M0/M1 implemented**（P0-01–P0-10、P1-01–P1-04）；M2–M7 planned；A8 5 个已实现 |
| 基线 | `main` @ `a4a5ba33`（M0 close；P0-01–P0-09 implemented） |
| 权威语义 | [`solution-03-annotation.md`](../solution-03-annotation.md)（S3 1.0.0） |
| 相关文档 | [`ANNOTATION-IR.md`](ANNOTATION-IR.md)、[`ANNOTATION-PLAN.md`](ANNOTATION-PLAN.md)、[`ANNOTATION-CATALOG.md`](ANNOTATION-CATALOG.md)、[`ANNOTATION-ADOPTION.md`](ANNOTATION-ADOPTION.md)、[`ARCHITECTURE.md`](ARCHITECTURE.md) §6 |
| 范围 | mini 1.0 注解平台：IR、内建注册、处理器清单、阶段调度、生成源码、固定点、沙箱、诊断合并、一致性门禁；A8 迁移；CLI/codec/validate/http/sql 五个领域闭环 |
| 不包含 | XNull 1.0 全领域注解；B5–B10 全包实现；运行时反射/扫描/动态加载 |
| 分支约束 | 只在 `main` 工作；不创建新分支、不创建 worktree |

---

## 1. 目标与完成定义

mini 1.0 的注解能力必须做到：

1. 新增一个领域注解 + 处理器，不需要修改编译器主流程。
2. 新增一个派生注解，只注册 Internal Processor，不再改 `main.x` 的 if-chain。
3. 新注解目标/值类型有版本化扩展路径，不是散落硬编码。
4. 处理器清单可显式启用/禁用，阶段、顺序、固定点、沙箱、诊断、生成源码全部可验证。
5. 生成物入库，`--check-generated` 能发现漂移。
6. 运行时只有编译器生成的只读 Registry，无反射/扫描。
7. 至少五个领域闭环真实可用：
   - `@CliCommand` → 命令树/参数/help/completion；
   - `@Serializable`/`@JsonName` → 编解码器；
   - `@Validate`/`@Min`/`@Max`/`@Pattern` → 校验器；
   - `@HttpRoute`/`@Header`/`@Query` → 路由表/参数绑定；
   - `@Sql`/`@Param`/`@Row` → DAO/行映射。
8. 每个领域注解都有：声明、处理器、生成物、业务逻辑、成功/失败场景、诊断、文档状态。

> 上述五个领域能力依赖各自包：`xdk.cli` 已有；`xdk.codec`、`xdk.validate`、`xdk.net.http`、`xdk.sql` 仍是设计稿。计划把“包实现 + 注解 + 处理器 + 生成物”作为一个闭环，不接受只写注解声明。

---

## 2. 当前状态

| 能力 | 状态 |
| --- | --- |
| 注解语法/目标/保留/TypeUse/Repeatable | 已实现 |
| `xdk.annotations` 14 类型 + Registry | 已实现 |
| 内建检查 | 已实现 |
| A8 五个派生：Value/Data/Copy/Builder/Delegate | 已实现，含限制 |
| 注解 IR | 未有独立稳定 IR |
| 内建注册表 | `initBuiltins` 硬编码 |
| 处理器清单 | 无 |
| 阶段调度/固定点 | 无 |
| 生成源码落盘/加载 | 无 |
| 沙箱 | 无 |
| 诊断合并 | 只有编译期诊断，无处理器诊断合并 |
| 生成物一致性门禁 | 无 |
| 领域注解 | 设计/catalog；无实现 |
| 领域包 | `xdk.cli` 已存在；codec/validate/http/sql 设计稿 |

---

## 3. 目标架构

```text
Source
  → Parser
  → Annotation IR
  → Builtin Registry
  → Processor Scheduler
      ├─ Internal Processors（语言级/A8）
      ├─ External Processors（领域包）
      └─ Generated Source Pipeline（多轮固定点）
  → Checker / CGen
  → Runtime Annotation Registry（只读，Runtime retention）
  → API Annotation Surface / IDE extractor
```

### 3.1 Annotation IR

- 声明：包、名称、目标、保留、字段、默认值、版本；
- 使用：目标、参数、源位置、重复索引；
- 值树：标量、枚举、类型引用、数组、嵌套注解；
- 包归属/全限定名；
- 来源标记；
- 稳定版本号；
- 编译器/处理器/API 文档/Registry 共用，不直接依赖 AST。

### 3.2 Builtin Registry

- 每个内建注解一个 descriptor + handler；
- `initBuiltins` 只加载注册表；
- 新内建注解不改主流程；
- 内建注解仍属于编译器版本，不是包级扩展。

### 3.3 Processor Manifest

字段至少：

- `name`、`version`；
- `phases`；
- `inputs`（注解全限定名）；
- `outputs`（生成文件模式）；
- `options` schema；
- `sandbox`（进程/资源/网络禁入）；
- `priority`/依赖；
- `cacheKey` 输入。

manifest 格式必须写进 S3 / Part 8 / Part 10，不在实现里临时发明。

### 3.4 Phase Scheduler

- `Resolve → Validate → Generate（多轮）→ Finalize`；
- 同阶段按依赖/priority；
- Generate 固定点，设置最大轮次；
- 检测循环/不收敛；
- Finalize 禁止生成；
- 处理器只能收到声明阶段；
- 失败原子性。

### 3.5 Generated Source Pipeline

- 生成目录：`<package>/generated/`；
- 文件带 `generated` 标记和来源；
- 生成后解析/检查，进入下一轮；
- 生成失败整批回滚；
- 生成物入库；
- `--check-generated` 对比生成物与源码；
- 生成物参与 API 文档与 Registry。

### 3.6 Sandbox

- External Processor 独立进程；
- 只读 IR 输入；
- 只能写声明输出目录；
- 禁止网络/反射/动态加载/任意文件写/启动进程；
- 资源上限与超时；
- 确定性环境：无时间、随机、绝对路径、哈希顺序依赖。

### 3.7 Diagnostics

- `AN0100–AN0199`：调度/生成；
- `AN1000–AN1999`：领域包；
- 诊断合并、排序、去重；
- 稳定源位置；
- 失败不落半成品。

### 3.8 Runtime Registry

- 只有 `Runtime` 进入；
- schema 版本化；
- 无反射/扫描/动态加载；
- 新值类型/目标升版本；
- 领域逻辑优先用生成显式代码。

### 3.9 API Annotation Surface

- 每个公共 API 文档必须写注解面；
- 注解声明、目标、保留、处理器、生成物、诊断、状态；
- 注解是 API 合同；
- planned/implemented/open 明确。

---

## 4. 工作包

### P0 平台地基

| ID | 交付 | 依赖 | 验收 | 状态 |
| --- | --- | --- | --- | --- |
| P0-01 | Annotation IR v1 + 版本规则 | S3 | IR 能表达现有全部注解/值/目标；往返测试稳定 | implemented（`annotation_ir/run.sh`、`--dump-annotations`） |
| P0-02 | Builtin Registry | P0-01 | 内建注解由注册表加载；行为不回归 | implemented（`builtinDescriptors()`，B1 行为 PASS） |
| P0-03 | Processor Manifest 规范 + 解析 | P0-01 | 清单可启用/禁用；非法清单稳定诊断 | implemented (M0.2) |
| P0-04 | Phase Scheduler + 固定点 | P0-02/03 | 阶段顺序、轮次、循环检测、Finalize 禁生成 | implemented (M0.2) |
| P0-05 | Generated Source Pipeline | P0-04 | 生成/落盘/加载/回滚；`--check-generated` | implemented (M0.3：generated-dir staging/原子替换/标记/固定点/check) |
| P0-06 | Sandbox 进程适配 | P0-04 | 网络/文件/进程越界被拒；超时/资源限制 | implemented (M0.4：Darwin sandbox-exec；其他平台 limits-only) |
| P0-07 | 诊断合并/码段 | P0-04 | 多处理器诊断稳定排序/去重 | implemented (M0.2) |
| P0-08 | 玩具注解 + 玩具处理器 | P0-01–07 | 不改主流程新增一个注解/处理器/生成物 | implemented (M0：toy_processor + annotation_platform) |
| P0-09 | 平台门禁脚本 | P0-08 | 一键跑 IR/manifest/phase/fixed/sandbox/check-generated | implemented (M0：`annotation_platform/m0_gate.sh`) |
| P0-10 | Program IR：类型/字段/方法/构造器 symbols | P0-01 | v2 symbols；v1 兼容；确定性 | implemented (M0.6：`irVersion=2`, `symbols.types`) |

### P1 A8 迁移

| ID | 交付 | 依赖 | 验收 | 状态 |
| --- | --- | --- | --- | --- |
| P1-01 | Value/Data/Copy → Internal Processors | P0 | 行为/诊断/测试不回归 | implemented (A8CoreProcessor) |
| P1-02 | Builder/Delegate → Internal Processors | P1-01 | 同上；非泛型边界保留 | implemented (A8BuilderProcessor/A8DelegateProcessor) |
| P1-03 | 删除 `a8HasAnno` 硬编码分支 | P1-01/02 | 新派生注解只注册，不改主流程 | implemented (`a8Processors()`；无 `expandA8Class`) |
| P1-04 | A8 回归矩阵 | P1-03 | A8 全部场景 + 负例 + full xdk.sh | implemented (`a8_registry.sh` + m0_gate) |

### P2 CLI 试点

| ID | 交付 | 依赖 | 验收 |
| --- | --- | --- | --- |
| P2-01 | `@CliCommand`/`@CliSubcommand`/`@Option`/`@Arg` 声明 | P0 | 注解可声明/校验 |
| P2-02 | CliProcessor Resolve/Validate | P2-01 | 目标/参数/重复/错误诊断 |
| P2-03 | 生成命令树/参数表/help/completion | P2-02 | 生成物入库；真实 CLI 场景 |
| P2-04 | CLI 业务闭环 | P2-03 | 解析/帮助/补全/错误路径 PASS |

### P3 codec / `@Serializable`

| ID | 交付 | 依赖 | 验收 |
| --- | --- | --- | --- |
| P3-01 | `xdk.codec` 包骨架（13 类型） | P0；B6 包合同 | 类型契约可编译 |
| P3-02 | `@Serializable`/`@JsonName` 声明 | P3-01 | 目标/保留/参数校验 |
| P3-03 | CodecProcessor Resolve/Validate/Generate | P3-02 | 生成 JSON codec；诊断 |
| P3-04 | codec 业务闭环 | P3-03 | 序列化/反序列化/字段名/失败路径 |
| P3-05 | 生成物一致性/文档 | P3-04 | `--check-generated` + API 注解面 |

### P4 validate / `@Validate`

| ID | 交付 | 依赖 | 验收 |
| --- | --- | --- | --- |
| P4-01 | `xdk.validate` 包骨架（8 类型） | P0；B9 合同 | 类型契约可编译 |
| P4-02 | `@Validate`/`@Min`/`@Max`/`@Pattern` | P4-01 | 目标/参数校验 |
| P4-03 | ValidateProcessor Generate | P4-02 | 生成校验器/错误路径 |
| P4-04 | validate 业务闭环 | P4-03 | 成功/失败/边界/错误路径 |

### P5 http / `@HttpRoute`

| ID | 交付 | 依赖 | 验收 |
| --- | --- | --- | --- |
| P5-01 | `xdk.net.http` 包骨架（40 类型） | P0；B7 合同 | 路由/请求/响应可编译 |
| P5-02 | `@HttpRoute`/`@Header`/`@Query` | P5-01 | 目标/参数校验 |
| P5-03 | HttpProcessor Generate | P5-02 | 路由表/参数绑定 |
| P5-04 | http 业务闭环 | P5-03 | 方法/路径/参数/错误/404 |

### P6 sql / `@Sql`

| ID | 交付 | 依赖 | 验收 |
| --- | --- | --- | --- |
| P6-01 | `xdk.sql` 包骨架（12 类型） | P0；B7 合同 | DAO/行/参数可编译 |
| P6-02 | `@Sql`/`@Param`/`@Row` | P6-01 | 目标/参数校验 |
| P6-03 | SqlProcessor Generate | P6-02 | DAO/行映射/参数绑定 |
| P6-04 | sql 业务闭环 | P6-03 | 查询/行映射/错误/类型不匹配 |

### P7 平台硬化

| ID | 交付 | 依赖 | 验收 |
| --- | --- | --- | --- |
| P7-01 | Registry schema v2 扩展测试 | P0 | 新字段/版本兼容/旧表可读 |
| P7-02 | 新目标/值类型扩展流程 | P0 | 版本化 fixture；不散落 if-chain |
| P7-03 | 增量缓存/性能 | P0 | 相同输入命中；变更失效 |
| P7-04 | API 文档注解面自动提取 | P0 | 文档门禁 |
| P7-05 | 泛型 Builder/Delegate 评估 | P1 | owner 决策；不在 1.0 阻塞 |

---

## 5. 里程碑与顺序

| 里程碑 | 内容 | 出口 | 状态 |
| --- | --- | --- | --- |
| M0 | P0 平台地基 | 玩具注解/处理器/生成物/沙箱/门禁 PASS | implemented（`annotation_platform/m0_gate.sh`） |
| M1 | P1 A8 迁移 | A8 行为不回归；硬编码分支删除 | implemented（A8 processor registry） |
| M2 | P2 CLI | `@CliCommand` 业务闭环 | planned |
| M3 | P3 codec | `@Serializable` 业务闭环 | planned |
| M4 | P4 validate | `@Validate` 业务闭环 | planned |
| M5 | P5 http | `@HttpRoute` 业务闭环 | planned |
| M6 | P6 sql | `@Sql` 业务闭环 | planned |
| M7 | P7 硬化 | 版本/缓存/API 文档/扩展流程 | planned |

顺序原则：

1. M0 不通过，不开始 M2–M6。
2. M1 不通过，不把 A8 当成平台能力。
3. M2 是第一个领域试点；通过后再开 codec/validate/http/sql。
4. M3–M6 可评估顺序，但都在同一个 `main` 上串行；不创建分支/worktree。
5. 每个里程碑结束提交并推送。

### M0 出口证据

```text
commit chain: a8b0eca0 / 6de47c5a / e121db6c / baf9719d
m0_gate.sh: PASS
xdk2.sh: 28 scenarios PASS
xdk2_extra.sh / xdk_core.sh: PASS
xdk.sh: PASS（最后 mini xdk: PASS）
```

### M1 出口证据

```text
A8Processor protocol + a8Processors(): A8Core/A8Builder/A8Delegate
expandA8Class: removed
a8_registry.sh: PASS
A8 场景：a8_core / builder / delegate / packages / negative 全 PASS
m0_gate.sh: PASS
IR v2 symbols: PASS（`annotation_ir` golden + annotation_platform symbols probe）
```

---

## 6. 每批门禁

### 平台/编译器改动

- `src/mini/build.sh`
- `xdk2.sh`
- `xdk2_extra.sh`
- `xdk_core.sh`
- 完整 `xdk.sh`（900s）
- 平台专项：IR 往返、manifest、阶段、固定点、沙箱、确定性、失败回滚、`--check-generated`

### 领域包

- 包场景（成功/失败/边界）
- 生成物 diff
- API 注解面
- `xdk2` / `xdk_core` / full `xdk.sh`
- `check_doc_naming`、`check_links`、`check_ui_scope`
- `git diff --check`

### 通用

- `python3 .agent/bin/check.py`
- `check_b4_contracts.py`、`check_b4_status.py`（涉及 B4 时）
- 无运行时反射/扫描/动态加载
- 文档状态不得把 planned 写成 implemented

---

## 7. 风险与决策

| 风险 | 处理 |
| --- | --- |
| 外部处理器引导（bootstrap） | Phase P0 先支持进程适配 + 稳定 IR；XNull 原生处理器后续再接 |
| 生成物漂移 | 入库 + `--check-generated` |
| 处理器安全 | 独立进程、沙箱、资源限制 |
| 诊断噪音 | 稳定码段 + 合并/排序/去重 |
| 新目标/值类型 | 版本化扩展；不在包级硬塞 |
| 领域包缺失 | 每个领域闭环包含包实现，不写空壳 |
| 与 B5/B6 排序冲突 | 注解平台先行；领域包按包插入，不改变包合同 |
| 泛型限制 | 1.0 保留非泛型边界；泛型扩展单独评估 |

S3 OPEN-1–OPEN-8 仍需 owner 签字；本计划默认：

- OPEN-1：混合模型（Internal A8 + External package processors）；
- OPEN-2：`AN0100–AN0199` 调度、`AN1000–AN1999` 领域；
- OPEN-3：`hash()` 暂不生成；
- OPEN-4/5：1.0 仅非泛型 Builder/Delegate；
- OPEN-6：`@Value` 浅校验，深度校验后置；
- OPEN-7：优先静态 manifest，Runtime 仅运行时发现；
- OPEN-8：每个领域注解随包实现时冻结。

---

## 8. 执行规则

- 只在 `main`；不创建分支/worktree。
- 一批 = 一个用户可见停点；批内不逐条汇报。
- 每批结束：commit、门禁、push、更新本计划状态。
- 不把“注解声明通过编译”当完成；必须处理器 + 生成物 + 业务逻辑 + 场景。
- 不先铺 73 个领域注解；按 M2–M6 闭环推进。
- 编译器内建注解只放语言级语义；领域语义进包级处理器。
- 生成物必须入库并可审计。

---

## 9. 当前下一步

1. Owner 接受本计划与 S3 OPEN 默认值。
2. 开 M0/P0：Annotation IR + Builtin Registry + Manifest + Scheduler + Generated Source + Sandbox + Diagnostics + 玩具闭环。
3. M0 通过后立即做 M1/A8 迁移。
4. 再开 M2/CLI 试点。
