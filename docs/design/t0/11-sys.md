# xdk.sys —— T0 平台与进程 v1.0

| 项 | 值 |
| --- | --- |
| 包 | `xdk.sys` |
| 层级 | T0 |
| 稳定性 | `preview` |
| 依赖 | `xdk.runtime`、`xdk.errors` |
| 被依赖 | cli、config、fs |
| 对应源码 | `src/xdk/io/base/Sys.x`；完整面在 `io/system`、`io/resource` |
| 当前状态 | Partial（文件简化面通过；File/Dir/Process 为 T0-X） |

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

**非目标**：信号、进程组、stdio 管道、环境枚举（T0-X/T1）。

## 2. 顶层函数（T0-K）

```text
String readFileText(String path)
Bool fileExists(String path)
Int writeFileText(String path, String text)
```

- `readFileText` 失败（缺失/IO/超过 64 MiB）必须显式诊断，不返回空串。
- `fileExists` 不可区分“缺失”和“权限不足”；需要区分时用 T0-X File。
- `writeFileText` 返回写入的 UTF-8 字节数；写入失败抛出明确诊断，
  不返回 `0` 冒充成功。T0-X 改 `Result`。
- 资源读取 T0-X：`resourceExists`、`readResourceText`、`resourceCount`。

## 3. 所有权与错误

- 顶层便捷函数不暴露句柄，无 `close()`。
- T0-X `File`/`Dir`/`Process` 持有 OS 资源，必须 `close()` 幂等。
- 错误分类：`NotFound`、`PermissionDenied`、`Io`、`Unsupported`。

## 4. 测试义务

- 存在/不存在；
- 读取文本与写入后回读，写入返回 UTF-8 字节数；
- 资源 base/full/cancel；
- 进程退出码（T0-X）；
- 目录遍历（T0-X）。

场景：`xdk_sys.x`、`resources.sh`。

## 5. 已知缺口

- 顶层读写仍是简化面，不是完整 `Result`；
- File/Dir/Process 未纳入 T0-K；
- 信号/管道/环境枚举未实现。
