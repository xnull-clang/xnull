# 回执：S3-MEM09b（E5 任务根生命周期）

- 执行位：运行时线 E5
- 分支：`pod/e5-runtime`（按 ADR-010 未写 main）
- 结论：**修复**——同一 env 的多个任务按计数保根，最后一个任务退出才 unbind
- 证据：`evidence/S3-MEM09b/`；接力棒 `handoff/S3-MEM09b-E5.md`

## 先红

基线 `test_shared_env_root` 断言失败：
`Assertion failed: (xrt_weak_read(w) == env)`，EXIT=134；fast 完成即撤根，
`rt_gc_collect()` 回收 env，slow 读到已回收对象。

## 修复

`rt_task.c`：
- 新增 per-env 根计数表（`g_env_root_mu` 保护）；
- `task_env_bind`：同 env count++；0→1 才 `xrt_task_root_bind`；
- `task_env_unbind`：count--；1→0 才 `xrt_task_root_unbind` 并释放表项；
- spawn/worker 改走这两个函数。

`test_task.c`：
- `test_shared_env_root`：fast/slow 共享 env；join(fast)+collect 后弱读仍为 env；
  join(slow) 读到 42；两者终结后 collect 弱读 NULL。

## 后绿

- `test_task` 全用例 PASS（含 `test_shared_env_root`）。
- `sh impl/runtime/build_rt.sh`：全套 exit 0。
- `go test ./internal/codegen -run TestS7_05`：PASS。

## 边界

- 仅改 `rt_task.c` + `test_task.c`；`rt_gc.c`/`rt_weak.c`/`xrt_abi.c` 未动。
- GC 收集仍按既有安全点/主线程前提。
