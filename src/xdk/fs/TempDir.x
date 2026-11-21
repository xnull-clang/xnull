// Tier: T0；依赖：xdk.errors；稳定性：preview。
// xdk.fs —— 临时目录租约；close 递归删除并幂等。
package xdk.fs
import xdk.errors

class TempDir {
    final String path
    Bool removed

    TempDir(String path) {
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
        Result<Unit, Error> removedResult = removeDirAll(self.path)
        if removedResult.isErr() {
            return Err(removedResult.error())
        }
        self.removed = true
        return Ok()
    }

    Result<Unit, Error> close() {
        return self.remove()
    }
}
