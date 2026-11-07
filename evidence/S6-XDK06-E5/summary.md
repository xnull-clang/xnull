# S6-XDK06（E5）：runtime 补口 + 解释路径桥 + 资源符号兜底

- 卡片：QA 判定 `验收-S6-XDK-06` FAIL 的 E5 侧补口
- 基线：main `d4f0209`（E4 S6-03/04 已合）
- 结论：`dumpTasks` 走运行时计数；`exit` 保留已产生输出；资源符号弱兜底；
  解释器补齐 runtime 桥；XDK-06 的 compiled/interp 两条路径均通过

## 失败项 → 修复

| QA 失败项 | 归属（QA） | 本次处理 |
| --- | --- | --- |
| `dumpTasks` TY-229 | E2 sema | `xdksig.go` 增 `dumpTasks` 签名；删除旧负例 |
| `dumpTasks` 未用运行时 | E5 | codegen 改为 `xdkc_dump_tasks()`；删除生成侧 `xn_task_live` |
| 解释路径 rc=1（nowMono 未定义） | E3 interp | 新增 `runtime_xdk.go`：nowMono/nowWall/env/dumpTasks/exit |
| `exit` 丢已产生输出 | E5 | `xdkc_exit` 先 `fflush(NULL)` 再 `_Exit` |
| Exit 测试缺资源符号 | E4/E6 | 新增 `rt_std_res_empty.c` 弱兜底，进 `runtimeCSources` |

## 实现细节

### dumpTasks
- `impl/internal/codegen/codegen.go`：删除 `xn_task_live`/`xn_dump_tasks`，发射
  `xrt_safepoint(); xdkc_dump_tasks();`。
- `impl/internal/codegen/s504.go`：删除 spawn/join 对 `xn_task_live` 的维护。
- `impl/runtime/rt_task.c`：输出改为单行 `tasks: live=%d spawned=%d settled=%d carrier=%d`。
- 计数唯一来源是调度器原子计数，避免生成侧/运行时两套计数漂移。

### exit
- `impl/runtime/rt_std_runtime.c`：`fflush(NULL); _Exit(code);`。
  不执行 defer/atexit（S1 §10.3），但 stdio 缓冲中的既有输出不丢失。
- 解释器 `exit(code)`：`exitSignal` panic；`execBlock` 默认分支不跑 defer；
  `RunWithDiag` 捕获并原样返回退出码。

### 资源符号兜底
- 新增 `impl/runtime/rt_std_res_empty.c`：`xrt_resource_count/get/at` 弱定义。
- `impl/internal/codegen/build.go`：加入 `runtimeCSources`。
- 强表（工程资源表或 build.go 空表）在链接期覆盖弱定义；
  手工 cc 测试/零资源工程不再缺 `xrt_resource_*`。

### 解释器桥
- `impl/internal/interp/runtime_xdk.go`：nowMono（进程内单调毫秒）、nowWall（UTC 毫秒）、
  env（首次使用冻结快照，缺失 → null）、dumpTasks（`tasks: live=N` 单行）、
  exit（跳过 defer）。
- `impl/internal/interp/tasks.go`：spawn 期间维护 `liveTasks`（同步执行，体内为 1）。

## 先红

- `xnull check dump.x`：`TY-229 XDK API dumpTasks 尚未支持`（`red-check.log`）。
- `xnull run --interp core.x`：`未定义的函数：nowMono`（`red-interp.log`）。
- `go test ./internal/codegen -run TestS6_02`：RuntimeSurface/DumpTasks 红（`red-gotest.log`）。

## 后绿

| 场景 | 结果 | 证据 |
| --- | --- | --- |
| `xnull run core.x` | rc=0，`true/true/true`，diagnose 单行 | `green-core-compiled.log` |
| `xnull run --interp core.x` | rc=0，同上 | `green-core-interp.log` |
| `xnull check dump.x` | rc=0 | `green-check-dump.log` |
| `xnull run dump.x` | `tasks: live=0 spawned=0 settled=0 carrier=0` | `green-dump-compiled.log` |
| `xnull run --interp dump.x` | `tasks: live=0` | `green-dump-interp.log` |
| `xnull run exit.x` | stdout `before`，rc=7，无 defer | `green-exit-compiled.log` |
| `xnull run --interp exit.x` | 同上 | `green-exit-interp.log` |
| `go test ./internal/codegen -run 'TestS6_0[234]'` | 9/9 PASS | `green-gotest-codegen.log` |
| `go test ./internal/interp -run TestS6XDK06` | 3/3 PASS | `green-gotest-interp.log` |
| `go test ./internal/sema ...` | PASS | `green-gotest-sema.log` |
| `go test ./internal/codegen -run TestBuild*` | PASS | `green-gotest-build.log` |
| `sh impl/runtime/build_rt.sh` | 全套 exit 0（含 empty fallback） | `green-build_rt.log` |

## 全量 codegen 说明

`go test ./internal/codegen`（`green-full-codegen.log`）仍有 2 项失败：

- `TestXdkSeedUnitCompiles`：`codegen：类型 Char 未支持（M4.1 范围）`
- `TestXdkPackageSkeletons`：`text.x 依赖 xdk.errors 不在依赖矩阵允许集（[]）`

已在 main `d4f0209` 的干净工作树复核，同样失败（`main-preexisting-failures.log`），
不是本卡引入。其余 codegen 用例全绿。

## 边界

- `dumpTasks` 仍是非承诺诊断（S6 §4.4）；输出字段可调整，但保持单行、无堆。
- 解释器为单载体同步执行，`dumpTasks` 的 live 在任务体内为 1、体外为 0；
  与编译路径的异步计数不承诺逐值一致。
- `env` 在解释器侧首次使用时冻结快照（进程级），与 C 侧“首次读取即快照”一致。
- `rt_std_res_empty.c` 是弱符号兜底，不改变有表工程的语义。
