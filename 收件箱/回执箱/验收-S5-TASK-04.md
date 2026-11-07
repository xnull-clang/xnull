# 验收：S5-TASK-04（任务内 panic → 进程终止）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main 含 S5-01/02/03（`03c1085`/`1dc8314`/`63d15e6`；按任务声明，本次**未运行任何 git 命令**）
> **时间**：2026-11-08
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/QA-S5A/runtime-build.log`、`evidence/S5-01/green-task.log`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 任务内 `panic`/fatal 终止整个进程 | **PASS**：`test_panic_fatal` fork-exec，子进程非零退出 |
| 无任务级隔离 | **PASS**：任务体直接 `rt_fatal`，无 catch/恢复路径 |
| 诊断输出 | **PASS**：`xnull runtime fatal: 任务内 panic（S5 §8：进程级终止）` |

**判定：PASS。** 任务内 fatal 走进程级终止，符合 S5 §8“任务内 panic 终止整个进程，无任务级隔离”。

---

## 二、实测

`test_task.c::run_panic`：

```c
static int32_t body_panic(void *env, xrt_context *ctx, xrt_task_result *out) {
    rt_fatal("任务内 panic（S5 §8：进程级终止）");
    return 0;
}
```

`test_panic_fatal` 通过 fork + exec 子进程运行，断言子进程退出非零；父进程继续。

`runtime-build.log`：

```text
xnull runtime fatal: 任务内 panic（S5 §8：进程级终止）
task tests passed (spawn/join/close/cancel/token/deadline/cleanup/timeout/root/panic)
```

---

## 三、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S5A/runtime-build.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S5-01/green-task.log`
- 断言依据：S5 §8、§10 TASK-04
