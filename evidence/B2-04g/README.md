# B2-04g 证据：可取消的外部解释器 runner

## 实现

- 新增 `impl/cmd/xnselfhost`：`xnselfhost <program.x> [args...]`，用 `xfront` 加载 `xparser.x`/`xlex.x`，
  再用 `interp.Run` 执行；程序 stdout/stderr 与 `xnull run --interp` 一致。
- `frontbridge` 自动构建/缓存 helper（`go build ./cmd/xnselfhost`，缓存键含 helper 源码 + `go.mod` + 版本），
  用 `exec.CommandContext` 调用，默认 **5s** 硬超时（`XNULL_SELFHOST_TIMEOUT`）。
- 超时一律回退 Go 并记录 **B2-002**（`frontbridge.LastIssue()`）；显式 `xnull` 的其它失败仍报 B2-001。
- 不再依赖进程内 runner；原生 parser 仅显式 `XNULL_NATIVE_XPARSER` 可选（暂缓）。
- 默认模式 = xnull 管线（helper + 磁盘缓存）；helper 不可用/失败时回退 Go。

## 实测

主线临时工作树（含 interp `Bytes`；提交本身仍在 pod）：

```bash
XNULL_FRONTEND=xnull XNULL_FRONTBRIDGE_CACHE=<cold> \
  xnull dev test --parallel 4 ./internal/codegen      # 冷缓存
```

| 场景 | 墙钟 | 结果 |
| --- | ---: | --- |
| xnull 冷缓存 `./internal/codegen` | **102.7s** | 绿 |
| xnull 热缓存 `./internal/codegen` | **94.2s** | 绿 |
| 默认（xnull 管线）全量 `dev test --parallel 4 ./...` | **167.3s** | 绿 |
| 本工作树默认 `go test ./internal/codegen`（helper 缺 Bytes → Go 回退） | 67.1s | 绿 |

- `TestS2BND08CrossPackageNew/Static` 现在触发 5s 超时 → 回退 Go → 绿（B2-002 已记录）。
- B2：L1 `40/40`、L2 `42/42`。
- `go test -p 4`（排除未跟踪 `impl/Tests/`）：仅既有 `devtool` 台账 golden 红。

## 说明

- 主线临时工作树为运行 `dev test --parallel` 打了两个**未提交**的临时补丁：
  `knownFlags` 增补 `--parallel/--shard/--fast/--merge`；`dev_test.go` 用法串同步 `|test`。
  二者属 main 基线既有不一致，不属于本卡提交。
- 本工作树 interp 缺 `Bytes`，helper 首次运行失败后按进程缓存标记，后续直接 Go 回退。

## 原始输出

`codegen-xnull-cold.*`、`codegen-xnull-warm.*`、`full-default.*`、`codegen-pod-default.*`、
`b2-l1.out`、`b2-l2.out`、`frontbridge-test.out`、`go-test-p4.out`。

## 边界

- 只改 `impl/cmd/xnselfhost`、`impl/internal/frontbridge/`、handoff 与证据。
- 未改 interp/xparser 语义，未改 `internal/xfront`。
