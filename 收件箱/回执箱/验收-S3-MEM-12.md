# 验收：S3-MEM-12（确定性）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `412fcac`（S3 计划 v0.2 `31bf5f1`）
> **时间**：2026-11-08
> **二进制**：`/tmp/xnull-s3b`，sha256 `d7fe3b72506598e04df2df831494680d6519b03be5e1a5c8a9c4480c3341dcba`
> **证据**：`evidence/S3-QA/MEM-12/`
> **依据**：`收件箱/门/S3验收计划-E2.md` MEM-12；S3 §25 / S1 DET-01 内存维
> **确认方式**：按“禁止 git”指令未执行任何 git 命令；main 版本读取 `.git/refs/heads/main`。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 同源同版本同选项策略判定一致 | **PASS**：`TestPolicyDeterministic` |
| 两次 `xnull policy` 输出逐字节一致 | **PASS**：`cmp` exit 0 |
| 两次运行输出逐字节一致 | **PASS**：`cmp` exit 0 |
| 策略 JSON 排序/字段稳定 | **PASS**：同一输入两次 `policy=gc, rule=5` |

**判定：PASS。** 判定与运行结果在同源/同版本/同选项下可复现。

---

## 二、实测

```text
$ go test ./internal/sema -run TestPolicyDeterministic -count=1
ok  xnull.dev/xnull/internal/sema

$ xnull policy /tmp/policy_mem07.x > a.json
$ xnull policy /tmp/policy_mem07.x > b.json
$ cmp a.json b.json   # exit 0

$ xnull run /tmp/mem12.x > a.out
$ xnull run /tmp/mem12.x > b.out
$ cmp a.out b.out     # exit 0
```

---

## 三、证据

- `evidence/S3-QA/MEM-12/gotest.out`
- `evidence/S3-QA/MEM-12/policy-a.out`、`policy-b.out`（`policy-same.exit=0`）
- `evidence/S3-QA/MEM-12/run-a.out`、`run-b.out`（`run-same.exit=0`）
- `evidence/S3-QA/MEM-12/matrix.tsv`
