# B4b 门（v1.0.2）：PARTIAL

- **判定**：`PARTIAL`（B4c 不得启动）
- **时间**：2026-11-11 14:55
- **原判定**：`B4b门-v1.0.1.md`
- **范围**：`handoff/B4b-c-plan.md`

## 已完成

| 卡 | 内容 | 结果 |
|---|---|---|
| B4b-01 | Go-free build/run 管线 | 9 示例 9/9 |
| B4b-02 | native xparser `--file`，大文件 12/12 | AST 逐字节一致 |
| B4b-03a | xpd/manifest/validate | proj02 4/4 |
| B4b-03b-1 | reactor 聚合构建（拓扑/对象/链接） | proj02 4/4，app C 与 Go 一致 |
| B4b-03b-2 | resman/config/artifact | 资源表逐字节一致，proj02 7/7 |
| B4b-04a | tree/why | 与 Go 逐字节一致，5/5 |

## 未完成

- **B4b-04b**：install、plugin、repro、xpd/xmeta 扩展；
- **B4b-05**：XNull CLI vs Go CLI 全命令对拍（fmt/clean/version/doctor/tree/why/install/lint/doc/completion/lsp/repl/audit）；
- **B4c**：冻结 golden、删除 Go 构建/测试/CLI、无 Go 环境验证；
- 现有 XNull 工具仍以“脚本 + native 小工具”形态，尚未统一为单一 `xnull` CLI。

## 证据

- `handoff/B4b-01.md`、`B4b-02.md`、`B4b-03-design.md`、`B4b-03a.md`、
  `B4b-03b-1.md`、`B4b-03b-2.md`、`B4b-04a.md`；
- `tests/b4/xnull-build.sh`、`reactor-check.sh`、`validate-check.sh`、
  `tree-why-check.sh`；
- `handoff/B4b-xparser-largefile.md`、`B3-09-bindings-path.md`。

## 判定

B4b **PARTIAL**。剩余为工程工具 + 全命令对拍 + 去 Go，建议继续按卡推进；
B4c 不启动。
