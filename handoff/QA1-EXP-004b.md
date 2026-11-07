# 接力棒：QA1-EXP-004b

- **卡片ID**：QA1-EXP-004b（E2 合并后复验：GEN-01 26 项 / NEG-01 60 项 / PKG-01 逐项）
- **状态**：**准备完成，等待 E2 合并入 main**（2026-11-07）
- **输入**（上游产物/条款/接口）：
  - S1 §3.5（包/导入/别名）、§8（泛型）、§0.6/§1.3（负例矩阵）；台账 GEN-01 / NEG-01 / PKG-01。
  - main `20f101d`：含 G11 修复 `b23fa42`（`List<T>` 形参元素 `get` 的清理顺序）。
  - `pod/e2-sema`：含 G9 `c55dd81`（签名位置 `RES-101`）、NEG `3749bd3`（NEG 60/60），**尚未入 main**。
  - 用例来源：`difftest/gen01/cases.json`（QA1 自写 26 项）；`pod/c3-rd3:impl/Tests/neg_test.go`（60 项）；`evidence/M1-PKG-01-qa/qa2_independent_test.go`（49 子项）+ `evidence/QA1-anchors-2026-11-07/pkg/`（F1/F2/F3）。
- **输出文件**（精确路径）：
  - `difftest/anchors/run-gen.sh`、`run-neg.sh`、`run-pkg.sh`、`run-all.sh`、`README.md`
  - `difftest/anchors/cases/qa2_pkg_accept_test.go`、`difftest/anchors/cases/pkg/`
  - 复验证据：`evidence/QA1-verify-<YYYYMMDD>/`（按 `--out` 生成）
  - 根验收：`收件箱/回执箱/验收-M1-GEN-01.md`、`验收-M1-NEG-01.md`、`验收-M1-PKG-01.md`
- **commit**：见本次提交（harness + 本接力棒）
- **验证命令**（可复制）：
  ```bash
  cd /Users/vjs/Desktop/XNull-Lang/wt/qa-1
  # E2 合并后，一次跑完三项
  bash difftest/anchors/run-all.sh --sha main --out evidence/QA1-verify-$(date +%Y%m%d)
  # 单项
  bash difftest/anchors/run-gen.sh --sha main
  bash difftest/anchors/run-neg.sh --sha main
  bash difftest/anchors/run-pkg.sh --sha main
  ```
- **当前基线（main `20f101d`，E2 合并前）**：
  - **GEN-01：不可判**。main 无 `impl/internal/codegen/generics.go`，10+ 项 accept 在编译路径报 `codegen：类型 T 未支持`；不能把该结果当作 GEN 回归。
  - **NEG-01：51/60**。9 FAIL：`neg-0.6-41`、`neg-1.3-01..06`、`neg-1.3-08`、`neg-1.3-09`（全 sema，与 `handoff/PKG-01.md` 一致）。
  - **PKG-01：46/49 + CLI 0/4**。F1/F3 `RES-102`（期望 `RES-103`）；F2 `RES-106`（期望接受）；c1 同 F1。
  - 对照：`pod/e2-sema@1f960b0` 上 GEN 已 26/26（`evidence/GEN-G11-reverify/gen01-reverify.log`）。
- **复验通过标准**：
  1. GEN-01：`GEN-QA 26/26`，exit 0。
  2. NEG-01：`PASS=60 / FAIL=0`，exit 0。
  3. PKG-01：Go 子项 `PASS=49 / FAIL=0` 且 CLI `4/4`（F1/F3/c1 → `RES-103`；F2 接受）。
  4. 三项全绿才在根 `收件箱/回执箱/` 写 PASS；任一失败按项列 FAIL 与本轮原始日志路径，不得用“0 FAIL”摘要覆盖。
- **已知缺口/风险**：
  - GEN 的 codegen 单态化只在 `pod/e2-sema`；E2 合并前在 main 复跑无意义。
  - NEG 用例文件仅存于 `pod/c3-rd3`；脚本以 `--neg-ref`（默认 `pod/c3-rd3`）注入，不改被测树。
  - PKG 的 F1/F3/c1 当前先触发 `RES-102`（多文件加载器把同名类并入同一包），该行为本身可能另属缺陷；本卡只按 §3.5 判 FAIL。
  - TUPLE-01 F1/F2 已在 `e91e33c` 修复（interp 8/8），不在本卡范围；TUPLE 编译路径仍无 codegen。
- **下一步**（谁接、做什么）：
  1. E2：把 `pod/e2-sema`（含 `c55dd81`、`3749bd3`）合入 main，回报 merge sha。
  2. QA1：以 merge sha 跑 `run-all.sh`；全绿后写三份根验收并更新台账锚点。
  3. 若未全绿：按失败项开缺陷卡回 E2，保留逐项证据。
- **上一棒**：`handoff/QA1-B1-03.md`（B1-03 PASS，`4ab3029`）
- **下一棒**：`handoff/QA1-EXP-004c.md`（复验结论后建）
- **last-green**：`4ab3029`（QA 线；全仓 `go test ./...` exit 0）；本轮不翻转，等 E2 合并。
