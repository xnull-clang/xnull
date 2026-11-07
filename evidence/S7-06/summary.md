# S7-06（E5）：`.unaware + @longRunning` 伴生路由（runtime 侧）

- 卡片：S7-06 runtime 面（S7 §7.3；FFI-07）
- 基线：main `eeb7b04`
- 结论：伴生执行器 API 作为长阻塞 `.unaware` 的运行时入口；新增分类一致性诊断
  `xrt_companion_thread_count/on_worker`；64 并发 + 16 取消风暴 + 载体不受阻压力用例

## 先红

基线 `eeb7b04` 上 `test_companion.c` 编译失败：
`xrt_companion_on_worker` / `xrt_companion_thread_count` 未声明
（`red.log`）。这正是 runtime 侧缺失的分类一致性诊断入口。

## 实现

- `xrt.h` / `rt_task.c`：
  - `int xrt_companion_thread_count(void)`：返回伴生池线程数（触发一次初始化）。
  - `int xrt_companion_on_worker(void)`：当前线程是否伴生 worker（`_Thread_local`）。
  - 伴生 worker 在 `companion_main` 入口置位；主线程/载体线程为 0。
- `test_companion.c`：独立运行时套件（`build_rt.sh` 纳入）：
  1. `XNULL_COMPANIONS=4`，断言池大小 4；
  2. 64 个长阻塞调用并发提交，全部完成、结果正确、回调线程非主线程；
  3. 伴生池排队期间，普通任务在载体上 200ms 内完成（不占载体）；
  4. 16 个取消风暴：过期 Context 等待立即 `XRT_ERR_CANCELLED`，
     原生调用继续；随后 `NULL` Context 再等待取得结果。

## 后绿

- `test_companion`：`pool=4, stress=64+cancel=16, carrier-free` PASS。
- `build_rt.sh` 全套 exit 0。
- `go test ./internal/codegen -run 'TestS7_02|TestS6_0[234]'` PASS（确认 xrt.h 附加声明不回归）。

## 分工与边界

- **E4 发射面**：`.xfb` 的 `.unaware + @longRunning` 入口在调用点生成
  `xrt_companion_submit(thunk, arg)` → `xrt_companion_wait(f, ctx, &res)`；
  thunk 只做原生阻塞调用，不在伴生线程触碰 GC 对象（GC 仍单线程）。
- **E5 runtime**：提交/等待/取消/池诊断与压力用例；不修改 codegen/ffi。
- 清单一致性：`TestBlockingClassificationDocInSync` 仍归 E4；本卡的
  `on_worker/thread_count` 为运行时行为证据，`@longRunning` 的实际调用点路由由 E4 接。
- `xrt_companion_*` 诊断为附加 API（非语言 API），不改变 v1 既有符号。
