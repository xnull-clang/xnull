# 验收：S6-XDK-08（text）

> **验收人**：QA1（独立质量线）
> **结论：BLOCKED/P2**（sema 与 C 原语可验；text.xfb/XNull 包装端到端未接）
> **复验点**：main `64e7052`
> **时间**：2026-11-08
> **证据**：`evidence/S6-QA/XDK-08/`
> **依据**：S6 §4.6、XDK-08；S6-05 E2/E3 回执
> **确认方式**：main 版本读取 `.git/refs/heads/main`；未做分支/提交操作。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `Format` builder / `parseInt` / `parseFloat` / Regex 签名 | **PASS**：`TestS605` 3/3 |
| 非法实参拒绝 | **PASS**（sema 负例） |
| C 原语 parse/format/utf/regex | **PASS**：`build_rt.sh` std 套件 |
| `text.xfb`/包装端到端 | **BLOCKED/P2**：缺绑定/语言面接线；`TestXdkTextUnitSurface` 接受但有 `Char 未支持` 边界 |

**判定：BLOCKED/P2。** sema 与运行时原语成立；XDK 文本包的绑定与端到端路径未落地，不能按完整锚点签 PASS。

---

## 二、证据

- `evidence/S6-QA/XDK-08/matrix.tsv`
- `sema.log`（TestS605 PASS）
- `codegen.log`（TestXdkTextUnitSurface PASS，含 Char 边界）
- `runtime-build.log`（std text 套件）
- `impl/lib/xdk/text.x`
