# S0-21a golden 基线摘要

## 环境（固定）

| 项 | 值 |
| --- | --- |
| 日期（UTC） | 见 env.txt |
| cwd | `/Users/vjs/Desktop/XNull-Lang/wt/e6-toolchain` |
| HEAD | `ad70f1976b6ed08fd59be59b1f30692b5f1cb718` |
| locale | `LC_ALL=C` |
| Python | `Python 3.12.14` |
| 系统 | macOS（Darwin，见 env.txt） |

## 一致性结论

| 脚本 | 3 次输出是否一致 | sha256（3 次相同） |
| --- | --- | --- |
| `check_specs.py`（工作树布局） | 是 | `36298756313f980a91a7a35d3d6c1b0dc5045751cc300099b54096259c91e566` |
| `check_specs.py`（主树布局，只读） | 是 | `614b1051cc00f4429c487db1fcffde832dbb1c48c0f70ae9b0beab9249acab3f` |
| `gen_ledger.py` | 是 | `dc8b94a367e69bd4a0cb418e39f83ad931d8ceb6cc4d51f6f9a1b8327ca889b3` |
| `gen_resources.py`（固定 fixture） | 是 | `2f88b9314adf77fc9a731202627d042242f7ebfe71e76c244afa9326b3c95949` |
| `gen_resources.py`（空目录） | 单次 | `ca00666cdbebd979f91d9243a699cfb6eb5a38da748970def0270c2f1698d5ce` |

## check_specs 基线（两布局）

- 工作树（`ROOT=wt/e6-toolchain`，无 `xnull/spec/en`）：退出码 **1**，仅 1 处缺陷 `en 目录不存在`。
- 主树（只读执行 `/Users/vjs/Desktop/XNull-Lang` 的原脚本）：退出码 **1**，9 份 EN 对照中 `Conformance-Ledger-v1.0.0.md` 因母本 mtime 更新报「晚于母本改动」。
- 其余四项（头部三方一致、零待定、§ 引用、根目录二进制拦截）均为 `[ok]`。
- 说明：工作树缺 `xnull/` 公开副本，属预期；主树的缺陷来自台账文件被 checkout 刷新 mtime，非内容差异。

## 台账 golden

- 行数：**101**（`^| [A-Z]{2,6}-\d{2,3} |` 计数）。
- 状态分布：**PASS 10 / 部分 19 / 未实现 72**。
- 按文档：`{'S1': 14, 'S2': 29, 'S3': 11, 'S4': 10, 'S5': 9, 'S6': 10, 'S7': 7, 'S8': 11}`。
- 按里程碑：`{'M0/M3': 11, 'M1': 20, 'M2': 50, 'M3': 20}`。
- 生成前已备份原台账到 `before/`，生成后 `git checkout --` 还原，`git status` 无脏行。

## 资源生成器 golden

固定输入 `fixture/res/`：`a.txt`（`hello`）、`b.bin`（`01 02 FF`）、`config.json`（`{"k":1}`），写入顺序故意 b 先于 a。

- 正向输出：按名升序（`a.txt` < `b.bin` < `config.json`），sha256 见上表。
- 负向行为（Go 版必须复现）：

| 场景 | 退出码 | stderr |
| --- | --- | --- |
| 子目录 `sub/x.txt` | 2 | `gen_resources: 资源名非法（限 [A-Za-z0-9_.-]）：sub/x.txt` |
| 文件名含空格 `bad name.txt` | 2 | `gen_resources: 资源名非法（限 [A-Za-z0-9_.-]）：bad name.txt` |
| 目录不存在 | 2 | `gen_resources: 资源目录不存在：<路径>` |
| 空目录 | 0 | 生成空表（sha256 见上） |

注意：**子目录当前被拒绝**，按 v1.4.0 第 5 条，S0-21 阶段必须复现该拒绝行为；允许子目录属 S0-25，不在本卡。

## 复现

见 `command.txt`；原始输出见 `golden-*/`，汇总见 `stdout.txt` / `stderr.txt` / `exit_code.txt`。所有产物哈希见 `artifact.sha256`。
