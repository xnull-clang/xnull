# S6-XDK04（E5）：TaskGroup 组必关运行时强制

- 卡片：QA `验收-S6-XDK-04` BLOCKED 的 E5 运行时侧（组必关）
- 基线：main `fa0d967`
- 结论：未 `close` 的组在作用域退出/释放时一律合同 fatal（含无活跃任务、任务已失败）；
  拥有型任务/上下文句柄局部在作用域退出 release，使「离开作用域」真正触发诊断

## 先红（基线 `fa0d967`）

- 运行时：`test_unclosed_group_fatal` 断言子进程应 fatal，实际子进程 exit 0 →
  `Assertion failed: (rc == 1)`（`red-task.log`）。
- codegen：未 close 的 `TaskGroup` 程序正常退出 0、stderr 空
  （`red-codegen.log: TestS6_XDK04GroupMustClose`）。
- 根因：
  1. `group_deinit` 只在 `active > 0` 时 fatal；无活跃任务时静默释放；
  2. codegen 对 `TaskGroup`/`Context`/`Task` 局部不发射 `rt_release`，
     作用域退出不触发 deinit，运行时强制没有入口。

## 实现

### 运行时（`impl/runtime/rt_task.c`）

`group_deinit`：
```c
if (!g->closed) {
    if (g->active > 0) rt_fatal("任务组在未关闭且仍有活跃任务时释放（S5 §3.2 合同错误）");
    rt_fatal("任务组在未关闭时释放（S5 §3.2 合同错误）");
}
```
- `close` 是唯一合法终结路径（S5 §3.2）；无活跃任务、任务失败都不豁免。
- 任务失败仍由 `close` 返回首个非取消错误（既有 `test_ok_and_err` 覆盖）。

### codegen 句柄所有权（`impl/internal/codegen/codegen.go` / `s504.go`）

- 任务/上下文句柄局部在**拥有型**初始化时登记作用域退出 release：
  `Context.background()`、`Context.withDeadline()`、`Context.child()`、
  `TaskGroup.create()`、`group.spawn()`。
- 标识符、`null`、`ctx.token()` 等借用形态不 release，避免重复释放。
- 这样 `TaskGroup g = TaskGroup.create(c)` 在作用域退出会 `rt_release(g)`；
  未 close → `group_deinit` 合同诊断。

## 后绿

| 场景 | 结果 | 证据 |
| --- | --- | --- |
| `test_task`（含 unclosed-group / unclosed-failed-group） | PASS | `green-task.log` |
| `go test ./internal/codegen -run TestS6_XDK04` | 2/2 PASS | `green-codegen.log` |
| `go test ./internal/codegen -run 'TestS5|TestS6_0[234]'` | PASS | `green-codegen-regression.log` |
| `go test ./internal/codegen`（全量） | PASS | `green-full-codegen.log` |
| `go test ./internal/cli ./internal/interp ./internal/sema` | PASS | `green-cli-interp-sema.log` |
| `sh impl/runtime/build_rt.sh` | 全套 exit 0 | `green-build_rt.log` |
| 未 close 的 XNull 程序 | fatal `任务组在未关闭时释放` | `green-forgot-close.log` |
| 已 close 的 XNull 程序 | exit 0 | `green-closed-ok.log` |

## 与 E2 sema 的关系

- E2 当前没有「组必关」静态检查；本卡提供运行时兜底，不依赖静态分析。
- 若 E2 后续加静态约束（如局部 TaskGroup 必须 `close`），运行时的 fatal 仍是
  逃过静态检查/动态路径的最终防线；两者不冲突。
- `impl/lib/xdk/tasks.x` 仍是包骨架；XDK 包装/绑定（QA 04-2）不在本卡范围，
  继续挂 E4/E5 的 P2。

## 边界

- fatal 是进程级（`rt_fatal` → abort），与既有重复 join/任务 panic 同类；
  CLI 观测为信号终止（`xnull run` 报 255）。
- 借用/别名句柄不释放，避免误伤；Task 句柄按 S5 §3.1「不可复制票据」使用。
- 解释器路径仍是同步模型，本卡未加作用域级 TaskGroup 检查；XDK-04 的 interp
  基础用例（spawn/join/close）保持 PASS。
