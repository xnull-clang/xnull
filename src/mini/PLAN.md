# Mini 0.3.0 / M10-T0 计划

> Mini 0.2.0 / M9-CUT 小里程碑已完成并归档。
> 旧计划：`src/mini/archive/2026-11-18-m9cut/`
> 本文件从 2026-11-18 起作为唯一活动计划。

## 1. 起点

- 默认引擎：`mini`
- 保留引擎：`legacy`（显式 `--engine=legacy` / `XNULL_ENGINE=legacy`，oracle）
- 已完成：Mini 1.0、M9-PAR 47 个正向场景、M9-CUT、26 个回归、selfhost、m8
- 当前版本：`mini 0.2.0`；下一目标版本：`mini 0.3.0`
- 当前仍不完整：全部 T0 XDK、部分语言边界、完整 Resource/Context、M7-F1
  Result/companion

本里程碑不重做 M0–M9；只在现有 mini/legacy 双引擎基础上补齐 T0 面和剩余语言边界。

## 2. 里程碑目标

**M10-T0：让 mini 覆盖全部 T0 XDK 的可运行面，并闭合当前已知语言/FFI 边界。**

完成标准：

- 每个 T0 包至少有一个可运行场景；导入、构建、运行、错误路径均有证据。
- 新增全 T0 `m10_parity.sh`，legacy/mini 的 stdout/stderr/退出码为 `diff=0`；
  现有 `m9_parity.sh` 47 个场景继续全绿。
- 26 个现有回归、selfhost、m8 冷启动路径保持全绿。
- 默认 mini、legacy 可显式选择；legacy 不删除。
- 性能不出现明显回退（相对 0.2.0 基准不超过 20%；基准曲线随版本更新）。
- `mini 0.3.0` 版本、验收记录、tag 和 README 同步完成。

**不在本里程碑范围：** T1/T2 全量包、完整语言规范、删除 legacy、泛化性能排名。

## 3. T0 包矩阵

| 包 | 当前状态 | 本里程碑验收 |
| --- | --- | --- |
| `xdk.errors` | 基础面已完成 | 错误分类/wrap/mapErr 场景 |
| `xdk.runtime` | 基础面已完成 | diagnose/exit/clock 正负例 |
| `xdk.meta` | 基础面已完成 | 版本/平台/build 信息场景 |
| `xdk.log` | 源码与场景缺失 | Logger/Level/sink 最小场景 |
| `xdk.config` | 源码与场景缺失 | 配置快照/env allowlist 场景 |
| `xdk.text` | `text/full` 已接入 | UTF/format/regex/parse 回归 |
| `xdk.bytes` | 运行时能力已有，包面未产品化 | Bytes/ByteBuffer 端到端场景 |
| `xdk.collections` | 源存在，受泛型函数类型/空 Map 字面量阻塞 | List/Map/Set/排序/分组场景 |
| `xdk.math` | 已接入 | 数值/Int128 当前面场景 |
| `xdk.time` | 已接入 | Instant/DateTime/时区场景 |
| `xdk.io` | 源码与场景缺失 | Reader/Writer/Stream 最小场景 |
| `xdk.fs` | 源码缺失；File/Dir 在 Sys 面部分存在 | 路径/文件/目录/原子写场景 |
| `xdk.sys` | File/Dir/Process 部分完成 | Env/platform/资源/上下文场景 |
| `xdk.tasks` | 空骨架 | Task/TaskGroup/Context 场景 |
| `xdk.sync` | 空骨架 | Mutex/Channel/Atomic 场景 |
| `xdk.cli` | 源码与场景缺失 | Args/Command/退出码场景 |

另有 **完整 Sys `Resource.x`/`Context` 子单元** 作为跨包切面处理，不单独建 T1 计划。

## 4. 工作包

### M10-P0：清单、场景与边界（先做）

- 确定每个 T0 包的真实源码位置、依赖和当前可运行最小场景。
- 建 `src/mini/tests/m10_*` 场景骨架；缺源码的包先登记为“等待”，不写空实现。
- 定 `m10_parity.sh` 的包→场景映射和 base/full 模式表。
- 产出：矩阵、场景清单、失败清单；不改语言核心。

### M10-P1：collections 打开

- 泛型函数类型参数的最小支持面。
- 空 `Map`/容器字面量与类型推断。
- `List`/`Map`/`Set` 的排序、分组、去重接口。
- 验收：`xdk.collections` 场景 + legacy 差分；相关负例。

### M10-P2：tasks / sync

- 从运行时已有 task/sync 原语接出 `Task`、`TaskGroup`、`Context`、`Mutex`、`Channel`、`Atomic*`。
- 并发最小场景要覆盖成功、取消、超时和错误返回。
- 验收：tasks/sync 场景 + 无泄漏/无挂起 + legacy 差分。

### M10-P3：Sys Resource / Context

- 完整 Sys 模式载入 `Resource.x` 和 Context 子单元。
- 资源存在/读取/计数/缺失错误路径；Context 取消与超时映射。
- 验收：base/full 两种 Sys 模式 + 资源工程 + 负例。

### M10-P4：Result / companion / FFI

- 完成 M7-F1 的 Result/companion 语义。
- 自定义 `.xfb` 的 Result 返回、companion、借出/归还、errorCode。
- 验收：`xfb_error` 扩展场景 + 负例；legacy 差分仅在能力重叠处比较。

### M10-P5：缺失 T0 包

按依赖顺序补 `xdk.log`、`xdk.config`、`xdk.bytes`、`xdk.io`、`xdk.fs`、`xdk.cli` 的
源码/适配面和最小场景。每包独立提交，失败不阻塞其他包。

### M10-P6：语言边界

- 泛型函数类型参数完整边界。
- 空容器/字面量推断一致性。
- 闭包环境回收/lifetime。
- 编译诊断、退出码和负例与 M8-P5 口径保持一致。

### M10-P7：全 T0 差分与性能

- `m10_parity.sh`：全部 T0 正向场景，base/full，stdout/stderr/退出码。
- 保留 `m9_parity.sh` 作为回归门。
- 更新性能曲线：至少覆盖 25M/50M/100M/200M 和自举构建。
- 性能回退 >20% 作为阻塞项。

### M10-P8：版本与收口

- 版本 `mini 0.3.0`，更新 `MILESTONES.md`、README、RESUME。
- tag、dev/main、归档和 clean worktree。
- legacy 保留；删除或默认切换需单独批准。

## 5. 顺序与门禁

```text
P0 清单/场景
  ↓
P1 collections ──┐
P2 tasks/sync ───┤
P3 Resource/Context ┤
P4 Result/FFI ───┤
P5 缺失 T0 包 ───┘
  ↓
P6 语言边界
  ↓
P7 全 T0 差分 + 性能
  ↓
P8 版本/收口
```

- P0 未完成前不进入 P1。
- P1/P4/P5 可并行，但共享 CGen/FFI 时必须串行合并。
- 每个工作包必须有代码、场景、回归、提交；没有场景的能力保持“等待”。
- 每个包完成后更新 `RESUME.md` 和本表状态。

## 6. 当前已知阻塞

- `xdk.collections`：泛型函数类型参数、空 Map 字面量。
- `xdk.tasks`/`xdk.sync`：源码为空骨架，需要运行时桥接。
- 完整 Sys：`Resource.x`/`Context` 尚未随 `xdk.sys` 完整载入。
- M7-F1：Result/companion 未全。
- 语言边界：泛型函数类型参数、闭包环境回收仍有缺口。
- 性能：legacy 对完整 `src/mini/main.x` 的 xparser 仍有超时边界（oracle 侧）。

## 7. 归档

- 旧计划：`src/mini/archive/2026-11-18-m9cut/`
- 里程碑记录：`src/mini/MILESTONES.md`
- 旧计划不再修改；只在归档目录保留历史上下文。
