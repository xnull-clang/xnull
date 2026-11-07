# 接力棒：S5-SCHED01

- **卡片ID**：S5-SCHED01（载体池 + 伴生执行器；QA SCHED-01 FAIL 修复）
- **输入**：S5 §2.2/§7.3；QA 判定（单载体 FIFO、`.unaware` 无伴生执行器）；
  `handoff/S5-01.md`/`S5-02.md`；基线 `04a11c4`
- **输出文件**：
  - `impl/runtime/rt_task.c`（载体池、伴生执行器、future）
  - `impl/runtime/xrt.h`（`xrt_blocking_fn`/`xrt_future`/`xrt_companion_submit/wait`）
  - `impl/runtime/test_task.c`（载体池/伴生执行器/取消等待用例）
  - `impl/docs/runtime-contract.md`（SCHED-01 增补）
  - `evidence/S5-SCHED01/{summary.md,red-compile.log,red-carrier-old.log,green-carrier-new.log,green-task.log,green-build_rt.log}`
- **commit**：见本次提交（仅 `pod/e5-runtime`）
- **验证命令**：
  ```bash
  cd impl/runtime && sh build_rt.sh
  # 载体探针对比：旧 rc=6/hit=0，新 rc=0/hit=1
  ```
- **已知缺口/风险**：
  - 载体池解决“占唯一载体”；真正的 M:N 栈挂起未做（需 S3-06 并发 GC 前提）。
  - `.unaware` 路由需 E4 发射面调用 companion（运行时 API 已就绪）。
  - 多载体并发执行仍受 GC 单线程结构限制；测试避免并行 GC 变更。
- **下一步**：E4 接 companion 路由；S6-02 回执；S5-06 验收（SCHED-01 清单/压力）。
- **上一棒**：`handoff/S5-02.md`（`1dc8314`）
- **下一棒**：`handoff/S5-06.md`（待建）
- **last-green**：本次提交（task/sync/build_rt 全绿）
