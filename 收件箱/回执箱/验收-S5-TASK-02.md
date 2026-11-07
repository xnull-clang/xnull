# 验收：S5-TASK-02（组 close / 结构化并发）

> **验收人**：QA1（独立质量线）
> **结论：PASS（运行时合同）**
> **复验点**：main 含 S5-01/02/03（`03c1085`/`1dc8314`/`63d15e6`；按任务声明，本次**未运行任何 git 命令**）
> **时间**：2026-11-08
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/QA-S5A/runtime-build.log`、`evidence/S5-01/green-task.log`、`evidence/S5-02/summary.md`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `close` 取消全部未终结子任务 | **PASS**：`test_cancel_close` → `join` 得 `XRT_ERR_CANCELLED` |
| `close` 等待全部子任务终结 | **PASS**：`test_cancel_close`/`test_cleanup_queued`，`close` 返回时 `active=0` |
| 清理路径完整执行（取消不跳过） | **PASS**：`test_cleanup_queued`：取消后 50ms 清理完成，`close` 等待（elapsed≥40ms） |
| 活跃任务未关闭即释放组 → 拒绝 | **PASS**：`group_deinit` 在 `active>0` 时 `rt_fatal("任务组在未关闭/未终结时释放（S5 §3.2 合同错误）")` |
| 重复 `close` → 合同错误 | **PASS**：`xrt_task_group_close` 重复关闭 `rt_fatal` |
| 组关闭后 `spawn` → 合同错误 | **PASS**：`xrt_task_group_spawn` 在 `closed` 时 `rt_fatal` |

**判定：PASS（运行时组生命周期合同）。** close 取消 + 等待 + 清理不跳过成立；活跃任务未终结时释放组被拒绝。

---

## 二、实测

`test_task.c`：

- `test_cancel_close`：子任务在 `check_cancel` 循环中，`close` 取消并等待；`join` 得 `Cancelled`。
- `test_cleanup_queued`：取消后清理体执行 50ms，`close` 返回后 `g_cleanup_done==1`，`elapsed≥40ms`。
- `test_task.c` 汇总：

```text
task tests passed (spawn/join/close/cancel/token/deadline/cleanup/timeout/root/panic)
```

`rt_task.c`：

```c
static void group_deinit(void *obj) {
    if (g->active > 0) {
        rt_fatal("任务组在未关闭/未终结时释放（S5 §3.2 合同错误）");
    }
    ...
}
```

---

## 三、边界

- “空组（无活跃任务）未 `close` 即退出作用域”的语言级拒绝依赖 S5-05/E4 作用域检查；本轮 runtime 卡只覆盖“活跃任务未终结时释放 → fatal”。若董事会要求空组作用域退出的编译期拒绝，该项转 S5-05 FAIL/BLOCKED。
- 首版主线程在 `join/close` 期间不并发触达 GC（S3-06/B3 前置）。

---

## 四、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S5A/runtime-build.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S5-01/green-task.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S5-02/summary.md`
- 断言依据：S5 §3.2/§4、§10 TASK-02
