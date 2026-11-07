# 接力棒：QA1-EXP-004

- **卡片ID**：QA1-EXP-004（黄金用例库：规范构造 × 路径矩阵 + AST 快照）
- **输入**（上游产物/条款/接口）：
  - `XNull一致性用例台账-v1.0.0.md` 的 PASS/部分行（29 个锚点）
  - ADR-001/002/003；EXP-004（`收件箱/专家评审/董事会处置-v1.0.0.md`）
  - 集成 main `548a06d`（B0-01/02/03/04/05 已入）
- **输出文件**（精确路径）：
  - `difftest/golden/catalog.tsv`
  - `difftest/golden/cases/{LEX-01,STMT-01,TYPE-01,TYPE-02,EXPR-01,CTRL-01}/{src.x,stdout.txt,exit.txt,ast.txt}`
  - `difftest/golden/astdump/main.go`（QA overlay 工具，不入生产树）
  - `difftest/golden/build-tools.sh`、`difftest/golden/run-golden.sh`
- **commit**：`5d0c0ff`（代码/用例；本接力棒随后单独提交）
- **验证命令**（可复制）：
  ```bash
  cd /Users/vjs/Desktop/XNull-Lang/wt/qa-1
  bash difftest/golden/build-tools.sh
  bash difftest/golden/run-golden.sh
  ( cd impl && go test ./... -count=1 -timeout 300s )
  ```
  `run-golden.sh` 当前输出：PASS=2 / FAIL=4；台账覆盖 6/29。
- **已知缺口/风险**：
  - 仅覆盖 6/29 个 PASS+部分锚点；S1 partial（ERR/BLD/TUPLE/PKG/ENTRY/DET）与 S2 PASS（FIELD/INH）未建例。
  - 已发现 4 个 PASS 假绿：LEX-01（进制/下划线/Char 编译路径失败）、TYPE-01（`??` 编译）、TYPE-02（可空字段 `??` 编译）、CTRL-01（标签语句编译）。
  - AST 快照以当前 parser 输出为基线，尚未做“规范形态”人工审校第二轮。
  - 未覆盖诊断负例矩阵、变异测试、跨文件/multi 路径；示例集已排除，仅作回归。
- **下一步**（谁接、做什么）：QA1 接 EXP-004b——补 S1 partial 与 S2 PASS 锚点用例；首批 4 个假绿转缺陷卡给前端/自举线；之后再开 ERR/PKG/TUPLE/ENTRY 复验。
- **上一棒**：main `548a06d`（`wt/qa-1` ff 合并）
- **下一棒**：`handoff/QA1-EXP-004b.md`（待建）
- **last-green**：`5d0c0ff`（QA 线；`go test ./... -count=1 -timeout 300s` exit 0，2026-11-07 14:20）
