# 回执：GEN-01 独立复验（QA1）

- **被测**：`pod/e2-sema` @ `b17e5cc`（含 `33d11ee`；G9 `c55dd81`、G11 `b23fa42`）
- **结果**：**PASS 26/26**（独立 26 项 harness，exit 0）
- **定点复验**：
  - G9 `static T g(T x)` → `error[RES-101]: 未定义的类型 T`（sema）
  - G11 `List<T> box = [local]; box.get(0)` → interp `4` / compiled `4`
  - 非泛型最小例 `List<Int> box = [v]; return box.get(0)` → `4`，exit 0
- **范围**：main 尚未并入 E2 codegen 单态化；main 上泛型仍报「类型 T 未支持」，本 PASS 只在 `pod/e2-sema` 成立，不覆盖 main。
- **证据**：`wt/qa-1/evidence/GEN-G11-reverify/`；完整回执 `收件箱/回执箱/CEO1/验收-M1-GEN-01.md`。
- **复现**：`bash difftest/gen01/run.sh --bin /tmp/xnull-e2gen --root ../e2-sema`
