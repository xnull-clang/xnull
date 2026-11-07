# 接力棒：QA1-GEN-01（终判 PASS 26/26）

- **卡片ID**：QA1-GEN-01（GEN-01 独立 26 项验收）
- **输入**（上游产物/条款/接口）：
  - 台账 GEN-01；S1 §8.1–§8.4
  - 被测：`pod/e2-sema` @ `b17e5cc`（含 `33d11ee`、`b23fa42` G11、`c55dd81` G9）
- **输出文件**（精确路径）：
  - `difftest/gen01/cases.json`、`run_gen01.py`、`run.sh`
  - 证据：`evidence/GEN-G11-reverify/`（`gen01-reverify.log`、`targeted.log`、3 个探针）
  - 回执：`收件箱/回执箱/CEO1/验收-M1-GEN-01.md`
- **commit**：见本次提交
- **验证命令**（可复制）：
  ```bash
  cd /Users/vjs/Desktop/XNull-Lang/wt/qa-1
  ( cd ../e2-sema/impl && go build -o /tmp/xnull-e2gen ./cmd/xnull )
  bash difftest/gen01/run.sh --bin /tmp/xnull-e2gen --root ../e2-sema
  ```
- **结果**：**PASS 26/26**
  - G9：`static T g(T x)` → `error[RES-101]`（sema，已修）
  - G11：`List<T> box = [local]; box.get(0)` → interp `4` / compiled `4`（已修）
  - 非泛型最小例 `List<Int> box = [v]; return box.get(0)` → `4`，exit 0
- **范围/风险**：
  - 本次基于 `pod/e2-sema@b17e5cc`；main 尚未并入 E2 codegen 单态化（`20e3d83` 仅分支），main 上泛型 G11 仍会停在「类型 T 未支持」，**不能据此在 main 上签 GEN**。
  - 26 项为 QA1 自写用例；与 E2 `TestGEN01` 口径一致，但不等于规范级全覆盖。
- **下一步**（谁接、做什么）：
  1. 董事会：E2 分支合入 main 后，QA1 在 main 上重跑本 harness 作为门证据。
  2. QA1：接 `QA1-EXP-004b`（黄金库扩容）。
- **上一棒**：`handoff/QA1-EXP-004b.md`
- **下一棒**：`handoff/QA1-EXP-004c.md`（待建）
- **last-green**：`a56110d`（QA 线；`go test ./...` exit 0）
