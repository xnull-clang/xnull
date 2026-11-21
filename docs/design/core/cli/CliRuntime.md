# `CliRuntime`

| 项 | 值 |
| --- | --- |
| 类型 | `class CliRuntime` |
| 包 | `xdk.cli` |
| 稳定性 | `preview` |
| 依赖 | `Args`、`Env`、`Reader`、`Writer`、`Platform`、`Stdio` |

---

## 1. 定位

显式的 CLI 运行时上下文：原始参数 `Args`、环境 `Env`、工作目录、stdin/stdout/stderr、输入/输出终端标志。

它把“进程级输入”收拢为一个可传递、可替换、可测试的对象；解析器、Shell、诊断输出都从调用方显式接收它，而不是偷偷读全局。

不做：全局单例、环境修改、关闭标准流、参数解析、命令执行、终端 UI、信号处理。

---

## 2. 设计逻辑

- 字段全部 `final`；所有 `with*` 返回新实例。
- `current(Args arguments)` 是一次显式快照：读取 `Env.snapshot()`、`Platform.cwd()`、`Stdio.stdin/stdout/stderr`、`Stdio.isTerminalIn/Out`。
- `Parser` 不读取 `CliRuntime`；调用方用 `runtime.arguments().raw()` 显式传入。
- `Shell` 不读取 `CliRuntime`；调用方把 cwd/env 显式放进 `CommandLine`/`ShellOptions`。
- 标准流是借用引用；`CliRuntime` 不 close 它们。
- `isInteractive` 只在输入和输出都是终端时为 true；仅一个方向是 TTY 不算交互。
- `describe` 不打印参数值、环境值或流内容。
- 无 close；无资源所有权；可共享，但底层 Reader/Writer 的并发安全由实现决定。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_arguments` | `Args` | 原始 argv 快照 |
| `_environment` | `Env` | 环境快照 |
| `_workingDirectory` | `String` | 当前工作目录 |
| `_stdin` | `Reader` | 标准输入 |
| `_stdout` | `Writer` | 标准输出 |
| `_stderr` | `Writer` | 标准错误 |
| `_isTerminalInput` | `Bool` | stdin 是否 TTY |
| `_isTerminalOutput` | `Bool` | stdout 是否 TTY |

不变量：

- `arguments`/`environment`/`stdin`/`stdout`/`stderr` 非 null；
- `workingDirectory` 非空、不含 NUL；
- 不可变；不 close 标准流。

---

## 4. 生命周期

构造后不可变；无 close；标准流由进程/调用方拥有；可跨任务传递，但 Reader/Writer 是否可并发使用取决于其实现。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `CliRuntime(Args arguments, Env environment, String workingDirectory, Reader stdin, Writer stdout, Writer stderr, Bool isTerminalInput, Bool isTerminalOutput)` | 见 §6 | 非 null；cwd 非空；无 NUL | 非法 → panic |
| `CliRuntime.current(Args arguments)` | arguments | 非 null | null → panic |

`current` 是显式便利入口；它不是全局单例，也不缓存。每次调用捕获当时的环境/cwd/终端状态。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `current` | 从进程状态捕获 | `Args arguments` | `CliRuntime` | null → panic |
| `arguments` | 原始参数 | 无 | `Args` | 无 |
| `environment` | 环境快照 | 无 | `Env` | 无 |
| `workingDirectory` | cwd | 无 | `String` | 无 |
| `stdin` | 标准输入 | 无 | `Reader` | 无 |
| `stdout` | 标准输出 | 无 | `Writer` | 无 |
| `stderr` | 标准错误 | 无 | `Writer` | 无 |
| `isTerminalInput` | stdin 是否 TTY | 无 | `Bool` | 无 |
| `isTerminalOutput` | stdout 是否 TTY | 无 | `Bool` | 无 |
| `isInteractive` | 输入输出都是 TTY | 无 | `Bool` | 无 |
| `withArguments` | 替换参数 | `Args value` | `CliRuntime` | null → panic |
| `withEnvironment` | 替换环境 | `Env value` | `CliRuntime` | null → panic |
| `withWorkingDirectory` | 替换 cwd | `String path` | `CliRuntime` | 空/null/NUL → panic |
| `withStdin` | 替换 stdin | `Reader value` | `CliRuntime` | null → panic |
| `withStdout` | 替换 stdout | `Writer value` | `CliRuntime` | null → panic |
| `withStderr` | 替换 stderr | `Writer value` | `CliRuntime` | null → panic |
| `withTerminalInput` | 替换输入 TTY 标志 | `Bool value` | `CliRuntime` | 无 |
| `withTerminalOutput` | 替换输出 TTY 标志 | `Bool value` | `CliRuntime` | 无 |
| `describe` | 诊断摘要（不含值） | 无 | `String` | 无 |

说明：

- `arguments()`/`environment()` 返回不可变对象；`stdin/stdout/stderr` 返回借用引用。
- `with*` 不复制流，只替换引用；所有权仍归调用方。
- `describe` 只显示参数个数、环境变量数、cwd、两个终端标志和交互标志；不显示参数值、环境值或流内容。

---

## 8. 使用的技术

- 显式上下文对象；
- 不可变值字段；
- 借用流引用；
- 快照工厂；
- TTY 标志。

---

## 9. 需要的支撑

- 语言：class、String、Bool；
- 运行时：`Env.snapshot`、`Platform.cwd`、`Stdio.stdin/stdout/stderr`、`Stdio.isTerminalIn/Out`；
- 接口：`Args`、`Env`、`Reader`、`Writer`、`Platform`、`Stdio`。

---

## 10. 依赖的特性/接口/类

`Args`、`Env`、`Reader`、`Writer`、`Platform`、`Stdio`。

---

## 11. 所有权与并发

`Args`/`Env` 不可变；`Reader`/`Writer` 借用，`CliRuntime` 不 close；不可变对象可共享；底层流的并发行为由实现决定，跨任务写入需外部同步。引用语义；未提供 `equals`/哈希。

---

## 12. 示例与反例

正确：

```xnull
CliRuntime runtime = CliRuntime.current(new Args(rawArguments))
Result<ParseResult, Error> parsed = new Parser(app).parse(runtime.arguments().raw())
```

测试替换：

```xnull
ByteArrayWriter stdout = new ByteArrayWriter()
CliRuntime runtime = new CliRuntime(new Args(["app"]), Env.snapshot(), "/work",
    new StringReader(""), stdout, new ByteArrayWriter(), false, false)
```

反例：

- 让 `Parser` 自己读 `Env`/`Stdio`；
- 把 `CliRuntime` 做成全局单例；
- 在 `describe` 中打印 argv/env；
- `CliRuntime` 负责 close 标准流；
- 期望 `withStdin` 复制 Reader。

---

## 13. 测试/场景义务

`current` 快照；参数/环境替换；cwd 替换；stdin/stdout/stderr 替换；TTY 标志；`isInteractive` 组合；`describe` 不含值；非法 cwd panic；流借用不 close；副本独立性（Args/Env 不可变，流引用相同）。

---

## 14. XNull 伪代码

```xnull
class CliRuntime {
    final Args _arguments
    final Env _environment
    final String _workingDirectory
    final Reader _stdin
    final Writer _stdout
    final Writer _stderr
    final Bool _isTerminalInput
    final Bool _isTerminalOutput

    CliRuntime(Args arguments, Env environment, String workingDirectory, Reader stdin,
               Writer stdout, Writer stderr, Bool isTerminalInput, Bool isTerminalOutput) {
        if arguments == null || environment == null {
            throw "CliRuntime: null source"
        }
        if workingDirectory == null || workingDirectory == "" || workingDirectory.indexOf("\0") >= 0 {
            throw "CliRuntime: invalid working directory"
        }
        if stdin == null || stdout == null || stderr == null {
            throw "CliRuntime: null stream"
        }
        _arguments = arguments
        _environment = environment
        _workingDirectory = workingDirectory
        _stdin = stdin
        _stdout = stdout
        _stderr = stderr
        _isTerminalInput = isTerminalInput
        _isTerminalOutput = isTerminalOutput
    }

    static CliRuntime current(Args arguments) {
        if arguments == null { throw "CliRuntime.current: null arguments" }
        return new CliRuntime(
            arguments,
            Env.snapshot(),
            Platform.cwd(),
            Stdio.stdin(),
            Stdio.stdout(),
            Stdio.stderr(),
            Stdio.isTerminalIn(),
            Stdio.isTerminalOut())
    }

    Args arguments() { return _arguments }
    Env environment() { return _environment }
    String workingDirectory() { return _workingDirectory }
    Reader stdin() { return _stdin }
    Writer stdout() { return _stdout }
    Writer stderr() { return _stderr }
    Bool isTerminalInput() { return _isTerminalInput }
    Bool isTerminalOutput() { return _isTerminalOutput }
    Bool isInteractive() { return _isTerminalInput && _isTerminalOutput }

    CliRuntime withArguments(Args value) {
        if value == null { throw "CliRuntime.withArguments: null value" }
        return new CliRuntime(value, _environment, _workingDirectory, _stdin,
            _stdout, _stderr, _isTerminalInput, _isTerminalOutput)
    }

    CliRuntime withEnvironment(Env value) {
        if value == null { throw "CliRuntime.withEnvironment: null value" }
        return new CliRuntime(_arguments, value, _workingDirectory, _stdin,
            _stdout, _stderr, _isTerminalInput, _isTerminalOutput)
    }

    CliRuntime withWorkingDirectory(String path) {
        if path == null || path == "" || path.indexOf("\0") >= 0 {
            throw "CliRuntime.withWorkingDirectory: invalid path"
        }
        return new CliRuntime(_arguments, _environment, path, _stdin,
            _stdout, _stderr, _isTerminalInput, _isTerminalOutput)
    }

    CliRuntime withStdin(Reader value) {
        if value == null { throw "CliRuntime.withStdin: null value" }
        return new CliRuntime(_arguments, _environment, _workingDirectory, value,
            _stdout, _stderr, _isTerminalInput, _isTerminalOutput)
    }

    CliRuntime withStdout(Writer value) {
        if value == null { throw "CliRuntime.withStdout: null value" }
        return new CliRuntime(_arguments, _environment, _workingDirectory, _stdin,
            value, _stderr, _isTerminalInput, _isTerminalOutput)
    }

    CliRuntime withStderr(Writer value) {
        if value == null { throw "CliRuntime.withStderr: null value" }
        return new CliRuntime(_arguments, _environment, _workingDirectory, _stdin,
            _stdout, value, _isTerminalInput, _isTerminalOutput)
    }

    CliRuntime withTerminalInput(Bool value) {
        return new CliRuntime(_arguments, _environment, _workingDirectory, _stdin,
            _stdout, _stderr, value, _isTerminalOutput)
    }

    CliRuntime withTerminalOutput(Bool value) {
        return new CliRuntime(_arguments, _environment, _workingDirectory, _stdin,
            _stdout, _stderr, _isTerminalInput, value)
    }

    String describe() {
        return "arguments=" + str(_arguments.length())
            + " environment=" + str(_environment.length())
            + " cwd=" + _workingDirectory
            + " terminalIn=" + str(_isTerminalInput)
            + " terminalOut=" + str(_isTerminalOutput)
            + " interactive=" + str(self.isInteractive())
    }
}
```
