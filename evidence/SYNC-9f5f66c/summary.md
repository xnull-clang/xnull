# SYNC：main@9f5f66c 合入 pod/c1-rd1

> 合并提交见 `git log -1`（非快进，父 `d82fc1b` + `9f5f66c`）。采集 2026-11-07。

## 冲突与解决

| 文件 | 类型 | 解决 |
|---|---|---|
| `evidence/SYNC-7df123d/command.txt` | add/add（两分支各自建立同名证据目录） | 内容并集：A 段（pod/c1-rd1）、B 段（pod/e2-sema） |
| `evidence/SYNC-7df123d/summary.md` | add/add | 同上 |

代码文件无冲突（`impl/internal/**` 自动合并）。

## 测试结果

| 项 | 结果 | 证据 |
|---|---|---|
| `go vet ./...` | **exit 0** | `go-vet.out` |
| `go test ./... -count=1 -timeout 300s` | **10/10 包 ok，exit 0** | `full-suite.out` |
| `bash impl/runtime/build_rt.sh` | **exit 0**（gc/hard-semantics/abi/std/资源表全通过） | `build-rt.out` |
| PKG-01 锚点矩阵 | **8/8 PASS** | `anchor-pkg01.out` |
| NEG `TestDiagMatrixS1` | **51/60**；剩余 9 项均在 sema（类型别名、保留名×6、`Array`、`true` 声明名） | `neg-matrix.out` |
| `examples/multi` 双路径 | 退出码 0/0/0；stdout 逐字节一致 | `dualpath*.out`、`dualpath.diff`（空） |

## 边界

- 本次 merge 未改 `xfront`；PKG-01 边界（CLI 未接 `AnalyzeWithDeps`）不变。
- 合并主侧新增 TUPLE-01 / ENTRY-01 / B0 证据与本锚点无重叠。
