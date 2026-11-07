# BND-07 / BND-08 / BND-12 复验摘要（main 47fedb8）

- 日期：2026-11-07
- main：`47fedb8ad1659925af04a677a9e82b861c2dffcd`
- 二进制：`/tmp/xnull-s2-47fedb8`（由 main 47fedb8 的 `impl/cmd/xnull` 构建）
- binary sha256：`46a22fee8a5523ef1a6061be2a4c73d3adb8c474762a930efa69850c56d14150`
- Go：`go version go1.27.3 darwin/amd64`

## 判定

| 锚点 | 判定 | 说明 |
|---|---|---|
| BND-07 | **FAIL** | `singleton` 未进 sema 名称空间；正例 `RES-101`，只读/前向引用未拒绝 |
| BND-08 | **FAIL** | `factory` 未进 sema 名称空间；正例 `RES-101`，不可见 Target/泛型实参/非类型 Target 未拒绝 |
| BND-12 | **PASS** | R01–R03 全部拒绝且带码/位置；泛型类单态化双路径通过 |

## 证据

- `evidence/S2-QA/BND-07-47fedb8/matrix.tsv`
- `evidence/S2-QA/BND-08-47fedb8/matrix.tsv`
- `evidence/S2-QA/BND-12-47fedb8/matrix.tsv`
- 回归：`evidence/S2-QA/BND-07-47fedb8/regression/`、`evidence/S2-QA/BND-12-47fedb8/regression/`

## 回归

- `go test ./internal/sema ./internal/codegen ./internal/xfront ./internal/cli ./internal/interp -count=1`：全绿。
- `go vet ./...`：exit 0。
- `go test ./... -count=1`：1 红，`internal/devtool TestBuildLedgerRepoGoldenScale`（台账 PASS 13，golden 18），与本三项无关，阻断 GATE-01。
