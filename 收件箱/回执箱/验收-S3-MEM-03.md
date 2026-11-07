# 验收：S3-MEM-03（15.6 六条不变量）

> **验收人**：QA1（独立质量线）
> **结论：PASS（运行期/解释路径）**
> **复验点**：main 含 S3 计划 v0.2（`31bf5f1`）与 S3-04（`7b50704`）；按任务声明，本次**未运行任何 git 命令**
> **时间**：2026-11-08
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/QA-S3A/runtime-build.log`、`tests-s3-interp.log`、`tests-s3-compiled.log`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 15.6 六条不变量（运行时） | **PASS**：`gc tests passed (invariants 2/3/5/6)` + `test_hard` |
| 对象身份 | **PASS**：`mem03/identity` interp `5` |
| 直接环 | **PASS**：`mem03/cycle` interp `7` |
| 容器中介环 | **PASS（解释）**：`mem03/container_cycle` interp `1` |
| 编译路径 | **BLOCKED(E4)**：`mem03/container_cycle` compiled rc=1，`类成员接收者 *xfront.Call 未支持（M5.1-b 范围）` |

**判定：PASS（MEM-03 运行期门）。** 15.6 运行时六条不变量与解释路径的 identity/cycle/container_cycle 均成立。  
**边界**：容器中介环的编译路径受 E4 表达式支持（M5.1-b）阻塞；按计划归属 E4，不影响 MEM-03 的运行期判定。

---

## 二、命令与结果

```bash
sh impl/runtime/build_rt.sh
bash tests/s3/run.sh --root .
bash tests/s3/run.sh --root . --compiled
```

解释路径（`tests-s3-interp.log`）：

```text
PASS  mem03/container_cycle  interp=1
PASS  mem03/cycle  interp=7
PASS  mem03/identity  interp=5
汇总：PASS=11 FAIL=0
```

编译路径（`tests-s3-compiled.log`）中 mem03：

```text
PASS  mem03/cycle  compiled=7
PASS  mem03/identity  compiled=5
BLOCKED/FAIL  mem03/container_cycle  compiled rc=1 err=...M5.1-b 范围
```

运行时（`runtime-build.log`）：

```text
gc tests passed (invariants 2/3/5/6)
hard-semantics tests passed
```

---

## 三、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S3A/runtime-build.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S3A/tests-s3-interp.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S3A/tests-s3-compiled.log`
- 断言依据：S3 §15.6、S3 计划 v0.2 MEM-03
