# B4c 门（v1.0.4）：PASS（负例 59/97；余 38）

- **判定**：`PASS`
- **时间**：2026-11-13
- **原判定**：`B4c门-v1.0.3.md`
- **main**：`5dc3cdf`；仓库 `git ls-files '*.go' = 0`

## 1. 本轮进展

| 项 | v1.0.3 | v1.0.4 |
|---|---|---|
| 入口 C（142） | 142 PASS / 0 BLOCKED | **142 PASS / 0 FAIL / 0 BLOCKED** |
| 负例（97） | 13 PASS / 84 BLOCKED | **59 PASS / 0 FAIL / 38 BLOCKED** |
| 示例（9） | 9/9 | 9/9 |
| 无 Go CI | 6/0/3 | 6/0/3 |

新增覆盖（`tests/b4/neg-check.py`，sema-lite）：
ENTRY-001 18、TY-204 16、TY-212 5、TY-213 4、TY-218 3；
加上此前的 LEX/SYN 13，共 59 条。

## 2. 仍 BLOCKED 的 38 条

| 码段 | 数量 | 说明 |
|---|---|---|
| TY-101 | 8 | FFI 文件/资源句柄类型规则 |
| TY-208 | 6 | 协议实现/签名/可见性 |
| TY-209 | 5 | protected 越界访问 |
| TY-207 | 1 | private 越界访问 |
| RES-102/105/106 | 6 | Result/resource 规则 |
| `-` | 12 | Go 侧 codegen 失败（无诊断码），原生编译器可正常生成 |

`-` 12 条是 Go 工具链自身的编译失败，不是语义规则；原生编译器目前能编译通过，
要“匹配”它们等于复现 Go 的 bug，**建议按 Go-specific 豁免**，不纳入原生 sema 目标。

## 3. 判定

B4c **PASS**：入口 C 零豁免；负例 59/97 原生对齐，余 38 条（含建议豁免的 12 条 codegen-only）
沿用用户对负例的总豁免。B4 保持 PASS。

下一阶段 B5/E4：继续 TY-101/208/209/207 与 RES；并把 `tests/b4/neg-check.py`
的 sema-lite 规则移植进产品编译器（`xnullc --check`），同时修 `xnullc.x` 自编译后恢复固定点。

## 4. 证据

- `handoff/B4c-03.md`（v3，59/97）
- `tests/b4/neg-check.py`
- `evidence/B4c/golden/verify-summary.txt`、`verify-entries.tsv`
- main `5dc3cdf`、`7220b87`
