# `CommandResult`

| 项 | 值 |
| --- | --- |
| 类型 | `class CommandResult` |
| 包 | `xdk.cli` |
| 稳定性 | `preview` |
| 依赖 | `CommandLine`、`ShellOptions`、`CommandOutput`、`Process`、`Signal`、`Context`、`Duration`、`Bytes`、`Writer`、`Error` |

---

## 1. 定位

一次命令执行的结果句柄：`Shell.spawn` 返回未完成结果，`Shell.run` 返回已完成结果；`wait` 完成唯一状态迁移，之后提供退出码、信号、耗时、输出快照和超时/取消标志。

不做：命令行解析、shell 解释、进程创建（`Shell` 负责）、把非零退出当错误、进程退出调用、重试。

---

## 2. 设计逻辑

- 两态：**pending**（已启动、未完成）与 **completed**（已回收、字段冻结）。
- `wait` 是唯一完成入口：排空 stdin/stdout/stderr、处理超时、回收进程、构造 `CommandOutput`、写入最终字段。
- 非零退出码是正常完成，不是 `Err`；`isSuccess()` 只对“已完成、未超时、未取消、exit 0”为 true。
- `signalOrNull` 是信号终止的权威信息；`exitCodeOrNull` 是 OS 等待状态，信号终止时可能是平台相关的 `128 + signal`，不得当业务码。
- 超时是**执行结果**：到点后先 `Terminate`，宽限期后 `Kill`；`terminateGraceMillis == 0` 时直接 `Kill`；最终仍返回 `Ok(exitCode)`，由 `isTimedOut()` 标记。
- 取消是**调用方中止**：kill、回收、构造部分输出，然后 `wait` 返回 `Err(Cancelled)`；`isCancelled()` 为 true。
- `close` 在 pending 时表示放弃：kill、回收、丢弃输出；`wait` 之后返回 `Unavailable`。`close` 幂等。
- 启动失败/管道创建失败在 `Shell.spawn` 就返回 `Err`，不会产生 `CommandResult`。
- 输出保留上限只影响捕获，不影响排空；sink 失败视为执行期 I/O 失败，kill 并返回 `Err(Io)`。
- 未完成的 `outputOrNull()` 返回 null；`output()` 在未完成时是合同错误。
- 所有公开字段读取在完成后稳定；pending 期间只允许单等待者/单读取者，不承诺线程安全。
- `describe` 不打印参数值、环境值、stdin 或输出内容。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_commandLine` | `CommandLine` | 命令规格 |
| `_options` | `ShellOptions` | 执行策略（含 sink/stdin/上限/超时） |
| `_startedAtMillis` | `Long` | 单调启动时刻 |
| `_process` | `Process?` | pending 时非 null；完成后 null |
| `_stdoutPipe` | `PipeHandle?` | stdout 管道 |
| `_stderrPipe` | `PipeHandle?` | stderr 管道；合并时 null |
| `_stdinPipe` | `PipeHandle?` | stdin 管道 |
| `_stdoutCapture` | `Bytes` | 已保留 stdout |
| `_stderrCapture` | `Bytes` | 已保留 stderr |
| `_stdoutByteCount` | `Long` | 已排空 stdout 总字节 |
| `_stderrByteCount` | `Long` | 已排空 stderr 总字节 |
| `_stdinOffset` | `Int` | 已写入 stdin 的字节偏移 |
| `_isStdoutOpen` | `Bool` | stdout 管道仍可读 |
| `_isStderrOpen` | `Bool` | stderr 管道仍可读 |
| `_isStdinOpen` | `Bool` | stdin 管道仍可写 |
| `_isTruncated` | `Bool` | 是否丢弃过保留字节 |
| `_output` | `CommandOutput?` | 完成后输出快照 |
| `_exitCode` | `Int?` | 完成后退出码 |
| `_signal` | `Signal?` | 信号终止/无 |
| `_durationMillis` | `Long?` | 完成后/放弃后耗时 |
| `_isTimedOut` | `Bool` | 是否因超时终止 |
| `_isCancelled` | `Bool` | 是否被取消 |
| `_isAbandoned` | `Bool` | 是否被 close 放弃 |
| `_isComplete` | `Bool` | 是否已完成迁移 |

不变量：

- pending：`_process != null`、`_isComplete == false`、`_isAbandoned == false`、`_output == null`、`_exitCode == null`、`_durationMillis == null`；
- completed：`_process == null`、`_isComplete == true`、`_output != null`、`_exitCode != null`、`_durationMillis != null`；
- abandoned：`_process == null`、`_isAbandoned == true`、`_isComplete == false`、`_output == null`；取消清理失败时 `_isCancelled` 也为 true；
- `_isTimedOut` 只能在 completed 时为 true；
- `_isCancelled` 为 true 时 `wait` 始终返回 `Cancelled`；
- `CommandOutput` 的计数/截断由 Shell 的排空循环保证。

---

## 4. 生命周期

`Shell.spawn` 创建 pending；`wait` 完成并回收；`close` 可提前放弃；完成后 `close` 幂等 no-op；`output` 快照在完成后可重复读取。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `CommandResult(CommandLine commandLine, ShellOptions options, Process process, PipeHandle? stdoutPipe, PipeHandle? stderrPipe, PipeHandle? stdinPipe, Long startedAtMillis)` | 见 §6 | 非 null；进程打开；stdout/stdin 管道非 null；`startedAtMillis ≥ 0` | 非法 → panic |

构造器是包内合同，主要供 `Shell.spawnWith` 使用；调用方不应直接创建。

---

## 6. 字段表

见 §3；字段私有。`PipeHandle` 是 `xdk.cli` 内部管道句柄，不是公开类型。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `commandLine` | 命令规格 | 无 | `CommandLine` | 无 |
| `wait` | 等待完成/排空/回收 | `Context context` | `Result<Int, Error>` | `Cancelled`/`Io`/`Unavailable`；null → panic |
| `isComplete` | 是否完成 | 无 | `Bool` | 无 |
| `isAbandoned` | 是否被放弃 | 无 | `Bool` | 无 |
| `exitCodeOrNull` | 退出码/未完成 | 无 | `Int?` | 无 |
| `signalOrNull` | 终止信号/无 | 无 | `Signal?` | 无 |
| `durationMillisOrNull` | 耗时/未完成 | 无 | `Long?` | 无 |
| `elapsedMillis` | 已运行时间 | 无 | `Long` | 无 |
| `outputOrNull` | 输出快照/未完成 | 无 | `CommandOutput?` | 无 |
| `output` | 输出快照 | 无 | `CommandOutput` | 未完成 → panic |
| `isSuccess` | 成功完成 | 无 | `Bool` | 无 |
| `isTimedOut` | 是否超时 | 无 | `Bool` | 无 |
| `isCancelled` | 是否取消 | 无 | `Bool` | 无 |
| `isSignaled` | 是否信号终止 | 无 | `Bool` | 无 |
| `signal` | 向 pending 进程发信号 | `Context context, Signal signal` | `Result<Unit, Error>` | `Unavailable`/`Io`；null → panic |
| `close` | 放弃/释放 | 无 | `Result<Unit, Error>` | `Io` |
| `describe` | 诊断摘要（不含值） | 无 | `String` | 无 |

内部方法：

| 方法 | 用途 | 失败 |
| --- | --- | --- |
| `pumpStdin` | 非阻塞写 stdin | `Io` |
| `pumpStdout` | 非阻塞读 stdout + sink | `Io` |
| `pumpStderr` | 非阻塞读 stderr + sink | `Io` |
| `appendBounded` | 有界追加 | 无 |
| `requestTermination` | 超时 Terminate/Kill | 无（best effort） |
| `finishCompleted` | 回收并冻结结果 | `Cancelled`/`Io`/`Unavailable` |
| `finishCancelled` | 取消清理 | `Cancelled` |
| `failWith` | I/O 失败清理 | 原错误 |
| `releasePipes` | 关闭全部管道 | 无（诊断） |
| `buildOutput` | 构造 `CommandOutput` | 无 |
| `isProcessAlive` | 存活查询 | 无 |

说明：

- `wait` 完成后再次调用：正常/超时返回同一 `exitCode`；取消返回 `Cancelled`；放弃返回 `Unavailable`。
- `spawn` 只启动；排空发生在 `wait` 期间。未 `wait` 前子进程可能因 stdout/stderr 管道写满而阻塞；调用方应尽快 `wait`。sink 的实时写入也发生在 `wait` 的排空循环中。
- `wait` 成功回收后对管道/进程 `close` 采用 best-effort；close 诊断错误不改变已知命令结果；`close()` 放弃 pending 时返回清理错误。
- 超时且直接子进程已退出时，`wait` 停止等待后代可能持有的管道，关闭管道并结束；此时输出可能不完整，`isTimedOut()` 为真。
- `durationMillisOrNull` 在 `close` 放弃 pending 时也会写入“已运行时间”，但没有退出码。
- `signal` 只对 pending 有效；completed/abandoned 返回 `Unavailable`。
- `isSuccess` 对 pending/超时/取消/非零退出均为 false。
- `describe` 只报告程序名、参数个数、退出码/信号、耗时、超时/取消和输出计数。

---

## 8. 使用的技术

- 两态结果对象；
- 非阻塞管道泵；
- 超时 + 终止宽限；
- 有界捕获；
- 信号/退出码归一；
- sink 流式写入；
- 幂等 close。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Int、Long、Bytes、List、Result、Context；
- 运行时：`readPipeAvailableRaw`、`writePipeAvailableRaw`、`closePipeRaw`、`pollPipesRaw`、`signalFromStatusRaw`、`signalNumber`、`nowMono`、`Duration.ofMillis`；
- 接口：`Process`、`Signal`、`CommandOutput`、`Writer`、`BasicError`、`ErrorKind`。

`PipeHandle`/`PipedProcess` 是内部管道句柄；不是公开类型。`readPipeAvailableRaw` 返回 >0 字节数、0 暂无数据、<0 EOF；`writePipeAvailableRaw` 返回 >0 已写字节、0 暂时不可写；`pollPipesRaw` 最多等待给定毫秒并返回就绪状态。

---

## 10. 依赖的特性/接口/类

`CommandLine`、`ShellOptions`、`CommandOutput`、`Process`、`Signal`、`Context`、`Duration`、`Writer`、`BasicError`、`ErrorKind`、`Bytes`。

---

## 11. 所有权与并发

- pending 时拥有进程与管道；`wait` 或 `close` 释放。
- 完成后只拥有不可变输出快照；进程/管道已关闭。
- pending 期间不承诺线程安全：单等待者、单输出读取者；`signal` 与 `wait` 并发使用需外部同步。
- 完成后可共享读取；`output` 快照只读。
- 引用语义（同一对象状态迁移）；未提供 `equals`/哈希，不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：

```xnull
CommandResult result = shell.runWith(context, commandLine, options).value()
Int status = result.exitCodeOrNull() as Int
if result.isTimedOut() {
    diagnose("command timed out")
}
CommandOutput output = result.output()
```

启动后等待：

```xnull
CommandResult pending = shell.spawnWith(context, commandLine, options).value()
Result<Int, Error> status = pending.wait(context)
if status.isErr() {
    diagnose(status.error().describe())
}
```

反例：

- 非零退出时 `Shell.runWith` 返回 `Err`；
- 未完成调用 `output()`；
- 超时后期望 `wait` 返回 `Err(Timeout)`（超时是结果，不是错误）；
- 取消后继续 `wait` 期望成功；
- `close` 后继续 `wait` 期望输出；
- 多任务并发 `wait`/读输出；
- 在日志里打印 `commandLine.argv()` 或输出内容。

---

## 13. 测试/场景义务

正常退出 0/非零；stdout/stderr；空输出；大输出截断；合并 stderr；超时 Terminate/Kill；超时后仍读到部分输出；取消；close pending；close 幂等；wait 重复；wait 后 close；signal pending/completed；sink 写失败；管道读失败；`describe` 不含值；`isSuccess` 各状态。

---

## 14. XNull 伪代码

```xnull
class CommandResult {
    final CommandLine _commandLine
    final ShellOptions _options
    final Long _startedAtMillis
    Process? _process
    PipeHandle? _stdoutPipe
    PipeHandle? _stderrPipe
    PipeHandle? _stdinPipe
    Bytes _stdoutCapture
    Bytes _stderrCapture
    Long _stdoutByteCount
    Long _stderrByteCount
    Int _stdinOffset
    Bool _isStdoutOpen
    Bool _isStderrOpen
    Bool _isStdinOpen
    Bool _isTruncated
    CommandOutput? _output
    Int? _exitCode
    Signal? _signal
    Long? _durationMillis
    Bool _isTimedOut
    Bool _isCancelled
    Bool _isAbandoned
    Bool _isComplete

    CommandResult(CommandLine commandLine, ShellOptions options, Process process,
                  PipeHandle? stdoutPipe, PipeHandle? stderrPipe, PipeHandle? stdinPipe,
                  Long startedAtMillis) {
        if commandLine == null || options == null || process == null {
            throw "CommandResult: null argument"
        }
        if stdoutPipe == null || stdinPipe == null {
            throw "CommandResult: missing pipe"
        }
        if !options.isMergeStderr() && stderrPipe == null {
            throw "CommandResult: missing stderr pipe"
        }
        if startedAtMillis < 0 {
            throw "CommandResult: negative start"
        }
        _commandLine = commandLine
        _options = options
        _startedAtMillis = startedAtMillis
        _process = process
        _stdoutPipe = stdoutPipe
        _stderrPipe = stderrPipe
        _stdinPipe = stdinPipe
        _stdoutCapture = Bytes.empty()
        _stderrCapture = Bytes.empty()
        _stdoutByteCount = 0
        _stderrByteCount = 0
        _stdinOffset = 0
        _isStdoutOpen = true
        _isStderrOpen = !options.isMergeStderr() && stderrPipe != null
        _isStdinOpen = true
        _isTruncated = false
        _output = null
        _exitCode = null
        _signal = null
        _durationMillis = null
        _isTimedOut = false
        _isCancelled = false
        _isAbandoned = false
        _isComplete = false
    }

    CommandLine commandLine() { return _commandLine }

    Result<Int, Error> wait(Context context) {
        if context == null { throw "CommandResult.wait: null context" }
        if _isCancelled {
            return Err(new BasicError(ErrorKind.Cancelled, "command cancelled"))
        }
        if _isAbandoned {
            return Err(new BasicError(ErrorKind.Unavailable, "command result abandoned"))
        }
        if _isComplete {
            Int? code = _exitCode
            if code == null {
                return Err(new BasicError(ErrorKind.Internal, "missing exit code"))
            }
            return Ok(code as Int)
        }
        if context.isCancelled() {
            return self.finishCancelled()
        }
        Bytes readBuffer = Bytes.alloc(32768)
        Bool timeoutRequested = false
        while true {
            if context.isCancelled() {
                return self.finishCancelled()
            }
            Result<Bool, Error> stdinProgress = self.pumpStdin(context)
            if stdinProgress.isErr() { return self.failWith(context, stdinProgress.error()) }
            Result<Bool, Error> stdoutProgress = self.pumpStdout(context, readBuffer)
            if stdoutProgress.isErr() { return self.failWith(context, stdoutProgress.error()) }
            Result<Bool, Error> stderrProgress = self.pumpStderr(context, readBuffer)
            if stderrProgress.isErr() { return self.failWith(context, stderrProgress.error()) }
            if !timeoutRequested && self.isTimeoutReached() {
                timeoutRequested = true
                _isTimedOut = true
                self.requestTermination(context)
            }
            Bool processAlive = self.isProcessAlive()
            if _isTimedOut && !processAlive {
                self.releasePipes()
                break
            }
            if !processAlive && !_isStdoutOpen && !_isStderrOpen && !_isStdinOpen {
                break
            }
            Bool didWork = stdinProgress.value() || stdoutProgress.value() || stderrProgress.value()
            if !didWork {
                self.waitForActivity(context)
            }
        }
        return self.finishCompleted(context)
    }

    private Result<Bool, Error> pumpStdin(Context context) {
        if !_isStdinOpen { return Ok(false) }
        PipeHandle? pipe = _stdinPipe
        if pipe == null {
            _isStdinOpen = false
            return Ok(false)
        }
        Bytes stdin = _options.stdin()
        if _stdinOffset >= stdin.length() {
            Result<Unit, Error> ignored = closePipeRaw(pipe)
            _isStdinOpen = false
            return Ok(true)
        }
        Result<Int, Error> written = writePipeAvailableRaw(pipe, stdin, _stdinOffset)
        if written.isErr() {
            if self.isProcessAlive() { return Err(written.error()) }
            Result<Unit, Error> ignored = closePipeRaw(pipe)
            _isStdinOpen = false
            return Ok(true)
        }
        if written.value() > 0 {
            _stdinOffset = _stdinOffset + written.value()
            return Ok(true)
        }
        if !self.isProcessAlive() {
            Result<Unit, Error> ignored = closePipeRaw(pipe)
            _isStdinOpen = false
            return Ok(true)
        }
        return Ok(false)
    }

    private Result<Bool, Error> pumpStdout(Context context, Bytes buffer) {
        if !_isStdoutOpen { return Ok(false) }
        PipeHandle? pipe = _stdoutPipe
        if pipe == null {
            _isStdoutOpen = false
            return Ok(false)
        }
        Result<Int, Error> read = readPipeAvailableRaw(pipe, buffer)
        if read.isErr() { return Err(read.error()) }
        if read.value() < 0 {
            _isStdoutOpen = false
            return Ok(true)
        }
        if read.value() == 0 { return Ok(false) }
        Bytes chunk = slice(buffer, 0, read.value())
        _stdoutByteCount = _stdoutByteCount + read.value()
        Bool truncated = self.appendBounded(_stdoutCapture, chunk, _options.maximumOutputBytes())
        if truncated { _isTruncated = true }
        Result<Unit, Error> sink = self.writeStdoutSink(context, chunk)
        if sink.isErr() { return Err(sink.error()) }
        return Ok(true)
    }

    private Result<Bool, Error> pumpStderr(Context context, Bytes buffer) {
        if !_isStderrOpen { return Ok(false) }
        PipeHandle? pipe = _stderrPipe
        if pipe == null {
            _isStderrOpen = false
            return Ok(false)
        }
        Result<Int, Error> read = readPipeAvailableRaw(pipe, buffer)
        if read.isErr() { return Err(read.error()) }
        if read.value() < 0 {
            _isStderrOpen = false
            return Ok(true)
        }
        if read.value() == 0 { return Ok(false) }
        Bytes chunk = slice(buffer, 0, read.value())
        _stderrByteCount = _stderrByteCount + read.value()
        Bool truncated = self.appendBounded(_stderrCapture, chunk, _options.maximumOutputBytes())
        if truncated { _isTruncated = true }
        Result<Unit, Error> sink = self.writeStderrSink(context, chunk)
        if sink.isErr() { return Err(sink.error()) }
        return Ok(true)
    }

    private Bool appendBounded(Bytes target, Bytes chunk, Long maximumBytes) {
        Long retained = target.length() as Long
        if maximumBytes == 0 {
            Int index = 0
            while index < chunk.length() {
                target.push(chunk.get(index))
                index = index + 1
            }
            return false
        }
        if retained >= maximumBytes { return true }
        Long remaining = maximumBytes - retained
        Int take = chunk.length()
        if (take as Long) > remaining { take = remaining as Int }
        Int index = 0
        while index < take {
            target.push(chunk.get(index))
            index = index + 1
        }
        return take < chunk.length()
    }

    private Result<Unit, Error> writeStdoutSink(Context context, Bytes chunk) {
        Writer? sink = _options.stdoutSink()
        if sink == null { return Ok(unit) }
        Writer writer = sink as Writer
        Result<Unit, Error> written = writer.writeAll(context, chunk)
        if written.isErr() { return Err(written.error()) }
        return writer.flush()
    }

    private Result<Unit, Error> writeStderrSink(Context context, Bytes chunk) {
        Writer? sink = _options.stderrSink()
        if sink == null { return Ok(unit) }
        Writer writer = sink as Writer
        Result<Unit, Error> written = writer.writeAll(context, chunk)
        if written.isErr() { return Err(written.error()) }
        return writer.flush()
    }

    private Bool isTimeoutReached() {
        if _options.timeoutMillis() <= 0 { return false }
        Long elapsed = nowMono() - _startedAtMillis
        return elapsed >= _options.timeoutMillis()
    }

    private void requestTermination(Context context) {
        Process? process = _process
        if process == null { return }
        Process target = process as Process
        if _options.terminateGraceMillis() <= 0 {
            Result<Unit, Error> killed = target.kill(context)
            return
        }
        Result<Unit, Error> terminated = target.signal(context, Signal.Terminate)
        if terminated.isErr() { return }
        Result<Int, Error> status = target.waitTimeout(
            context, Duration.ofMillis(_options.terminateGraceMillis()))
        if status.isOk() { return }
        Result<Unit, Error> killed = target.kill(context)
        return
    }

    private void waitForActivity(Context context) {
        pollPipesRaw(_stdoutPipe, _stderrPipe, _stdinPipe, context, 20)
    }

    private Bool isProcessAlive() {
        Process? process = _process
        if process == null { return false }
        Process target = process as Process
        return target.isAlive()
    }

    private Result<Int, Error> finishCompleted(Context context) {
        Process? process = _process
        if process == null {
            return Err(new BasicError(ErrorKind.Unavailable, "command result closed"))
        }
        Process target = process as Process
        Result<Int, Error> status = target.wait(context)
        if status.isErr() {
            self.releasePipes()
            Result<Unit, Error> ignored = target.close()
            _process = null
            _isAbandoned = true
            if status.error().kind() == ErrorKind.Cancelled {
                _isCancelled = true
            }
            _durationMillis = nowMono() - _startedAtMillis
            return Err(status.error())
        }
        self.releasePipes()
        Result<Unit, Error> ignored = target.close()
        _process = null
        _output = self.buildOutput()
        _exitCode = status.value()
        _signal = signalFromStatusRaw(status.value())
        _durationMillis = nowMono() - _startedAtMillis
        _isComplete = true
        return Ok(_exitCode as Int)
    }

    private Result<Int, Error> finishCancelled() {
        _isCancelled = true
        Context cleanupContext = Context.background()
        Process? process = _process
        if process != null {
            Process target = process as Process
            Result<Unit, Error> ignored = target.signal(cleanupContext, Signal.Kill)
        }
        Result<Int, Error> finished = self.finishCompleted(cleanupContext)
        if finished.isErr() {
            return Err(new BasicError(ErrorKind.Cancelled, "command cancelled during cleanup"))
        }
        return Err(new BasicError(ErrorKind.Cancelled, "command cancelled"))
    }

    private Result<Int, Error> failWith(Context context, Error error) {
        Process? process = _process
        if process != null {
            Process target = process as Process
            Result<Unit, Error> ignored = target.kill(context)
        }
        self.releasePipes()
        if process != null {
            Process target = process as Process
            Result<Unit, Error> ignored = target.close()
        }
        _process = null
        _isAbandoned = true
        if error.kind() == ErrorKind.Cancelled {
            _isCancelled = true
        }
        _durationMillis = nowMono() - _startedAtMillis
        return Err(error)
    }

    private void releasePipes() {
        PipeHandle? stdinPipe = _stdinPipe
        if stdinPipe != null {
            Result<Unit, Error> ignored = closePipeRaw(stdinPipe)
        }
        PipeHandle? stdoutPipe = _stdoutPipe
        if stdoutPipe != null {
            Result<Unit, Error> ignored = closePipeRaw(stdoutPipe)
        }
        PipeHandle? stderrPipe = _stderrPipe
        if stderrPipe != null {
            Result<Unit, Error> ignored = closePipeRaw(stderrPipe)
        }
        _isStdinOpen = false
        _isStdoutOpen = false
        _isStderrOpen = false
    }

    private CommandOutput buildOutput() {
        return new CommandOutput(_stdoutCapture, _stderrCapture, _stdoutByteCount,
            _stderrByteCount, _options.isMergeStderr(), _isTruncated)
    }

    Bool isComplete() { return _isComplete }
    Bool isAbandoned() { return _isAbandoned }
    Int? exitCodeOrNull() { return _exitCode }
    Signal? signalOrNull() { return _signal }
    Long? durationMillisOrNull() { return _durationMillis }

    Long elapsedMillis() {
        Long? duration = _durationMillis
        if duration != null { return duration as Long }
        return nowMono() - _startedAtMillis
    }

    CommandOutput? outputOrNull() { return _output }

    CommandOutput output() {
        CommandOutput? output = _output
        if output == null {
            throw "CommandResult.output: not complete"
        }
        return output as CommandOutput
    }

    Bool isSuccess() {
        if !_isComplete || _isTimedOut || _isCancelled { return false }
        Int? code = _exitCode
        if code == null { return false }
        return (code as Int) == 0
    }

    Bool isTimedOut() { return _isTimedOut }
    Bool isCancelled() { return _isCancelled }

    Bool isSignaled() {
        if _signal == null { return false }
        return true
    }

    Result<Unit, Error> signal(Context context, Signal signal) {
        if context == null || signal == null {
            throw "CommandResult.signal: null argument"
        }
        if _isComplete || _isAbandoned || _process == null {
            return Err(new BasicError(ErrorKind.Unavailable, "command result closed"))
        }
        Process target = _process as Process
        return target.signal(context, signal)
    }

    Result<Unit, Error> close() {
        if _isComplete || _isAbandoned { return Ok(unit) }
        _isAbandoned = true
        Error? firstError = null
        PipeHandle? stdinPipe = _stdinPipe
        if stdinPipe != null {
            Result<Unit, Error> closed = closePipeRaw(stdinPipe)
            if closed.isErr() && firstError == null { firstError = closed.error() }
        }
        PipeHandle? stdoutPipe = _stdoutPipe
        if stdoutPipe != null {
            Result<Unit, Error> closed = closePipeRaw(stdoutPipe)
            if closed.isErr() && firstError == null { firstError = closed.error() }
        }
        PipeHandle? stderrPipe = _stderrPipe
        if stderrPipe != null {
            Result<Unit, Error> closed = closePipeRaw(stderrPipe)
            if closed.isErr() && firstError == null { firstError = closed.error() }
        }
        Process? process = _process
        if process != null {
            Process target = process as Process
            Result<Unit, Error> closed = target.close()
            if closed.isErr() && firstError == null { firstError = closed.error() }
        }
        _process = null
        _isStdinOpen = false
        _isStdoutOpen = false
        _isStderrOpen = false
        _durationMillis = nowMono() - _startedAtMillis
        if firstError != null {
            return Err(firstError as Error)
        }
        return Ok(unit)
    }

    String describe() {
        String state = "pending"
        if _isAbandoned { state = "abandoned" }
        if _isComplete {
            Int? code = _exitCode
            if code != null { state = "exit=" + str(code as Int) }
        }
        String result = _commandLine.program() + " (" + str(_commandLine.argumentCount()) + " arguments) " + state
        if _isTimedOut { result = result + " timed_out" }
        if _isCancelled { result = result + " cancelled" }
        Long? duration = _durationMillis
        if duration != null {
            result = result + " duration=" + str(duration as Long) + "ms"
        }
        Signal? signal = _signal
        if signal != null {
            result = result + " signal=" + str(signalNumber(signal as Signal))
        }
        CommandOutput? output = _output
        if output != null {
            CommandOutput snapshot = output as CommandOutput
            result = result + " stdout=" + str(snapshot.stdoutByteCount()) + "B"
                + " stderr=" + str(snapshot.stderrByteCount()) + "B"
                + " truncated=" + str(snapshot.isTruncated())
        }
        return result
    }
}
```
