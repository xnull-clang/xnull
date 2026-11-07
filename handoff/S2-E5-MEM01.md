# 接力棒：S2-E5-MEM01

- **卡片ID**：S2-E5-MEM01（MEM-01 对象生命周期 + MEM-02 混合引用图，运行时侧）
- **输入**（上游产物/条款/接口）：
  - 审计：`收件箱/门/S2审计-E5.md`（MEM-01/MEM-02/BND-10）
  - 条款：S2 §6.4、§15.8；S3 §8/§14/§15/§15.6/§16
  - 基线：`main=fa6d821`
- **输出文件**（精确路径）：
  - `impl/runtime/rt_gc.c`（清扫顺序：deinit → scan 释放 ARC 引用）
  - `impl/runtime/test_gc.c`（第 6 段：GC deinit 内 ARC 字段有效）
  - `impl/internal/codegen/mem01_test.go`（deinit 顺序 / stack 判定 / struct 拒绝 / 环判定）
  - `evidence/S2-E5-MEM01/{summary.md,red-sweep-order.log,green-build_rt.log,mem01-tests.log}`
- **commit**：见本卡提交（pod/e5-runtime；未合并 main）
- **验证命令**（可复制）：
  ```bash
  cd impl/runtime && sh build_rt.sh
  cd impl && go test ./internal/codegen/ -run 'TestS2MEM' -count=1 -v
  ```
- **已知缺口/风险**：
  - 派生类自定义 deinit 被 sema `TY-203` 拒绝（S2 §6.4 要求允许）→ E2。
  - stack 分配未实现（判定就绪；§2.7 为许可优化）。
  - 容器中介的引用环未被策略识别（`List<Node>` 自引用）→ E2。
  - struct 端到端 codegen 未实现 → E4。
- **下一步**（谁接、做什么）：E4/E5 的 BND-10 卡消费策略（GC 分配 + scan + 收集）；E2 修 deinit 覆写与容器环判定。
- **上一棒**：`handoff/S2-E5-deinit.md`（复签 `beba3f6`）
- **下一棒**：`handoff/S2-E5-BND10.md`（待建）
- **last-green**：本卡 commit（`build_rt.sh` 六套件 exit 0；`TestS2MEM*` 4 例 PASS，日志 `evidence/S2-E5-MEM01/`）
