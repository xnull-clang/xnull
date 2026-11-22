# `xdk.cli` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.cli` |
| 层 | `xdk.core` / L3 |
| 依赖 | `xdk.errors`、`xdk.bytes`、`xdk.io`、`xdk.sys`、`xdk.time`、`xdk.runtime` |
| 被依赖 | 应用入口、工具程序 |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

`xdk.cli` 提供两段能力，边界固定：

**解析**：命令行规格、解析、帮助文本、用法错误和退出码：

- `Command` 声明命令树；
- `OptionSpec` 声明长/短选项、flag、值、默认值、重复策略；
- `Parser` 把 argv 解析成 `ParseResult`；
- `Args` 提供原始 argv 只读视图；
- `ParseResult` 提供已解析的选项值、出现次数、位置参数、命令路径；
- `HelpFormatter` 只生成 help/usage 文本；
- `UsageError` 表达用户输入错误；
- `ExitCode` 固定常用退出码；
- `ValueParser` 给选项值做可插拔的字符串校验/归一化。

**执行与运行时**：argv 级命令执行、结果、系统资源只读快照、显式运行时上下文：

- `CommandLine` 描述程序 + 参数 + cwd/env 覆盖；
- `ShellOptions` 描述执行策略：stdin、超时、终止宽限、输出上限、合并、流式 sink；
- `CommandOutput` 是完成后的 bytes/text/lines 不可变输出；
- `CommandResult` 是 pending/completed 两态结果句柄；
- `Shell` 启动并等待 argv 命令，不经过 shell；
- `SystemResource` 只读探针，组合 core `sys` 的 `SystemInfo`/`Env`/`Platform`/`Process`；
- `SystemSnapshot` 是不可变的系统资源快照；
- `CliRuntime` 显式持有 args/env/cwd/stdin/stdout/stderr/terminal。

`Shell` 不是 shell 解释器：它不接收单个命令字符串，不展开 glob/变量，不解析管道/重定向；`completionBash` 只返回补全文本，不执行/安装脚本。

不做：进程退出、stdout/stderr 写入策略（由调用方/`CliRuntime` 决定）、`Completion`/`CompletionScript` 类型、交互式提示、配置绑定、命令处理器、TUI、参数文件、PTY、全局 shell/进程表、权限提升、 `xdk.os` 扩展资源。1.x `completionBash` 仅作为文本生成兼容面保留。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 显式命令树 | 没有全局 parser/command；由调用方持有 `Command` |
| 解析无副作用 | `Parser.parse` 不读环境、不写终端、不退出进程 |
| 用户错误走 Result | 缺值、未知选项、重复、校验失败 → `UsageError` |
| 合同错误 panic | null 参数、非法 spec、非法名字 → panic |
| 不伪造成功 | flag 没有值；值选项才参与 `values/valueOrNull` |
| 默认值显式 | Parser 只从 `OptionSpec` 取默认值，不偷读环境/配置文件；`defaultFromEnv`/`resolveValue` 是显式 1.x 兼容助手 |
| 祖先选项可见 | 子命令可继续使用祖先声明的选项；同一路径重名直接拒绝 |
| 终止符 | `--` 之后全部是位置参数；不再识别选项/子命令 |
| 帮助分离 | `HelpFormatter` 只返回文本；是否打印由调用方决定 |
| 不自动 help | `--help` 不是魔法；需要时显式声明 `OptionSpec("help")` |
| 无短选项合并 | `Parser` 不接受 `-abc`；需要 1.x 短选项簇时显式 `Args.expandShortFlags` 预展开 |
| 无缩写匹配 | `--out` 不会匹配 `--output` |
| 解析/执行分离 | `Parser` 只解析；`Shell` 只执行；二者不互相调用 |
| argv 执行 | program 与 arguments 分开；没有 shell 字符串；不展开 glob/变量/管道/重定向 |
| 显式运行时 | `CliRuntime` 由调用方传递；没有全局单例；Parser/Shell 不偷读全局 |
| 命令结果两态 | `spawn` 返回 pending；`wait` 唯一完成迁移；非零退出不是 `Err` |
| 超时是结果 | 超时终止进程后返回 `CommandResult`，`isTimedOut` 为真；取消才是 `Err(Cancelled)` |
| 有界输出 | 默认 1 MiB/流；只限制保留量，始终排空管道；`isTruncated` |
| 流式显式 | 通过 `ShellOptions` 的 `Writer` sink；Shell 不隐式写终端 |
| 系统只读 | `SystemResource` 只读快照；不写环境/文件/进程；不依赖  `xdk.os` |
| 快照不可变 | `CommandOutput`/`SystemSnapshot` 不可变；`CliRuntime` 字段显式 |
| 无全局 shell | 没有全局 Shell/进程表；调用方持有 `Shell`/`CommandResult` |
| 不自动退出 | `Shell`/`Parser` 不调用进程退出；应用映射 `ExitCode`/`CommandResult` |
| 不提升权限 | Shell 以调用方身份执行；不注入 sudo/权限包装；不提供提权 API |
| 无 secret 日志 | `describe` 不输出参数值、环境值、stdin、输出内容 |
| 补全文本后置 | `Completion`/`CompletionScript` 类型仍 X；`completionBash` 作为 1.x 兼容文本函数保留 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `ExitCode` | enum | 常用退出码 | [`ExitCode.md`](ExitCode.md) |
| `Args` | class | 原始 argv 只读视图 | [`Args.md`](Args.md) |
| `OptionSpec` | class | 选项规格 | [`OptionSpec.md`](OptionSpec.md) |
| `ValueParser` | protocol | 选项值校验/归一化 | [`ValueParser.md`](ValueParser.md) |
| `Command` | class | 命令/选项/子命令树 | [`Command.md`](Command.md) |
| `ParseResult` | class | 解析结果 | [`ParseResult.md`](ParseResult.md) |
| `Parser` | class | argv → ParseResult | [`Parser.md`](Parser.md) |
| `HelpFormatter` | class | help/usage 文本 | [`HelpFormatter.md`](HelpFormatter.md) |
| `UsageError` | class | 用法错误 | [`UsageError.md`](UsageError.md) |
| `CommandLine` | class | argv/cwd/env 命令规格 | [`CommandLine.md`](CommandLine.md) |
| `ShellOptions` | class | 执行策略/stdin/超时/上限/流 | [`ShellOptions.md`](ShellOptions.md) |
| `CommandOutput` | class | 输出 bytes/text/lines 快照 | [`CommandOutput.md`](CommandOutput.md) |
| `CommandResult` | class | 命令结果句柄/快照 | [`CommandResult.md`](CommandResult.md) |
| `Shell` | class | argv 执行/流式/启动 | [`Shell.md`](Shell.md) |
| `SystemResource` | class | CPU/内存/磁盘/进程/env/platform 只读探针 | [`SystemResource.md`](SystemResource.md) |
| `SystemSnapshot` | class | 不可变系统资源快照 | [`SystemSnapshot.md`](SystemSnapshot.md) |
| `CliRuntime` | class | 显式 args/env/cwd/流/终端上下文 | [`CliRuntime.md`](CliRuntime.md) |

X 未纳入本批：`Completion`、`CompletionScript`、`PositionalSpec`、`CommandHandler`、`HelpTheme`、`VersionSpec`、`Pipeline`、`Pty`、`ResponseFile`。这些必须在后续批次单独设计，不得塞进现有类。

### 3.1 跨类型规则

1. **Parser 与 Shell 不互相调用**：`Parser` 只产生 `ParseResult`；应用把解析结果映射成 `CommandLine`，再交给 `Shell`。
2. **CommandLine 与 ShellOptions 优先级**：cwd 为 `CommandLine` > `ShellOptions` > `Platform.cwd()`；环境为进程快照（按 `inheritEnvironment`）→ `ShellOptions.environment` → `CommandLine.environment`。
3. **CommandResult 状态**：pending 只能通过 `wait` 完成；`close` 提前放弃；`wait` 后 `close` 幂等。正常/超时返回 `Ok`，取消返回 `Err(Cancelled)`；三者都可能有部分输出。
4. **CommandOutput 语义**：计数是排空总数，字节是保留量；`isTruncated` 时二者不等；合并 stderr 时 stderr 为空；行视图只对保留字节生效。
5. **SystemResource/SystemSnapshot**：只读、一次性快照；不缓存、不实时刷新；只覆盖当前进程或显式传入的子进程，不枚举进程表；不依赖  `xdk.os`。
6. **CliRuntime**：显式字段；`current` 只是快照工厂；Parser/Shell 都不读取它；标准流借用、不 close。
7. **退出码**：`UsageError.exitCode()` 固定 `ExitCode.Usage`；Shell 不调用进程退出；应用把 `CommandResult.exitCodeOrNull()` 映射到 `ExitCode`/业务码；信号终止以 `signalOrNull()` 为准，不用 `exitCode` 猜信号。
8. **秘密**：`describe` 只报告形状/计数；`CommandLine.argv()`、`CommandResult.output()` 是显式内容访问，调用方负责日志脱敏。

---

## 4. 顶层函数

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `isOptionToken` | 是否选项 token | `String token` | `Bool` | 无 |
| `optionName` | token → 选项名 | `String token` | `String?` | 无（非选项 → null） |
| `isValidLongName` | 长名/命令名校验 | `String name` | `Bool` | 无 |
| `isValidOptionShortName` | 短名校验 | `String name` | `Bool` | 无 |
| `exitCodeValue` | 枚举 → 进程码 | `ExitCode code` | `Int` | 无 |
| `exitCodeName` | 枚举 → 稳定名 | `ExitCode code` | `String` | 无 |
| `usage` | 简单 usage 行 | `String program, String summary` | `String` | 无 |
| `completionWords` | 补全词表 | `Command command` | `String` | null → panic |
| `completionBash` | bash `complete -W` 文本 | `Command root` | `String` | null → panic |
| `defaultFromEnv` | 环境/兜底两段 | `String envName, String fallback` | `String` | null → panic |
| `resolveValue` | argv/env/config/fallback 优先级 | `Args arguments, String flag, String envName, String configValue, String fallback` | `String` | null → panic |

执行/系统类型没有额外顶层函数：入口是 `Shell`/`SystemResource` 的方法；校验是各类型的构造契约。

### 4.1 顶层函数伪代码

```xnull
Bool isOptionToken(String token) {
    if token == null || token == "" { return false }
    if token == "-" || token == "--" { return false }
    return token.startsWith("-")
}

String? optionName(String token) {
    if !isOptionToken(token) { return null }
    Int equals = token.indexOf("=")
    String head = token
    if equals >= 0 {
        head = token.substring(0, equals)
    }
    if head.startsWith("--") {
        return head.substring(2, head.length() - 2)
    }
    return head.substring(1, head.length() - 1)
}

Bool isValidLongName(String name) {
    if name == null || name == "" { return false }
    if name.length() > 64 { return false }
    Int index = 0
    while index < name.length() {
        Char character = name.charAt(index)
        if index == 0 {
            if character < 'a' || character > 'z' { return false }
        } else {
            Bool isLetter = character >= 'a' && character <= 'z'
            Bool isDigit = character >= '0' && character <= '9'
            if !isLetter && !isDigit && character != '-' { return false }
        }
        index = index + 1
    }
    if name.endsWith("-") { return false }
    return true
}

Bool isValidOptionShortName(String name) {
    if name == null || name.length() != 1 { return false }
    Char character = name.charAt(0)
    if character >= 'a' && character <= 'z' { return true }
    if character >= 'A' && character <= 'Z' { return true }
    if character >= '0' && character <= '9' { return true }
    return false
}

Int exitCodeValue(ExitCode code) {
    if code == ExitCode.Ok { return 0 }
    if code == ExitCode.Error { return 1 }
    if code == ExitCode.Usage { return 2 }
    if code == ExitCode.NotFound { return 127 }
    return 128
}

String exitCodeName(ExitCode code) {
    if code == ExitCode.Ok { return "ok" }
    if code == ExitCode.Error { return "error" }
    if code == ExitCode.Usage { return "usage" }
    if code == ExitCode.NotFound { return "not_found" }
    return "signal_base"
}

String usage(String program, String summary) {
    if program == null || summary == null { throw "usage: null argument" }
    if summary == "" { return "usage: " + program }
    return "usage: " + program + " " + summary
}

String completionWords(Command command) {
    if command == null { throw "completionWords: null" }
    String words = "help"
    List<OptionSpec> options = command.options()
    Int index = 0
    while index < options.length() {
        OptionSpec option = options.get(index)
        words = words + " " + option.longToken()
        String? shortToken = option.shortToken()
        if shortToken != null { words = words + " " + shortToken }
        index = index + 1
    }
    List<Command> children = command.children()
    index = 0
    while index < children.length() {
        words = words + " " + children.get(index).name()
        index = index + 1
    }
    return words
}

String completionBash(Command root) {
    if root == null { throw "completionBash: null" }
    String text = "complete -W \"" + completionWords(root) + "\" " + root.name()
    List<Command> children = root.children()
    Int index = 0
    while index < children.length() {
        Command child = children.get(index)
        text = text + "\ncomplete -W \"" + completionWords(child) + "\" \""
            + root.name() + " " + child.name() + "\""
        index = index + 1
    }
    return text
}

String defaultFromEnv(String envName, String fallback) {
    if envName == null || fallback == null { throw "defaultFromEnv: null" }
    if envName != "" && envHas(envName) { return envOr(envName, "") }
    return fallback
}

String resolveValue(Args arguments, String flag, String envName,
                    String configValue, String fallback) {
    if arguments == null || flag == null || envName == null
        || configValue == null || fallback == null {
        throw "resolveValue: null argument"
    }
    if arguments.has(flag) { return arguments.valueOr(flag, fallback) }
    if envName != "" && envHas(envName) { return envOr(envName, "") }
    if configValue != "" { return configValue }
    return fallback
}
```

---

## 5. 技术/支撑/依赖

- 技术：argv token 扫描、长/短选项、`--` 终止符、命令树、路径选项查找、默认值/必填检查、重复策略、帮助布局、退出码表；argv 级进程启动、cwd/env 合并、管道 stdio、非阻塞排空、超时/信号、有界捕获、显式 Writer 流式、系统快照组合。
- 支撑：`String`、`List`、`Map`、`Bytes`、`Reader`/`Writer`、`ProcessBuilder`/`Process`、`SystemInfo`/`Env`/`Platform`、`Context`、`Duration`、`Result`、`Error`。
- 依赖：`xdk.errors`、`xdk.bytes`、`xdk.io`、`xdk.sys`、`xdk.time`、`xdk.runtime`。
- 内部支撑：`spawnPipedRaw`、`PipeHandle`/`PipedProcess`、`readPipeAvailableRaw`、`writePipeAvailableRaw`、`closePipeRaw`、`pollPipesRaw`、`signalFromStatusRaw`、`nowMono`、`nowEpochMillis`。
- 不依赖： `xdk.os`、 包、任何全局 shell/进程表。

---

## 6. 场景

### C1：最小 CLI

```text
app --output out.txt --verbose file.txt
```

`Command("app")` + `OptionSpec("output").withValue()` + `OptionSpec("verbose")`；`Parser.parse` 后读 `result.valueOr("output","-")`、`result.hasOption("verbose")`、`result.positionals()`。

### C2：子命令

```text
app build --release src
```

根命令声明 `build` 子命令；`--release` 在子命令上；`ParseResult.commandPath()` 返回 `app build`，`positionals()` 返回 `["src"]`。

### C3：help

```text
app --help
app build --help
```

应用显式声明 `help` flag；解析后调用 `HelpFormatter.format(command, "app")`，由应用决定写 stdout 还是 stderr。

### C4：类型化值

```text
app --port 8080
```

`OptionSpec("port").withValue().withValueParser(parser)`；`ValueParser.parse` 返回归一化字符串，失败转 `UsageError`。

### C5：用法错误

```text
app --unknown
app --output
app build --release --release
```

分别产生未知选项、缺值、重复选项 `UsageError`；应用可用 `error.exitCode()` 得到 `ExitCode.Usage`。

### C6：终止符与负数

```text
app -- -1 --not-an-option
```

`--` 后全部作为位置参数；负数位置参数必须放在 `--` 后。

### C7：argv 执行，不做 shell 注入

```text
git status --short
```

```xnull
CommandLine line = new CommandLine("git", ["status", "--short"])
Result<CommandResult, Error> result = new Shell().run(context, line)
```

空格、`*`、`$HOME`、`|`、`>` 都是参数字符；不会展开、不会被 shell 解释。

### C8：cwd/env 优先级

```xnull
ShellOptions options = ShellOptions.defaults()
    .withWorkingDirectory("/work")
    .withEnvironment("LANG", "C")
CommandLine line = new CommandLine("env", [])
    .withWorkingDirectory("/work/repo")
    .withEnvironment("LANG", "C.UTF-8")
```

最终 cwd 是 `/work/repo`；`LANG` 是 `C.UTF-8`；其余环境来自进程快照。

### C9：超时与信号

```xnull
ShellOptions options = ShellOptions.defaults()
    .withTimeoutMillis(5000)
    .withTerminateGraceMillis(1000)
CommandResult result = shell.runWith(context, line, options).value()
if result.isTimedOut() {
    diagnose("timed out")
}
```

超时先 `Terminate`，宽限后 `Kill`；`wait` 返回 `Ok(exitCode)`，`isTimedOut` 为真。

### C10：流式与有界捕获

```xnull
ShellOptions options = ShellOptions.defaults()
    .withStdoutSink(Stdio.stdout())
    .withMaximumOutputBytes(65536)
    .withMergeStderr(true)
```

sink 实时收到合并后的 stdout；捕获只保留前 64 KiB，其余排空并丢弃；`isTruncated` 为真。

### C11：spawn + wait + close

```xnull
CommandResult pending = shell.spawnWith(context, line, options).value()
Result<Int, Error> status = pending.wait(context)
```

启动后可先做其他工作，再 `wait`；不等待时必须 `close` 放弃，否则进程/管道泄漏。

### C12：系统资源快照

```xnull
SystemResource resource = new SystemResource()
SystemSnapshot snapshot = resource.capture()
Int cores = snapshot.cpuCores()
Long available = snapshot.memoryAvailableBytes()
```

只读、一次性；不缓存、不监控、不枚举进程表。

### C13：显式 CliRuntime

```xnull
CliRuntime runtime = CliRuntime.current(new Args(rawArguments))
Result<ParseResult, Error> parsed = new Parser(app).parse(runtime.arguments().raw())
```

测试时用内存 Reader/Writer 替换；`CliRuntime` 不 close 标准流。

### C14：退出码映射

```xnull
if parsed.isErr() {
    diagnose(parsed.error().describe())
    return exitCodeValue(ExitCode.Usage)
}
CommandResult result = shell.runWith(context, line, options).value()
if result.isSuccess() {
    return exitCodeValue(ExitCode.Ok)
}
return exitCodeValue(ExitCode.Error)
```

应用决定进程退出；Shell 不调用退出。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| shell 字符串/管道/重定向/glob/变量 | 不做；只接受 `CommandLine`；需要 shell 语义时调用方显式执行 `/bin/sh -c`，风险自担 |
| Pipeline | X；当前不提供 `Pipeline` 类型，调用方显式组合 sys 进程原语 |
| PTY/交互式 stdin | X；`ShellOptions.stdin` 只支持固定字节，不继承终端 |
| shell 补全 | `Completion`/`CompletionScript` 类型 X；`completionBash`/`completionWords` 只生成 `complete -W` 文本，不执行/安装 |
| 参数文件/response file | X |
| sys 公开 stdio 管道 | `xdk.sys` 的 1.x `spawnProcessPiped`/Process stdio 兼容面保留；CLI `Shell` 仍用内部管道，不把它变成 Shell 语法 |
| 环境变量 unset | 不支持；用 `withInheritEnvironment(false)` + 精确 env 覆盖 |
| 默认值优先级 | Parser 不偷读；`resolveValue` 显式 argv > env > 非空 config > fallback |
| 超时 | 是结果，不是 `Err(Timeout)`；不合成 124；`isTimedOut` 权威 |
| 信号 |  只基本 Terminate/Kill；Windows 语义受限，返回 `Unsupported`/`Unavailable` |
| 进程组/后代 | `Shell` 不 kill 进程组；`xdk.sys.Process.sendGroupSignal` 是独立 1.x 兼容面 |
| 输出上限 | 每流独立；0 = 不限制；只限制保留，始终排空；sink 不受上限保护 |
| secret 日志 | `describe` 脱敏；调用方不得把 argv/env/stdin/输出直接写日志 |
| SystemResource 范围 | 当前系统/当前或指定进程；不枚举进程表、不读 cgroup/容器/GPU/温度/网络 |
| SystemSnapshot 一致性 | 快照；不承诺实时/强一致；缺失字段沿用 sys 的 0/空 |
|  `xdk.os` | 不依赖；CPU/内存/磁盘/平台只走 core `sys` |
| CliRuntime.current | 读取进程全局的显式便利入口；Parser/Shell 不隐式调用 |
| CommandResult 并发 | 单等待者/单输出读取者；跨任务需外部同步 |
| spawn 排空时机 | 只启动；stdin/输出/超时在 `wait` 中处理；未 wait 前子进程可能因管道写满阻塞 |
| `wait` 后 close | 幂等 no-op；close 错误不再影响已知命令结果 |
| 非零退出 | 不是 `Err`；由调用方映射业务退出码 |
| 应用退出 | `Shell`/`Parser` 不调用进程退出；应用负责 |
| 默认输出上限 | 1 MiB/流；防止无界捕获；可显式放宽/关闭 |
| 默认 stdin | 空字节 EOF；不继承父 stdin |
| 系统资源只读 | 不写环境/文件/进程；不发信号 |
| 参数校验 | 非法名字/数值/管道 panic；执行期失败走 `Result` |
| 权限提升 | 不做；Shell 以调用方身份执行，不注入 sudo/权限包装 |

---

## 8. 行业调研与取舍

| 来源 | 观察 | 取舍 |
| --- | --- | --- |
| [Cobra](https://cobra.dev/) | 命令树、持久 flag、自动 help、shell completion；`Execute` 返回错误 | 命令树已有；不自动 help/completion；Shell 不执行命令字符串 |
| [picocli](https://picocli.info/) | `CommandLine.execute` 返回退出码，应用再 `System.exit`；类型转换、补全 | 采纳“执行返回结果、应用退出”；不采纳注解/反射/自动补全 |
| [clap](https://docs.rs/clap/latest/clap/) | 解析器与 help 一体；补全由独立 `clap_complete` | 解析/执行/补全分离；补全仍 X |
| [System.CommandLine](https://learn.microsoft.com/en-us/dotnet/standard/commandline/) | POSIX 风格解析、tab completion、response files | 采纳 POSIX 风格；response file/补全后置 |
| [CLI Guidelines](https://clig.dev/) | 成功 exit 0；主输出 stdout、消息 stderr；信号；不要在 flag 中放 secret | 采纳退出码/流分离/秘密原则；不强制交互提示 |
| [execve(2)](https://man7.org/linux/man-pages/man2/execve.2.html) | 程序与 argv 数组分开，内核不解析 shell 语法 | 采纳 argv-only；拒绝 shell 字符串 |
| [pipe(2)](https://man7.org/linux/man-pages/man2/pipe.2.html) | 管道是显式 fd，需调用方连接 | 采纳显式管道；不做 shell 管道语法；Pipeline X |
| [wait(2)](https://man7.org/linux/man-pages/man2/wait.2.html) | 退出状态与终止信号分开 | 采纳 `exitCode` + `signal` 双字段；不把信号硬编码成业务码 |
| [signal(7)](https://man7.org/linux/man-pages/man7/signal.7.html) | 信号语义平台差异；SIGKILL 不可捕获 | 采纳基本 Terminate/Kill；平台不支持返回 `Unsupported` |
| [Rust `std::process::Command`](https://doc.rust-lang.org/std/process/struct.Command.html) | `spawn` 返回子进程，`output` 等待并捕获 | 采纳 spawn/run 双入口；结果对象持有生命周期 |
| [Python `subprocess`](https://docs.python.org/3/library/subprocess.html) | argv 列表与 `shell=True` 明确分开 | 采纳“默认 argv、无 shell”；不提供等价 `shell=True` |
| [Go `os/exec`](https://pkg.go.dev/os/exec) | `Command` 不经过 shell；stdin/stdout/stderr 显式 | 采纳显式 stdio；不继承隐式终端 |

> 系统资源字段沿用 core `sys` 的 `SystemInfo`/`Env`/`Platform`/`Process`；本包不复制  OS 类型，也不把容器/cgroup/GPU 探测塞进 CLI。

## 9. 1.x 兼容合同（C7）

| 1.x API | 2.x 合同 | 失败/边界 |
| --- | --- | --- |
| `OptionSpec.withShort(String)` | [`OptionSpec.md`](OptionSpec.md) `withShort` 别名 → `withShortName` | 非法短名 → panic |
| `Args.expandShortFlags(List<String>)` | [`Args.md`](Args.md)；全已知 `-abc` → `-a -b -c`，未知原样 | null → panic；Parser 不自动展开 |
| `Args.value` / `lastValue` / `values` | `Args` 同名；首次/末次/全部 | 缺失返回空串/空列表；不改变 `valueOrNull` last-wins |
| `Args.terminatorIndex` | `Args` 同名 | 无 `--` → -1 |
| `completionBash(Command)` / `completionWords(Command)` | 顶层同名；生成 bash `complete -W` 文本 | null → panic；只生成文本，不执行 |
| `defaultFromEnv(String, String)` | 顶层同名；env 存在 → env，否则 fallback | null → panic |
| `resolveValue(Args, String, String, String, String)` | 顶层同名；argv > env > 非空 config > fallback | null → panic |
| `CommandMatch` | 2.x 主名 `ParseResult`；`CommandMatch` 为兼容别名 | 不新增第二套解析结果 |

示例：

```xnull
OptionSpec output = new OptionSpec("output").withShort("o").withValueName("file")
Args expanded = new Args(["-abc"]).expandShortFlags(["a", "b", "c"])
String text = completionBash(command)
String value = resolveValue(args, "--mode", "APP_MODE", configValue, "default")
```

测试义务：短名别名；短选项簇全已知/含未知/`--` 后；首次/末次/全部值；`completionBash` 根/子命令文本；env/config/fallback 优先级；`CommandMatch` 别名；Parser 仍拒绝未预展开的 `-abc`。

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | `@CliCommand`、`@CliSubcommand`、`@Option`、`@Arg` |
| 本包消费 | `@Value`、`@Builder`、`@Copy`、`@Deprecated` |
| 处理器 | CliAnnotationProcessor（Resolve/Validate/Generate） |
| 生成物 | 命令树、选项/参数表、帮助/补全元数据、解析器绑定 |
| 状态 | 领域注解 planned；A8 派生 planned；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 命令类 | `@CliCommand` | 命令树/帮助元数据 |
| 子命令类 | `@CliSubcommand` | 子命令表 |
| 命令字段/参数 | `@Option`/`@Arg` | 解析表/默认值/必填校验 |
| `Command`/`ParseResult` | `@Value` | 值语义/复制 |
| `OptionSpec` | — | 已是显式 builder，不叠加 `@Builder` |

### 声明

```x
@Target(Type)
@Retention(Runtime)
@annotation CliCommand {
    final String name
    final String summary = ""
}

@Target(Type)
@Retention(Runtime)
@annotation CliSubcommand {
    final String name
}

@Target(Field, Parameter)
@Retention(Runtime)
@annotation Option {
    final String name
    final String shortName = ""
    final Bool required = false
}

@Target(Field, Parameter)
@Retention(Runtime)
@annotation Arg {
    final String name
    final Bool required = true
}
```

### 使用

```x
@CliCommand("deploy", "Deploy an artifact")
class DeployCommand {
    @Option("--env", "-e") String env = "dev"
    @Arg("artifact") String artifact
}

@CliSubcommand("status")
class StatusCommand {
    @Option("--json") Bool json = false
}
```

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
