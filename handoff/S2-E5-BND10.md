# 接力棒：S2-E5-BND10

- **卡片ID**：S2-E5-BND10（策略→运行行为：GC 分配、scan、退出收集）
- **输入**（上游产物/条款/接口）：
  - 上一卡：`S2-E5-MEM01`（`9e90d4e`，清扫顺序 deinit→释放）
  - 策略来源：`impl/internal/sema/policy.go`（§15.1 判定表，`Strategy.Policy/RefCycle`）
  - 条款：S2 §2.7/§15.1/§15.6；S3 §8/§15.6/§188；`runtime-contract.md` P-09
  - 基线：`main=fa6d821`
- **输出文件**（精确路径）：
  - `impl/internal/codegen/build.go`（AnalyzeWith → Strategies → codegen）
  - `impl/internal/codegen/codegen.go`（`EmitCWithStrategies`、`policy`、GC 所有权守卫、退出收集、容器 GC 元素拒绝）
  - `impl/internal/codegen/classes.go`（GC 分配、scan 钩子、deinit 字段过滤）
  - `impl/internal/codegen/classes_expr.go`（`classIsGC`/`classPtrName`、GC 字段赋值）
  - `impl/internal/codegen/mem_bnd10_test.go`（4 例：环收集、GC 持 ARC、分配种类、纯值保持 ARC）
  - `evidence/S2-E5-BND10/{summary.md,S2-E5-BND10-red.log,green-cycle.log,green-mixed.log,green-generated-c.txt,tests.log,build_rt.log}`
- **commit**：见本卡提交（pod/e5-runtime；未合并 main）
- **验证命令**（可复制）：
  ```bash
  cd impl && go build -o /tmp/xnull-mem ./cmd/xnull
  XNULL_RUNTIME=impl/runtime /tmp/xnull-mem build <cycle.x> -o /tmp/cycle && /tmp/cycle
  cd impl && go test ./internal/codegen/ -run 'TestBND10|TestS2MEM' -count=1 -v
  ```
- **已知缺口/风险**：
  - 只在退出时 `rt_gc_collect`；无中途安全点与全局根登记（SINGLE-01/ENUM-01 前置）。
  - 容器元素为 GC 类型显式拒绝（B2 引用语义容器）。
  - 容器中介的引用环未被策略判定为 GC（E2 的 `classRefCycle` 只看直接类字段）。
  - 派生类自定义 deinit 仍被 sema `TY-203` 拒绝（E2）。
  - stack 分配未实现（§2.7 许可优化）。
- **下一步**（谁接、做什么）：
  1. E5 后续卡：安全点/根登记（与调度器切片一起）→ 中途收集；
  2. E2：deinit 覆写与容器环判定；
  3. E4：B2 引用语义容器 / struct 端到端（不阻塞本卡）。
- **上一棒**：`handoff/S2-E5-MEM01.md`（commit `9e90d4e`）
- **下一棒**：E5 安全点/根登记卡（待派）
- **last-green**：本卡 commit（`build_rt.sh` exit 0；`TestBND10*`+`TestS2MEM*` 9 例 PASS；环/混合程序输出正确）
