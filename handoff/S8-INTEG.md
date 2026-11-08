# 接力棒：S8-INTEG

- **卡片ID**：S8 集成收口（build 端到端：锁/配置/资源/插件）
- **输入**：S8 §5.2–§5.6、§8；E4 的 `cli/manifest.go` 生命周期；E6 的 `resman/plugin/repro/config`
- **输出文件**：`impl/internal/cli/manifest.go`、`impl/internal/cli/manifest_integration.go`、`manifest_integration_test.go`；`impl/internal/devtool/resources.go`（`GenerateResourcesFromMap`）；`impl/internal/resman`（`**` 语义修正）；`impl/internal/manifest/{deps,graph}.go`（groupId 点号路径）
- **commit**：见 `git log --oneline -- impl/internal/cli/manifest_integration.go`
- **验证命令**：
  ```bash
  cd impl && go test ./internal/cli -run TestManifestIntegration -v
  cd impl && go test ./internal/cli ./internal/manifest ./internal/resman ./internal/plugin ./internal/repro ./internal/config ./internal/devtool -count=1
  ```
- **已知缺口/风险**：全量 `go test ./...` 因 codegen/codegen-ffi 在途为红（main 基线同样红，非本卡）；配置键 schema、插件执行、test 资源并入、`.xmeta` 与 E4 字段对齐未完成。
- **下一步**：E4 对齐 `.xmeta` 字段表并接插件执行；配置 key registry；全量测试转绿后由 INTEG 合并。
- **上一棒**：`handoff/S8-09-E6.md`。
- **下一棒**：待派。
