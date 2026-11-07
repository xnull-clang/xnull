# 验收：S5-TASK-03（任务 env 根）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main 含 S5-01/02/03（`03c1085`/`1dc8314`/`63d15e6`；按任务声明，本次**未运行任何 git 命令**）
> **时间**：2026-11-08
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/QA-S5A/runtime-build.log`、`evidence/S5-01/green-task.log`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 任务存活期间 env 可达 | **PASS**：`test_env_root`：join 前弱读 `xrt_weak_read(w) == env` |
| 任务终结后 env 根注销/可回收 | **PASS**：join 后 `rt_gc_collect()`，弱读为 `NULL` |
| spawn 绑定 / 终结解绑 | **PASS**：`rt_task.c` 在 spawn 调 `xrt_task_root_bind`，任务终结调 `xrt_task_root_unbind` |

**判定：PASS。** 任务闭包 env 作为 external root 在任务存活期间保活，终结后注销并可被 GC 回收（S5 §2.1、S3 §11.1）。

---

## 二、实测

`test_task.c::test_env_root`：

```c
test_env_t *env = rt_gc_new(&RT_TYPE_TEST_ENV);
xrt_weak_slot *w = xrt_weak_bind(env);
xrt_task_group_spawn(g, body_ok, env, &t);
xrt_task_join(t, &r);
assert(xrt_weak_read(w) == env);   // 存活期间可达
rt_gc_collect();                    // 任务已终结：根已注销
assert(xrt_weak_read(w) == NULL);   // 回收
```

`runtime-build.log`：`task tests passed (... root ...)`。

---

## 三、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S5A/runtime-build.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S5-01/green-task.log`
- 断言依据：S5 §2.1/§9、S3 §11.1、§10 TASK-03
