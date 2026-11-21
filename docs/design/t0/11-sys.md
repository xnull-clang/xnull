# xdk.sys —— T0 平台与进程 v1.1

| 项 | 值 |
| --- | --- |
| 包 | `xdk.sys` |
| 层级 | T0 |
| 稳定性 | `preview` |
| 依赖 | `xdk.runtime`、`xdk.errors`；OS 原语经 `sys_raw.xfb` |
| 被依赖 | cli、config、fs、time |
| 对应源码 | `src/xdk/io/base/Sys.x`（默认面）、`io/system`（File/Dir 兼容面）、`io/resource/Resource.x` |
| 当前状态 | Verified（Result 面、File/Dir/Process、stdio 管道、信号、进程组、环境枚举、内嵌资源读取子集均通过） |

## 1. 能力

| 能力 | 说明 | 承载 | 层级 |
| --- | --- | --- | --- |
| CAP-1 文件读取 | UTF-8 整文件读取，失败走 `Result` | `readFileText` | K |
| CAP-2 文件存在 | 存在判断（不区分缺失/权限） | `fileExists` | K |
| CAP-3 文件写入 | 覆盖写，返回 UTF-8 字节数 | `writeFileText` | K |
| CAP-4 资源读取 | 内嵌资源存在/大小/字节/文本/计数/列举 | `resourceExists`、`readResource`、`readResourceText`、`listResources`、`resourceCount` | X |
| CAP-5 进程 | spawn/wait/close/退出码/stdout 捕获 | `Process`、`spawnProcess`、`runProcess`、`runProcessResult` | K |
| CAP-6 目录 | open/next/entries/close | `Dir`、`openDir`（完整面） | X |
| CAP-7 平台 | platform/arch/hostname/pid/cwd/chdir/mtime | `platform`、`arch`、`hostname`、`pid`、`cwd`、`chdir`、`fileMtime` | X |
| CAP-8 stdio 管道 | stdin/stdout/stderr 管道读写 | `spawnProcessPiped`、`Process.*Stdin/Std*` | X |
| CAP-9 信号 | 常用信号编号、发送、进程自杀/终止 | `Signal`、`signalNumber`、`sendSignal`、`Process.sendSignal` | X |
| CAP-10 进程组 | 子进程自成组，按组发送信号 | `Process.groupId`、`sendGroupSignal`、`Process.sendGroupSignal` | X |
| CAP-11 环境枚举 | 全部环境变量名（升序） | `envNames`、`env`、`envHas` | X |
| CAP-12 文件句柄 | File 打开/读写/seek/flush/close（完整面） | `File`、`FileMode`、`openFile*` | X |

**非目标**：伪终端/PTY、网络套接字（`xdk.net`/T1）、进程间共享内存、作业控制
（挂起/继续会话）、Windows 专有句柄、完整 POSIX 信号实时扩展。

文件/目录句柄的**规范实现**是 `xdk.fs`；`xdk.sys` 在完整面上保留同契约的兼容
`File`/`Dir`/`Path`，供只导入 `xdk.sys` 的旧调用方使用。同一个程序同时导入
`xdk.fs` 与 `xdk.sys` 时，句柄类型以 `xdk.fs` 为准，避免同名类型冲突。

## 2. 顶层文件面（T0-X：Result）

```text
Result<String, Error> readFileText(String path)
Bool fileExists(String path)
Result<Long, Error> writeFileText(String path, String text)
```

| 函数 | 前置 | 后置 | 失败 |
| --- | --- | --- | --- |
| `readFileText(path)` | path 非空，目标非目录 | 返回 UTF-8 文本 | `InvalidArgument`、`NotFound`、`Io`（含 >64 MiB） |
| `fileExists(path)` | 无 | 跟随链接后存在返回 true | 无（缺失/权限都 false） |
| `writeFileText(path, text)` | path 非空 | 覆盖写入，返回 UTF-8 字节数 | `InvalidArgument`、`NotFound`、`PermissionDenied`、`Io` |

- 禁止把“文件不存在”映射成空字符串；读取失败必须返回 `Err`。
- 写入字节数按 UTF-8 计（非 ASCII 文本的字符数 ≠ 字节数）。
- 顶层函数不暴露句柄，无 `close()`。

## 3. `Process`（class）

```text
Result<Process, Error> spawnProcess(String command)
Result<Process, Error> spawnProcessPiped(String command)
Int runProcess(String command)
Result<ProcessResult, Error> runProcessResult(String command)

class Process {
    Bool isOpen()
    Bool isPiped()
    Int pid()
    Int groupId()
    Result<Int, Error> wait()
    Result<Unit, Error> kill(Int signalNumber)
    Result<Unit, Error> sendSignal(Signal signal)
    Result<Unit, Error> sendGroupSignal(Signal signal)
    Result<Unit, Error> terminate()
    Result<Long, Error> writeStdin(Bytes data)
    Result<Long, Error> writeStdinText(String text)
    Result<Unit, Error> closeStdin()
    Result<Bytes, Error> readStdout(Long maximumBytes)
    Result<Bytes, Error> readStdoutAll()
    Result<String, Error> readStdoutText()
    Result<Bytes, Error> readStderr(Long maximumBytes)
    Result<Bytes, Error> readStderrAll()
    Result<String, Error> readStderrText()
    Result<Unit, Error> close()
}

class ProcessResult {
    Int code
    String output
    Int status()
    String stdout()
}
```

| 方法 | 前置 | 后置 | 失败 |
| --- | --- | --- | --- |
| `wait()` | 句柄未关闭 | 阻塞等待并返回退出码；重复调用返回同一状态 | `Unavailable`、`Io` |
| `kill(n)` / `sendSignal(s)` | 句柄未关闭，信号有效 | 向子进程发送信号 | `InvalidArgument`、`Unsupported`、`Io` |
| `sendGroupSignal(s)` | 句柄未关闭，信号有效 | 向进程组 `-pid` 发送信号 | 同上 |
| `writeStdin*` | 管道进程、stdin 未关闭 | 写入字节/UTF-8 文本，返回字节数 | `Unavailable`、`Unsupported`、`Io` |
| `readStdout*/readStderr*` | 管道进程 | 读至多 N 字节或读到 EOF 的副本 | `InvalidArgument`、`Unavailable`、`Unsupported`、`Io` |
| `close()` | 无 | 关闭管道、未终结则 SIGKILL 并回收；幂等 | `Io`（仅诊断，句柄已释放） |

- 每个子进程自成一个进程组（组号 = `pid`），组信号覆盖 shell 后代。
- `wait()` 被信号终止按 `128 + signum` 返回（如 SIGTERM → 143）。
- 非管道进程调用 stdio 管道方法返回 `Unsupported`，不静默成功。
- `runProcessResult` 捕获 stdout，不捕获 stderr；输出不经过 shell 解析之外的转义。

## 4. 信号

```text
enum Signal { Hangup, Interrupt, Quit, Kill, Terminate, User1, User2,
              Pipe, Alarm, Child, Stop, Continue }

Int signalNumber(Signal signal)
Int signalNumberFromName(String name)
Result<Unit, Error> sendSignal(Int targetPid, Signal signal)
Result<Unit, Error> sendGroupSignal(Int processGroup, Signal signal)
```

- 名称映射由运行时完成（`HUP`/`INT`/`QUIT`/`KILL`/`TERM`/`USR1`/`USR2`/
  `PIPE`/`ALRM`/`CHLD`/`STOP`/`CONT`）；未知名称返回 `-1`。
- `sendSignal`/`sendGroupSignal` 要求目标为正；失败返回 `Io`，未知信号返回
  `Unsupported`。
- 信号不用于表达可恢复业务失败；业务失败仍走 `Result`/`ErrorKind`。

## 5. 环境与平台

```text
String env(String name)
Bool envHas(String name)
List<String> envNames()

String hostname()
String platform()
String arch()
Int pid()
String cwd()
Bool chdir(String path)
Long fileMtime(String path)
Result<Long, Error> fileMtimeResult(String path)
String stdinReadLine()
```

- `envNames()` 返回升序名称、不含值；值用 `env(name)` 读取。缺失变量返回空串
  （用 `envHas` 区分“缺失”和“空值”）。
- `fileMtime` 失败返回 `-1`（兼容面）；需要错误分类时用 `fileMtimeResult`。
- `chdir` 成功返回 true；不抛错。
- `pid` 使用 `Int`（POSIX pid 范围），文件大小/时间仍用 `Long`。

## 6. 内嵌资源（读取子集）

```text
Bool resourceExists(String path)
Int? resourceSize(String path)
Int resourceCount()
Result<Bytes, Error> readResource(Context context, String path)
Result<String, Error> readResourceText(Context context, String path)
Result<List<String>, Error> listResources(Context context, String prefix)
```

- 路径相对 `resources/` 根、`/` 分隔；绝对路径、`..`、空段、反斜杠非法
  （`InvalidArgument`）。
- 缺失 → `NotFound`；文本非 UTF-8 → `DataCorrupted`；不回退到文件系统。
- `Context` 首参遵循取消惯例；取消返回 `Cancelled`。
- `listResources` 返回字典序资源路径；前缀不是目录时返回空列表。

## 7. 完整面 `File` / `Dir` / `Path`

完整面（`io/system`）提供与 `xdk.fs` 同契约的句柄：

```text
enum FileMode { Read, Write, Append, ReadWrite }

class File {
    Result<Unit, Error> open(FileMode mode)
    Bool isOpen()
    Bool isReadable()
    Bool isWritable()
    Result<Long, Error> position()
    Result<Long, Error> size()
    Result<Unit, Error> seek(Long offset)
    Result<Bytes, Error> read(Long maximumBytes)
    Result<Bytes, Error> readAll()
    Result<String, Error> readText()
    Result<Long, Error> write(Bytes data)
    Result<Long, Error> writeText(String text)
    Result<Long, Error> writeLine(String line)
    Result<Unit, Error> flush()
    Result<Unit, Error> close()
}

class Dir {
    Bool isOpen()
    Result<String?, Error> next()
    Result<List<String>, Error> entries()
    Result<Unit, Error> close()
}
```

- offset/size 使用 `Long`；`Read`/`Write`/`Append`/`ReadWrite` 模式语义与
  `xdk.fs` 一致。
- `Dir.next()` 跳过 `"."`/`".."`，结束返回 `Ok(null)`；遍历顺序不承诺。
- 所有句柄 `close()` 幂等；关闭后读写返回 `Unavailable`。
- `Path` 为纯词法视图（`name/parent/extension/isAbsolute/join/normalize`），
  不访问文件系统。

## 8. 所有权与错误

- 顶层便捷函数不暴露句柄；`File`/`Dir`/`Process` 持有 OS 资源，必须 `close()`。
- 错误分类：`InvalidArgument`、`NotFound`、`PermissionDenied`、`AlreadyExists`、
  `Busy`、`Unavailable`、`Unsupported`、`DataCorrupted`、`Cancelled`、`Io`。
- 失败点只有一条通道：可恢复失败走 `Result`；契约破坏/越界由运行时诊断终止。
- `close()` 失败只报告诊断，句柄仍视为已释放；重复 `close()` 返回 `Ok()`。

## 9. 测试义务

- 顶层读写：成功、缺失、非 ASCII 字节数、回读；
- 内嵌资源：base/full/cancel、缺失、非法路径、大小/计数/列举；
- 进程：退出码、stdout 捕获、wait 重复调用、close 幂等；
- stdio 管道：stdin→stdout、stderr、EOF、非管道进程返回 `Unsupported`；
- 信号/进程组：SIGTERM 终止子进程组，wait 返回 143；
- 环境枚举：`envNames` 含注入变量，`env`/`envHas` 一致；
- 平台：platform/arch/hostname/cwd/pid/mtime；
- File/Dir：Long offset、seek、read/readAll、close 幂等、Dir EOF。

场景：`xdk_sys.x`、`xdk_sys_full.x`、`xdk_core.x`、`m7_sys.x`、`resources.sh`。

## 10. T0-X 变更记录（2026-11-21）

- `readFileText` 由 `String` 改为 `Result<String, Error>`；
  `writeFileText` 由 `Int` 改为 `Result<Long, Error>`，返回 UTF-8 字节数。
- `Process` 增加管道、`pid/groupId`、命名信号、进程组信号、幂等 close；
  所有子进程自成进程组。
- 新增 `spawnProcessPiped` 与 stdin/stdout/stderr 管道方法（hex 桥传输，
  二进制不被 NUL 截断）。
- 新增 `Signal` 枚举、名称→编号映射、进程/进程组发送面。
- 新增 `envNames` 环境枚举；平台/环境函数从完整面提升到默认面。
- 内嵌资源默认面升级为 `Result` + `Context` 取消 + 大小/计数/列举。
- `io/system` 的 File/Dir/Path 对齐 `xdk.fs` 契约（Long offset、`Ok(null)` EOF、
  Result 面、幂等 close）。
- 运行时 `rt_string_from_c(NULL)` 统一为空串，避免空字节/失败读取在
  Bytes/字符串转换处崩溃。
- 编译器修正 `platformRaw` 的 String 包装（此前直接返回 C 指针）。

## 11. 已知缺口

- 无 T0 阻塞缺口。
- T1：PTY、网络、进程会话/作业控制、实时信号扩展、独立 `xdk.resource` 包。
