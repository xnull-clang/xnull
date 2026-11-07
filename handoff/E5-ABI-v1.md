# 接力棒：E5-ABI-v1

- **卡片ID**：E5-ABI-v1（ABI v1 候选冻结标注 + EXP-010/011/012 规范草案）
- **输入**（上游产物/条款/接口）：
  - EXP-010/011/012 原文：`收件箱/专家评审/评审意见-2026-11-07-v1.0.0.md`
  - 董事会处置：`收件箱/专家评审/董事会处置-v1.0.0.md`（三者均“接受”，owner=E5）
  - 现行 ABI：`impl/runtime/xrt.h`、`impl/docs/runtime-contract.md`
  - 母本：`XNull解决方案-第2部分-对象编程-v3.3.0.md`、`XNull解决方案-第5部分-运行时任务与并发-v1.0.0.md`
- **输出文件**（精确路径）：
  - `impl/docs/runtime-contract.md`（新增 A0：候选冻结/转正判据）
  - `impl/runtime/xrt.h`（头注释状态行）
  - `收件箱/E5/规范草案/XNull解决方案-第2部分-对象编程-v3.4.0-草案-EXP-010.md`
  - `收件箱/E5/规范草案/XNull解决方案-第5部分-运行时任务与并发-v1.1.0-草案-EXP-011.md`
  - `收件箱/E5/规范草案/ABI-v1-候选冻结-EXP-012-2026-11-07.md`
- **commit**：`0304002`（pod/e5-runtime）
- **验证命令**（可复制）：
  ```bash
  cd impl/runtime && sh build_rt.sh                       # exit 0
  cd impl && go test ./internal/codegen/ffi/ -count=1      # ok
  git diff HEAD~1 --stat -- '*第2部分*' '*第5部分*'          # 空：母本未改
  ```
- **已知缺口/风险**：
  - ABI 转正判据未满足：numeric 变体（Bytes/`@errorCode`/`Option<handle>`/Bool）仍属 E4/E2 缺口，证据 `evidence/B0-07c/numeric-after.log`。
  - EXP-010/011 草案待董事会终审；终审前不得替换母本或改索引权威条款。
  - 草案基于母本全文复制（v3.4.0 / v1.1.0），后续母本升版需 rebase 草案。
- **下一步**（谁接、做什么）：董事会终审 EXP-010/011；E4 清 numeric 四项后通知 E5 复跑；通过后 E5 将 A0 与 `xrt.h` 同步改“稳定 v1”，并在 `ABI-v1-候选冻结-EXP-012-2026-11-07.md` 追加转正记录。
- **上一棒**：`handoff/B0-07c.md`（commit `e83f93c`）
- **下一棒**：待定（B0-07c numeric 复验 / B2 前置）
- **last-green**：`0304002`（`build_rt.sh` exit 0；`go test ./internal/codegen/ffi/` exit 0，日志 `evidence/B0-07c/line-green.log`）
