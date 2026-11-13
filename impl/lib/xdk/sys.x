// xdk.sys —— S6-08 源码单元：文件/目录/子进程 + 内嵌资源（S6 §4.7/§4.8）
//
// 依赖矩阵（S6 §2）：sys → errors；运行时服务：handle、ffi-contract。
// 稳定性：@preview。
//
// 实现口径（B5 之前的编译面约束）：
//   - File 为**直接落盘**模型：write 立即写，不缓冲；二进制经 hex 桥传输，
//     文本经 append 原语传输；read 每次按 offset 重新读取。
//   - Dir 用运行时句柄表索引迭代；顺序依文件系统，不排序。
//   - 资源读取按 S6 §4.8：合法路径/只读/不回退 FS/缺失 NotFound。
//   - Context 首参为 S6 §3 惯例；单线程运行时无挂起点，取消面随调度器切片补齐。
//   - 当前产品编译器不支持类静态方法调用，工厂以顶层函数提供：
//     openFileRead/openFileWrite/openFileAppend/openDir/spawnProcess。

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

// ---------- 字节/hex ----------

static String hexChar(Int v) {
    String table = "0123456789abcdef"
    return table.substring(v, 1)
}

static String hexEncode(Bytes b) {
    // 逐字节拼接（编译器暂无 StringBuilder/List.join 发射面）；大文件写入
    // 受此实现限制，首版以 1 MiB 为上限，超过返回 Unsupported。
    String res = ""
    Int i = 0
    while i < b.length() {
        Int v = b.get(i)
        res = $"{res}{hexChar(v / 16)}{hexChar(v % 16)}"
        i = i + 1
    }
    return res
}

static Int lastIndexOfChar(String s, String ch) {
    Int i = 0
    Int last = -1
    while i < s.length() {
        if s.substring(i, 1) == ch {
            last = i
        }
        i = i + 1
    }
    return last
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

static Bytes hexDecode(String hex) {
    Bytes res = Bytes.fromString("")
    Int i = 0
    while i + 1 < hex.length() {
        Int hi = hexValueAt(hex, i)
        Int lo = hexValueAt(hex, i + 1)
        res.push(hi * 16 + lo)
        i = i + 2
    }
    return res
}

// ---------- File ----------

// File：直接落盘的读写句柄。close 幂等；关闭后读写返回 Unavailable。
class File {
    final String path
    Int pos
    Bool writable
    Bool opened

    File(String p, Bool w) {
        self.path = p
        self.pos = 0
        self.writable = w
        self.opened = true
    }

    Bool isOpen() {
        return self.opened
    }

    Bool isWritable() {
        return self.writable
    }

    Int position() {
        return self.pos
    }

    // 定位（只影响后续 read；write 总是追加到文件尾）。
    Result<void, Error> seek(Int offset) {
        if offset < 0 {
            return Err(sysError(ErrorKind.InvalidArgument, "File.seek: 偏移为负"))
        }
        self.pos = offset
        return Ok()
    }

    // 文件字节数（磁盘当前值；缺失返回 -1 经 Err 报告）。
    Result<Int, Error> size() {
        String p = self.path
        Int n = fileSizeRaw(p)
        if n < 0 {
            return Err(sysError(ErrorKind.NotFound, $"File.size: 无法读取 {self.path}"))
        }
        return Ok(n)
    }

    // 从当前位置读全部剩余字节。
    Result<Bytes, Error> readAll() {
        if !self.opened {
            return Err(sysError(ErrorKind.Unavailable, "File.readAll: 文件未打开"))
        }
        String p = self.path
        if fileExistsRaw(p) == 0 {
            return Err(sysError(ErrorKind.NotFound, $"File.readAll: 文件不存在 {self.path}"))
        }
        Bytes all = hexDecode(readFileHexRaw(p))
        if self.pos >= all.length() {
            Bytes empty = Bytes.fromString("")
            return Ok(empty)
        }
        Bytes res = all.slice(self.pos, all.length())
        self.pos = all.length()
        return Ok(res)
    }

    // 从当前位置读至多 maxBytes 字节。
    Result<Bytes, Error> read(Int maxBytes) {
        if maxBytes < 0 {
            return Err(sysError(ErrorKind.InvalidArgument, "File.read: maxBytes 为负"))
        }
        if !self.opened {
            return Err(sysError(ErrorKind.Unavailable, "File.read: 文件未打开"))
        }
        String p = self.path
        if fileExistsRaw(p) == 0 {
            return Err(sysError(ErrorKind.NotFound, $"File.read: 文件不存在 {self.path}"))
        }
        Bytes all = hexDecode(readFileHexRaw(p))
        if self.pos >= all.length() {
            Bytes empty = Bytes.fromString("")
            return Ok(empty)
        }
        Int n = all.length() - self.pos
        if maxBytes < n {
            n = maxBytes
        }
        Int end = self.pos + n
        Bytes res = all.slice(self.pos, end)
        self.pos = end
        return Ok(res)
    }

    // 读取全部文本（UTF-8；独立于 offset）。
    Result<String, Error> readText() {
        if !self.opened {
            return Err(sysError(ErrorKind.Unavailable, "File.readText: 文件未打开"))
        }
        String text = readFileTextImpl(self.path)
        return Ok(text)
    }

    // 追加二进制内容；返回追加字节数。
    Result<Int, Error> write(Bytes data) {
        if !self.opened {
            return Err(sysError(ErrorKind.Unavailable, "File.write: 文件未打开"))
        }
        if !self.writable {
            return Err(sysError(ErrorKind.InvalidArgument, "File.write: 只读模式不可写"))
        }
        if data.length() > 1048576 {
            return Err(sysError(ErrorKind.Unsupported, "File.write: 首版二进制写入上限 1 MiB"))
        }
        String p = self.path
        Int rc = writeFileHexRaw(p, hexEncode(data), true)
        if rc != 0 {
            return Err(sysError(ErrorKind.Io, $"File.write: 无法写入 {self.path}"))
        }
        return Ok(data.length())
    }

    // 追加文本；返回追加字节数。
    Result<Int, Error> writeText(String text) {
        if !self.opened {
            return Err(sysError(ErrorKind.Unavailable, "File.writeText: 文件未打开"))
        }
        if !self.writable {
            return Err(sysError(ErrorKind.InvalidArgument, "File.writeText: 只读模式不可写"))
        }
        String p = self.path
        Int rc = appendFileTextRaw(p, text)
        if rc != 0 {
            return Err(sysError(ErrorKind.Io, $"File.writeText: 无法写入 {self.path}"))
        }
        return Ok(text.length())
    }

    // 追加一行。
    Result<Int, Error> writeLine(String line) {
        return self.writeText($"{line}\n")
    }

    // 关闭（写已直接落盘，无缓冲需要 flush）；幂等。
    Result<void, Error> close() {
        self.opened = false
        return Ok()
    }
}

// openFileRead：只读打开；文件不存在 → NotFound。
Result<File, Error> openFileRead(String path) {
    if path.length() == 0 {
        return Err(sysError(ErrorKind.InvalidArgument, "openFileRead: 路径为空"))
    }
    if fileExistsRaw(path) == 0 {
        return Err(sysError(ErrorKind.NotFound, $"openFileRead: 文件不存在 {path}"))
    }
    return Ok(new File(path, false))
}

// openFileWrite：写模式（立即截断）。
Result<File, Error> openFileWrite(String path) {
    if path.length() == 0 {
        return Err(sysError(ErrorKind.InvalidArgument, "openFileWrite: 路径为空"))
    }
    Int rc = writeFileTextRaw(path, "")
    if rc != 0 {
        return Err(sysError(ErrorKind.Io, $"openFileWrite: 无法创建 {path}"))
    }
    return Ok(new File(path, true))
}

// openFileAppend：追加模式（不截断）。
Result<File, Error> openFileAppend(String path) {
    if path.length() == 0 {
        return Err(sysError(ErrorKind.InvalidArgument, "openFileAppend: 路径为空"))
    }
    return Ok(new File(path, true))
}

// ---------- 文件系统操作 ----------

Bool fileExists(String path) {
    if path.length() == 0 {
        return false
    }
    return fileExistsRaw(path) != 0
}

Result<void, Error> removeFile(String path) {
    if fileExistsRaw(path) == 0 {
        return Err(sysError(ErrorKind.NotFound, $"removeFile: 文件不存在 {path}"))
    }
    Int rc = fileRemoveRaw(path)
    if rc != 0 {
        return Err(sysError(ErrorKind.Io, $"removeFile: 删除失败 {path}"))
    }
    return Ok()
}

Result<void, Error> renameFile(String from, String to) {
    if from.length() == 0 || to.length() == 0 {
        return Err(sysError(ErrorKind.InvalidArgument, "renameFile: 路径为空"))
    }
    Int rc = fileRenameRaw(from, to)
    if rc != 0 {
        return Err(sysError(ErrorKind.Io, $"renameFile: {from} -> {to} 失败"))
    }
    return Ok()
}

// copyFile：整文件复制（二进制安全）；覆盖目标。
Result<void, Error> copyFile(String from, String to) {
    if fileExistsRaw(from) == 0 {
        return Err(sysError(ErrorKind.NotFound, $"copyFile: 源不存在 {from}"))
    }
    String hex = readFileHexRaw(from)
    Int rc = writeFileHexRaw(to, hex, false)
    if rc != 0 {
        return Err(sysError(ErrorKind.Io, $"copyFile: 无法写入 {to}"))
    }
    return Ok()
}

Result<void, Error> makeDir(String path) {
    if path.length() == 0 {
        return Err(sysError(ErrorKind.InvalidArgument, "makeDir: 路径为空"))
    }
    Int rc = dirMakeRaw(path)
    if rc != 0 {
        return Err(sysError(ErrorKind.Io, $"makeDir: 无法创建 {path}"))
    }
    return Ok()
}

Result<void, Error> removeDir(String path) {
    if path.length() == 0 {
        return Err(sysError(ErrorKind.InvalidArgument, "removeDir: 路径为空"))
    }
    Int rc = dirRemoveRaw(path)
    if rc != 0 {
        return Err(sysError(ErrorKind.Io, $"removeDir: 无法删除 {path}"))
    }
    return Ok()
}

// ---------- Path ----------

// Path：路径字符串的轻量视图（不访问文件系统）。
class Path {
    final String raw

    Path(String p) {
        self.raw = p
    }

    String toString() {
        return self.raw
    }

    Bool isAbsolute() {
        return self.raw.length() > 0 && self.raw.substring(0, 1) == "/"
    }

    // 最后一段；以 / 结尾时去掉尾部分隔符。
    String name() {
        String s = self.raw
        while s.length() > 1 && s.substring(s.length() - 1, 1) == "/" {
            s = s.substring(0, s.length() - 1)
        }
        Int i = lastIndexOfChar(s, "/")
        if i < 0 {
            return s
        }
        return s.substring(i + 1, s.length() - i - 1)
    }

    // 父目录（无分隔符时返回 "."）。
    String parent() {
        String s = self.raw
        while s.length() > 1 && s.substring(s.length() - 1, 1) == "/" {
            s = s.substring(0, s.length() - 1)
        }
        Int i = lastIndexOfChar(s, "/")
        if i <= 0 {
            if i == 0 {
                return "/"
            }
            return "."
        }
        return s.substring(0, i)
    }

    // 扩展名（不含点）；无扩展名返回空串。
    String ext() {
        String n = self.name()
        Int i = lastIndexOfChar(n, ".")
        if i <= 0 {
            return ""
        }
        return n.substring(i + 1, n.length() - i - 1)
    }
}

// pathJoin：连接两段路径，处理重复分隔符。
String pathJoin(String a, String b) {
    if a.length() == 0 {
        return b
    }
    if b.length() == 0 {
        return a
    }
    if a.substring(a.length() - 1, 1) == "/" {
        return $"{a}{b}"
    }
    return $"{a}/{b}"
}

// ---------- Dir ----------

// Dir：目录迭代。next() 返回空串表示结束；entries() 消费剩余全部条目。
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
        Int d = self.id
        return dirNextIdRaw(d)
    }

    // 读取剩余全部条目（含 "." 与 ".."，与运行时一致）。
    Result<List<String>, Error> entries() {
        if !self.opened {
            return Err(sysError(ErrorKind.Unavailable, "Dir.entries: 目录未打开"))
        }
        List<String> res = []
        String name = self.next()
        while name.length() > 0 {
            res.push(name)
            name = self.next()
        }
        return Ok(res)
    }

    Result<void, Error> close() {
        if !self.opened {
            return Ok()
        }
        self.opened = false
        Int d = self.id
        Int rc = dirCloseIdRaw(d)
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
        Int64 h = self.handle
        Int64 st = procWaitRaw(h)
        if st < 0 {
            return Err(sysError(ErrorKind.Io, "Process.wait: 等待失败"))
        }
        return Ok(st)
    }

    Result<void, Error> kill(Int sig) {
        if !self.opened {
            return Err(sysError(ErrorKind.Unavailable, "Process.kill: 句柄已关闭"))
        }
        Int64 h = self.handle
        Int rc = procKillRaw(h, sig)
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
        Int64 h = self.handle
        Int rc = procCloseRaw(h)
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
    Int64 code = procExitCodeRaw(command)
    return code
}

// ProcessResult：命令输出与退出码。
class ProcessResult {
    Int code
    String output

    ProcessResult(Int c, String o) {
        self.code = c
        self.output = o
    }

    Int status() {
        return self.code
    }

    String stdout() {
        return self.output
    }
}

// runProcessResult：运行命令并捕获 stdout（stderr 不捕获）。
Result<ProcessResult, Error> runProcessResult(String command) {
    if command.length() == 0 {
        return Err(sysError(ErrorKind.InvalidArgument, "runProcessResult: 命令为空"))
    }
    String text = procOutputRaw(command)
    Int code = procLastStatusRaw()
    if code < 0 {
        return Err(sysError(ErrorKind.Io, "runProcessResult: 无法执行命令"))
    }
    return Ok(new ProcessResult(code, text))
}

// ---------- 旧兼容入口（K-07：编译器读源文件） ----------

// readFileTextImpl：读取失败（缺失/IO/超过 64 MiB）→ throw 明确诊断，不返回空串。
// 与 readFileText 分开命名：产品编译器对 readFileText 有 K-07 专用发射（调用点丢参）。
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
