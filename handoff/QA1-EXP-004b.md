# 接力棒：QA1-EXP-004b

- **卡片ID**：QA1-EXP-004b（黄金用例库扩容：S1 partial + S2 PASS 锚点；兼锚点台账复验）
- **输入**（上游产物/条款/接口）：
  - `XNull一致性用例台账-v1.0.0.md`（101 行；S1 partial 19 项、S2 PASS 项）
  - `XNull解决方案-第1部分-基础语法-v3.3.0.md`（S1 §2–§11）
  - 既有验收：`收件箱/回执箱/`（ERR/PKG/TUPLE/ENTRY 当前判定见各自根文件）
  - 黄金库基座：`difftest/golden/`（首卡 6 锚点，commit `5d0c0ff`）
- **输出文件**（精确路径）：
  - `difftest/golden/catalog.tsv`（新增锚点行）
  - `difftest/golden/cases/<锚点>/`（`src.x`、`stdout.txt`、`exit.txt`、`ast.txt`）
  - `handoff/QA1-EXP-004b.md`（本文件）
- **commit**：待建（本卡开工提交）
- **验证命令**（可复制）：
  ```bash
  cd /Users/vjs/Desktop/XNull-Lang/wt/qa-1
  bash difftest/golden/build-tools.sh
  bash difftest/golden/run-golden.sh
  ```
- **当前锚点状态**（main `d349f6a` 复验，证据 `evidence/QA1-anchors-2026-11-07/`）：
  - **ERR-01：PASS**（QA 用例 0 FAIL；测试期望已按 S1 §10.3 修正）
  - **PKG-01：FAIL**（F1/F3 报 RES-102 而非 RES-103；F2 `xdk.net.http` 仍报 RES-106）
  - **TUPLE-01：FAIL**（引用元素 `==`、数组元素 `==`、String `===` 3 项未修）
  - **ENTRY-01：FAIL**（`main` 重载被拒、编译路径 fatal 不终止、`c7e` rc=255、`str(Bool)` 双路径不一致）
  - **GEN-01：FAIL 24/26**（G9 签名位置、G11 列表字面量形参元素）
  - **B1-03：PASS**（main 回归 122/155 0 差异、诊断 6/6）
- **已知缺口/风险**：
  - 黄金库仍 6/29 锚点；本卡只补 S1 partial 与 S2 PASS，不重做已判 FAIL 的锚点。
  - 4 个历史 PASS 假绿（LEX-01/TYPE-01/TYPE-02/CTRL-01）仍待转缺陷卡。
  - `xnull dev board` 若未就绪，last-green 以 `handoff/last-green.tsv` 为准，不手改。
- **下一步**（谁接、做什么）：
  1. QA1：按 catalog 补 S1 partial + S2 PASS 锚点用例与 AST 快照。
  2. 实现线：PKG/TUPLE/ENTRY/GEN 未修项按各自根验收失败清单修；修完后 QA1 用 `evidence/QA1-anchors-2026-11-07/` 同口径复验。
- **上一棒**：`handoff/QA1-B1-03.md`（B1-03 PASS，commit `4ab3029`）
- **下一棒**：`handoff/QA1-EXP-004c.md`（待建）
- **last-green**：`4ab3029`（QA 线；`go test ./...` exit 0）
