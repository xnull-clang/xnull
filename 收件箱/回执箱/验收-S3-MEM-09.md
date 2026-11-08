# 验收：S3-MEM-09（任务 env external root）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main 含 E5 修复 `0dfc84b`（任务 env 根按任务计数；按任务声明，本次**未运行任何 git 命令**）
> **时间**：2026-11-08
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/S3-QA/MEM-09/`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| spawn 时 env 登记为 external root | **PASS**：`task_env_bind(env)` |
| 两个任务共享同一 env，先完成者不得撤根 | **PASS**：`alive=1`，第二个任务读到 `value=42` |
| 挂起/慢任务存活期间 env 保活 | **PASS**：共享探针 `alive=1` |
| 取消后清理路径期间 env 保活 | **PASS**：`alive_during_cancel=1` |
| join 后仅剩任务终结才可回收 | **PASS**：`collected_after_both=1` / `collected_after_join=1` |
| close/取消链路 | **PASS**：`task tests passed (... cancel ... root ... group-must-close)` |
| 全部任务退出后 env 可回收 | **PASS**：`rt_gc_collect()` 后弱读 NULL |

**判定：PASS。** `0dfc84b` 将 env 根改为按 env 计数（`task_env_bind/unbind`），同一 env 被多任务共享时只在最后一个任务退出时 `xrt_task_root_unbind`，不再提前回收。

---

## 二、共享 env 探针

`probe.c`：两个任务共享同一 GC env，`body_fast` 先完成，`body_slow` 睡眠 50ms 后读取 `env->tag`。

```text
alive=1 joinB=0 ok=1 value=42
shared_env_alive_during_slow_task=1 collected_after_both=1
```

- fast 任务 join + `rt_gc_collect()` 后，慢任务仍存活，弱读仍为 env（`alive=1`）。
- 慢任务读到 `tag=42`，证明持有对象未被提前回收。
- 两个任务都终结后 `rt_gc_collect()`，弱读 NULL（可回收）。

## 三、取消/join/close 探针

`cancel_probe.c`：任务在 `checkCancel` 循环中，取消后执行 50ms 清理；取消后立即 `rt_gc_collect()`。

```text
alive_during_cancel=1 cancelled=1 collected_after_join=1
```

- 取消后的清理路径期间 env 仍被根保活。
- `join` 得到 `Cancelled`（`value=42` 保留）。
- 任务终结 unbind 后 `rt_gc_collect()` 可回收。

`runtime-build.log`：

```text
task tests passed (spawn/join/close/cancel/token/deadline/cleanup/timeout/root/panic/group-must-close/dump/pool/companion)
```

---

## 四、实现证据

`impl/runtime/rt_task.c`：

```c
typedef struct task_env_root { void *env; size_t count; ... } task_env_root;
static void task_env_bind(void *env) { /* 同 env count++；首次 xrt_task_root_bind */ }
static void task_env_unbind(void *env) { /* --count == 0 时 xrt_task_root_unbind + free */ }
```

调用点：spawn → `task_env_bind(env)`；worker 任务体结束 → `task_env_unbind(env)`。

---

## 五、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/S3-QA/MEM-09/probe.c`、`probe.out`、`probe.exit`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S3-QA/MEM-09/cancel_probe.c`、`cancel.out`、`cancel.exit`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S3-QA/MEM-09/root-impl.txt`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S3-QA/MEM-09/runtime-build.log`
- 断言依据：S3 §11.1/§25 MEM-09；S5 §2.1/§9
