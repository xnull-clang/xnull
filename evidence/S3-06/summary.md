# S3-06（E5）：并发内存收口——弱表原子化 + 写屏障合同

- 卡片：S3-06（弱表并发安全 / 写屏障合同）
- 分支：`pod/e5-runtime`（按 ADR-010 未写 main）
- 文件边界：仅 `rt_weak.c`、`xrt_abi.c`、`xrt.h`、对应测试；未动 `rt_task.c`/`rt_gc.c`

## 先红

基线 `test_weak.c` 编译失败：`XRT_WRITE_BARRIER_SAFEPOINT_ONLY` 未定义；
旧 `rt_weak.c` 为单线程无锁实现，无复用池与 `rt_weak_pool_size` 诊断（`red.log`）。

## 实现

### 弱表（`rt_weak.c`）

- 全局 `pthread_mutex_t g_weak_mu` 保护：
  `rt_weak_create` / `rt_weak_get` / `rt_weak_destroy` / `rt_weak_clear_slots` /
  `rt_weak_is_detached` / `rt_weak_pool_size`。
- **目标死亡清除**：`rt_weak_clear_slots` 在锁内遍历目标侧链，置 `cleared=1`、
  `target=NULL`、清空 `weak_head`；`destroy` 不再解引用已释放目标。
- **复用池**：槽位销毁进入 `g_free_slots`（不 `free`）；create 优先复用；
  池操作同受锁保护；`rt_weak_pool_size()` 供测试诊断。
- `rt_weak_get` 在锁内检查 `cleared/target/terminated`；返回后目标可能在下一次
  安全点死亡，调用方按弱引用合同使用（文档化）。

### 写屏障（`xrt.h` / `xrt_abi.c`）

- 采用“**仅安全点/显式 collect 的 STW 标记-清扫**”合同：
  `XRT_WRITE_BARRIER_SAFEPOINT_ONLY 1`；两次安全点之间的 mutator 写入无需增量屏障。
- `xrt_write_barrier` 保持存活校验（写入已终结对象 fatal），不触发收集；
  收集前所有 mutator 必须静止/到达安全点；并发增量收集不在 v1 承诺。

### 测试（`test_weak.c`，并入 `build_rt.sh`）

1. 基本弱引用/目标死亡清除/复用池；
2. 8 线程 × 20000 次 create/get/destroy 并发池压力；
3. 8 线程 get/destroy 与主线程释放目标的死亡竞态；
4. 8 线程 × 20000 次写 GC 子引用 + `xrt_write_barrier`，join 后
   `rt_gc_collect` 验证写点引用可达（安全点收集合同）；
5. `XRT_WRITE_BARRIER_SAFEPOINT_ONLY == 1` 合同断言。

## 后绿

- `test_weak`：`weak/barrier tests passed (atomic pool + safepoint-only barrier)`。
- `sh impl/runtime/build_rt.sh`：全套 exit 0（`green-build_rt.log`）。
- `go test ./internal/codegen -run TestS7_05`：PASS（xrt.h 变更不回归）。
- `go test ./internal/codegen/ffi -run 'TestS7_05|TestXdkBindingsLoadAndEmit|TestBlockingClassificationDocInSync'`：PASS。

## 边界

- 弱读返回值是借用指针，不是强引用；目标可在返回后死亡（合同已注明）。
- 本卡不实现并发增量 GC；只承诺安全点/显式 collect 的 STW 收集。
- `rt_gc.c`/`rt_task.c` 未修改。
