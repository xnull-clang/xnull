# xdk.sys ——  平台与进程 v1.0

> **1.x legacy**：本文件是旧 core 包级设计/状态账本，不是 2.x 类型合同。2.x 以 [`core/`](README.md) 的逐包目录与 [`../PACKAGE-MAP.md`](../PACKAGE-MAP.md) 为准；执行层统一为 `xdk.execution`。

> **状态（2026-11-21）**：本文件是  v1 包级设计/实现状态账本。
> 公开类型与方法形态以 [`core/`](README.md) 为准；状态汇总见 [`STATUS.md`](STATUS.md)；
> 本文件的 `当前状态`、源码路径与 K/X 明细继续保留。

| 项 | 值 |
| --- | --- |
| 包 | `xdk.sys` |
| 层级 |  |
| 稳定性 | `preview` |
| 依赖 | `xdk.runtime`、`xdk.errors` |
| 被依赖 | cli、config、fs |
| 对应源码 | `src/xdk/io/base/Sys.x`；完整面在 `io/system`、`io/resource` |
| 当前状态 | Partial（文件简化面通过；File/Dir/Process 为 X） |

## 1. 能力

| 能力 | 说明 | 层级 |
| --- | --- | --- |
| CAP-1 文件读取 | 读取 UTF-8 文件文本 | K |
| CAP-2 文件存在 | 存在判断 | K |
| CAP-3 文件写入 | 覆盖写文本 | K |
| CAP-4 资源读取 | 内嵌资源存在/文本/计数 | X |
| CAP-5 进程 | spawn/wait/exit code | X |
| CAP-6 目录 | open/next/close | X |
| CAP-7 平台 | platform/cwd/pid/mtime | X |

**非目标**：信号、进程组、stdio 管道、环境枚举（X/）。

## 2. 顶层函数（K）

```text
String readFileText(String path)
Bool fileExists(String path)
Int writeFileText(String path, String text)
```

- `readFileText` 失败（缺失/IO/超过 64 MiB）必须显式诊断，不返回空串。
- `fileExists` 不可区分“缺失”和“权限不足”；需要区分时用 X File。
- `writeFileText` 返回写入字节数；失败当前为简化面，X 改 `Result`。
- 资源读取 X：`resourceExists`、`readResourceText`、`resourceCount`。

## 3. 所有权与错误

- 顶层便捷函数不暴露句柄，无 `close()`。
- X `File`/`Dir`/`Process` 持有 OS 资源，必须 `close()` 幂等。
- 错误分类：`NotFound`、`PermissionDenied`、`Io`、`Unsupported`。

## 4. 测试义务

- 存在/不存在；
- 读取文本与写入后回读；
- 资源 base/full/cancel；
- 进程退出码（X）；
- 目录遍历（X）。

场景：`xdk_sys.x`、`resources.sh`。

## 5. 已知缺口

- 顶层读写仍是简化面，不是完整 `Result`；
- File/Dir/Process 未纳入 K；
- 信号/管道/环境枚举未实现。
