// Tier: T0；依赖：xdk.runtime、xdk.errors；稳定性：preview。
// xdk.sys —— T0 平台与进程（默认精简编译单元）。
//
// 本单元是 `xdk.sys` 的默认面：顶层 Result 读写、环境/平台、内嵌资源、
// Process（含 stdio 管道、信号、进程组）。File/Dir 句柄的完整契约在
// `xdk.fs`（同目录 io/system 保留兼容实现）；同一程序中同时导入 fs 与 sys
// 时，句柄类型以 fs 的规范实现为准，避免同名类型冲突。
package xdk.sys
import xdk.errors

// ---------- 错误映射 ----------

static Error sysError(ErrorKind kind, String message) {
    BasicError error = new BasicError(kind, message)
    return error
}

static ErrorKind sysKind(Int code) {
    if code == 1 { return ErrorKind.NotFound }
    if code == 2 { return ErrorKind.PermissionDenied }
    if code == 3 { return ErrorKind.AlreadyExists }
    if code == 4 { return ErrorKind.InvalidArgument }
    if code == 5 { return ErrorKind.Io }
    if code == 6 { return ErrorKind.Unsupported }
    if code == 7 { return ErrorKind.Busy }
    return ErrorKind.Internal
}

static Error sysOperationError(String operation) {
    Int code = fsErrorRaw()
    if code == 0 {
        return sysError(ErrorKind.Io, $"{operation}: 系统调用失败")
    }
    return sysError(sysKind(code), $"{operation}: 系统错误（{code}）")
}

static Error sysPathError(String operation, String path) {
    Int code = fsErrorRaw()
    if code == 0 {
        return sysError(ErrorKind.Io, $"{operation}: {path}")
    }
    return sysError(sysKind(code), $"{operation}: {path}（{code}）")
}

static ErrorKind resourceKind(Int code) {
    if code == 1 { return ErrorKind.NotFound }
    if code == 2 { return ErrorKind.InvalidArgument }
    if code == 3 { return ErrorKind.DataCorrupted }
    return ErrorKind.Io
}

// ---------- 字节/hex ----------

static String hexChar(Int value) {
    String table = "0123456789abcdef"
    return table.substring(value, 1)
}

static String hexEncode(Bytes data) {
    String result = ""
    Int i = 0
    while i < data.length() {
        Int value = data.get(i)
        result = $"{result}{hexChar(value / 16)}{hexChar(value % 16)}"
        i = i + 1
    }
    return result
}

static Int hexValueAt(String text, Int index) {
    String ch = text.substring(index, 1)
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
    Bytes result = Bytes.fromString("")
    Int i = 0
    while i + 1 < hex.length() {
        Int hi = hexValueAt(hex, i)
        Int lo = hexValueAt(hex, i + 1)
        result.push(hi * 16 + lo)
        i = i + 2
    }
    return result
}

// ---------- 顶层文件面（T0-X：Result） ----------

Result<String, Error> readFileText(String path) {
    if path.length() == 0 {
        return Err(sysError(ErrorKind.InvalidArgument, "readFileText: 路径为空"))
    }
    String text = readFileTextRaw(path)
    if readFileTextError() != 0 {
        if fileExistsRaw(path) == 0 {
            return Err(sysError(ErrorKind.NotFound, $"readFileText: 文件不存在 {path}"))
        }
        return Err(sysError(ErrorKind.Io, $"readFileText: 无法读取文件 {path}"))
    }
    return Ok(text)
}

Bool fileExists(String path) {
    if path.length() == 0 {
        return false
    }
    return fileExistsRaw(path) != 0
}

// 写入 UTF-8 文本并返回写入字节数（非 ASCII 按字节计）。
Result<Long, Error> writeFileText(String path, String text) {
    if path.length() == 0 {
        return Err(sysError(ErrorKind.InvalidArgument, "writeFileText: 路径为空"))
    }
    Int rc = writeFileTextRaw(path, text)
    if rc != 0 {
        return Err(sysPathError("writeFileText", path))
    }
    return Ok(text.length() as Long)
}

// ---------- 环境与平台（T0-X：枚举 + 稳定投影） ----------

String env(String name) {
    return envRaw(name)
}

Bool envHas(String name) {
    return envHasRaw(name) != 0
}

// 全部环境变量名（升序、不含值）；值用 env(name) 读取。
List<String> envNames() {
    String raw = envNamesRaw()
    if raw.length() == 0 {
        List<String> empty = []
        return empty
    }
    return raw.split("\n")
}

String hostname() {
    return hostnameRaw()
}

String platform() {
    return platformRaw()
}

String arch() {
    return archRaw()
}

Int pid() {
    return pidRaw() as Int
}

String cwd() {
    return cwdRaw()
}

Bool chdir(String path) {
    return chdirRaw(path) != 0
}

// 失败返回 -1；需要错误分类时用 fileMtimeResult。
Long fileMtime(String path) {
    return fileMtimeRaw(path)
}

Result<Long, Error> fileMtimeResult(String path) {
    Long value = fileMtimeRaw(path)
    if value < 0 {
        return Err(sysError(ErrorKind.NotFound, $"fileMtime: 无法读取 {path}"))
    }
    return Ok(value)
}

// 读取一行 stdin（EOF 返回空串）；阻塞面，取消随调度器切片补齐。
String stdinReadLine() {
    return stdinLineRaw()
}

// ---------- 兼容文件系统面（规范实现见 xdk.fs；此处仅保留 sys 旧调用方） ----------

Result<Unit, Error> removeFile(String path) {
    if path.length() == 0 {
        return Err(sysError(ErrorKind.InvalidArgument, "removeFile: 路径为空"))
    }
    Int rc = fileRemoveRaw(path)
    if rc != 0 {
        return Err(sysPathError("removeFile", path))
    }
    return Ok()
}

String pathJoin(String basePath, String childName) {
    if basePath.length() == 0 {
        return childName
    }
    if childName.length() == 0 {
        return basePath
    }
    if basePath.substring(basePath.length() - 1, 1) == "/" {
        return $"{basePath}{childName}"
    }
    return $"{basePath}/{childName}"
}

Bool dirExists(String path) {
    Result<Dir, Error> opened = openDir(path)
    if opened.isErr() {
        return false
    }
    Result<Unit, Error> closed = opened.value().close()
    return closed.isOk()
}

Bool isDir(String path) {
    return dirExists(path)
}

// 递归收集 root 下的全部非目录条目（深度优先，不跟随目录符号链接）。
Result<List<String>, Error> walk(String root) {
    List<String> result = []
    Result<Dir, Error> opened = openDir(root)
    if opened.isErr() {
        return Err(opened.error())
    }
    Dir directory = opened.value()
    Result<List<String>, Error> listed = directory.entries()
    if listed.isErr() {
        Error error = listed.error()
        Result<Unit, Error> closed = directory.close()
        return Err(error)
    }
    List<String> names = listed.value()
    Int index = 0
    while index < names.length() {
        String child = pathJoin(root, names.get(index))
        if dirExists(child) {
            Result<List<String>, Error> nested = walk(child)
            if nested.isErr() {
                Error error = nested.error()
                Result<Unit, Error> closed = directory.close()
                return Err(error)
            }
            Int nestedIndex = 0
            while nestedIndex < nested.value().length() {
                result.push(nested.value().get(nestedIndex))
                nestedIndex = nestedIndex + 1
            }
        } else {
            result.push(child)
        }
        index = index + 1
    }
    Result<Unit, Error> closed = directory.close()
    if closed.isErr() {
        return Err(closed.error())
    }
    return Ok(result)
}

Result<Unit, Error> mkdirAll(String path) {
    if path.length() == 0 {
        return Err(sysError(ErrorKind.InvalidArgument, "mkdirAll: 空路径"))
    }
    Int index = 0
    while index < path.length() {
        if path.substring(index, 1) == "/" && index > 0 {
            String prefix = path.substring(0, index)
            Int rc = dirMakeRaw(prefix)
            if rc != 0 && !dirExists(prefix) {
                return Err(sysPathError("mkdirAll", prefix))
            }
        }
        index = index + 1
    }
    Int rc = dirMakeRaw(path)
    if rc != 0 && !dirExists(path) {
        return Err(sysPathError("mkdirAll", path))
    }
    return Ok()
}
