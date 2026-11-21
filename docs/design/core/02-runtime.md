# xdk.runtime ——  运行时面 v1.0

> **1.x legacy**：本文件是旧 core 包级设计/状态账本，不是 2.x 类型合同。2.x 以 [`core/`](README.md) 的逐包目录与 [`../PACKAGE-MAP.md`](../PACKAGE-MAP.md) 为准；执行层统一为 `xdk.execution`。

> **状态（2026-11-21）**：本文件是  v1 包级设计/实现状态账本。
> 公开类型与方法形态以 [`core/`](README.md) 为准；状态汇总见 [`STATUS.md`](STATUS.md)；
> 本文件的 `当前状态`、源码路径与 K/X 明细继续保留。

| 项 | 值 |
| --- | --- |
| 包 | `xdk.runtime` |
| 层级 |  |
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

**非目标**：日志格式（log）、任务调度（tasks）、平台探测（sys）、
文件/网络 I/O、可取消 sleep。

## 2. 契约

```text
void diagnose(String message)
void exit(Int code)
Long nowMono()
Long nowWall()
```

| 函数 | 前置 | 后置 | 失败 | 并发 |
| --- | --- | --- | --- | --- |
| `diagnose(message)` | 无 | 写 stderr；返回 `void` | 底层写失败只再尝试一次诊断，不抛错 | 可从任意任务调用 |
| `exit(code)` | `0 <= code <= 255` | 终止进程 | 非法 code 由调用方保证；底层失败只诊断 | 终止性 |
| `nowMono()` | 无 | 单调毫秒 | 无 | 线程安全 |
| `nowWall()` | 无 | UNIX epoch 毫秒 | 无 | 线程安全 |

## 3. 所有权与语义

- 全部函数无资源、无 `close()`。
- 时间统一毫秒；不使用秒/微秒混用。
- `nowMono` 不受墙钟调整影响；`nowWall` 可回拨，不能用于超时。
- `diagnose` 不返回 `Result`：诊断失败不是业务失败，不应改变控制流。

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
- base/full 模式输出一致。

场景：`xdk_runtime.x`、`xdk_integration.x`。

## 6. 后续（X/）

- `sleep(Duration)` / `sleepUntilMono` 与取消面；
- stdio 流、RuntimeInfo、断言、fatal 边界。
