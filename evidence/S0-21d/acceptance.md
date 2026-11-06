# S0-21d 自检结论

| 验收项 | 判据 | 实测 |
| --- | --- | --- |
| go vet | 0 | 0 |
| go test 全量 | 全绿 | 仅 codegen 超时（P0-1，已知），其余绿 |
| 9 示例双路径 | 输出与退出码一致 | 9/9 一致 |
| 两布局守门 | 退出码 0 | 主树 0、公开布局 0 |
| Python 文件 | 0 | 0 |
| Python 引用 | 0（登记例外除外） | 1 处冻结头，已登记 |

## 七件套

`command.txt`、`stdout.txt`、`stderr.txt`、`exit_code.txt`、`sha.txt`、`artifact.sha256`、`acceptance.md`；附加 `go-vet.out`、`go-test.out`、`dualpath/`、`bin/`、`check-main.out`、`check-public.out`、`summary.md`。

## 声明

执行侧自检，不构成验收签署。
