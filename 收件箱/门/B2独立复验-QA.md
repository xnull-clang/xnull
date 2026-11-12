# B2 独立复验（QA1）：B2-01 / B2-02

> **验收人**：QA1（独立质量线）
> **基线**：main 当前工作树（`e1cdf78` 系列；本次**未运行任何 git 命令**）
> **性质**：独立复跑，不复用 E2 证据；只读验证
> **时间**：2026-11-08
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/B2-QA/`

---

## 0. 结论

| 项 | 输出差分 | 语料哈希 | 判定 |
|---|---|---|---|
| **B2-01 L1** | **PASS**：`PASS=40 FAIL=0`（含 35 语料 + 1 extra + 5 负例；另 1 条 extra 不计数） | **FAIL**：35 条中 34 匹配、1 条不一致 | **FAIL（仅语料哈希）** |
| **B2-02 L2** | **PASS**：`PASS=7 FAIL=0` | L2 用 `parser_cases/`，不在 corpus.tsv | **PASS** |

**结论：** B2-01/B2-02 的 Go/XNull 逐字节输出均无差异；但 B2-01 的冻结语料清单有 1 处 SHA-256 不一致（`impl/lib/xdk/text.x`），说明语料在冻结后被改动而清单未刷新。B2-01 不能按当前 `corpus.tsv` 记 PASS，需更新语料哈希/rebaseline 后重跑。

---

## 1. B2-01 L1

命令：

```bash
cd /Users/vjs/Desktop/XNull-Lang
bash tests/b2/run-l1.sh
```

结果（`evidence/B2-QA/l1.log`）：

```text
PASS L1 examples/ast-seed.x
...
PASS EXTRA tests/b2/lex_extra/interp_float.x
PASS LEX bad_escape.x
PASS LEX bad_underscore.x
PASS LEX empty_char.x
PASS LEX unclosed_comment.x
PASS LEX unclosed_string.x
汇总：PASS=40 FAIL=0
```

- 语料 `corpus.tsv`：35 文件。
- `lex_extra`：1 文件。
- `lex_neg`：5 文件。
- 无 L1 输出差异、无诊断码/位置差异。

## 2. B2-02 L2

命令：

```bash
bash tests/b2/run-l2.sh
```

结果（`evidence/B2-QA/l2.log`）：

```text
PASS L2 tests/b2/parser_cases/basic.x
PASS L2 tests/b2/parser_cases/expr.x
PASS L2 tests/b2/parser_cases/lambda.x
PASS L2 tests/b2/parser_cases/stmt.x
PASS NEG chain_cmp.x
PASS NEG missing_brace.x
PASS NEG missing_paren.x
汇总：PASS=7 FAIL=0
```

- L2 子集 4 正例 + 3 负例全过；无 AST/诊断差异。
- `parser_cases/`、`parser_neg/` 不在 `corpus.tsv` 的 35 条冻结清单内，因此无 L2 语料哈希项。

## 3. 语料哈希核对（35/35）

校验脚本：逐行读取 `tests/b2/corpus.tsv`，`shasum -a 256` 与清单第一列比对；同时检查路径存在与路径排序。

```text
total=35  ok=34  diff=1  missing=0
sorted=yes
```

唯一差异：

```text
DIFF  impl/lib/xdk/text.x
want= cf783a7bd82508117ee2feede0cd4e163f337829b06a83e672b246e78de27a8b
got = b25c4e79ce8b998b459a7e51ff42a3d19c96cdeabe7e8d34c2d4a66bbd81535f
```

- 其余 34 条（examples、tests/s3、tests/s6、impl/xnfmt 等）全部匹配。
- 无缺失文件；清单按路径升序。
- 差异原因：`impl/lib/xdk/text.x` 在 `corpus.tsv` 冻结后更新（E3 XDK-08 相关），清单未同步。
- 影响：L1 当前仍逐字节 PASS，但“冻结语料 + SHA-256”证据不再自洽；不能证明跑的是清单声明的语料版本。

## 4. 放行条件

1. 更新 `tests/b2/corpus.tsv` 中 `impl/lib/xdk/text.x` 的 SHA-256 为当前 `b25c4e79…`（或回退 `text.x` 到清单版本），并注明 rebaseline 原因与时间。
2. 重新运行 `run-l1.sh`、`run-l2.sh`，保存新的 `PASS/FAIL` 与哈希清单。
3. 复跑后 B2-01 才可按冻结语料记 PASS。
4. B2-02 当前输出 PASS，无需因哈希项重跑；若 parser 用例后续纳入 corpus，再补哈希。

## 5. 证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/B2-QA/l1.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/B2-QA/l2.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/B2-QA/corpus-hash.tsv`
- `/Users/vjs/Desktop/XNull-Lang/evidence/B2-QA/sha.txt`
- 断言依据：`tests/b2/FORMAT-v1.md` §3（语料路径与 SHA-256 以 corpus.tsv 为准）、`收件箱/门/B2计划-E2.md` §6
