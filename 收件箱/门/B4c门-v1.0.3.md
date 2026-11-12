# B4c 门（v1.0.3）：PASS（6 入口豁免已消除；余 84 负例 + plugin/xpd）

- **判定**：`PASS`
- **时间**：2026-11-13
- **原判定**：`B4c门-v1.0.2.md`
- **范围**：`handoff/B4b-c-plan.md` 的 B4c-01/02a/02b/03
- **main**：`5f7d5fc`（B4c 负例收口第一批）；仓库 `git ls-files '*.go' = 0`

## 1. 本轮收口

| 项 | v1.0.2 | v1.0.3 |
|---|---|---|
| 入口 C（142） | 136 PASS / 6 BLOCKED | **142 PASS / 0 FAIL / 0 BLOCKED** |
| 负例（97） | 0 PASS / 97 BLOCKED | **13 PASS / 0 FAIL / 84 BLOCKED** |
| 示例（9） | 9/9 | 9/9 |
| 无 Go CI | 6/0/3 | 6/0/3 |

- 6 条原 `via=interp` 入口用新 bootstrap 编译器工件全部复现，**入口豁免消除**；
- LEX/SYN 13 条由原生 parser 对齐（词法诊断合并、协议字段/函数体、泛型协议、
  enum `implements`、重复 `default`）；
- 新编译器工件 `bootstrap/xn-s4.c`（当前 `xnullc.x` + 2 处 C 级修复）：
  115,751 行，sha256 `27ae5245…`；**不是自举固定点**（E4 债务）。

## 2. 仍豁免/债务

1. **84 条负例**：TY 48、ENTRY 18、`-` 12、RES 6；需要 sema/entry/codegen 诊断。
2. **B4b plugin/xpd**：此前用户豁免（B4b 门 v1.0.5）。
3. **编译器非固定点**：当前 `xnullc.x` 自编译在 `emitStmt` 阶段挂起；
   源级修复 `+` 拼接与 NUL 字面量后应重新自举。
4. `xparser.x` 与编译器的 C 工件均为 B4c-03 生成；B2 静态门无法无 Go 复跑，
   以 142 条 golden C + 13 条负例作为回归证据。

## 3. 判定

B4c **PASS**（沿用用户对 84 负例 + plugin/xpd 的豁免），B4 保持 PASS。
下一阶段 B5/E4：按 TY-204 → TY-208/209/212/213/218 → ENTRY/RES 顺序移植 sema，
并修复 `xnullc.x` 自编译后恢复固定点。

## 4. 证据

- `handoff/B4c-03.md`（v3）
- `evidence/B4c/golden/hashes-b4c03.tsv`、`verify-summary.txt`、`verify-entries.tsv`
- main `5f7d5fc`、`ba4acf0`、`cdd70cb`、`496693d`
