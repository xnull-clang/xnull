// xdk.runtime —— 诊断、退出、时钟（T0-A）
// Tier: T0；依赖：runtime_raw.xfb；稳定性：stable。
//
// 原语由 runtime_raw.xfb 提供；env / dumpTasks 在后续切片补齐。
package xdk.runtime

Void diagnose(String msg) {
    Int rc = diagnoseRaw(msg)
    if rc != 0 {
        diagnoseRaw("diagnose failed")
    }
}

Void exit(Int code) {
    Int rc = exitRaw(code)
    if rc != 0 {
        diagnose("exit failed")
    }
}

Long nowMono() {
    return nowMonoRaw()
}

Long nowWall() {
    return nowWallRaw()
}
