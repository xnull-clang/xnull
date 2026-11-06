# S0-21b 自检结论

| 验收项 | 判据 | 实测 |
| --- | --- | --- |
| res 逐字节 | sha256 相同 | 通过（正向、空表、3 组负向） |
| check 退出码/诊断 | 一致 | 通过（工作树布局、主树布局，退出码 1） |
| ledger | 101 行、分布一致、仅头部一行差异 | 通过（行数 101、PASS 10、唯一差异为生成器名） |
| 单测 | `go test ./internal/devtool ./internal/cli -count=1` | 通过 |
| 对比不合格即停 | 无差异 | 未触发 |

## 七件套

`command.txt`、`stdout.txt`、`stderr.txt`、`exit_code.txt`、`sha.txt`、`artifact.sha256`、`acceptance.md`；附加 `summary.md`、`compare/`（Python 与 Go 的原始产物与退出码）。

## 声明

执行侧自检，不构成验收签署。
