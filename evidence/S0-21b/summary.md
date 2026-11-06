# S0-21b Go 实现与 golden 对比

## 基线变更

采集 golden 时 HEAD=`ad70f19`；随后按董事会指示 `git merge main --ff-only` 快进到 **`fe19e7c`**（仅改 `.gitignore` 锚定与新增 `impl/cmd/xnull/main.go`）。合并后已用 Python 复跑三脚本，输出与 golden **完全一致**（`compare/py-*`），确认基线变更不影响 golden。

## 交付

| 文件 | 说明 |
| --- | --- |
| `impl/internal/devtool/devtool.go` | 布局探测（工作区/公开双布局）、EN 目录定位、行切分等公共函数 |
| `impl/internal/devtool/specs.go` | `check`：五项守门，输出格式与旧脚本逐字节对齐 |
| `impl/internal/devtool/ledger.go` | `ledger`：抽取、去重、统计、状态旁表，101 行 |
| `impl/internal/devtool/resources.go` | `res`：资源遍历、名字校验、C 源生成 |
| `impl/internal/cli/dev.go` | `xnull dev check\|ledger\|res` 分派与退出码 |
| `impl/internal/cli/cli.go` | 注册 `dev`（命令表 + 用法） |
| `*_test.go` | 逐字节 golden 测试、负向用例、统计固化（101 / PASS 10） |

`impl/cmd/xnull/main.go` 由 main 带入（fe19e7c），本卡未新建。

## 对比结果

| 项 | 判据 | 结果 |
| --- | --- | --- |
| res 正向 | sha256 相同 | `2f88b9314adf77fc9a731202627d042242f7ebfe71e76c244afa9326b3c95949`（Python = Go = golden） |
| res 空表 | sha256 相同 | `ca00666cdbebd979f91d9243a699cfb6eb5a38da748970def0270c2f1698d5ce` |
| res 负向（子目录/含空格/缺目录） | 退出码 2 + stderr 逐字节 | 三项 `diff` 均为空 |
| check 工作树布局 | stdout + 退出码 | `diff` 为空；退出码 1 |
| check 主树布局（只读） | stdout + 退出码 | `diff` 为空；退出码 1 |
| ledger 文件 | 仅头部生成器名称一行 | 唯一差异：`impl/tools/gen_ledger.py` → `xnull dev ledger`（第 3 行） |
| ledger stdout | 完全一致 | `diff` 为空 |
| ledger 规模 | 101 行 / PASS 10 | 一致 |

## 已知的有意差异（非 golden 覆盖路径）

1. `check` 出错（找不到索引/读文件失败）时，Go 返回 1 并输出 `xnull: <错误>`；旧脚本是 Python traceback（退出码 1）。诊断文本不同，仅发生在异常路径。
2. `findLayout` 自 cwd/参数向上查找索引；旧脚本用自身脚本路径定位。正常在仓库根调用时结果一致。
3. 资源子目录**仍被拒绝**（与 golden 一致）。放开子目录是 S0-25，不在本卡。

## 结论

逐字节/逐行对比通过，未触发硬闸，可进入 S0-21c。
