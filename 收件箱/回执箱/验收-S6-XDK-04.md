# 验收：S6-XDK-04（tasks）

> **验收人**：QA1（独立质量线）
> **结论：BLOCKED/P2**（组必关未强制；XDK 包装/绑定未落）
> **复验点**：main 含 S6-03/04/05 合并（按任务声明；本次**未运行任何 git 命令**）
> **时间**：2026-11-08
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/QA-S6A/sema-s6.log`、`evidence/S5-01/green-task.log`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 顶层 `spawn` 不可调用 | **PASS**：`xdk.tasks` 仅组入口；自由 spawn `RES-101` |
| `TaskGroup.spawn/close` 正例 | **PASS**：sema/interp/runtime 用例 |
| `join` 返回 `Result<T,TaskError>` | **PASS** |
| 取消/超时错误面 | **PASS**：S5-02 runtime |
| 组必须关闭（作用域级强制） | **BLOCKED**：无静态/作用域检查；仅活跃任务未终结时释放 fatal |
| XDK 包装/绑定（`.xfb`/lib 单元） | **BLOCKED/P2**：`tasks.x` 仅骨架；运行时 C 为 S5 直连 |

**判定：BLOCKED/P2。** 任务运行时与 sema/interp 基础面通过，但 XDK-04 的“组关闭唯一终结路径”缺少语言级强制，且 XDK 包装/绑定未落，按计划“部分”不能签 PASS。

---

## 二、实测

- `TestS5TasksSemaSurface`：PASS（`@tasks` + `TaskGroup.spawn/join/close` 通过；块外 `Context` → `TyTasksBlock`）。
- `TestS5TasksBasic`：PASS（SpawnJoinClose / BusinessErrorPassthrough / ContextCancel）。
- `runtime-build.log`：`task tests passed (spawn/join/close/cancel/token/deadline/cleanup/timeout/root/panic)`。
- 自由 `spawn`：`RES-101`（无该入口）。

---

## 三、缺口

| # | 缺口 | 归属 |
|---:|---|---|
| 04-1 | 组未关闭退出作用域无静态检查 | S5-05/E2/E4 |
| 04-2 | `impl/lib/xdk/tasks.x` 仅骨架，未形成 XDK 包装/绑定 | E4/E5 |
| 04-3 | `Task<Any>` 类型推断/编译路径未闭合 | E2/E4 |

---

## 四、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S6A/sema-s6.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S5-01/green-task.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S5-02/summary.md`
- 断言依据：S6 §4/§10 XDK-04；S5 §3/§4
