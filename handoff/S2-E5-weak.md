# 接力棒：S2-E5-weak

- **卡片ID**：S2-E5-weak（S2 审计 S2-E5-06：弱槽位目标死亡后的 UAF）
- **输入**（上游产物/条款/接口）：
  - 审计：`收件箱/门/S2审计-E5.md` §三 S2-E5-06
  - 条款：S3 §16（弱表不阻止回收、清除后槽位可复用、禁止观察已终结目标）、S2 §6.4（弱引用在 deinit 前清除）、S7 §6.2（`xrt_weak_*` 入口面）
  - 基线：`main=e97dc8e`
- **输出文件**（精确路径）：
  - `impl/runtime/rt_weak.c`（clear/destroy/get 解绑与安全检查）
  - `impl/runtime/rt.h`（内部诊断 `rt_weak_is_detached`，不进 `xrt.h` ABI）
  - `impl/runtime/test_hard.c`（第 5 段：release → `rt_quarantine_flush()` → 断言解绑 → destroy）
  - `evidence/S2-E5/red.log`、`green.log`、`summary.md`
- **commit**：`9e6de30`（pod/e5-runtime）
- **验证命令**（可复制）：
  ```bash
  cd impl/runtime && sh build_rt.sh          # 六套件 exit 0（先红：red.log / 后绿：green.log）
  cd impl && go test ./internal/codegen/... -count=1   # 全绿
  ```
- **已知缺口/风险**：
  - 目标死亡后 `rt_weak_is_detached` 为真、destroy 不再解引用目标；弱槽位仍无复用池（S2-E5-11，后置）。
  - 并发原子性未做（单线程骨架；S3 §16 的原子要求随调度器切片）。
  - 内存策略消费（BND-10/MEM-01）与 GC 根/收集（S2-E5-02/03）按指令后置。
  - deinit 发射（S2-E5-01/04/05）属 E4 codegen；本卡只对齐契约，未改 `internal/codegen/**`。
- **下一步**（谁接、做什么）：
  1. E4：按回执中的 deinit 发射契约实现（用户 deinit 体 → 字段释放；字段赋值 retain/release；handle/Bytes 字段释放）；
  2. E5：S2 实现第二卡（内存策略消费 / GC 根与收集）待派；
  3. QA1：弱槽位死亡后操作的独立复验（可复用 `test_hard` 第 5 段）。
- **上一棒**：`handoff/B0-07c.md`（numeric 前置）→ `收件箱/门/S2审计-E5.md`（审计）
- **下一棒**：`handoff/S2-E5-memory.md`（待建）→ E4 的 deinit 发射卡
- **last-green**：`9e6de30`（`build_rt.sh` 六套件 exit 0；`go test ./internal/codegen/...` 全绿；日志 `evidence/S2-E5/green.log`）
