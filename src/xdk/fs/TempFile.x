// Tier: T0；依赖：xdk.errors；稳定性：preview。
// xdk.fs —— 临时文件租约；close 删除并幂等。
package xdk.fs
import xdk.errors

class TempFile {
    final String path
    Bool removed

    TempFile(String path) {
        self.path = path
        self.removed = false
    }

    Bool isRemoved() {
        return self.removed
    }

    Result<Unit, Error> remove() {
        if self.removed {
            return Ok()
        }
        Result<Unit, Error> removedResult = removeFile(self.path)
        if removedResult.isErr() && removedResult.error().kind() != ErrorKind.NotFound {
            return Err(removedResult.error())
        }
        self.removed = true
        return Ok()
    }

    Result<Unit, Error> close() {
        return self.remove()
    }
}
