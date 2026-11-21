// Tier: T0；依赖：xdk.errors、xdk.runtime；稳定性：preview。
// xdk.sys —— 子进程、stdio 管道、信号与进程组。
package xdk.sys
import xdk.errors

// ProcessResult：命令输出与退出码。
class ProcessResult {
    Int code
    String output

    ProcessResult(Int codeValue, String outputValue) {
        self.code = codeValue
        self.output = outputValue
    }

    Int status() {
        return self.code
    }

    String stdout() {
        return self.output
    }
}

// Process：子进程句柄。wait 可重复取同一退出状态；close 未终结则 SIGKILL 并回收。
// 每个子进程自成一个进程组（组号 = pid），因此 sendGroupSignal 覆盖 shell 后代。
class Process {
    Long handle
    Bool opened
    Bool piped

    Process(Long handleValue, Bool pipedValue) {
        self.handle = handleValue
        self.opened = true
        self.piped = pipedValue
    }

    Bool isOpen() {
        return self.opened
    }

    Bool isPiped() {
        return self.piped
    }

    Int pid() {
        if !self.opened {
            return -1
        }
        Long h = self.handle
        return procPidRaw(h)
    }

    // 进程组号；spawn 后等于 pid。
    Int groupId() {
        return self.pid()
    }

    // 阻塞等待并返回退出码（被信号终止按 128+signum）。
    Result<Int, Error> wait() {
        if !self.opened {
            return Err(sysError(ErrorKind.Unavailable, "Process.wait: 句柄已关闭"))
        }
        Long h = self.handle
        Long status = procWaitRaw(h)
        if status < 0 {
            return Err(sysError(ErrorKind.Io, "Process.wait: 等待失败"))
        }
        return Ok(status as Int)
    }

    // 原始信号编号形态；推荐使用 sendSignal(Signal)。
    Result<Unit, Error> kill(Int signal) {
        if !self.opened {
            return Err(sysError(ErrorKind.Unavailable, "Process.kill: 句柄已关闭"))
        }
        if signal <= 0 {
            return Err(sysError(ErrorKind.InvalidArgument, "Process.kill: 信号编号非法"))
        }
        Long h = self.handle
        Int rc = procKillRaw(h, signal)
        if rc != 0 {
            return Err(sysError(ErrorKind.Io, "Process.kill: 发送信号失败"))
        }
        return Ok()
    }

    Result<Unit, Error> sendSignal(Signal signal) {
        Int number = signalNumber(signal)
        if number <= 0 {
            return Err(sysError(ErrorKind.Unsupported, "Process.sendSignal: 信号不受支持"))
        }
        return self.kill(number)
    }

    // 向整个进程组发送信号（覆盖 shell 及其后代）。
    Result<Unit, Error> sendGroupSignal(Signal signal) {
        if !self.opened {
            return Err(sysError(ErrorKind.Unavailable, "Process.sendGroupSignal: 句柄已关闭"))
        }
        Int number = signalNumber(signal)
        if number <= 0 {
            return Err(sysError(ErrorKind.Unsupported, "Process.sendGroupSignal: 信号不受支持"))
        }
        Long h = self.handle
        Int rc = procSignalGroupRaw(h, number)
        if rc != 0 {
            return Err(sysError(ErrorKind.Io, "Process.sendGroupSignal: 发送组信号失败"))
        }
        return Ok()
    }

    Result<Unit, Error> terminate() {
        Int number = signalNumberFromName("TERM")
        if number <= 0 {
            return Err(sysError(ErrorKind.Unsupported, "Process.terminate: TERM 不受支持"))
        }
        return self.kill(number)
    }

    // ---------- stdio 管道（仅 spawnProcessPiped 创建的进程可用） ----------

    Result<Long, Error> writeStdin(Bytes data) {
        if !self.opened {
            return Err(sysError(ErrorKind.Unavailable, "Process.writeStdin: 句柄已关闭"))
        }
        if !self.piped {
            return Err(sysError(ErrorKind.Unsupported, "Process.writeStdin: 进程未启用管道"))
        }
        Long h = self.handle
        Long written = procWriteStdinHexRaw(h, hexEncode(data))
        if written < 0 {
            return Err(sysError(ErrorKind.Io, "Process.writeStdin: 写入失败"))
        }
        return Ok(written)
    }

    Result<Long, Error> writeStdinText(String text) {
        return self.writeStdin(Bytes.fromString(text))
    }

    Result<Unit, Error> closeStdin() {
        if !self.opened {
            return Err(sysError(ErrorKind.Unavailable, "Process.closeStdin: 句柄已关闭"))
        }
        if !self.piped {
            return Err(sysError(ErrorKind.Unsupported, "Process.closeStdin: 进程未启用管道"))
        }
        Long h = self.handle
        Int rc = procCloseStdinRaw(h)
        if rc != 0 {
            return Err(sysError(ErrorKind.Io, "Process.closeStdin: 关闭失败"))
        }
        return Ok()
    }

    Result<Bytes, Error> readStdout(Long maximumBytes) {
        if maximumBytes < 0 {
            return Err(sysError(ErrorKind.InvalidArgument, "Process.readStdout: 长度为负"))
        }
        if !self.opened {
            return Err(sysError(ErrorKind.Unavailable, "Process.readStdout: 句柄已关闭"))
        }
        if !self.piped {
            return Err(sysError(ErrorKind.Unsupported, "Process.readStdout: 进程未启用管道"))
        }
        Long h = self.handle
        return Ok(hexDecode(procReadStdoutHexRaw(h, maximumBytes)))
    }

    Result<Bytes, Error> readStdoutAll() {
        if !self.opened {
            return Err(sysError(ErrorKind.Unavailable, "Process.readStdoutAll: 句柄已关闭"))
        }
        if !self.piped {
            return Err(sysError(ErrorKind.Unsupported, "Process.readStdoutAll: 进程未启用管道"))
        }
        Long h = self.handle
        return Ok(hexDecode(procReadAllStdoutHexRaw(h)))
    }

    Result<String, Error> readStdoutText() {
        Result<Bytes, Error> data = self.readStdoutAll()
        if data.isErr() {
            return Err(data.error())
        }
        return Ok(data.value().toString())
    }

    Result<Bytes, Error> readStderr(Long maximumBytes) {
        if maximumBytes < 0 {
            return Err(sysError(ErrorKind.InvalidArgument, "Process.readStderr: 长度为负"))
        }
        if !self.opened {
            return Err(sysError(ErrorKind.Unavailable, "Process.readStderr: 句柄已关闭"))
        }
        if !self.piped {
            return Err(sysError(ErrorKind.Unsupported, "Process.readStderr: 进程未启用管道"))
        }
        Long h = self.handle
        return Ok(hexDecode(procReadStderrHexRaw(h, maximumBytes)))
    }

    Result<Bytes, Error> readStderrAll() {
        if !self.opened {
            return Err(sysError(ErrorKind.Unavailable, "Process.readStderrAll: 句柄已关闭"))
        }
        if !self.piped {
            return Err(sysError(ErrorKind.Unsupported, "Process.readStderrAll: 进程未启用管道"))
        }
        Long h = self.handle
        return Ok(hexDecode(procReadAllStderrHexRaw(h)))
    }

    Result<String, Error> readStderrText() {
        Result<Bytes, Error> data = self.readStderrAll()
        if data.isErr() {
            return Err(data.error())
        }
        return Ok(data.value().toString())
    }

    Result<Unit, Error> close() {
        if !self.opened {
            return Ok()
        }
        self.opened = false
        Long h = self.handle
        Int rc = procCloseRaw(h)
        if rc != 0 {
            return Err(sysError(ErrorKind.Io, "Process.close: 回收失败"))
        }
        return Ok()
    }
}

// spawnProcess：不启用 stdio 管道；子进程自成进程组。
Result<Process, Error> spawnProcess(String command) {
    if command.length() == 0 {
        return Err(sysError(ErrorKind.InvalidArgument, "spawnProcess: 命令为空"))
    }
    Long handle = procSpawnRaw(command)
    if handle == 0 {
        return Err(sysError(ErrorKind.Io, "spawnProcess: 无法启动子进程"))
    }
    return Ok(new Process(handle, false))
}

// spawnProcessPiped：stdin/stdout/stderr 均接入管道。
Result<Process, Error> spawnProcessPiped(String command) {
    if command.length() == 0 {
        return Err(sysError(ErrorKind.InvalidArgument, "spawnProcessPiped: 命令为空"))
    }
    Long handle = procSpawnPipedRaw(command)
    if handle == 0 {
        return Err(sysError(ErrorKind.Io, "spawnProcessPiped: 无法启动子进程"))
    }
    return Ok(new Process(handle, true))
}

// runProcess：便捷同步形态，运行 shell 命令并返回退出码。
Int runProcess(String command) {
    Long code = procExitCodeRaw(command)
    return code as Int
}

// runProcessResult：运行命令并捕获 stdout（stderr 不捕获）。
Result<ProcessResult, Error> runProcessResult(String command) {
    if command.length() == 0 {
        return Err(sysError(ErrorKind.InvalidArgument, "runProcessResult: 命令为空"))
    }
    String text = procOutputRaw(command)
    Int code = procLastStatusRaw()
    if code < 0 {
        return Err(sysError(ErrorKind.Io, "runProcessResult: 无法执行命令"))
    }
    return Ok(new ProcessResult(code, text))
}
