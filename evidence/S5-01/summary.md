# S5-01：调度器核心（任务对象/队列/载体线程）

- 卡片：S5-01（按 `handoff/S5-00-接口冻结.md` 实现）
- 基线：`main=2ac7e21`；分支 `pod/e5-runtime`（未合 main）
- 结论：任务/组/上下文与 spawn/join/joinDeadline/close/cancel 落地；单载体线程 + FIFO

## 先红

旧树无 `rt_task.c` / 任务 ABI：编译测试即失败（`red.log`：`no such file or directory: 'rt_task.c'`）。

## 实现（`impl/runtime/rt_task.c`）

- 对象：`xrt_context`（父链取消 + deadline）、`xrt_task_group`（互斥量/条件变量/active/任务表/
  first_error）、`xrt_task`（body/env/state/result/queue 链）；均 ARC。
- 队列/载体：全局 FIFO + 单载体线程（惰性 `pthread_once` 启动）；任务体在载体线程执行。
- 生命周期：
  - `spawn`：组关闭后 spawn → fatal；任务入组表（组持有）、env `xrt_task_root_bind`、入队；
  - `join`：等待终结，一次性；重复 join → fatal；结果所有权移交调用方；
  - `join_deadline`：到期返回 `XRT_ERR_TIMEOUT`，不消费结果、任务继续；
  - `close`：置 closed、取消 context、等待 active=0；重复 close → fatal；
    `first_error` 返回首个非取消错误 kind（value/error 仍归 join，v0 口径见冻结文档）；
  - `cancel`：置 context 取消位（幂等）。
- 上下文：`background/child/with_deadline/check_cancel/cancelled/cancel/token`；
  取消沿父链检查；deadline 到期自动置取消（等效 Cancelled）；`xrt_clock_mono_ms`。
- 错误/panic：合同错误与任务内 `rt_fatal` 均进程级终止（exit 134），无任务隔离。
- env 根：spawn 绑定、任务终结解绑（`xrt_task_root_unbind`）。

## 后绿

- `test_task.c`（spawn/join Ok/Err、close 取消+等待、joinDeadline 超时后 join、
  env 根回收、重复 join fork-exec 终止、任务内 panic 终止）PASS。
- `build_rt.sh` 六套件 + task 套件 exit 0。
- `go test ./internal/codegen/...` 全绿（`rt_task.c` + `-pthread` 已入构建清单）。
- 生成程序冒烟：`xnull build` + 运行正常。

## 边界

| 项 | 状态 |
|---|---|
| Channel / Mutex / Atomic* | S5-03 |
| 多载体线程 / 并发 GC | S3-06（原子弱表/屏障）后；首版主线程在 join/close 期间不并发触达 GC |
| 任务内 panic | 进程终止（S5 §8），无隔离 |
| `first_error` 的 value/error 所有权 | v0 只给 kind；join 仍持有完整结果（冻结文档 §九-7 待确认） |
