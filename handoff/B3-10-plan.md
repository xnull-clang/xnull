# B3-10 B4 前置计划（v1.0.0）

> 依据：`handoff/B3-xnullc-plan.md` 第 157 行、ADR-001（B4 拆 a/b/c）、ADR-009。
> B3-10 只做 B4a 前的验证与清单，不删 Go。

## 1. 目标

1. 证明 `impl/lib/b3/xnullc.x` 能被 Go oracle 编译为原生 `xn-s1`；
2. 用 `xn-s1` 编译 `xnullc.x` 得到 `xn-s2`；
3. 用 `xn-s2` 编译 `xnullc.x` 得到 `xn-s3`；
4. 证明 `xn-s2` 与 `xn-s3` 行为/产物一致（不动点）；
5. 产出 Go 删除清单，供 B4a/B4b/B4c 执行。

## 2. 固定点判定

### 2.1 产物一致

- `xn-s2 --` 与 `xn-s3 --` 对**同一输入**生成的 C 文本逐字节一致（`cmp`）；
- 覆盖：B3-09 的 143 个 Go 入口 + 9 示例 + xnullc.x 自身；
- 两次生成（同一二进制）也须一致（确定性）。

### 2.2 二进制一致

- 若构建可复现（无时间戳/随机路径），要求 `sha256(xn-s2) == sha256(xn-s3)`；
- 若暂不可复现，记录差异原因，并以“C 产物一致 + 行为一致”作为 B3-10 通过条件，
  二进制一致降为 B4a 的改进项（需在证据中明确声明，不得静默跳过）。

### 2.3 行为一致

- `xn-s2` 与 `xn-s3` 跑 B3 负例矩阵，诊断码/退出码一致；
- 跑 9 示例双路径，stdout/exit code 一致；
- 跑 xnullc 自编译链：`xn-s2` 编译自身得到 `xn-s3`，`xn-s3` 再编译自身得到
  `xn-s4`，要求 `xn-s3` 与 `xn-s4` 产物一致（多一代验证）。

## 3. 卡与命令

| 卡 | 内容 | 命令/证据 |
|---|---|---|
| B3-10-01 | Go oracle 编译 xnullc → xn-s1 | `xnull build impl/lib/b3/xnullc.x -o /tmp/xn-s1`；记录 sha256、`--version` |
| B3-10-02 | xn-s1 编译 xnullc → xn-s2 | 用 xn-s1 的 CLI 同参数编译；记录 sha256、编译日志 |
| B3-10-03 | xn-s2 编译 xnullc → xn-s3 | 同上；记录 sha256 |
| B3-10-04 | 固定点比对 | 2.1/2.2/2.3 三组日志 + `hashes.tsv` |
| B3-10-05 | Go 删除清单 | 全仓 `*.go`、`go.mod`、`go.sum`、构建脚本逐项分类 |

## 4. Go 删除清单口径

按目录/用途分四类：

1. **B4a 保留（oracle/验收）**：`impl/internal/codegen`、`impl/internal/sema`、
   `impl/internal/xfront` 等仅用于差分比对的包；B4a 结束前不得删。
2. **B4b 替换（CLI/devtool）**：`impl/cmd/xnull`、`impl/internal/cli`、
   `impl/internal/devtool`、`impl/internal/manifest`、`impl/internal/resman` 等；
   由 XNull 版 CLI 接管后删除。
3. **B4c 删除（构建/工具链）**：`go.mod`、`go.sum`、`Makefile` 中 Go 目标、
   CI 的 Go 步骤、`impl/**/*.go` 剩余文件。
4. **测试/证据**：`impl/**/*_test.go`、`evidence/**` 的 Go 快照；测试迁移到
   XNull 测试后删除，历史证据保留只读。

清单字段：`path, purpose, class(keep/replace/delete), replacement, blocker, owner`。
输出 `handoff/B3-10-go-inventory.tsv` + 汇总 md。

## 5. 通过条件

- xn-s1/s2/s3 三份二进制可执行，sha256 记录；
- xn-s2 与 xn-s3 的 C 产物全量一致，负例/示例行为一致；
- 多一代 xn-s4 与 xn-s3 产物一致；
- Go 删除清单完成并经董事会确认，B4a 可开工。

## 6. 不包含

- 不执行删除（B4c）；
- 不改 Go oracle；
- 不把 `xn-s2` 接入默认构建（B4b）。
