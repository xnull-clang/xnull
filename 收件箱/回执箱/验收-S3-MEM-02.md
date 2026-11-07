# 验收：S3-MEM-02（判定输入与混合图不退化）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main 含 S3 计划 v0.2（`31bf5f1`）与 S3-04（`7b50704`）；按任务声明，本次**未运行任何 git 命令**
> **时间**：2026-11-08
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/QA-S3A/`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 判定输入全部来自源码（无源码策略注解入口） | **PASS**：`TestPolicyInternalAnnos` |
| `@arc` / `@gc` 拒绝 | **PASS**：`TY-201` |
| 判定表基础行不退化 | **PASS**：`TestPolicyTable`（10 行） |
| 混合图/弱引用运行时不变量 | **PASS**：`runtime-build.log` 中 `test_hard.c` 全过 |
| 判定确定性 | **PASS**：`TestPolicyDeterministic` |

**判定：PASS。** 策略输入只来自源码与 §15.1 判定表；运行时 `test_hard.c` 的弱引用/复活/强引用不变量通过。

---

## 二、命令与结果

```bash
cd impl
go test ./internal/sema -run 'TestPolicyInternalAnnos|TestPolicyTable|TestPolicyDeterministic' -count=1 -v
cd impl/runtime && sh build_rt.sh
```

`runtime-build.log`：

```text
ok  resurrection detection terminates (fatal handler)
ok  weak slot detached after target death
ok  weak slots (invariant 4, cleared before deinit, reusable)
hard-semantics tests passed
```

---

## 三、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S3A/sema-s3.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S3A/runtime-build.log`
- 断言依据：S3 §25、S3 计划 v0.2 MEM-02
