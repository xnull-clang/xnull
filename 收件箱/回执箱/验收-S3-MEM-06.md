# 验收：S3-MEM-06（容器 GC）

> **验收人**：QA1（独立质量线）
> **结论：FAIL**（sema/codegen GC 核心与解释路径通过；编译路径 `gc_elem`/`mapset` 被 E4 阻塞）
> **复验点**：main 含 S3 计划 v0.2（`31bf5f1`）与 S3-04（`7b50704`）；按任务声明，本次**未运行任何 git 命令**
> **时间**：2026-11-08
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/QA-S3A/`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 容器元素区分配/扫描（GC 化） | **PASS**：`TestS3_01ContainerGCAllocation`、`TestS3_01GCContainerElements` |
| 容器字段与 `clear` 释放 | **PASS**：`TestS3_01ContainerField`、`TestS3_01ClearReleasesARCElements` |
| 容器中介环判定 | **PASS**：`TestS3ContainerCycleAndEscape`、`TestS3GCRootVisibility` |
| 解释路径 `array/list/mapset/gc_elem/holder` | **PASS**：5/5 |
| 编译路径 `array/holder/list` | **PASS** |
| **编译路径 `gc_elem`** | **FAIL**：`codegen：类成员接收者 *xfront.Call 未支持（M5.1-b）` |
| **编译路径 `mapset`** | **FAIL**：`codegen：Int 表达式 *xfront.Call 未支持（M4.1）` |
| D01 双路径一致 | **FAIL**：`gc_elem`/`mapset` 缺编译路径 |

**判定：FAIL。** 容器 GC 的分配/扫描/`clear`/中介环核心用例在 sema/codegen 与解释路径通过；参考用例的编译路径 `gc_elem`、`mapset` 被 E4 表达式支持阻塞，MEM-06 的编译面未闭合。

---

## 二、命令与结果

```bash
cd impl
go test ./internal/sema -run 'TestS3GCRootVisibility|TestS3ContainerCycleAndEscape' -count=1 -v
go test ./internal/codegen -run 'TestS3' -count=1 -v
bash tests/s3/run.sh --root .
bash tests/s3/run.sh --root . --compiled
```

解释（`tests-s3-interp.log`）：

```text
PASS  mem06/array  interp=13
PASS  mem06/gc_elem  interp=5
PASS  mem06/holder  interp=0
PASS  mem06/list  interp=4
PASS  mem06/mapset  interp=6
```

编译（`tests-s3-compiled.log`）：

```text
PASS  mem06/array  compiled=13
BLOCKED/FAIL  mem06/gc_elem  compiled rc=1 err=...类成员接收者 *xfront.Call 未支持（M5.1-b）
PASS  mem06/holder  compiled=0
PASS  mem06/list  compiled=4
BLOCKED/FAIL  mem06/mapset  compiled rc=1 err=...Int 表达式 *xfront.Call 未支持（M4.1）
```

codegen 核心（`codegen-s3.log`）：`TestS3_01*` 四例全 PASS。

---

## 三、失败项与归属

| # | 失败项 | 证据 | 归属 |
|---:|---|---|---|
| S3-M06-01 | `mem06/gc_elem` 编译路径阻塞（`xs.get(0).x`） | `tests-s3-compiled.log` | E4 M5.1-b |
| S3-M06-02 | `mem06/mapset` 编译路径阻塞（`m.get(...)` 表达式） | 同上 | E4 M4.1 |
| S3-M06-03 | D01 编译面不完整 | 同上 | E4 |

---

## 四、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S3A/sema-s3.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S3A/codegen-s3.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S3A/tests-s3-interp.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S3A/tests-s3-compiled.log`
- 断言依据：S3 §25、S3 计划 v0.2 MEM-06；`tests/s3/README.md`
