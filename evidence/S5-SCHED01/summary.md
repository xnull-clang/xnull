# SCHED-01：载体池 + 伴生执行器（任务感知阻塞/`.unaware` 长阻塞）

- 卡片：SCHED-01（S5 §2.2/§7.3；优先于 S6-02）
- 基线：`04a11c4`（S6-02 runtime 先落）；分支 `pod/e5-runtime`
- 结论：不再“单线程 FIFO”；阻塞任务不占唯一载体；`.unaware` 走伴生执行器，等待可取消

## 先红

1. 旧调度器单载体：3 个 200ms 阻塞任务 + 1 个 flag 任务，`join_deadline(flag, +150ms)`
   返回 `rc=6`（Timeout）、flag 未执行（`red-carrier-old.log`）。
2. 旧树无伴生执行器 API：`xrt_future`/`xrt_companion_submit` 未声明，新测试编译失败
   （`red-compile.log`）。

## 实现（`rt_task.c` / `xrt.h`）

- **载体池**：默认 4 个载体线程（`XNULL_CARRIERS` 1..64 可调）；全局 FIFO 多消费者。
  任务感知阻塞（sleep/Channel/join）占用一个载体，但其余任务仍可被调度。
- **伴生执行器**：默认 2 线程（`XNULL_COMPANIONS`）；API：
  ```c
  xrt_future *xrt_companion_submit(xrt_blocking_fn fn, void *arg);
  int32_t xrt_companion_wait(xrt_future *f, xrt_context *ctx, void **out);
  ```
  `.unaware` 长阻塞由 `fn` 在伴生线程执行；`wait` 5ms 轮询上下文取消，取消立即返回
  `XRT_ERR_CANCELLED`（原生调用继续，future 仍可稍后 wait 取结果）。
- **取消/超时**：Channel 等待与 companion wait 均 5ms 轮询；`join_deadline` 不变。
- dumpTasks 输出 `carrier=N`。

## 后绿

- 载体池：同场景 `join_deadline rc=0 hit=1`（`green-carrier-new.log`）。
- `test_carrier_pool`：3 阻塞任务 + flag 在 150ms 内完成；`test_companion_executor`：
  2 个 150ms 伴生调用期间普通任务 80ms 内完成；取消等待 10ms 返回 Cancelled，
  稍后再次 wait 取得结果。
- `test_task` 全用例 PASS；`build_rt.sh` 七套件 exit 0。

## 边界/转出

- 真正的栈挂起/M:N（阻塞任务不占任何载体）需栈切换或异步原语；当前用载体池 +
  伴生执行器满足「不占唯一载体」与 `.unaware` 隔离。并发 GC 前提为 S3-06。
- E4 发射面：`.unaware` + `longRunning` 入口调用点需路由到 `xrt_companion_submit/wait`
  （运行时 API 已就绪）。
- S6-02 runtime 面已先落（`04a11c4`），回执待补。
