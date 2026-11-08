# S3-MEM09b（E5）：任务根生命周期修复（共享 env）

- 卡片：MEM-09 补口（QA FAIL：共享 env 提前撤根）
- 分支：`pod/e5-runtime`（按 ADR-010 未写 main）
- 文件边界：仅 `impl/runtime/rt_task.c` + `impl/runtime/test_task.c`

## 先红

新增 `test_shared_env_root` 在基线失败：
`Assertion failed: (xrt_weak_read(w) == env)`（`red.log`，EXIT=134）。
两个任务共享同一 env，fast 任务完成即 `rt_weak` 根被移除，`rt_gc_collect`
提前回收；slow 任务读到已回收对象。

## 修复

`rt_task.c` 增加 per-env 根计数表：

- `task_env_root { env, count, next }` + `g_env_root_mu`。
- `task_env_bind(env)`：同 env `count++`；0→1 时调用 `xrt_task_root_bind(env)`。
- `task_env_unbind(env)`：`count--`；1→0 时才调用 `xrt_task_root_unbind(env)` 并释放表项。
- spawn 改调 `task_env_bind`；worker 任务体结束改调 `task_env_unbind`。
- 根表操作与任务 spawn/完成由互斥量串行，覆盖 attach/spawn/join/close 链路。

## 用例

`test_shared_env_root`：
1. 创建一个 GC env（marker=42），建立弱槽；
2. 同一 `TaskGroup` 提交 `body_shared_fast` 与 `body_shared_slow`，共享 env；
3. `join(fast)` 后 `rt_gc_collect()`，弱读必须仍为 env；
4. `join(slow)` 读到 `value=42`；
5. 两任务都终结后 `rt_gc_collect()`，弱读为 NULL。

## 后绿

- `test_shared_env_root` PASS；`test_task` 全用例 PASS。
- `sh impl/runtime/build_rt.sh`：全套 exit 0（`green-build_rt.log`）。
- `go test ./internal/codegen -run TestS7_05`：PASS。

## 边界

- 只修任务根生命周期；`rt_gc.c`/`rt_weak.c`/`xrt_abi.c` 未改。
- 根计数表是进程级缓存；任务全部退出后表项释放。
- GC 收集仍按既有安全点/主线程前提；本卡不改变 GC 并发模型。
