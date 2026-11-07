# 接力棒：QA1-GEN-01（终判）

- **卡片ID**：QA1-GEN-01（GEN-01 独立 26 项验收）
- **输入**（上游产物/条款/接口）：
  - 台账 GEN-01；S1 §8.1–§8.4
  - 被测：`pod/e2-sema` @ `c969a83`（merge `131c244`）
- **输出文件**（精确路径）：
  - `difftest/gen01/cases.json`（26 项，QA1 自写）
  - `difftest/gen01/run_gen01.py`（双路径 accept / 单路径 reject）
  - `difftest/gen01/run.sh`
  - 回执：`收件箱/回执箱/CEO1/验收-M1-GEN-01.md`
- **commit**：见本次提交
- **验证命令**（可复制）：
  ```bash
  cd /Users/vjs/Desktop/XNull-Lang/wt/qa-1
  bash difftest/gen01/run.sh --bin <xnull-c969a83> --root <同提交导出树>
  ```
- **结果**：**FAIL 24/26**
  - G9：`static T g(T x)` 签名位置未由 sema 报 `RES-101`，落到 codegen `类型 T 未支持`。
  - G11：`List<T> box = [local]; box.get(0)` 编译路径 `fatal: 容器下标越界`（exit 134），解释路径正常。
  - G11 根因非泛型：`List<Int> box = [v]`（形参元素）+ `box.get(0)` 在 main `4d1495c` 同样崩溃；`[4]` 与局部变量元素正常。
- **口径差异**：E2 `TestGEN01` 在本提交 26/26 PASS（QA1 已复跑确认）；其 G9 用例只覆盖函数体位置，G11 用例不调用 `get`。
- **已复核项**：G5c 实际 TY-101、G10 实际 RES-102，按条款“必须拒绝”判 PASS；G12 用 `Any f = identity<Int>` 构造，按解析拒绝判 PASS。
- **下一步**（谁接、做什么）：
  1. 董事会：裁定 GEN-01 门判定（建议：主体认可，G9/G11 开缺陷卡，不阻塞合入）。
  2. 前端线 E2：修 sema 签名位置；修列表字面量形参元素。
  3. QA1：修复后复跑 `difftest/gen01/run.sh`。
- **上一棒**：`handoff/QA1-B1-03.md`
- **下一棒**：`handoff/QA1-EXP-004b.md`（待建）
- **last-green**：见 `handoff/last-green.tsv`（board 生成）。
