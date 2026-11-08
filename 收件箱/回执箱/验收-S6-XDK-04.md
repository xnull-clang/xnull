# 验收：S6-XDK-04（tasks）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `44d7681`（含 E5 XDK-04 组必关；按任务声明，本次**未运行任何 git 命令**）
> **时间**：2026-11-08
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/QA-XDK0410/XDK-04/`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 顶层 `spawn` 不可调用 | **PASS**：`xdk.tasks` 仅组入口；自由 spawn `RES-101` |
| `TaskGroup.spawn/close` 正例 | **PASS**：`TestS5TasksBasic` / sema |
| 组必须 close（作用域退出强制） | **PASS**：`TestS6_XDK04GroupMustClose`：未 close → `任务组在未关闭时释放` fatal，code≠0 |
| 显式 close 后可退出 | **PASS**：`TestS6_XDK04GroupCloseOK` code=0 |
| 取消/超时错误面 | **PASS**：S5-02 runtime |
| 运行时组必关 | **PASS**：`runtime.log` `group-must-close` 子项通过 |

**判定：PASS。** 组资源化与 close 唯一终结路径已落地：未关闭组退出作用域触发合同诊断，显式 close 正常退出。

---

## 二、实测

- `codegen-xdk04.log`：
  - `TestS6_XDK04GroupMustClose` PASS（stderr 含 `任务组在未关闭时释放`，code≠0）。
  - `TestS6_XDK04GroupCloseOK` PASS（code=0）。
- `runtime.log`：`task tests passed (... group-must-close ...)`。
- sema/interp：`TestS5TasksSemaSurface`、`TestS5TasksBasic` PASS。

---

## 三、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-XDK0410/XDK-04/codegen-xdk04.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-XDK0410/XDK-04/runtime.log`
- 断言依据：S6 §4/§10 XDK-04；S5 §3.2/§4
