# 验收：S3-MEM-10（清理 defer/try/errdefer）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `412fcac`（S3 计划 v0.2 `31bf5f1`）
> **时间**：2026-11-08
> **二进制**：`/tmp/xnull-s3b`，sha256 `d7fe3b72506598e04df2df831494680d6519b03be5e1a5c8a9c4480c3341dcba`
> **证据**：`evidence/S3-QA/MEM-10/`
> **依据**：`收件箱/门/S3验收计划-E2.md` MEM-10；S3 §17
> **确认方式**：按“禁止 git”指令未执行任何 git 命令；main 版本读取 `.git/refs/heads/main`。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `defer` 成功路径清理 | **PASS**：`examples/defer-cleanup.x` 输出 `cleanup 2/cleanup 1` |
| `try` 传播路径 errdefer/defer | **PASS**：`errdefer: error path` → `defer: run exits` |
| 错误返回路径 | **PASS**：`recovered: neg` |
| fatal 路径 | **PASS**：`TestThrow`/`TestFatal` PASS（134 终止） |
| 双路径一致 | **PASS**：interp/compiled stdout 完全一致 |
| `TestDefer/TestTry/TestErrdefer` | **PASS** |

**判定：PASS。** 解释与编译路径的 defer/errdefer/try/fatal 行为一致。

---

## 二、实测

```text
$ /tmp/xnull-s3b run --interp examples/defer-cleanup.x
A
B
C
inner cleanup
D
cleanup 2
cleanup 1
---
ok path: 5
defer: run exits
---
errdefer: error path
defer: run exits
recovered: neg
exit 0

$ /tmp/xnull-s3b run examples/defer-cleanup.x
（stdout 与 interp 完全一致，diff exit 0）
```

---

## 三、证据

- `evidence/S3-QA/MEM-10/defer-interp.out`、`defer-compiled.out`（diff 0）
- `evidence/S3-QA/MEM-10/gotest.out`（`TestDefer|TestTry|TestErrdefer|TestThrow|TestFatal`）
- `evidence/S3-QA/MEM-10/matrix.tsv`
- 夹具：`examples/defer-cleanup.x`
