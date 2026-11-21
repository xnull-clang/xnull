// Tier: T0；依赖：无；稳定性：preview。
// xdk.fs —— 文件系统条目类型。
package xdk.fs

enum EntryKind {
    Missing,
    File,
    Directory,
    Symlink,
    Other
}

static EntryKind entryKindFromCode(Int code) {
    if code == 1 { return EntryKind.File }
    if code == 2 { return EntryKind.Directory }
    if code == 3 { return EntryKind.Symlink }
    if code == 4 { return EntryKind.Other }
    return EntryKind.Missing
}

static Bool entryKindIsFile(EntryKind kind) {
    return kind == EntryKind.File
}

static Bool entryKindIsDirectory(EntryKind kind) {
    return kind == EntryKind.Directory
}

static Bool entryKindIsSymlink(EntryKind kind) {
    return kind == EntryKind.Symlink
}

static Bool entryKindIsOther(EntryKind kind) {
    return kind == EntryKind.Other
}
