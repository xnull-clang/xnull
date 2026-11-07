# 回执：ERR-01-B2（诊断位置）

- **卡片ID**：ERR-01-B2（前端线 E2；EXP-003）
- **状态**：`DONE`
- **commit**：`9adbc334d739`（`error.go` 位置回退 + 全诊断码守门）；前置 `041d8f807d7f`；merge main `dc7c950`
- **修复**：
  - `LocalDeclStmt` 清理体诊断不再 `0:0`：`defer Int x = 1` → `2:11`（指向 `Int`）；类型缺失时回退到 `defer/errdefer` 关键字位置。
  - 新增 `impl/internal/sema/diagpos_test.go`：31 个单文件可触发诊断码逐码断言 `Line>0 && Col>0`；ERR-205 精确位置 2:11。
- **验证**：
  - 红：`evidence/FIX-ERR-B2/before/sema.out`，exit 1，`ERR-205 位置 = 0:0`。
  - 绿：`after/sema-target-postmerge.out` exit 0；`go test ./internal/sema/ -count=1` exit 0。
  - 全仓：`go test ./... -count=1 -timeout 300s` exit 0。
- **证据**：`evidence/FIX-ERR-B2/`（before/after/command/acceptance）。
- **接力棒**：`handoff/ERR-01-B2.md`（七字段）；下一棒 `handoff/PKG-01.md`。
- **边界**：RES-104/RES-108/RES-110/RES-111 属注册表/多文件加载器，不在 sema 单文件守门面；AST 全局位置条款仍待 S9。
