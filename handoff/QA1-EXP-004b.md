# 接力棒：QA1-EXP-004b

- **卡片ID**：QA1-EXP-004b（E2 合并后复验：GEN-01 26 项 / NEG-01 60 项 / PKG-01 逐项）
- **状态**：**三项已复验完成**（2026-11-07，main `7887618`）；根验收已落盘
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
- **复验结果（main `7887618`，含合并 `3174618`）**：
  - **GEN-01：PASS 26/26**（G9 `RES-101`、G11 输出 `4` exit 0）。
  - **NEG-01：PASS 60/60**（0 FAIL、0 panic、0 静默接受）。
  - **PKG-01：PASS 49/49**（F1/F3 → `RES-103`；F2 接受 `import xdk.net.http`）。
  - 证据：`evidence/QA1-verify-2026-11-07/`；根验收：`收件箱/回执箱/验收-M1-{GEN,NEG,PKG}-01.md`。
- **合并前基线（main `20f101d`，留档）**：GEN 不可判（无 `generics.go`）；NEG 51/60；PKG 46/49。
- **复验通过标准（已达成）**：
  1. GEN-01：`GEN-QA 26/26`，exit 0。
  2. NEG-01：`PASS=60 / FAIL=0`，exit 0。
  3. PKG-01：Go 子项 `PASS=49 / FAIL=0`（sema `AnalyzeWithDeps` 面）。
  4. 三项证据与根验收均已落盘；CLI 导入诊断缺口单独挂账（见下）。
- **已知缺口/风险**：
  - **CLI 导入诊断未接线**：去掉无关 `lib.b` 后，`lib.a.X as P` + `lib.a.Y as P` 在 `xnull build` 下静默通过；跨包同名类仍 `RES-102`。属 `LoadUnits` 包前缀/CLI 未调 `AnalyzeWithDeps`，不是 F1/F2/F3 回归；建议另开卡。
  - NEG 用例文件仅存于 `pod/c3-rd3`；脚本以 `--neg-ref`（默认 `pod/c3-rd3`）注入，不改被测树。
  - TUPLE-01 F1/F2 已在 `e91e33c` 修复（interp 8/8），不在本卡范围；TUPLE 编译路径仍无 codegen。
  - main `7887618` 的 board 记录 codegen `TestFFIHandleOpenClose` 红，与本卡三项无关，登记待 E4/E5。
- **下一步**（谁接、做什么）：
  1. 董事会：按三项 PASS 更新 M1 锚点（GEN/NEG/PKG）。
  2. E2/E4：开卡处理 CLI 导入诊断未接线 + 加载器包前缀（§五）。
  3. QA1：等 TUPLE/ENTRY 编译路径与 NEG codegen 面补齐后另卡复验。
- **上一棒**：`handoff/QA1-B1-03.md`（B1-03 PASS，`4ab3029`）
- **下一棒**：`handoff/QA1-EXP-004c.md`（待建）
- **last-green**：`7887618`（QA 三项：GEN 26/26、NEG 60/60、PKG 49/49）
