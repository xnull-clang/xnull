# S0-21e 摘要

## 一次性结论

B-full 七项硬指标：**6 项绿、1 项红**。红项是 #1 全量测试，根因是 P0-1（`internal/codegen` 的 `TestExamplesCompileMatchesInterp/parser-seed.xn` 挂起/超时），不在 S0-21 改动范围内，按要求如实记录、不掩盖、不跳过。

## 关键数据

| 项 | 值 |
| --- | --- |
| 工作树 HEAD（执行前） | `dd751a6` |
| 用于两布局的二进制 | `evidence/S0-21d/bin/xnull`，sha256 `5668af912a9ed1742a030f98d8e24ecaa642a30d9196f6e6abc883e9f105a453` |
| 工作区布局 check | exit 0，五项 `[ok]` |
| 公开布局 check | exit 0，五项 `[ok]` |
| 台账 | 120 行 / 101 条 / PASS 10；唯一差异为头部生成器名 |
| res | Go 与 Python golden sha256 相同 |
| Python 文件 | 0；产品代码引用仅 `resources.go:99` 冻结头（令 §1.1 例外） |
| go test | `-timeout 180s` 下 codegen 187.869s 被终止；其余 8 包 ok |

## 证据边界（诚实声明）

1. 本机（主树 + 公开布局都在同一磁盘、mtime 已被多次操作刷新）两布局 check 通过；**这不能证明干净 clone 稳定**，因为 `specs.go:287` 仍按 mtime 判定。该缺陷按董事会令由 S0-27 修复。
2. `git grep` 字面命令命中 17 条，其中 16 条是 `evidence/` 下的历史命令记录文本，1 条是已登记例外；产品代码口径为 1。
3. S0-22（QA1 独立验收）不得在本文件基础上开跑；须等 P0-1/P0-3 关闭后由 QA1 独立重跑。
