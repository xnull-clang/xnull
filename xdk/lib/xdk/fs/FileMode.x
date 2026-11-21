// Tier: T0；依赖：无；稳定性：preview。
// xdk.fs —— 文件打开模式。
package xdk.fs

enum FileMode {
    Read,
    Write,
    Append,
    ReadWrite
}

static Int fileModeCode(FileMode mode) {
    if mode == FileMode.Write { return 1 }
    if mode == FileMode.Append { return 2 }
    if mode == FileMode.ReadWrite { return 3 }
    return 0
}
