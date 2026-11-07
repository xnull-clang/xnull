# 回执：M1-NEG-01

- **卡片ID**：M1-NEG-01（负例矩阵 60 项）
- **状态**：`DONE`｜`TestDiagMatrixS1` **60/60 PASS**
- **commit**：`3749bd390b14`（NEG-1.3 余项 + 保留名）；merge main `15f52e4` 后分支 HEAD `fb9e329`（main 合并由 COO 执行）
- **修复**：
  - `xfront.Reserved` 消费点：`async/await/yield/unsafe/extern/macro` 作标识符报 SYN-101；`true/false/null` 作声明名报 SYN-101。
  - `type Foo = Int` 类型别名、`Array xs` 类型名由 sema 拒绝。
  - 证据：`evidence/NEG-3/`（`neg_test.go`、60 项原始输出、command）。
- **验证**：
  - `go test ./Tests -run '^TestDiagMatrixS1$' -count=1 -v` → 60/60 PASS，exit 0。
  - `go test ./internal/sema/ ./internal/xfront/ -count=1` → 全绿。
- **边界**：类型别名当前经“未定义类型”路径拒绝，专属诊断文案可后续优化；PKG F1/F2/F3 仍未修（下一步）。
- **通知**：E3/QA1 复跑请求已投 `收件箱/E3/请求-NEG-01复跑.md`、`收件箱/QA1/通知-NEG-01验收.md`。
