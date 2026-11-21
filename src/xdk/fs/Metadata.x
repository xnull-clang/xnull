// Tier: T0；依赖：无；稳定性：preview。
// xdk.fs —— 路径元数据快照。
package xdk.fs

class Metadata {
    final EntryKind kind
    final Long size
    final Long modifiedMillis
    final Int permissions

    Metadata(EntryKind kind, Long size, Long modifiedMillis, Int permissions) {
        self.kind = kind
        self.size = size
        self.modifiedMillis = modifiedMillis
        self.permissions = permissions
    }

    Bool isFile() {
        return entryKindIsFile(self.kind)
    }

    Bool isDirectory() {
        return entryKindIsDirectory(self.kind)
    }

    Bool isSymlink() {
        return entryKindIsSymlink(self.kind)
    }

    Bool isOther() {
        return entryKindIsOther(self.kind)
    }

    Bool isExecutable() {
        return (self.permissions & 73) != 0
    }
}
