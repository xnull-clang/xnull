# B2-04 证据：差分接入与工具链切换

## 结论

- `check/run/build` 的解析入口统一为 `internal/frontbridge.ParseUnit`：Go `xfront` 仅作诊断 oracle 与回退，正常文件 AST 来自 `xparser.x`。
- 全语料三层差分（Go 测试内）：`L1 41 + L2 39 + L3 3 = PASS 83`（`diff.out`）。
- 双路径行为一致：`check`（含负例）、`run --interp`、`build` 产物输出逐字节相同（`dual-check.out`、`dual-run-build.out`）。
- 受影响包测试全绿：`frontbridge/cli/codegen/xdkcheck/xfront/interp/sema`（`go-test-touched.out`）。
- 全仓 `go test`（排除未跟踪的 `impl/Tests/`）仅剩 1 项既有红：`devtool` 台账 golden（基线 HEAD 同样红，SSOT 只读，见 `pre-existing-red.out`）。

## 复跑

```bash
cd impl
XNULL_B2_DIFF=1 XNULL_SELFHOST_BIN=/tmp/xnull-b2 \
  go test ./internal/frontbridge -run TestB2Differential -count=1 -v

XNULL_SELFHOST_BIN=/tmp/xnull-b2 bash ../ci/run.sh --only 04
```

`/tmp/xnull-b2` 是带完整 interp（`Bytes`）的主线快照构建；本工作树 `internal/interp` 尚缺 `Bytes`，
进程内执行器不可用，`auto` 会回退 Go。桥接同时支持外部二进制与进程内执行器，主分支合入后进程内自动生效。

## 文件

| 文件 | 说明 |
| --- | --- |
| `diff.out` | Go 测试内三层差分：`B2 差分 PASS=83` |
| `frontbridge-test.out` | 反序列化往返、模式/回退、oracle 诊断一致性 |
| `dual-check.out` | `check` 双路径（go vs xnull）退出码/输出一致 |
| `dual-run-build.out` | `run --interp` 与 `build` 产物输出一致 |
| `go-test-touched.out` | 受影响包全绿 |
| `go-test-all.out` | 全仓测试（排除未跟踪 `impl/Tests/`）结果 |
| `pre-existing-red.out` | 基线 HEAD `0d25ba8` 既有红复现 |
| `ci-04.out` | CI 第 04 项：`src/bin` 存在时 PASS |

## 已知边界

- `xnfmt.x` 的 AST dump 触发 64 层 `(depth-limit)`，传输会丢子树；`auto` 按失败回退 Go oracle，AST 完整。
  严格 `XNULL_FRONTEND=xnull` 下该文件返回 `B2-001`，属显式模式的可预期结果。
- `auto` 对 >16KB 源文件直接回退 Go（性能护栏，`XNULL_FRONTEND_MAX_BYTES` 可调）。
- `devtool` 台账 golden 是 SSOT 产物，本卡不手改；`xnfmt` 幂等扫描已排除 B2 故意非法的 `lex_neg`/`parser_neg` 负例目录。
