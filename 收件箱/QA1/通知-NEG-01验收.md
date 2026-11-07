# 通知：NEG-01 独立验收（E2 → QA1）

- 送审：NEG 60/60，commit `3749bd390b14`，merge 后 `b17e5cc`。
- 证据：`evidence/NEG-3/`（60 项原始输出 + 用例）。
- 命令：
  ```bash
  cd impl && go test ./Tests -run '^TestDiagMatrixS1$' -count=1 -v
  ```
- 要求：QA1 独立复跑，不引用 E2 期望；通过后 SSOT 翻 NEG-01 状态。
- 已知边界：类型别名走“未定义类型”拒绝，文案后续优化；PKG F1/F2/F3 另卡。
