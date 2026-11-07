# S5-03（E5）：同步原语运行时（Channel/Mutex/Atomic*）

- 卡片：S5-03 runtime（按 S5-00 冻结面；S5 §7）
- 基线：`1dc8314`（S5-02）；分支 `pod/e5-runtime`
- 结论：Channel/Mutex/Atomic* C 运行时落地；挂起点可取消

## 先红

旧树无 `rt_sync.c` 与同步 ABI，`test_sync` 编译失败
（`red.log`：`no such file or directory: 'rt_sync.c'`）。

## 实现（`impl/runtime/rt_sync.c` + `xrt.h`）

- **Channel**：有界环形缓冲（capacity>0），send/receive 为挂起点；
  每 5ms 以 `xrt_context_check_cancel` 检查取消（协作式，无需外部 signal）；
  `close` 幂等：唤醒挂起者、释放队列剩余（ops.release），之后 send/receive 返回
  `XRT_STATUS_CLOSED`。所有权：send 成功消费 +1；CANCELLED/CLOSED 不消费；
  receive 成功取得 +1。
- **Mutex**：数据携锁 + `xrt_mutex_with_lock(data, env, ctx)` 作用域回调；
  创建取得 data +1，deinit 释放；回调期间持锁，返回即解锁。
- **AtomicInt/Bool**：`atomic_llong`/`atomic_int`，load/store/CAS，seq_cst。
- **AtomicRef**：`_Atomic(void*)` + retain/release ops；store 持有新值并释放旧值；
  CAS 成功保留 desired、释放被替换值，失败释放 desired；deinit 释放当前值。
- 全部对象为 ARC 资源，描述符 deinit 负责缓冲/ops 释放。

## 后绿

- `test_sync.c`：原子 int/bool/ref、Channel 基本收发/关闭终态/剩余释放、
  阻塞 receive 的取消与 close 唤醒、双通道任务交换、Mutex 作用域与 data 释放。
  全部 PASS（`green-sync.log`）。
- `build_rt.sh` 七套件（rt/gc/hard/abi/std/task/sync/res）exit 0（`green-build_rt.log`）。
- `go test ./internal/codegen/`：仅 `TestS4_02WrapMapErrReport` / `TestS4_02ReportContract`
  失败——该红在 main c70d886 同样存在（E2 S4 变更与 S4-02 测试期望不一致），非 S5-03 引入。

## 与 E2/接口对齐

- S5-00 冻结签名一致（`xrt_channel_*`/`xrt_mutex_*`/`xrt_atomic_*`；`xrt_channel_ops`）。
- E2 的 `xdk.sync` 类型可见性（s5_05_test）已通过；语言侧降级由 E4 S5-05 卡接线，
  本卡只提供 C ABI 与运行时语义。

## 边界

| 项 | 状态 |
|---|---|
| 通道挂起依赖 5ms 轮询取消 | 协作式；无检查点的原生阻塞不在此列 |
| 单载体线程 | 两个任务互相阻塞于 Channel 会自锁（S5-01 限制；M:N 待 B3/S3-06） |
| AtomicRef GC 发布点 | ops 负责 retain/release；并发 GC 屏障待 S3-06 |
| Mutex 重入/公平性 | 不承诺（S5 §7.2） |
