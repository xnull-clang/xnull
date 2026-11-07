# 回执：S2-E2-GATE-01（诊断码表 + 无静默降级审计）

- **状态**：`DONE`（sema 面）
- **诊断码表**：`evidence/S2-GATE/diag-codes.md`（RES/DA/TY/GEN/ERR 全量，含典型触发与位置保证）。
- **无静默降级审计**：`evidence/S2-GATE/silent-audit.md`（扫描 codegen/interp “未支持”分支；区分语言非法构造 vs E4/E5 能力边界）。
- **本次修复**：`new P()`（协议）、`new E()`（枚举）由 check rc=0 → `TY-226` 拒绝；`new abstract`/注解 new 已在前序卡。
- **红→绿**：`evidence/S2-GATE/before/sema.out` exit 1 → `after/sema.out` exit 0。
- **验证**：`go test ./internal/sema/ ./internal/xfront/ ./internal/interp/ ./internal/codegen/ -count=1` 四包全绿。
- **不写 QA 门报告**；GATE 门报告由 QA/董事会按本表汇编。
