# 验收：S3-MEM-01（策略判定表）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main 含 S3 计划 v0.2（`31bf5f1`）与 S3-04（`7b50704`）；按任务声明，本次**未运行任何 git 命令**
> **时间**：2026-11-08
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/QA-S3A/sema-s3.log`、`runtime-build.log`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 判定表逐行正确（10 行） | **PASS**：`TestPolicyTable`，`policy table (10 rows, deterministic)` |
| 判定可复现 | **PASS**：`TestPolicyDeterministic` |
| 容器环 / 逃逸判定 | **PASS**：`TestS3ContainerCycleAndEscape` |
| `@arc` / `@gc` 源码使用拒绝 | **PASS**：`TestPolicyInternalAnnos` |
| 策略自捕获/struct 捕获边界 | **PASS**：`TestPolicySelfCaptureScan`、`TestPolicyStructSelfCapture` |

**判定：PASS。** MEM-01 的策略判定表、确定性与容器环判定均有可复现证据。

---

## 二、命令与结果

```bash
cd impl
go test ./internal/sema -run 'TestPolicy|TestS3ContainerCycleAndEscape' -count=1 -v
```

结果：`PASS`（`sema-s3.log`）。`runtime-build.log` 首行：

```text
ok  policy table (10 rows, deterministic)
```

`@arc`/`@gc`：`TestPolicyInternalAnnos` → `TY-201`。

---

## 三、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S3A/sema-s3.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S3A/runtime-build.log`
- 断言依据：S3 §25、`收件箱/门/S3验收计划-E2.md` v0.2 MEM-01
