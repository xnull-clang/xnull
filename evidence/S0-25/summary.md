# S0-25 摘要

## 一句话

`xnull dev res` 从「拒绝资源子目录」改为按 S8 §5.6 递归收录：资源名为相对资源根的 `/` 分隔路径，按字节序输出；非法名、绝对路径、`.`/`..` 段、断链、越界与指向目录的符号链接仍然失败（退出码 2）。

## 变更

| 文件 | 变更 |
| --- | --- |
| `impl/internal/devtool/resources.go` | 名字校验按段（允许 `/`）；遍历增加符号链接分支（跟随文件链接、断链失败、目录链接拒绝、越界拒绝）；`within` 判根 |
| `impl/internal/devtool/resources_test.go` | 删「拒绝子目录」用例；新增子目录多级收录、空目录零条目、名字校验表、子目录非法名、符号链接 4 例 |
| `impl/README.md` | 写明 §5.6 收录规则 |
| `evidence/S0-25/` | 新 fixture、新 golden、旧 golden diff、C 探针、负向日志、回归输出 |

## 与旧 Python golden 的差异

`golden/diff-vs-python-golden.diff` 只有 3 段新增条目（`sub/multi/deep.bin`、`sub/x.txt`、`templates/mail/welcome.html`）；旧 fixture 重生成的 sha256 与 S0-21a Python golden 完全相同（`2f88b931…`），说明根目录行为零漂移。生成物首行署名未改（S0-27b 可选项，未并入）。

## 结果

| 项 | 结果 |
| --- | --- |
| 子目录 fixture | 6 项资源全部收录，探针按名查找通过 |
| 非法名 | 2，点名 `sub/bad name.txt` |
| 断链 / 越界 / 目录链接 | 2 / 2 / 2，诊断明确 |
| `build_rt.sh` | 0（含「资源表测试通过」） |
| `go vet` / devtool+cli / 全量 | 0 / 0 / 0 |
| 旧行为回归 | 根目录 golden 逐字节一致 |

## 未覆盖（边界）

- 打包层的 `resources/` 前缀、`includes/excludes` glob、多资源根合并与冲突检测：本生成器不负责，属打包阶段。
- `application*.properties` 只允许顶层的校验需要 packaging 信息，`dev res` 不感知，未做。
- 文件名仍限 `[A-Za-z0-9_.-]`（含中文名会被拒）；规范未明确放宽，本卡不改字符集。
