# `Shell`

| 项 | 值 |
| --- | --- |
| 类型 | `class Shell` |
| 包 | `xdk.cli` |
| 稳定性 | `preview` |
| 依赖 | `CommandLine`、`ShellOptions`、`CommandResult`、`ProcessBuilder`、`Process`、`Env`、`Platform`、`Bytes`、`Writer`、`Error` |

---

## 1. 定位

argv 级命令执行器：接收 `CommandLine`，按 `ShellOptions` 解析 cwd/env/stdin、启动子进程、排空 stdout/stderr、处理超时/取消，返回 `CommandResult`。

它只执行，不解析：命令树/选项解析属于 `Parser`；Shell 不接收单个命令字符串，不做 shell 解释。

不做：shell 语法、glob/变量/管道/重定向解析、PTY、交互式终端、命令处理器、全局进程表、进程退出、补全脚本、权限提升、 `xdk.os` 依赖。

---

## 2. 设计逻辑

- `Shell` 持有默认 `ShellOptions`；`run`/`spawn` 使用默认值，`runWith`/`spawnWith` 使用显式值。
- `CommandLine` 决定“运行什么”；`ShellOptions` 决定“怎么运行”。
- cwd 解析顺序：`CommandLine.workingDirectory` > `ShellOptions.workingDirectory` > `Platform.cwd()`。
- env 解析顺序：当前环境快照（仅 `inheritEnvironment` 为 true）→ `ShellOptions.environment` → `CommandLine.environment`；同名后者覆盖前者。
- stdin 是 `ShellOptions.stdin` 的固定字节；由 `CommandResult.wait` 非阻塞写入并在结束时关闭。
- stdout/stderr 由内部 `spawnPipedRaw` 建立管道；`CommandResult` 排空并保留（受 `maximumOutputBytes` 限制）。
- 超时由 `CommandResult` 执行：先 `Terminate`，宽限后 `Kill`；超时是结果，不是 `Err`。
- 取消由 `Context` 传播：kill + 回收，返回 `Err(Cancelled)`。
- 非零退出码不是错误：`run` 返回 `Ok(CommandResult)`；调用方读 `exitCodeOrNull`/`isSuccess`。
- `spawn` 返回 pending `CommandResult`；调用方必须 `wait` 或 `close`。
- 流式输出通过 `ShellOptions` 的 `Writer` sink 显式开启；没有隐式写终端。
- Shell 不读取 `CliRuntime`，不修改全局 env/cwd，不缓存进程。
- 无 secret 日志：Shell 自身不打印；`CommandLine`/`CommandResult` 的 `describe` 不含参数值/环境值/stdin/输出内容。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_defaultOptions` | `ShellOptions` | 默认执行策略 |

不变量：`_defaultOptions` 非 null；Shell 不修改它；每次执行使用独立 `CommandResult`。

---

## 4. 生命周期

构造后复用；无 close；可共享；每次 `run`/`spawn` 产生独立结果与进程；不持有未完成进程（由 `CommandResult` 持有）。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Shell()` | 无 | 使用 `ShellOptions.defaults()` | 无 |
| `Shell(ShellOptions defaultOptions)` | defaultOptions | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `defaultOptions` | 默认策略 | 无 | `ShellOptions` | 无 |
| `run` | 用默认策略运行并等待 | `Context context, CommandLine commandLine` | `Result<CommandResult, Error>` | `NotFound`/`PermissionDenied`/`Io`/`Unavailable`/`Unsupported`/`Cancelled`；null → panic |
| `runWith` | 用显式策略运行并等待 | `Context context, CommandLine commandLine, ShellOptions options` | `Result<CommandResult, Error>` | 同上；null → panic |
| `spawn` | 用默认策略启动 | `Context context, CommandLine commandLine` | `Result<CommandResult, Error>` | 同上；null → panic |
| `spawnWith` | 用显式策略启动 | `Context context, CommandLine commandLine, ShellOptions options` | `Result<CommandResult, Error>` | 同上；null → panic |

内部方法：

| 方法 | 用途 | 失败 |
| --- | --- | --- |
| `resolveWorkingDirectory` | cwd 优先级 | 无 |
| `resolveEnvironment` | 环境合并 | 无 |
| `spawnPipedRaw` | 建立管道并启动（运行时原语） | `NotFound`/`PermissionDenied`/`Io`/`Unsupported`/`Cancelled` |

说明：

- `runWith` = `spawnWith` + `CommandResult.wait`；wait 已排空/回收，不再需要调用方 close。
- `spawnWith` 只启动并建立管道；stdin 写入、排空、超时和回收都发生在 `CommandResult.wait`。
- `runWith`/`spawnWith` 在 `Context` 已取消时直接返回 `Cancelled`，不创建进程。
- `runWith` 取消时返回 `Err(Cancelled)`，不携带结果；需要取消后的部分输出时，用 `spawnWith` + `CommandResult.wait` 并读取 `CommandResult`。
- 非零退出、信号终止、超时都返回 `Ok(CommandResult)`；只有启动/管道/IO/取消才返回 `Err`。
- `spawnPipedRaw` 是内部运行时原语；平台不支持管道时返回 `Unsupported`，不静默降级为继承 stdio。
- `Shell` 不提供 `pipeline`/`runAll`；管道组合属于 X `Pipeline` 或调用方显式使用 sys 进程原语。

---

## 8. 使用的技术

- argv 进程启动；
- cwd/env 合并；
- 管道 stdio；
- 非阻塞排空（由 `CommandResult`）；
- 超时/信号；
- 有界捕获；
- 显式 sink 流式；
- Context 取消。

---

## 9. 需要的支撑

- 语言：class、String、Bool、List、Map、Result、Context；
- 运行时：`spawnPipedRaw(Context, ProcessBuilder)`（argv + cwd + env + 管道）、`ProcessBuilder`、`Process`、`nowMono`；
- 接口：`CommandLine`、`ShellOptions`、`CommandResult`、`Env`、`Platform`、`Bytes`、`Writer`、`BasicError`、`ErrorKind`。

`PipedProcess`/`PipeHandle` 是内部管道句柄，不是公开类型。

---

## 10. 依赖的特性/接口/类

`CommandLine`、`ShellOptions`、`CommandResult`、`ProcessBuilder`、`Process`、`Env`、`Platform`、`Bytes`、`Writer`、`BasicError`、`ErrorKind`、`Context`。

---

## 11. 所有权与并发

- `Shell` 不拥有进程；pending 进程由 `CommandResult` 拥有。
- `Shell` 可并发调用；每次执行有独立 cwd/env 解析、管道和结果。
- `ShellOptions` 的 sink 是借用引用；同一个 sink 不应被多个执行并发写入。
- `_defaultOptions` 不可变；可共享。
- 引用语义；未提供 `equals`/哈希。

---

## 12. 示例与反例

正确：

```xnull
Shell shell = new Shell()
CommandLine line = new CommandLine("git", ["status", "--short"])
Result<CommandResult, Error> result = shell.run(context, line)
```

带策略：

```xnull
ShellOptions options = ShellOptions.defaults()
    .withWorkingDirectory("/work/repo")
    .withEnvironment("GIT_TERMINAL_PROMPT", "0")
    .withTimeoutMillis(30000)
Result<CommandResult, Error> result = shell.runWith(context, line, options)
```

流式：

```xnull
ShellOptions options = ShellOptions.defaults()
    .withStdoutSink(Stdio.stdout())
    .withMaximumOutputBytes(65536)
```

启动后等待：

```xnull
CommandResult pending = shell.spawnWith(context, line, options).value()
Result<Int, Error> status = pending.wait(context)
```

反例：

- `new CommandLine("git status --short", [])`：不执行 shell 拆分；
- 期望 Shell 展开 `*`、`$HOME`、`|`、`>`；
- 期望非零退出时 `runWith` 返回 `Err`；
- 期望超时时 `wait` 返回 `Err(Timeout)`；
- 期望 `spawn` 后不 `wait`/`close` 也能回收进程；
- 把 `Shell` 做成全局单例；
- 在日志里打印完整 argv/env/stdin/输出。

---

## 13. 测试/场景义务

argv 分离；含空格/元字符参数；cwd 优先级；env 继承/覆盖/命令覆盖；stdin 字节；空 stdout/stderr；非零退出；信号终止；超时 + 宽限；取消；spawn + wait；close pending；sink 流式；输出上限/截断；合并 stderr；程序不存在/无权限/管道不支持；`Context` 预取消；默认/显式 options；并发独立执行。

---

## 14. XNull 伪代码

```xnull
class Shell {
    final ShellOptions _defaultOptions

    Shell() {
        _defaultOptions = ShellOptions.defaults()
    }

    Shell(ShellOptions defaultOptions) {
        if defaultOptions == null {
            throw "Shell: null default options"
        }
        _defaultOptions = defaultOptions
    }

    ShellOptions defaultOptions() { return _defaultOptions }

    Result<CommandResult, Error> run(Context context, CommandLine commandLine) {
        return self.runWith(context, commandLine, _defaultOptions)
    }

    Result<CommandResult, Error> runWith(Context context, CommandLine commandLine,
                                         ShellOptions options) {
        if context == null || commandLine == null || options == null {
            throw "Shell.runWith: null argument"
        }
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "cancelled"))
        }
        Result<CommandResult, Error> spawned = self.spawnWith(context, commandLine, options)
        if spawned.isErr() { return Err(spawned.error()) }
        CommandResult result = spawned.value()
        Result<Int, Error> waited = result.wait(context)
        if waited.isErr() {
            Result<Unit, Error> ignored = result.close()
            return Err(waited.error())
        }
        return Ok(result)
    }

    Result<CommandResult, Error> spawn(Context context, CommandLine commandLine) {
        return self.spawnWith(context, commandLine, _defaultOptions)
    }

    Result<CommandResult, Error> spawnWith(Context context, CommandLine commandLine,
                                           ShellOptions options) {
        if context == null || commandLine == null || options == null {
            throw "Shell.spawnWith: null argument"
        }
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "cancelled"))
        }
        String workingDirectory = self.resolveWorkingDirectory(commandLine, options)
        Map<String, String> environment = self.resolveEnvironment(commandLine, options)
        ProcessBuilder builder = ProcessBuilder.of(commandLine.program())
        builder.args(commandLine.arguments())
        builder.cwd(workingDirectory)
        builder.envAll(environment)
        builder.inheritEnv(false)
        builder.redirectErrorStream(options.isMergeStderr())
        Result<PipedProcess, Error> spawned = spawnPipedRaw(context, builder)
        if spawned.isErr() { return Err(spawned.error()) }
        PipedProcess piped = spawned.value()
        return Ok(new CommandResult(
            commandLine,
            options,
            piped.process(),
            piped.stdoutPipe(),
            piped.stderrPipe(),
            piped.stdinPipe(),
            nowMono()))
    }

    private String resolveWorkingDirectory(CommandLine commandLine, ShellOptions options) {
        String? commandDirectory = commandLine.workingDirectory()
        if commandDirectory != null { return commandDirectory as String }
        String? optionDirectory = options.workingDirectory()
        if optionDirectory != null { return optionDirectory as String }
        return Platform.cwd()
    }

    private Map<String, String> resolveEnvironment(CommandLine commandLine, ShellOptions options) {
        Map<String, String> result = [:]
        if options.isInheritEnvironment() {
            result = Env.snapshot().all()
        }
        Map<String, String> optionEnvironment = options.environment()
        List<String> optionKeys = optionEnvironment.keys()
        Int optionIndex = 0
        while optionIndex < optionKeys.length() {
            String key = optionKeys.get(optionIndex)
            result.put(key, optionEnvironment.getOr(key, ""))
            optionIndex = optionIndex + 1
        }
        Map<String, String> commandEnvironment = commandLine.environment()
        List<String> commandKeys = commandEnvironment.keys()
        Int commandIndex = 0
        while commandIndex < commandKeys.length() {
            String key = commandKeys.get(commandIndex)
            result.put(key, commandEnvironment.getOr(key, ""))
            commandIndex = commandIndex + 1
        }
        return result
    }
}
```

> `spawnPipedRaw(Context, ProcessBuilder)` 是内部执行原语：以 argv 启动进程并返回 `PipedProcess`（`process`、`stdinPipe`、`stdoutPipe`、可选 `stderrPipe`）。它不经过 shell；不展开 glob/变量；管道创建失败返回 `Unsupported`/`Io`；取消返回 `Cancelled`。
