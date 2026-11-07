# 回执：S6-XDK04（E5 组必关运行时）

- 执行位：运行时线 E5
- 基线：main `fa0d967`
- 结论：**运行时强制完成**——未 `close` 的 TaskGroup 在作用域退出/释放时一律合同 fatal；
  含无活跃任务、任务已失败两种路径；codegen 对拥有型句柄局部补作用域 release
- 证据：`evidence/S6-XDK04-E5/`；接力棒 `handoff/S6-XDK04-E5.md`

## 先红

- 基线 `fa0d967`：`test_unclosed_group_fatal` 子进程实际 exit 0 →
  `Assertion failed: (rc == 1)`（`red-task.log`）。
- codegen：未 close 的 TaskGroup 程序正常 exit 0、stderr 空
  （`red-codegen.log`）。
- 根因：`group_deinit` 只在 `active > 0` 时 fatal；codegen 不释放任务/上下文句柄局部。

## 后绿

- `group_deinit`：`closed == 0` 一律 `rt_fatal`（活跃任务/无任务/任务失败都不豁免）。
- codegen：`Context.background/withDeadline/child`、`TaskGroup.create`、`group.spawn`
  产生的局部在作用域退出发射 `rt_release`；借用/标识符不释放。
- `test_task`（含 unclosed-group、unclosed-failed-group）PASS；
  `TestS6_XDK04GroupMustClose` / `GroupCloseOK` PASS；
  `TestS5|TestS6_0[234]` 回归 PASS；全量 `go test ./internal/codegen` PASS；
  `go test ./internal/cli ./internal/interp ./internal/sema` PASS；
  `build_rt.sh` 全套 exit 0。
- XNull 实测：未 close → fatal `任务组在未关闭时释放（S5 §3.2 合同错误）`；
  已 close → exit 0。

## 边界

- XDK 包装/绑定（`tasks.x` 骨架，QA 04-2）未在本卡范围，仍挂 P2。
- E2 当前无组必关静态检查；本卡是运行时兜底，两者可并存。
- 解释器未加作用域级 TaskGroup 检查；interp 基础用例保持 PASS。
- fatal 为进程级（abort），与重复 join/任务 panic 同类。
