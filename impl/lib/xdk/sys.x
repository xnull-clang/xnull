// xdk.sys —— S6-08 源码单元：文件/目录/子进程 + 内嵌资源（S6 §4.7/§4.8）
//
// 依赖矩阵（S6 §2）：sys → errors；运行时服务：handle、ffi-contract。
// 稳定性：@preview。
//
// 首版实现口径（B5 之前的编译面约束）：
//   - 文件按**整文件文本**处理（读入内存、close 时落盘）；不提供二进制流句柄。
//     运行时限额 64 MiB（K-07 同口径），超限 → Err。
//   - 目录用运行时句柄表索引迭代；顺序依文件系统，不排序。
//   - 资源读取按 S6 §4.8：合法路径/只读/不回退 FS/缺失 NotFound；
//     字节经 hex 桥传输，保证二进制不被 NUL 截断。
//   - Context 首参为 S6 §3 惯例；单线程运行时无挂起点，取消面随调度器切片补齐。
//   - 当前产品编译器不支持类静态方法调用（`File.openRead(...)` 会原样发射），
//     因此工厂函数以顶层形式提供：openFileRead/openFileWrite/openDir/spawnProcess；
//     类保留同名 static 方法，待 B5 编译器修复后作为首选入口。

import xdk.errors

// ---------- 错误映射 ----------

static Error sysError(ErrorKind kind, String message) {
    return new CauseError(kind, message, null)
}

static ErrorKind resourceKind(Int code) {
    if code == 1 {
        return ErrorKind.NotFound
    }
    if code == 2 {
        return ErrorKind.InvalidArgument
    }
    if code == 3 {
        return ErrorKind.DataCorrupted
    }
    return ErrorKind.Io
}

// ---------- File（整文件文本） ----------

// File：打开/读/写/关闭。close 幂等；关闭后再用返回 Unavailable，不 panic。
class File {
    final String path
    String content
    Bool writeMode
    Bool opened

    File(String p, String c, Bool w, Bool o) {
        self.path = p
        self.content = c
        self.writeMode = w
        self.opened = o
    }

    Bool isOpen() {
        return self.opened
    }

    Bool isWriteMode() {
        return self.writeMode
    }

    // 全部内容（读模式）。文本按 UTF-8 字节转为 Bytes。
    Result<Bytes, Error> readAll() {
        if !self.opened {
            return Err(sysError(ErrorKind.Unavailable, "File.readAll: 文件未打开"))
        }
        if self.writeMode {
            return Err(sysError(ErrorKind.InvalidArgument, "File.readAll: 写模式不可读"))
        }
        Bytes b = Bytes.fromString(self.content)
        return Ok(b)
    }

    // 全部内容（读模式，文本形态）。
    Result<String, Error> readText() {
        if !self.opened {
            return Err(sysError(ErrorKind.Unavailable, "File.readText: 文件未打开"))
        }
        if self.writeMode {
            return Err(sysError(ErrorKind.InvalidArgument, "File.readText: 写模式不可读"))
        }
        return Ok(self.content)
    }

    // 追加文本（写模式）；返回追加后总字节数。
    Result<Int, Error> write(String text) {
        if !self.opened {
            return Err(sysError(ErrorKind.Unavailable, "File.write: 文件未打开"))
        }
        if !self.writeMode {
            return Err(sysError(ErrorKind.InvalidArgument, "File.write: 只读模式不可写"))
        }
        self.content = $"{self.content}{text}"
        return Ok(self.content.length())
    }

    // 追加一行。
    Result<Int, Error> writeLine(String line) {
        return self.write($"{line}\n")
    }

    // 关闭：写模式落盘；幂等；句柄立即失效。
    Result<void, Error> close() {
        if !self.opened {
            return Ok()
        }
        self.opened = false
        if self.writeMode {
            Int rc = writeFileTextRaw(self.path, self.content)
            if rc != 0 {
                return Err(sysError(ErrorKind.Io, $"File.close: 无法写入 {self.path}"))
            }
        }
        return Ok()
    }
}

// openFileRead：只读打开（整文件读入）。失败（缺失/IO/超 64 MiB）→ Err。
Result<File, Error> openFileRead(String path) {
    if path.length() == 0 {
        return Err(sysError(ErrorKind.InvalidArgument, "openFileRead: 路径为空"))
    }
    String text = readFileTextRaw(path)
    if readFileTextError() != 0 {
        return Err(sysError(ErrorKind.NotFound, $"openFileRead: 无法读取 {path}"))
    }
    return Ok(new File(path, text, false, true))
}

// openFileWrite：写模式（内容先缓冲，close 时一次性覆盖落盘）。
Result<File, Error> openFileWrite(String path) {
    if path.length() == 0 {
        return Err(sysError(ErrorKind.InvalidArgument, "openFileWrite: 路径为空"))
    }
    return Ok(new File(path, "", true, true))
}

// ---------- Dir ----------

// Dir：目录迭代。next() 返回空串表示结束。
class Dir {
    Int id
    Bool opened

    Dir(Int i) {
        self.id = i
        self.opened = true
    }

    Bool isOpen() {
        return self.opened
    }

    // 下一个条目；结束返回空串（文件名不可能为空）。
    String next() {
        if !self.opened {
            return ""
        }
        return dirNextIdRaw(self.id)
    }

    Result<void, Error> close() {
        if !self.opened {
            return Ok()
        }
        self.opened = false
        Int rc = dirCloseIdRaw(self.id)
        if rc != 0 {
            return Err(sysError(ErrorKind.Io, "Dir.close: 关闭失败"))
        }
        return Ok()
    }
}

Result<Dir, Error> openDir(String path) {
    if path.length() == 0 {
        return Err(sysError(ErrorKind.InvalidArgument, "openDir: 路径为空"))
    }
    Int id = dirOpenIdRaw(path)
    if id == 0 {
        return Err(sysError(ErrorKind.NotFound, $"openDir: 无法打开 {path}"))
    }
    return Ok(new Dir(id))
}

// ---------- Process ----------

// Process：子进程句柄。wait 可重复取同一退出状态；close 未终结则 SIGKILL 并回收。
class Process {
    Int64 handle
    Bool opened

    Process(Int64 h) {
        self.handle = h
        self.opened = true
    }

    Bool isOpen() {
        return self.opened
    }

    // 阻塞等待并返回退出码（被信号终止按 128+signum，与运行时一致）。
    Result<Int, Error> wait() {
        if !self.opened {
            return Err(sysError(ErrorKind.Unavailable, "Process.wait: 句柄已关闭"))
        }
        Int64 st = procWaitRaw(self.handle)
        if st < 0 {
            return Err(sysError(ErrorKind.Io, "Process.wait: 等待失败"))
        }
        return Ok(st)
    }

    Result<void, Error> kill(Int sig) {
        if !self.opened {
            return Err(sysError(ErrorKind.Unavailable, "Process.kill: 句柄已关闭"))
        }
        Int rc = procKillRaw(self.handle, sig)
        if rc != 0 {
            return Err(sysError(ErrorKind.Io, "Process.kill: 发送信号失败"))
        }
        return Ok()
    }

    Result<void, Error> close() {
        if !self.opened {
            return Ok()
        }
        self.opened = false
        Int rc = procCloseRaw(self.handle)
        if rc != 0 {
            return Err(sysError(ErrorKind.Io, "Process.close: 回收失败"))
        }
        return Ok()
    }
}

Result<Process, Error> spawnProcess(String command) {
    if command.length() == 0 {
        return Err(sysError(ErrorKind.InvalidArgument, "spawnProcess: 命令为空"))
    }
    Int64 h = procSpawnRaw(command)
    if h == 0 {
        return Err(sysError(ErrorKind.Io, "spawnProcess: 无法启动子进程"))
    }
    return Ok(new Process(h))
}

// runProcess：便捷同步形态，运行 shell 命令并返回退出码。
Int runProcess(String command) {
    return procStatusRaw(command)
}

// ---------- 内嵌资源（S6 §4.8） ----------

// 路径规则：相对 `resources/` 根、`/` 分隔；绝对/`..`/空段/反斜杠非法。
static Bool resourcePathOk(String path, Bool allowEmpty) {
    Int n = path.length()
    if n == 0 {
        return allowEmpty
    }
    if path.substring(0, 1) == "/" {
        return false
    }
    if path.substring(n - 1, 1) == "/" {
        return false
    }
    if n >= 2 {
        if path.substring(0, 2) == ".." {
            return false
        }
    }
    Int i = 0
    while i < n {
        String ch = path.substring(i, 1)
        if ch == "\\" {
            return false
        }
        if ch == "/" {
            if i == 0 {
                return false
            }
            if path.substring(i - 1, 1) == "/" {
                return false
            }
            if i + 2 < n {
                if path.substring(i + 1, 2) == ".." {
                    return false
                }
            }
            if i + 2 == n {
                if path.substring(i + 1, 2) == ".." {
                    return false
                }
            }
        }
        i = i + 1
    }
    return true
}

// resourceExists：路径合法且资源存在；不存在/非法 → false（不报错）。
Bool resourceExists(String path) {
    if !resourcePathOk(path, false) {
        return false
    }
    return resourceExistsRaw(path) != 0
}

// resourceSize：字节数；缺失/非法返回 null。
Int? resourceSize(String path) {
    if !resourcePathOk(path, false) {
        return null
    }
    Int64 n = resourceSizeRaw(path)
    if n < 0 {
        return null
    }
    return n
}

static Int hexValueAt(String text, Int i) {
    String ch = text.substring(i, 1)
    if ch == "0" { return 0 }
    if ch == "1" { return 1 }
    if ch == "2" { return 2 }
    if ch == "3" { return 3 }
    if ch == "4" { return 4 }
    if ch == "5" { return 5 }
    if ch == "6" { return 6 }
    if ch == "7" { return 7 }
    if ch == "8" { return 8 }
    if ch == "9" { return 9 }
    if ch == "a" { return 10 }
    if ch == "b" { return 11 }
    if ch == "c" { return 12 }
    if ch == "d" { return 13 }
    if ch == "e" { return 14 }
    if ch == "f" { return 15 }
    return 0
}

// readResource：取全部字节。缺失 → NotFound；路径非法 → InvalidArgument。
Result<Bytes, Error> readResource(Context context, String path) {
    if !resourcePathOk(path, false) {
        return Err(sysError(ErrorKind.InvalidArgument, "readResource: 非法资源路径"))
    }
    String hex = readResourceHexRaw(path)
    Int code = resourceErrorRaw()
    if code != 0 {
        return Err(sysError(resourceKind(code), $"readResource: 无法读取 {path}"))
    }
    Bytes res = Bytes.fromString("")
    Int i = 0
    while i + 1 < hex.length() {
        Int hi = hexValueAt(hex, i)
        Int lo = hexValueAt(hex, i + 1)
        res.push(hi * 16 + lo)
        i = i + 2
    }
    return Ok(res)
}

// readResourceText：UTF-8 解码后返回文本。非法字节 → DataCorrupted。
Result<String, Error> readResourceText(Context context, String path) {
    if !resourcePathOk(path, false) {
        return Err(sysError(ErrorKind.InvalidArgument, "readResourceText: 非法资源路径"))
    }
    String text = readResourceTextRaw(path)
    Int code = resourceErrorRaw()
    if code != 0 {
        return Err(sysError(resourceKind(code), $"readResourceText: 无法读取 {path}"))
    }
    return Ok(text)
}

// listResources：列出前缀下的全部资源路径（`/` 分隔、字典序升序）。
// 空前缀 = 根；前缀不是目录 → 空列表；非法路径 → InvalidArgument。
Result<List<String>, Error> listResources(Context context, String prefix) {
    if !resourcePathOk(prefix, true) {
        return Err(sysError(ErrorKind.InvalidArgument, "listResources: 非法资源前缀"))
    }
    Int total = resourceCountRaw()
    List<String> res = []
    Int i = 0
    while i < total {
        String name = resourceAtRaw(i)
        if name.length() > 0 {
            if prefix.length() == 0 {
                res.push(name)
            } else if name.length() > (prefix.length() + 1) {
                if name.substring(0, prefix.length()) == prefix {
                    if name.substring(prefix.length(), 1) == "/" {
                        res.push(name)
                    }
                }
            }
        }
        i = i + 1
    }
    // 资源表由构建期按路径升序生成；此处不再二次排序（S6 §4.8 保证）。
    return Ok(res)
}

// ---------- 旧兼容入口（K-07：编译器读源文件） ----------

// readFileTextImpl：读取失败（缺失/IO/超过 64 MiB）→ throw 明确诊断，不返回空串。
// 与 readFileText 分开命名：产品编译器对 readFileText 有 K-07 专用发射（调用点丢参），
// 该名字保留给编译器自举面，实现走本函数。
String readFileTextImpl(String path) {
    String raw = readFileTextRaw(path)
    if readFileTextError() != 0 {
        throw $"readFileText: 无法读取文件 {path}"
    }
    return raw
}

// readFileText：K-07 兼容入口（编译器 --ast-file/--bundle-file 使用）。
String readFileText(String path) {
    return readFileTextImpl(path)
}
