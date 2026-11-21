// Tier: T0；依赖：无；稳定性：preview。
// xdk.sys —— 文件打开模式（兼容面）。
package xdk.sys

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
