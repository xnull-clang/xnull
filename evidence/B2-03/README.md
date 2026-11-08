# B2-03 证据：XNull 声明/类型 parser

## 结论

- L2 全语料（`tests/b2/corpus.tsv` 35 个文件 + `parser_cases` 4 个）逐字节一致。
- L3 负例（`parser_neg` 3 个）诊断码与位置序列与 Go oracle 完全一致。
- 汇总：`PASS=42 FAIL=0`（`l2-green.out`）。
- 先红：上一版 `xparser.x`（B2-02）在同一套 L2/L3 下 `PASS=8 FAIL=34`（`l2-red.out`）。

## 文件

| 文件 | 说明 |
| --- | --- |
| `l2-red.out` | 红：`git show HEAD:impl/lib/b2/xparser.x` 跑新版 `run-l2.sh` |
| `l2-green.out` | 绿：当前 `impl/lib/b2/xparser.x` 跑 `run-l2.sh`（42/42） |
| `l1.out` | L1 回归：`汇总：PASS=40 FAIL=0` |
| `check.out` | `xnull check impl/lib/b2/xparser.x` 通过 |
| `xfront-test.out` | `go test ./internal/xfront -count=1` 通过 |

## 关键实现点

- 声明/类型：package/import、顶层 func/field、class/struct/protocol/enum/singleton/factory/extension/@annotation、泛型、注解、主构造。
- oracle 对齐修复：package/import AST、void `Ret (nil)`、try unary、`as/is/as?` TypeAsExpr、泛型调用/局部声明判别、插值字符串 `Parts/Interps`、成员/调用/下标 `ExprStmt` 起点位置。
- 深度截断：Go `dumpReflect` 在反射深度 >64 时输出 `(depth-limit)`。XNull 侧在 `parseUnit` 末尾对自产 S 表达式做一次结构重放，按 Go 字段类型表（interface=+2、pointer=+1、value=+0、slice 元素按类型）计算节点深度并截断；仅 `impl/xnfmt/xnfmt.x` 的深层 `||` 链触发。

## 边界

- 未改 Go `internal/xfront`。
- 只改 `impl/lib/b2/xparser.x`、`tests/b2/run-l2.sh` 与 `evidence/B2-03/`。
