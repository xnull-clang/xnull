# B1-02/B1-03 自举线执行记录（E4）

## 结论

- **B1-03 差分：0 差异**（基线语料 155 文件；union 156 文件亦 0）。
- **幂等：0 违约**（Go / XNull 各二次格式化不变）。
- **诊断：3/4**（缺文件、目录、无参数 → FMT-104 + rc=2；非法 UTF-8 仍静默接受，缺运行时 utf8 校验 API）。
- **全量测试：绿**（`go test ./...`）。

## 环境

- 输入：main `f63fcba` 的 155 个 `.x`（`files-155.txt`）；union = 本树 `git ls-files '*.x'`（156，`files-union.txt`）。
- Go oracle：`impl/internal/xnfmt` + `impl/cmd/xnfmt`（B1-01，来自 `wt/e6-toolchain@8ed0153`），sha256 `56363f2a…`。
- XNull 版：`impl/xnfmt/xnfmt.x`（B1-02，来自 `wt/c3-rd1@c3d5ca6` + 本卡修复），用 `xnull build` 产出，sha256 `921f9bbb…`。

## 修复（4 处差异 → 0）

| # | 文件 | 根因 | 修法 |
|---|---|---|---|
| 1 | tuple-ok.x | XNull 未识别 `$"…"` 插值串与 `===` | 词法整体成 token；`matchOp` 增 `===` |
| 2 | tuple-switch.x | `case (` 被判为调用 | `controlKeyword` 增 `case` |
| 3 | branch-tuple-recv.x | 数字扫描吞掉 `1.` 后的标识符；`!`/一元 `(` 空格 | 数字只在点后为数字时收小数；一元规则前移 |
| 4 | text.x | XNull 未把「头部注释之后的独立注释」计入 import 区段，缺 R9.1 段间空行 | 新增 `secComments` 区段 + 段间 1 空行 |

## 证据

`command.txt`、`diff-155.txt`/`diff-union.txt`（空）、`idem-go.txt`/`idem-x.txt`（空）、`diagnostics.log`、`go-test-all.log`、`go-test-xnfmt.log`、`build-xnfmt-x.log`、`artifact.sha256`、`files-*.txt`、`stderr-*.txt`。

## 已知缺口

1. **非法 UTF-8 诊断（4/4 → 3/4）**：XNull 无字节级校验能力；需运行时线（E5）提供 `xdkc_utf8_valid(String) -> Bool`（或等同入口），绑定后可补最后一项。
2. XNull 版批处理仍按「一文件一进程」驱动（`impl/xnfmt/xnfmt`）；同进程多文件曾遇信号 11，未在本卡排查。
3. Go oracle 与 XNull 版均为“文本级”格式化；AST 结构化排版属 v2。
