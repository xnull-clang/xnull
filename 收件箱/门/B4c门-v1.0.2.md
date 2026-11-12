# B4c 门（v1.0.2）：PASS（用户裁决豁免 6 入口 + 97 负例）

- **判定**：`PASS`
- **时间**：2026-11-12
- **原判定**：`B4c门-v1.0.1.md`（PARTIAL）
- **范围**：`handoff/B4b-c-plan.md` 的 B4c-01/02a/02b/03
- **main**：`039518f`（B4c-03 合并）；仓库 `git ls-files '*.go' = 0`

## 裁决

用户裁决：**豁免 6 条 `via=interp` 入口与 97 条负例**，B4c 判 PASS；两项记入 B5/E4 债务，
不对外声称“无 Go 与 Go oracle 全量等价”。

## 完成面

| 项 | 结果 |
|---|---|
| B4c-01 冻结 golden | 142 入口 C / 97 负例 / 9 示例，diff=0 |
| B4c-02a 无 Go 引导 | `bootstrap/{xn-s4.c,xparser.c,build.sh}`，仅 cc，9/9 |
| B4c-02b 删除 Go | 365 `*.go` + `go.mod`；main `*.go = 0` |
| B4c-03 无 Go 验证 | 入口 C **136 PASS / 0 FAIL / 6 BLOCKED**；示例 **9/9**；FAIL=0 |
| 无 Go CI | `ci/run.sh` **PASS=6 FAIL=0 SKIP=3** |
| 原生 parser | 9 类语法修复；旧源 AST 与 Go 逐字节一致；136 条 golden C 复现 |

证据：`handoff/B4c-03.md`、`evidence/B4c/golden/verify-summary.txt`、
`evidence/B4c/golden/verify-entries.tsv`、main 复跑 `/tmp/main-verify.out`。

## 豁免项（B5/E4 债务）

1. **6 条入口**（`via=interp`）：冻结时由 Go 解释器生成；原生编译器自编译
   `impl/lib/b3/xnullc.x` 仍段错误。清单见 `handoff/B4c-03.md` §1。
2. **97 条负例**：原生无 sema/entry/codegen 诊断；`negatives.tsv` 作为未来回归基线。
3. **B4b plugin/xpd**：此前已由用户豁免（B4b 门 v1.0.5）。
4. `bootstrap/xn-s4.c` 仍是 B3-10 固定点（`347908a9…`），未随 B4a 后的 `xnullc.x` 重建；
   与第 1 项同根因。

## B4 总结

- B4a：PASS（xn-s4 native 9 示例双路径 9/9）；
- B4b：PASS（含 plugin/xpd 豁免；CLI 对拍 PASS 11 / DIFF 0 / NA 9）；
- B4c：PASS（含 6 入口 + 97 负例豁免；无 Go CI 6/0/3）。

**B4 判 PASS**。后续 B5/E4 应先修 `xnullc.x` 自编译段错误，再移植 sema 诊断，
以消除本门的两项豁免。
