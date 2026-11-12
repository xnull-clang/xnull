# B4c 门（v1.0.1）：PARTIAL（严格口径；待用户裁决 6 入口 + 97 负例豁免）

- **判定**：`PARTIAL`
- **时间**：2026-11-12
- **范围**：`handoff/B4b-c-plan.md` 的 B4c-01/02a/02b/03
- **main**：`039518f`（合并 E6 B4c-03；仓库 `*.go = 0`）
- **证据**：`handoff/B4c-03.md`、`evidence/B4c/golden/verify-summary.txt`、
  `evidence/B4c/golden/verify-entries.tsv`、`/tmp/main-verify.out`（main 复跑）

## 1. 已完成

| 项 | 结果 |
|---|---|
| B4c-01 冻结 golden | 142 入口 C / 97 负例 / 9 示例，diff=0 |
| B4c-02a 无 Go 引导 | `bootstrap/{xn-s4.c,xparser.c,build.sh}`，仅 cc，9/9 |
| B4c-02b 删除 Go | 365 `*.go` + `go.mod` 删除；main `git ls-files '*.go' = 0` |
| B4c-03 无 Go 验证 | 入口 C **136 PASS / 0 FAIL / 6 BLOCKED**；示例 **9/9** |
| 无 Go CI | `ci/run.sh` **PASS=6 FAIL=0 SKIP=3**（含 golden、运行时、示例、发布） |
| 原生 parser 修复 | 嵌套泛型 `>>`、函数类型、`??`、`!==`、`as?`、主构造器、`extension`、`[:]`、插值字符串；旧源 AST 与 Go 逐字节一致 |

## 2. 未达成（阻塞 PASS）

1. **6 条入口 C 无法原生再生**（`via=interp`）：冻结时由 Go 解释器生成；
   原生编译器自编译 `impl/lib/b3/xnullc.x` 仍段错误。清单见 `handoff/B4c-03.md` §1。
2. **97 条负例无法原生再生**：原生只有 lexer/parser，sema/entry/codegen 诊断未移植；
   冻结的 `negatives.tsv` 保留为未来回归基线，不计 PASS。

## 3. 风险/债务

- `impl/lib/b2/xparser.x` 在 B4c-03 被修复，B2 静态门（L1/L2）无法在无 Go 环境复跑；
  以 136 条 golden C 与旧源 AST 逐字节一致作为回归证据。
- `bootstrap/xparser.c` 已由原生链路重新生成；`xn-s4.c` 仍是 B3-10 固定点
  `347908a9…`，未随 B4a 之后的 `xnullc.x` 变化重建（自编译段错误是根因）。
- B4b 的 plugin/xpd 完整语义此前已由用户豁免，仍属 B4c 风险。
- 6 条 interp 入口与 97 负例若长期不补，属于 B5/E4 债务。

## 4. 判定

严格口径：B4c **PARTIAL**，B4 未完成；不得对外声称“无 Go 全量等价”。

可升级为 PASS 的条件（需用户裁决）：

- 接受 6 条 `via=interp` 为“冻结时已用解释器验证、原生不可再生”；
- 接受 97 负例为“冻结基线、待 sema 移植”，不作为 B4c 门禁；
- 其余 136 入口 + 9 示例 + 无 Go CI 已全绿。

未获裁决前，B4 不判 PASS。
