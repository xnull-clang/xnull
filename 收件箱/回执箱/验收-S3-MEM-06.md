# 验收：S3-MEM-06（容器 GC）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main 含 E4 S3-EXPR 补口 `077b20c`（按任务声明；本次**未运行任何 git 命令**）
> **时间**：2026-11-08
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/QA-S3A2/`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 容器元素区分配/扫描（GC 化） | **PASS**：`TestS3_01ContainerGCAllocation`、`TestS3_01GCContainerElements` |
| 容器字段与 `clear` 释放 | **PASS**：`TestS3_01ContainerField`、`TestS3_01ClearReleasesARCElements` |
| 容器中介环判定 | **PASS**：`TestS3ContainerCycleAndEscape`、`TestS3GCRootVisibility` |
| 解释路径 `array/list/mapset/gc_elem/holder` | **PASS**：5/5 |
| 编译路径 `array/list/mapset/gc_elem/holder` | **PASS**：5/5 |
| D01 双路径一致 | **PASS**：5/5，0 mismatch |
| S3-EXPR 回归（`Call` 接收者 / `Map.get` 表达式） | **PASS**：`TestS3_EXPRCallReceiver`、`TestS3_EXPRMapGetArithmetic` |

**判定：PASS。** S3-EXPR 补口后，`gc_elem` 的 `xs.get(0).x` 与 `mapset` 的 `m.get(...)` 均可在编译路径运行；容器 GC 的分配/扫描/`clear`/中介环与双路径全部成立。台账 MEM-06 可登记为 PASS。

---

## 二、命令与结果

```bash
cd impl
go test ./internal/sema -run 'TestS3GCRootVisibility|TestS3ContainerCycleAndEscape' -count=1 -v
go test ./internal/codegen -run 'TestS3' -count=1 -v
bash tests/s3/run.sh --root . --compiled
```

`tests-s3-compiled.log`：

```text
PASS  mem06/array     interp=13  compiled=13
PASS  mem06/gc_elem   interp=5   compiled=5
PASS  mem06/holder    interp=0   compiled=0
PASS  mem06/list      interp=4   compiled=4
PASS  mem06/mapset    interp=6   compiled=6
汇总：PASS=11 FAIL=0
```

上一轮的 `gc_elem`（M5.1-b）、`mapset`（M4.1）阻塞均已消失；新增 `TestS3_EXPRCallReceiver`、`TestS3_EXPRMapGetArithmetic` 等回归用例 PASS。

---

## 三、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S3A2/sema-s3.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S3A2/codegen-s3.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S3A2/tests-s3-interp.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S3A2/tests-s3-compiled.log`
- 断言依据：S3 §25、S3 计划 v0.2 MEM-06；`tests/s3/README.md`
