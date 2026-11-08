# B2-04f 证据：默认回退 go + 超时护栏

## 结论

- **默认模式改回 `go`**：未设置 `XNULL_FRONTEND` 即 Go oracle；E3 修复解释器递归前不得默认 `xnull`。
- **硬超时护栏**：解释器 runner 改为独立进程（外部二进制或自身 `xnull` CLI 的 `run --interp` 子进程），
  `exec.CommandContext` 硬超时，默认 **5s/文件**（`XNULL_SELFHOST_TIMEOUT` 可调）。
- 进程内 runner 已移除（`interp.Run` 不可取消，避免 goroutine 泄漏）。
- 超时行为：显式 `xnull` 返回 **B2-002** 诊断；`auto` 超时回退 Go，不阻塞工具链。
- 缓存仍优先：命中时直接反序列化，不启动 runner。

## 验证

| 项 | 结果 |
| --- | --- |
| `TestXNullTimeoutReturnsB2002` | PASS（200ms 超时，fake runner `sleep 5`） |
| `TestAutoTimeoutFallsBackToGo` | PASS（超时后 AST 与 Go oracle 一致） |
| `TestASTCacheMemoryAndDisk` | PASS（第二次不调用 runner；清内存后命中磁盘） |
| `go test ./internal/codegen -count=1`（默认 go） | `ok … 58.1s`（绿） |
| `go test -p 4`（排除未跟踪 `impl/Tests/`） | 仅既有 `devtool` 台账 golden 红 |

`codegen-default.out/.time`、`frontbridge-test.out`、`go-test-p4.out` 为原始输出。

## 复跑

```bash
cd impl
go test ./internal/frontbridge -run 'TestXNullTimeout|TestAutoTimeout|TestASTCache' -count=1 -v
go test ./internal/codegen -count=1
go test -p 4 ./...
```

## 边界

- 只改 `impl/internal/frontbridge/`、handoff 说明与证据。
- 未改 `xparser.x`/`xlex.x` 语义，未改 `internal/xfront`。
- 解释器递归（`callMethodFrom→dispatchCall`）归 E3；修复前默认保持 `go`。
