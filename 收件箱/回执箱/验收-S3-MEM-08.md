# 验收：S3-MEM-08（终结）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `412fcac`（S3 计划 v0.2 `31bf5f1`、S3-04 `7b50704`）
> **时间**：2026-11-08
> **二进制**：`/tmp/xnull-s3b`，sha256 `d7fe3b72506598e04df2df831494680d6519b03be5e1a5c8a9c4480c3341dcba`
> **证据**：`evidence/S3-QA/MEM-08/`
> **依据**：`收件箱/门/S3验收计划-E2.md` MEM-08；S3 §14/§15；ADR-007 第 1 项
> **确认方式**：按“禁止 git”指令未执行任何 git 命令；main 版本读取 `.git/refs/heads/main`。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| ARC 归零链 | **PASS**：`build_rt.sh` hard-semantics 通过 |
| GC 清扫顺序：deinit → release → 回收 | **PASS**：`test_gc.c` 两阶段清扫；deinit 时字段有效 |
| 复活行为终止进程 | **PASS**：`resurrection detection terminates (fatal handler)` |
| 弱引用终结前清除 | **PASS**：`weak slot detached after target death`、`cleared before deinit` |
| `TestS2MEM01/02` | **PASS** |

**判定：PASS。** 运行时六套件 exit 0；deinit/清扫顺序与复活终止均按 S3 v3.1.0 口径成立。

---

## 二、实测

```text
$ cd impl/runtime && sh build_rt.sh
ok  policy table (10 rows, deterministic)
rt tests passed
gc tests passed (invariants 2/3/5/6)
ok  resurrection detection terminates (fatal handler)
ok  weak slot detached after target death
ok  weak slots (invariant 4, cleared before deinit, reusable)
hard-semantics tests passed
abi 测试通过
std 测试通过
资源表测试通过
exit 0
```

`go test ./internal/codegen -run 'TestS2MEM01|TestS2MEM02'`：PASS。

---

## 三、证据

- `evidence/S3-QA/MEM-08/gotest.out`、`gotest.exit`
- `evidence/S3-QA/MEM-08/runtime-build.out`、`runtime-build.exit`
- `evidence/S3-QA/MEM-08/matrix.tsv`
- 运行时用例：`impl/runtime/test_hard.c`、`test_gc.c`
