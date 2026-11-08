# 接力棒：S3-MEM09b-E5（任务根生命周期）

- **卡片ID**：MEM-09 补口
- **输入**：`验收-S3-MEM-09.md`、QA 共享 env 探针、main/分支基线
- **输出文件**：
  - `impl/runtime/rt_task.c`（per-env root 计数）
  - `impl/runtime/test_task.c`（`test_shared_env_root`）
  - `evidence/S3-MEM09b/`
- **提交**：本次提交（仅 `pod/e5-runtime`；按 ADR-010 未写 main）
- **验证命令**：
  ```bash
  sh impl/runtime/build_rt.sh
  /tmp/xnull_test_task_mem09
  cd impl && go test ./internal/codegen -run TestS7_05
  ```
- **已知缺口/风险**：
  - 根计数表只覆盖 `rt_task.c` 的任务 env bind/unbind；GC 并发模型未改。
  - 任务 env 仍为 external root；最后一个任务退出才撤根。
- **下一步**：INTEG 合并分支；QA 重跑 `验收-S3-MEM-09` 探针。
- **上一棒**：`handoff/S3-06-E5.md`
- **last-green**：本次提交（build_rt + test_task + S7_05）
