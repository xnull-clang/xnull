# 接力棒：ERR-01-B2

- **卡片ID**：ERR-01-B2（前端线 E2；EXP-003 诊断位置）
- **输入**（上游产物/条款/接口）：
  - `收件箱/专家评审/董事会处置-v1.0.0.md` EXP-003：诊断位置 0:0
  - 历史缺口：`LocalDeclStmt` 诊断 `Line/Col` 为 0；需全诊断码行列非零守门
  - 上一棒：`handoff/GEN-01.md`（GEN 26/26，commit `20e3d838ea45`）
- **输出文件**（精确路径）：
  - `impl/internal/sema/sema.go` / `ty.go` / `assign.go`（诊断位置修正）
  - `impl/internal/sema/diagpos_test.go`（行列非零守门）
  - `handoff/ERR-01-B2.md`（本棒收工更新）
- **commit**：待实现（E2 owner 集成）
- **验证命令**（可复制）：
  ```bash
  cd impl
  go test ./internal/sema/ -run 'TestDiagPos|TestErr01' -v -count=1
  go test ./internal/sema/ -count=1
  go test ./... -count=1 -timeout 300s
  ```
- **已知缺口/风险**：
  - 需先枚举全部 sema 诊断码（RES/DA/TY/GEN/ER）并构造触发用例；禁止只修 `LocalDeclStmt` 一处。
  - 不改既有测试期望；新增守门测试必须断言 `Line>0 && Col>0`。
  - 与 `status.tsv` 无直接关系；ERR-01 端到端仍受 B1/B2 其他项影响。
- **下一步**（谁接、做什么）：
  - **谁接**：E2 owner。
  - **做什么**：先写红测（当前 0:0 触发失败），再修位置来源，最后全量+守门绿。
  - **验证**：见上方命令；另跑 `go vet ./...`。
- **上一棒**（路径或 commit）：`handoff/GEN-01.md`；`20e3d838ea45`
- **下一棒**（路径或 commit）：`handoff/PKG-01.md`（待建，PKG/TUPLE 复验）
- **last-green（前端线）**：`20e3d838ea45`
