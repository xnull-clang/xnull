# 接力棒：QA1-GEN-01

- **卡片ID**：QA1-GEN-01（GEN-01 独立验收，26 项）
- **输入**（上游产物/条款/接口）：
  - 台账 GEN-01（`XNull一致性用例台账-v1.0.0.md`）；S1 §8.1–§8.4
  - 检查表：`evidence/M1-GEN-01-sema/checklist-source.md`（只取 26 项定义，不引用 E2 测试/结论）
  - 被测：`pod/e2-sema` @ `20e3d83`（E2 声称 26/26；**尚未 merge main**）
- **输出文件**（精确路径）：
  - `difftest/gen01/cases.json`（26 个独立用例，QA 自写）
  - `difftest/gen01/run_gen01.py`（双路径 accept / 单路径 reject）
  - `difftest/gen01/run.sh`
- **commit**：Pending（本条提交）
- **验证命令**（可复制）：
  ```bash
  cd /Users/vjs/Desktop/XNull-Lang/wt/qa-1
  bash difftest/gen01/run.sh --bin <xnull> --root <repo>
  ```
  merge 后默认：`bash difftest/gen01/run.sh`（自行构建 main xnull）。
- **已知缺口/风险**：
  - **尚未 merge**：当前 main `4d1495c` 无 GEN 集成；以下为 `20e3d83` 分支预检，不是终判。
  - 分支预检：**GEN-QA 24/26**。
    - **G9 FAIL**：函数外使用 `T` 被 codegen 报 `类型 T 未支持`，不是 §8.1 要求的“未定义”（RES-101）。
    - **G11 FAIL**：`T local` + `List<T> box = [local]` 解释路径通过，编译路径 `fatal: 容器下标越界`（exit 134）。
  - G5c 实际诊断 TY-101（非 GEN-103），按“零候选必须编译错误”判 PASS；G10 实际 RES-102（非 SYN-101），按“必须拒绝重名”判 PASS。
  - G12 用 `Any f = identity<Int>` 构造，按解析拒绝判 PASS；若 E2 的 26 项口径不同，需董事会裁定。
- **下一步**（谁接、做什么）：E2 合入 main 后，QA1 立即跑 `difftest/gen01/run.sh`，回复 `GEN-QA PASS/FAIL <x/26>`；若仍 24/26，提交 G9/G11 缺陷。
- **上一棒**：`handoff/QA1-B1-03.md`（commit `e06df57`）
- **下一棒**：`handoff/QA1-GEN-01-final.md`（merge 后终判）
- **last-green**：`4e5bc64`（QA 线；最近一次全量测试绿）
