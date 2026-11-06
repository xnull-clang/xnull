# S0-21a 自检结论（golden 基线）

| 验收项 | 判据 | 实测 |
| --- | --- | --- |
| 三脚本各跑 3 次 | 每次输出落盘 | 已完成（check 两布局各 3 次、ledger 3 次、res 3 次） |
| 3 次输出一致 | sha256 相同 | 是（全部一致） |
| Python 版本 / locale / cwd 记录 | env.txt | 已记录（3.12.14 / LC_ALL=C / wt/e6-toolchain） |
| 台账基线 | 行数与状态分布 | 101 行；PASS 10 / 部分 19 / 未实现 72 |
| 原地写文件已备份并还原 | `git status` 干净 | 是（before/ 有备份，已 `git checkout --`） |

## 七件套

| 文件 | 内容 |
| --- | --- |
| `command.txt` | 本次全部命令 |
| `stdout.txt` | 全部运行 stdout |
| `stderr.txt` | 全部运行 stderr（含负向） |
| `exit_code.txt` | 每次运行退出码 |
| `sha.txt` | 基线 HEAD |
| `artifact.sha256` | golden 产物逐文件哈希 |
| `acceptance.md` | 本文件 |

附加：`env.txt`、`summary.md`、`golden-check/`、`golden-ledger/`、`golden-res/`、`fixture/`、`before/`。

## 结论

golden 基线成立，可进入 S0-21b。本文件为执行侧自检，不构成验收签署。
