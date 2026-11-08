# 验收：S3-MEM-05（栈分配与逃逸）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `5255d56`（含 E4 S3-EXPR 补口 `077b20c`；按任务声明，本次**未运行任何 git 命令**）
> **时间**：2026-11-08
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/QA-S3A2/`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 逃逸分类（局部/字段/闭包） | **PASS**：`TestS3EscapeClassification/LocalAndField/Closure` |
| `none` 栈局部：身份/语义不变（解释+编译） | **PASS**：双路径 `7` |
| `return` 逃逸路径（解释+编译） | **PASS**：双路径 `7` |
| `other` 字段逃逸路径（解释+编译） | **PASS**：双路径 `6`（上一轮 M5.1-b 阻塞已解除） |
| D01 双路径一致 | **PASS**：3/3，0 mismatch |
| S3-EXPR 回归（成员实参/调用接收者/Map.get 算术） | **PASS**：`TestS3_EXPRMemberArg/CallReceiver/MapGetArithmetic` |

**判定：PASS。** S3-EXPR 补口后，`mem05` 三个用例的解释/编译 stdout 与退出码逐字节一致；栈逃逸语义完整。台账 MEM-05 可登记为 PASS。

---

## 二、命令与结果

```bash
cd impl
go test ./internal/sema -run 'TestS3Escape' -count=1 -v
go test ./internal/codegen -run 'TestS3' -count=1 -v
bash tests/s3/run.sh --root . --compiled
```

`tests-s3-compiled.log`：

```text
PASS  mem05/none    interp=7  compiled=7
PASS  mem05/other   interp=6  compiled=6
PASS  mem05/return  interp=7  compiled=7
汇总：PASS=11 FAIL=0
```

上一轮失败项 `mem05/other`（`类实例实参只支持变量/new/调用（M5.1-b 范围）`）已消失；新增 `TestS3_EXPRMemberArg` 等回归用例 PASS。

---

## 三、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S3A2/sema-s3.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S3A2/codegen-s3.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S3A2/tests-s3-interp.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S3A2/tests-s3-compiled.log`
- 断言依据：S3 §25、S3 计划 v0.2 MEM-05；`tests/s3/README.md`
