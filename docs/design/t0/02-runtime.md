# xdk.runtime —— T0 运行时面 v1.0

| 项 | 值 |
| --- | --- |
| 包 | `xdk.runtime` |
| 层级 | T0 |
| 稳定性 | `stable` |
| 依赖 | L2 runtime raw FFI |
| 被依赖 | 所有 XDK 包 |
| 对应源码 | `src/xdk/core/runtime/Runtime.x` |
| 当前状态 | Verified（mini） |

## 1. 能力

| 能力 | 说明 | 承载 |
| --- | --- | --- |
| CAP-1 诊断 | 向 stderr 写一行诊断，不改变控制流 | `diagnose` |
| CAP-2 退出 | 以 0..255 退出码终止进程 | `exit` |
| CAP-3 单调时钟 | 毫秒级单调时间，用于耗时/超时 | `nowMono` |
| CAP-4 墙钟 | UNIX epoch 毫秒，仅用于展示/日历 | `nowWall` |
| CAP-5 任务诊断 | 写任务计数/状态到 stderr | `dumpTasks` |
| CAP-6 运行时信息 | 语言/XDK 版本、平台、架构、构建模式快照 | `RuntimeInfo`、`runtimeInfo` |
| CAP-7 分配统计 | 分配/释放/字节/GC 计数快照与开关 | `RuntimeStats`、`stats`、`statsEnabled`、`statsSetEnabled`、`statsReset` |

**非目标**：日志格式（log）、任务调度（tasks）、文件/网络 I/O、可取消
sleep（time）、动态能力探测（meta）。

## 2. 契约

```text
Void diagnose(String message)
Void exit(Int code)
Long nowMono()
Long nowWall()
void dumpTasks()

class RuntimeInfo {
    RuntimeInfo(String languageVersion, String xdkVersion, String platform,
                String arch, String mode)
    Bool complete()
    String describe()
}
RuntimeInfo runtimeInfo()

class RuntimeStats {
    RuntimeStats(Long allocs, Long frees, Long bytes,
                 Long gcCollections, Long gcFreed)
    Long live()
}
RuntimeStats stats()
Bool statsEnabled()
void statsSetEnabled(Bool enabled)
void statsReset()
```

| 函数 | 前置 | 后置 | 失败 | 并发 |
| --- | --- | --- | --- | --- |
| `diagnose(message)` | 无 | 写 stderr；返回 `void` | 底层写失败只再尝试一次诊断，不抛错 | 可从任意任务调用 |
| `exit(code)` | `0 <= code <= 255` | 终止进程 | 非法 code 由调用方保证；底层失败只诊断 | 终止性 |
| `nowMono()` | 无 | 单调毫秒 | 无 | 线程安全 |
| `nowWall()` | 无 | UNIX epoch 毫秒 | 无 | 线程安全 |
| `dumpTasks()` | 无 | 写一行 `tasks: live=… spawned=… settled=… carrier=…` 到 stderr | 无 | 可从任意任务调用 |
| `runtimeInfo()` | 无 | `RuntimeInfo` 快照；字段非空 | 无 | 只读 |
| `stats()` | 无 | 当前分配/GC 计数快照 | 无 | 只读；计数为近似值 |
| `statsEnabled()` | 无 | 统计是否开启 | 无 | 线程安全 |
| `statsSetEnabled(enabled)` | 无 | 开启/关闭后续计数 | 无 | 线程安全 |
| `statsReset()` | 无 | 清零计数 | 无 | 线程安全 |

- `RuntimeInfo` 字段只读；`mode` 为 `release` 或 `debug`（由编译器优化开关决定）。
- `RuntimeStats.live()` 为 `allocs - frees`，不是 GC 堆的精确存活估算。
- `statsReset()` 不改变开关状态；统计默认关闭以避免无谓开销。

## 3. 所有权与语义

- 全部函数无资源、无 `close()`。
- 时间统一毫秒；不使用秒/微秒混用。
- `nowMono` 不受墙钟调整影响；`nowWall` 可回拨，不能用于超时。
- `diagnose` 不返回 `Result`：诊断失败不是业务失败，不应改变控制流。
- `dumpTasks` 是诊断快照，字段名固定，完整格式不作为稳定契约；不得依赖它做业务分支。

## 4. 示例与反例

```text
diagnose("starting")
Long start = nowMono()
Long wall = nowWall()
if wall <= 0 { diagnose("clock unavailable") }
```

反例：

- 用 `nowWall` 计算超时；
- 用 `diagnose` 代替 `Result` 处理业务失败；
- `exit(256)` 或负数退出码。

## 5. 测试义务

- `diagnose` 写入 stderr；
- `nowMono/nowWall > 0`，且 `nowMono` 单调不减；
- `exit` 的退出码由 shell 观察；
- `dumpTasks` 在 1 个阻塞任务前后分别给出 `live=1`/`live=0`；
- `runtimeInfo()` 的版本/平台/架构/模式字段非空；
- `statsReset`/`statsSetEnabled`/`stats` 的快照与 C 层计数一致；
- base/full 模式输出一致。

场景：`xdk_runtime.x`、`xdk_integration.x`、`ref/u2_task_dump.x`、
`r4/runtime_info.x`、`r4/runtime_stats.x`。

## 6. 后续（T1）

- `sleepUntilMono` 与超时面；
- stdio 流、断言、fatal 边界。
