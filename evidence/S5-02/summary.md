# S5-02：取消 / 超时（Context / 令牌 / 清理排队）

- 卡片：S5-02（S5 §3.3/§5/§6；对齐 S4 Cancelled/Timeout）
- 基线：`03c1085`（S5-01）；分支 `pod/e5-runtime`（未合 main）
- 结论：取消位原子化、令牌 API、截止= Cancelled、joinDeadline= Timeout、清理不跳过

## 先红

旧树（`03c1085`）缺 `xrt_cancel_token_cancelled`；S5-02 测试编译失败
（`red.log`：`call to undeclared function 'xrt_cancel_token_cancelled'`）。

## 实现

- `context_obj.token` 改为 `atomic_int`：`xrt_context_cancel` / deadline 触发用
  release store，`check_cancel` / token 查询用 acquire load（跨线程可见）。
- `xrt_context_token` 返回上下文内嵌令牌（借用）；新增 `xrt_cancel_token_cancelled`
  （原子读，0/1）。
- 取消传播：子上下文沿父链检查；父取消 → 子 `check_cancel == XRT_ERR_CANCELLED`。
- 超时：`with_deadline` 到期等效 `Cancelled`；`join_deadline` 超时返回 `XRT_ERR_TIMEOUT`
  且不消费结果（S5 §6 / S4 §7.3）。
- 清理排队：任务被取消后仍完整执行清理路径；组 `close` 等待至清理完成才返回
  （S5 §5 清理不跳过；清理期间的取消保持置位，不再打断清理）。

## 后绿

- `test_task.c` 新增：
  - `test_cancel_token_and_deadline`：令牌读写、父→子传播、过去/未来 deadline；
  - `test_cleanup_queued`：取消后 50ms 清理完整执行，`close` 等待（elapsed≥40ms）。
- 既有 7 项任务用例继续 PASS；`build_rt.sh` exit 0。

## 边界

- 取消是协作式的：任务只在 `check_cancel` 检查点响应；无检查点的 CPU 循环按合同
  继续到下一个检查点（S5 §5）。
- 无 Channel/Mutex 挂起点（S5-03）；`join` 本身不可被 Context 取消（冻结 ABI 未含 ctx 参数）。
- 并发 GC 前提（S3-06）仍未做；首版主线程 join/close 期间不并发触达 GC。
