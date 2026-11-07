# 接力棒：S6-XDK04-E5

- **卡片ID**：S6-XDK04（QA `验收-S6-XDK-04` BLOCKED 的 E5 运行时侧：组必关）
- **输入**：`收件箱/回执箱/验收-S6-XDK-04.md`、S5 §3.2/§4、S3 §17、main `fa0d967`
- **输出文件**：
  - `impl/runtime/rt_task.c`（`group_deinit` 未 close 一律 fatal）
  - `impl/runtime/test_task.c`（unclosed-group / unclosed-failed-group 子进程用例）
  - `impl/internal/codegen/codegen.go`（拥有型句柄局部作用域 release）
  - `impl/internal/codegen/s504.go`（`taskValueOwned`）
  - `impl/internal/codegen/s6_xdk04_test.go`（未 close fatal / close OK）
  - `impl/docs/runtime-contract.md`
  - `evidence/S6-XDK04-E5/`
- **commit**：见本次提交（`pod/e5-runtime`）；main 合并 sha 见回复
- **验证命令**：
  ```bash
  cd impl/runtime && sh build_rt.sh
  cd impl && go test ./internal/codegen -count=1 -run 'TestS6_XDK04'
  cd impl && go test ./internal/codegen -count=1 -run 'TestS5|TestS6_0[234]'
  # 未 close：fatal；close：exit 0
  xnull run /tmp/xdk04_forgot.x
  xnull run /tmp/xdk04_ok.x
  ```
- **已知缺口/风险**：
  - XDK 包装/绑定（`impl/lib/xdk/tasks.x` 骨架、QA 04-2）未落，仍挂 P2。
  - E2 无「组必关」静态检查；运行时是兜底，不是静态保证。
  - 借用/别名句柄不 release（避免重复释放）；Task 句柄按不可复制票据使用。
  - 解释器未加作用域级 TaskGroup 检查；interp 基础用例保持 PASS。
- **下一步**：E2 评估静态「组必关」约束；E4/E5 补 tasks XDK 包装；
  QA 重跑 XDK-04 矩阵；main 合并按单会话互斥执行。
- **上一棒**：`handoff/S6-XDK06-E5.md`（`fa0d967`）
- **下一棒**：QA `验收-S6-XDK-04` 复验
- **last-green**：本次提交（test_task + codegen XDK04 + S5/S6 回归 + build_rt 全绿）
