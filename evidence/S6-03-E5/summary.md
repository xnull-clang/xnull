# S6-03（E5）：sys plain/Async 双形态 + Process C 原语

- 卡片：S6-03 runtime 侧（S6 §4.7 定案 3-g-2；S5 §2.2/§7.3）
- 基线：`47fd089`（SCHED-01）；分支 `pod/e5-runtime`
- 结论：File/Dir/Process 的 Async 形态（Context 首参、伴生执行器）与 Process 句柄 C 原语落地

## 先红

旧树无 Async/Process 符号，`test_sysasync` 链接失败（`red.log`：undefined
`xdkc_*_async`/`xdkc_proc_*`）。

## 实现（`rt_std_sys.c`）

**Async 形态（Context 首参）**
- `xdkc_file_open_read_async(ctx,path,len,&code)` / `_open_write_async`
- `xdkc_file_read_async(ctx,fp,buf,cap,&code)` / `_write_async(ctx,fp,buf,n)` / `_close_async`
- `xdkc_dir_open_async(ctx,path,len,&code)` / `_read_async(ctx,dp,&code)` / `_close_async`
- 阻塞原语投递到伴生执行器（S5 §2.2）；等待可取消。取消语义：等待返回
  `XRT_ERR_CANCELLED`（code=2），但仍等待完成以回收资源（open 结果自动 close），
  避免泄漏/UAF；写操作可能已产生副作用（原生调用不可抢占，B3 异步 I/O 收敛）。

**Process 句柄（S6 §4.7）**
- `xdkc_proc_spawn(cmd,len,&code)`（`/bin/sh -c`）；`proc_wait`（退出码/信号）；
  `proc_kill`；`proc_close` = 未终结则 SIGKILL + reap（句柄层 close 幂等）。
- `xdkc_proc_run_async(ctx,cmd,len,&status)`：伴生执行；取消立即返回
  `XRT_ERR_CANCELLED`，命令继续；`proc_status_async` 为便捷包装。

## 后绿

- `test_sysasync.c`：async 文件写读、目录遍历、Process spawn/wait/kill、proc_run 成功与
  取消（10ms deadline → Cancelled，命令稍后回收）。PASS（`green-sysasync.log`）。
- `build_rt.sh` 八套件 exit 0（`green-build_rt.log`）。

## E4 绑定对齐（待 E4 sys 卡）

- 句柄类型：File/Dir/Process（Process 新增 `handle Process { close = procClose }`）。
- plain 保留无后缀；Async 为 `fileOpenReadAsync(ctx,...)` 等，C 名 `xdkc_*_async`。
- Async 返回：File/Dir 句柄 + `Int32 code` 出参（0 成功/2 取消或 IO 失败）；
  dirReadAsync 返回 `String?`（NULL 结束，code 区分结束与错误——v0 用 code=0+NUL）。
- close 必达/幂等由句柄层（xrt_handle close）保证；Process close 先 kill+reap。

## 边界

- Async 取消不抢占原生阻塞调用；文件/目录等待取消后仍等待完成（回收资源）。
- 多载体下并发 GC 前提仍为 S3-06；本卡测试避免并行 GC 变更。
- 绑定入口与语言签名由 E4/E2 卡落地；本卡只提供 C 原语。
