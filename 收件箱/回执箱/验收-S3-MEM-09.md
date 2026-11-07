# 验收：S3-MEM-09（任务 env external root）

> **验收人**：QA1（独立质量线）
> **结论：BLOCKED(B3)**（按任务口径不计 FAIL）
> **复验点**：main `412fcac`（S3 计划 v0.2 `31bf5f1`）
> **时间**：2026-11-08
> **证据**：`evidence/S3-QA/MEM-09/`
> **依据**：`收件箱/门/S3验收计划-E2.md` MEM-09；ADR-007（S3-06 随 B3）
> **确认方式**：按“禁止 git”指令未执行任何 git 命令；main 版本读取 `.git/refs/heads/main`。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `xrt_task_root_bind/unbind` ABI | **已存在**：`impl/runtime/xrt.h:67-68`、`xrt_abi.c:77-79` |
| 任务 env external root 绑定/解除 + dispose 可回收 | **BLOCKED(B3)**：依赖 B3 调度器与任务 env 生命周期，驱动未建 |
| S3-06 弱表/屏障并发化 | **BLOCKED(B3)**：随 B3 调度器 |

**判定：BLOCKED(B3)。** 按任务口径不是 FAIL；不计入本轮 S3 定版阻塞，但必须在 B3 前补驱动与证据。

---

## 二、未执行项

- env root 绑定/解除的端到端驱动（需任务 env 创建/销毁、安全点、dispose 后回收）。
- 并发弱表/屏障用例（S3-06）。
- 现有 ABI 单测 `impl/runtime/test_abi.c:165` 只覆盖 `xrt_task_root_bind/unbind` 基本调用，不覆盖任务 env 生命周期。

---

## 三、证据

- `evidence/S3-QA/MEM-09/BLOCKED.md`
- `evidence/S3-QA/MEM-09/matrix.tsv`
- 源码：`impl/runtime/xrt.h`、`impl/runtime/xrt_abi.c`、`impl/runtime/test_abi.c`
