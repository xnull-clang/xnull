# S0-27 自检结论

| 验收项 | 判据 | 实测 |
| --- | --- | --- |
| mtime 打乱 3 次结果一致 | stdout 相同、退出码相同 | 通过（sha256 三次相同） |
| 真实内容变更仍报滞后 | 退出码 1 + 点名文件 | 通过 |
| 干净 clone 两布局通过 | 退出码 0 | 工作区布局 0、公开布局 0 |
| 不依赖 mtime | 代码中无 ModTime 比较 | 通过（`checkEnSync` 已移除） |
| 回归 | devtool/cli 单测 | 通过 |

## 七件套

`command.txt`、`stdout.txt`、`stderr.txt`、`exit_code.txt`、`sha.txt`、`artifact.sha256`、`acceptance.md`；附加 `summary.md`、`bin/xnull`、`go-test.out`、`clone-*.out`、`check-*.out`。

## 声明

执行侧自检，不构成验收签署（QA1 必签）。
