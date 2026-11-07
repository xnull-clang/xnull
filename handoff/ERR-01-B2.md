# 接力棒：ERR-01-B2

- **卡片ID**：ERR-01-B2（前端线 E2；EXP-003 诊断位置）
- **输入**（上游产物/条款/接口）：
  - `收件箱/专家评审/董事会处置-v1.0.0.md` EXP-003：诊断位置 0:0
  - 历史红源：`evidence/M1-ERR-01-fix2/before/`（`qa.x:0:0: error[ERR-205]`）
  - 上一棒：`handoff/GEN-01.md`（GEN 26/26，commit `20e3d838ea45`）
- **输出文件**（精确路径）：
  - `impl/internal/sema/error.go`（`LocalDeclStmt` 清理体诊断改用 `Type` 节点，指向 `Int`）
  - `impl/internal/sema/diagpos_test.go`（全诊断码位置非零守门 + ERR-205 精确 2:11）
  - `evidence/FIX-ERR-B2/`（red/green/全量原始输出）
  - `handoff/ERR-01-B2.md`（本棒）
- **commit**：`9adbc334d739`（error.go 回退 + 守门测试）；代码/测试前置 `041d8f807d7f`；merge main 后 HEAD `dc7c950`
- **验证命令**（可复制）：
  ```bash
  cd impl
  go test ./internal/sema/ -run 'TestAllDiagPositionsNonZero|TestERR205CleanupLocalDeclPosition' -v -count=1
  go test ./internal/sema/ -count=1
  go test ./... -count=1 -timeout 300s
  ```
  结果：目标测试 PASS；sema 全量 PASS；全仓 exit 0。
- **已知缺口/风险**：
  - 守门覆盖 31 个单文件可触发诊断码；RES-104（注册表无重名）、RES-108/RES-110/RES-111（多文件加载器）不在 `sema.Analyze` 单文件面，由 codegen/multifile 测试覆盖。
  - `LocalDeclStmt.Pos()` 本身仍为零；本卡采用 `Type` 节点定位。把“AST 节点必须携带源位置”写成 S9 基线条款仍待办（EXP-003 建议③）。
  - 未改既有测试期望。
- **下一步**（谁接、做什么）：
  - **谁接**：前端线 E2 owner。
  - **做什么**：`PKG-01` 复验（含 TUPLE-01 复验）；按 QA 口径核对 `status.tsv` 与根回执。
  - **验证命令**：
    ```bash
    cd impl
    go test ./internal/sema/ ./internal/interp/ ./internal/codegen/ -count=1
    go test ./... -count=1 -timeout 300s
    ```
  - QA1 复验 ERR-01 B2（本卡证据）；通过后 SSOT 更新 ERR-01 状态。
- **上一棒**（路径或 commit）：`handoff/GEN-01.md`；`20e3d838ea45`
- **下一棒**（路径或 commit）：`handoff/PKG-01.md`（待建）
- **last-green（前端线）**：`9adbc334d739`（全仓 `go test ./... -count=1 -timeout 300s` exit 0）
