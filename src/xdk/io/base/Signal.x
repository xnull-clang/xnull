// Tier: T0；依赖：xdk.errors；稳定性：preview。
// xdk.sys —— 信号名与发送面（POSIX 常用子集）。
package xdk.sys
import xdk.errors

enum Signal {
    Hangup,
    Interrupt,
    Quit,
    Kill,
    Terminate,
    User1,
    User2,
    Pipe,
    Alarm,
    Child,
    Stop,
    Continue
}

static String signalName(Signal signal) {
    if signal == Signal.Hangup { return "HUP" }
    if signal == Signal.Interrupt { return "INT" }
    if signal == Signal.Quit { return "QUIT" }
    if signal == Signal.Kill { return "KILL" }
    if signal == Signal.Terminate { return "TERM" }
    if signal == Signal.User1 { return "USR1" }
    if signal == Signal.User2 { return "USR2" }
    if signal == Signal.Pipe { return "PIPE" }
    if signal == Signal.Alarm { return "ALRM" }
    if signal == Signal.Child { return "CHLD" }
    if signal == Signal.Stop { return "STOP" }
    return "CONT"
}

// 平台信号编号；未知/不支持返回 -1。
Int signalNumber(Signal signal) {
    return signalNumberRaw(signalName(signal))
}

// 名称版本（大写，如 "TERM"）；未知返回 -1。
Int signalNumberFromName(String name) {
    return signalNumberRaw(name)
}

Result<Unit, Error> sendSignal(Int targetPid, Signal signal) {
    if targetPid <= 0 {
        return Err(sysError(ErrorKind.InvalidArgument, "sendSignal: pid 必须为正"))
    }
    Int number = signalNumber(signal)
    if number <= 0 {
        return Err(sysError(ErrorKind.Unsupported, "sendSignal: 信号不受支持"))
    }
    Int rc = signalSendRaw(targetPid, number)
    if rc != 0 {
        return Err(sysError(ErrorKind.Io, $"sendSignal: 无法发送 {signalName(signal)}"))
    }
    return Ok()
}

Result<Unit, Error> sendGroupSignal(Int processGroup, Signal signal) {
    if processGroup <= 0 {
        return Err(sysError(ErrorKind.InvalidArgument, "sendGroupSignal: 进程组必须为正"))
    }
    Int number = signalNumber(signal)
    if number <= 0 {
        return Err(sysError(ErrorKind.Unsupported, "sendGroupSignal: 信号不受支持"))
    }
    Int rc = signalGroupRaw(processGroup, number)
    if rc != 0 {
        return Err(sysError(ErrorKind.Io, $"sendGroupSignal: 无法发送 {signalName(signal)}"))
    }
    return Ok()
}
