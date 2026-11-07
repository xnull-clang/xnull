# 回执：SCHED-01（载体池 + 伴生执行器）

- 执行位：运行时线 E5
- 基线：`04a11c4`
- 结论：**修复**——载体池（默认 4）+ 伴生执行器（默认 2）；`.unaware` 不占载体；等待可取消
- 证据：`evidence/S5-SCHED01/`；接力棒 `handoff/S5-SCHED01.md`
- 纪律：仅提交 `pod/e5-runtime`

## 先红

- 单载体旧实现：3 个 200ms 阻塞任务 + flag，`join_deadline(+150ms)` → rc=6（Timeout）、hit=0。
- 旧树无 companion API，测试编译失败（`xrt_future` 未声明）。

## 后绿

- 同场景新实现：rc=0、hit=1。
- `test_carrier_pool` / `test_companion_executor` PASS；`test_task` 全用例 PASS；
  `build_rt.sh` 七套件 exit 0。
- 伴生 wait 10ms 取消返回 `XRT_ERR_CANCELLED`，原生调用继续，稍后再 wait 取结果。

## 边界

- 载体池满足“不占唯一载体”；真 M:N 栈挂起待 S3-06 并发 GC。
- E4 需将 `.unaware + longRunning` 入口路由到 `xrt_companion_submit/wait`。
- S6-02 runtime 面已先落（`04a11c4`），回执稍后补。
