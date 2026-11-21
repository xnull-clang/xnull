// Tier: T0；依赖：xdk.errors；稳定性：preview。
// xdk.fs —— 目录句柄。遍历顺序不承诺；跳过 "." 与 ".."。
package xdk.fs
import xdk.errors

class Dir {
    Int id
    Bool opened

    Dir(Int id) {
        self.id = id
        self.opened = true
    }

    Bool isOpen() {
        return self.opened
    }

    // 下一个条目；目录结束返回 Ok(null)。
    Result<String?, Error> next() {
        if !self.opened {
            return Err(fsError(ErrorKind.Unavailable, "Dir.next: 目录未打开"))
        }
        while true {
            String name = dirNextIdRaw(self.id)
            if fsErrorRaw() != 0 {
                return Err(fsOperationError("Dir.next"))
            }
            if name.length() == 0 {
                return Ok(null)
            }
            if name != "." && name != ".." {
                return Ok(name)
            }
        }
        return Ok(null)
    }

    Result<List<String>, Error> entries() {
        if !self.opened {
            return Err(fsError(ErrorKind.Unavailable, "Dir.entries: 目录未打开"))
        }
        List<String> result = []
        while true {
            Result<String?, Error> next = self.next()
            if next.isErr() {
                return Err(next.error())
            }
            if next.value() == null {
                break
            }
            result.push(next.value() as String)
        }
        return Ok(result)
    }

    Result<Unit, Error> close() {
        if !self.opened {
            return Ok()
        }
        self.opened = false
        Int rc = dirCloseIdRaw(self.id)
        if rc != 0 {
            return Err(fsOperationError("Dir.close"))
        }
        return Ok()
    }
}

Result<Dir, Error> openDir(String path) {
    if path.length() == 0 {
        return Err(fsError(ErrorKind.InvalidArgument, "openDir: 路径为空"))
    }
    Int id = dirOpenIdRaw(path)
    if id == 0 {
        return Err(fsPathError("openDir", path))
    }
    return Ok(new Dir(id))
}
