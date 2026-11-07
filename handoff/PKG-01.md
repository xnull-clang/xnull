# 接力棒：PKG-01

- **卡片ID**：PKG-01（前端线 E2；包导入 + PKG/TUPLE 复验）
- **输入**（上游产物/条款/接口）：
  - 台账 `XNull一致性用例台账-v1.0.0.md` PKG-01 / TUPLE-01
  - `XNull解决方案-第1部分-基础语法-v3.3.0.md` §3.1–§3.5、§2.11
  - 上一棒：`handoff/ERR-01-B2.md`（DONE，commit `9adbc334d739`）
- **输出文件**（精确路径）：
  - `impl/internal/sema/xdk.go` / `pkg.go`（导入/符号/环诊断）
  - `impl/internal/sema/pkg_test.go` / `xdk_test.go`（正反例）
  - `impl/internal/codegen/multifile*.go`（跨包加载，若需）
  - `handoff/PKG-01.md`（本棒收工更新）
- **commit**：待实现（E2 owner 集成）
- **验证命令**（可复制）：
  ```bash
  cd impl
  go test ./internal/sema/ -run 'TestPKG|TestImport|TestAlias|TestTuple' -v -count=1
  go test ./internal/sema/ ./internal/interp/ ./internal/codegen/ -count=1
  go test ./... -count=1 -timeout 300s
  ```
- **已知缺口/风险**：
  - RES-104 未消歧简单名当前无重名符号可触发；RES-108/RES-110/RES-111 属多文件加载器。
  - TUPLE-01 已 11/11 自检，需 QA 复验后翻状态；不得手改 `status.tsv`。
- **下一步**（谁接、做什么）：
  - **谁接**：前端线 E2 owner。
  - **做什么**：先红后绿复验 PKG-01 全项；随后 TUPLE-01 复验；产出证据到 `evidence/M1-PKG-01/e2-final`。
  - **验证**：见上方命令。
- **上一棒**（路径或 commit）：`handoff/ERR-01-B2.md`；`9adbc334d739`
- **下一棒**（路径或 commit）：`handoff/QA1-PKG-01.md`（待建，独立验收）
- **last-green（前端线）**：`9adbc334d739`
