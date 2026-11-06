# S0-21c 自检结论

| 验收项 | 判据 | 实测 |
| --- | --- | --- |
| build_rt.sh 调 `xnull dev res` | 无 python | 已改，`go run ./cmd/xnull dev res` |
| 删除三个 .py | `find impl -name '*.py'` 为空 | 0 |
| 文档/台账头部切换 | 无旧工具名（台账头允许的差异除外） | README、xdk-design、ledger-restructure、台账头均已切换 |
| build_rt.sh 通过 | 退出码 0 | 0 |

## 七件套

`command.txt`、`stdout.txt`、`stderr.txt`、`exit_code.txt`、`sha.txt`、`artifact.sha256`、`acceptance.md`；附加 `summary.md`、`build_rt.{out,err,exit}`。

## 声明

执行侧自检，不构成验收签署。
