# 验收：S5-TASK-01（任务生命周期 / join）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main 含 S5-01/02/03（`03c1085`/`1dc8314`/`63d15e6`；按任务声明，本次**未运行任何 git 命令**）
> **时间**：2026-11-08
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/QA-S5A/`、`evidence/S5-01/green-task.log`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `spawn` 仅经组；无组任务无法创建 | **PASS**：`xdk.tasks` 只暴露 `TaskGroup.spawn`；自由 `spawn()` → `RES-101` |
| `join` 一次性 | **PASS**：重复 join → 进程 fatal（`task_join：重复 join（S5 §3.1 合同错误）`） |
| `join` Ok/Err 交付 | **PASS**：Ok 值 `42`；Err `NotFound` 原样 |
| 业务错误 kind 不降级 | **PASS**：`join` 与 `close.first_error` 均为 `NotFound` |
| `@tasks` 块约束 | **PASS**：块外 `Context` → `TY-*`（S5-05 语言面） |

**判定：PASS。** 任务只能由 `TaskGroup.spawn` 创建；`join` 一次性与错误原样交付由运行时合同测试覆盖；自由 `spawn` 在 sema 层不可见。

---

## 二、实测

### 2.1 无组任务无法创建

夹具：`evidence/QA-S5A/TASK-01/free_spawn/source.x`

```text
free_spawn.x:3:19: error[RES-101]: 未定义的名称 `spawn`（§3.3 四级顺序解析后不可见）
```

`check` rc=1。`xdk.tasks` 公开面仅有 `TaskGroup.spawn`。

### 2.2 join 一次性 / Ok / Err

`test_task.c`：

- `test_ok_and_err`：`join` Ok `42`；Err `kind=NotFound`；`close` 的 `first_error` 仍为 `NotFound`（不消费 join 结果）。
- `test_contract_fatal`：重复 `join` → 子进程 fatal，退出码非零。

`runtime-build.log`：

```text
xnull runtime fatal: task_join：重复 join（S5 §3.1 合同错误）
task tests passed (spawn/join/close/cancel/token/deadline/cleanup/timeout/root/panic)
```

### 2.3 语言面

`sema-tasks.log`：`TestS5TasksSemaSurface` PASS（`@tasks` 块内 `TaskGroup.create/spawn/join/close` 通过；块外 `Context` → `TyTasksBlock`）。`interp-tasks.log`：`TestS5TasksBasic` 三子项 PASS（SpawnJoinClose / BusinessErrorPassthrough / ContextCancel）。

---

## 三、边界

- 编译路径的 `Task/Context` 发射与 `spawn` 闭包类型推断（当前 CLI 出现 `Task<Any>`）属 S5-05/E4 语言面，不在 S5-01/02/03 runtime 卡的 TASK-01 证据内；本轮以 C ABI + sema/interp 合同测试判定。
- `first_error` v0 只给 kind，value/error 仍归 `join`（S5-01 冻结口径 §九-7）。

---

## 四、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S5A/runtime-build.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S5A/sema-tasks.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S5A/interp-tasks.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S5A/TASK-01/free_spawn/`
- 断言依据：S5 §3.1/§3.4/§4、§10 TASK-01
