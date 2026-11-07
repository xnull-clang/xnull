# 验收：S3-MEM-05（栈分配与逃逸）

> **验收人**：QA1（独立质量线）
> **结论：FAIL**（sema 分类与解释路径通过；编译路径 `mem05/other` 被 E4 M5.1-b 阻塞）
> **复验点**：main 含 S3 计划 v0.2（`31bf5f1`）与 S3-04（`7b50704`）；按任务声明，本次**未运行任何 git 命令**
> **时间**：2026-11-08
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/QA-S3A/`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 逃逸分类（局部/字段/闭包） | **PASS**：`TestS3EscapeClassification/LocalAndField/Closure` |
| `none` 栈局部：身份/语义不变（解释） | **PASS**：`mem05/none` interp `7` |
| `return` 逃逸路径（解释） | **PASS**：`mem05/return` interp `7` |
| `other` 逃逸路径（解释） | **PASS**：`mem05/other` interp `6` |
| `none` 编译路径 | **PASS**：compiled `7` |
| `return` 编译路径 | **PASS**：compiled `7` |
| **`other` 编译路径** | **FAIL**：`codegen：类实例实参只支持变量/new/调用（M5.1-b 范围）` |
| D01 双路径一致 | **FAIL**：`other` 缺编译路径 |

**判定：FAIL。** MEM-05 的 sema 逃逸分类与解释路径全过；编译路径 `mem05/other` 因 E4 M5.1-b（类实例实参表达式）阻塞，A03/D01 不完整。

---

## 二、命令与结果

```bash
cd impl
go test ./internal/sema -run 'TestS3Escape' -count=1 -v
bash tests/s3/run.sh --root .
bash tests/s3/run.sh --root . --compiled
```

解释（`tests-s3-interp.log`）：

```text
PASS  mem05/none  interp=7
PASS  mem05/other  interp=6
PASS  mem05/return  interp=7
汇总：PASS=11 FAIL=0
```

编译（`tests-s3-compiled.log`）：

```text
PASS  mem05/none  compiled=7
BLOCKED/FAIL  mem05/other  compiled rc=1 err=xnull: 代码生成失败：codegen：类实例实参只支持变量/new/调用（M5.1-b 范围）
PASS  mem05/return  compiled=7
```

---

## 三、失败项与归属

| # | 失败项 | 证据 | 归属 |
|---:|---|---|---|
| S3-M05-01 | `mem05/other` 编译路径阻塞（`take(h.v)` 类实例实参） | `tests-s3-compiled.log` | E4 M5.1-b |
| S3-M05-02 | A03/D01 不完整 | 同上 | E4 |

---

## 四、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S3A/sema-s3.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S3A/tests-s3-interp.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S3A/tests-s3-compiled.log`
- 断言依据：S3 §25、S3 计划 v0.2 MEM-05；`tests/s3/README.md`
