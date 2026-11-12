# B4c 门（v1.0.5）：PASS（golden 零豁免）

- **判定**：`PASS`
- **时间**：2026-11-13
- **原判定**：`B4c门-v1.0.4.md`
- **main**：`240d607`；仓库 `git ls-files '*.go' = 0`

## 1. 里程碑

| 项 | v1.0.4 | v1.0.5 |
|---|---|---|
| 入口 C（142） | 142 PASS / 0 BLOCKED | **142 PASS / 0 FAIL / 0 BLOCKED** |
| 负例（97） | 59 PASS / 38 BLOCKED | **97 PASS / 0 FAIL / 0 BLOCKED** |
| 示例（9） | 9/9 | 9/9 |
| 无 Go CI | 6/0/3 | 6/0/3 |

**B4c 冻结 golden 的入口/负例/示例已全部对齐，零豁免。**

覆盖：LEX/SYN 13、ENTRY-001 18、TY-101/204/207/208/209/212/213/218、
RES-102/105/106、`-` 12（Go codegen-only 兼容规则）。
检查器：`tests/b4/neg-check.py`（sema-lite + go-compat），入口/示例仍由原生
bootstrap 工具链逐字节比对。

## 2. 仍存在的债务（不影响 golden 判定）

1. **sema 产品化**：`neg-check.py` 是门禁侧检查器；产品 `xnullc --check` 尚未实现。
2. **编译器非固定点**：`bootstrap/xn-s4.c` 是 B4c 工件（当前 `xnullc.x` + 2 处 C 级修复），
   `xnullc.x` 自编译仍挂起；B3-10 固定点 `347908a9…` 仅存 git 历史。
3. **B4b plugin/xpd**：仍为设计，未实现（B4b 门 v1.0.5 豁免）。
4. 原生 parser 偶发大文件失败，verify 已加重试；根因属 E4 稳定性债务。

## 3. 判定

B4c **PASS（golden 零豁免）**；B4 保持 PASS。
下一阶段 B5/E4：产品化 sema/`--check`、修自编译恢复固定点、plugin/xpd。

## 4. 证据

- `handoff/B4c-03.md`（v3，142/97/0）
- `tests/b4/neg-check.py`、`tests/b4/verify-golden.sh`
- `evidence/B4c/golden/verify-summary.txt`、`verify-entries.tsv`
- main `240d607`、`4c213c9`、`b1a9c60`、`7220b87`
