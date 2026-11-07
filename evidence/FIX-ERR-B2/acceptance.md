# ERR-01-B2 自检：诊断位置非零

- 结论：DONE。`LocalDeclStmt` 清理体诊断不再 0:0；新增全诊断码行列非零守门。
- 红：`before/sema.out`，exit 1；`ERR-205 位置 = 0:0，期望 2:11`。
- 绿：`after/sema-target.out` / `after/sema-target-postmerge.out`，exit 0。
- 全量：`after/sema-all.out` exit 0；`after/go-test-all-postmerge.out` exit 0。
- 覆盖：RES/DA/TY/GEN/ERR 共 31 个可触发诊断码逐码断言 `Line>0 && Col>0`；RES-104（注册表无重名）、RES-108/RES-110/RES-111（多文件加载器）不在 sema 单文件可触发面。
- 边界：`LocalDeclStmt.Pos()` 仍为零；修复采用 `Type` 节点（`defer Int x` → `2:11`），AST 全局位置基线条款另属 S9。
