// Tier: T0；依赖：xdk.bytes、xdk.errors；稳定性：preview。
// xdk.fs —— T0 文件系统：Result 顶层面、File/Dir/Path、元数据、遍历与临时文件。
package xdk.fs
import xdk.bytes
import xdk.errors

// ---------- 错误映射 ----------

static Error fsError(ErrorKind kind, String message) {
    BasicError error = new BasicError(kind, message)
    return error
}

static ErrorKind fsKind(Int code) {
    if code == 1 { return ErrorKind.NotFound }
    if code == 2 { return ErrorKind.PermissionDenied }
    if code == 3 { return ErrorKind.AlreadyExists }
    if code == 4 { return ErrorKind.InvalidArgument }
    if code == 5 { return ErrorKind.Io }
    if code == 6 { return ErrorKind.Unsupported }
    if code == 7 { return ErrorKind.Busy }
    return ErrorKind.Internal
}

static Error fsOperationError(String operation) {
    Int code = fsErrorRaw()
    if code == 0 {
        return fsError(ErrorKind.Io, $"{operation}: 文件系统调用失败")
    }
    return fsError(fsKind(code), $"{operation}: 文件系统错误（{code}）")
}

static Error fsPathError(String operation, String path) {
    Int code = fsErrorRaw()
    if code == 0 {
        return fsError(ErrorKind.Io, $"{operation}: {path}")
    }
    return fsError(fsKind(code), $"{operation}: {path}（{code}）")
}

// ---------- 存在性与顶层读写 ----------

Bool exists(String path) {
    if path.length() == 0 {
        return false
    }
    return pathKindRaw(path, 1) != 0
}

Bool isFile(String path) {
    if path.length() == 0 {
        return false
    }
    return pathKindRaw(path, 1) == 1
}

Bool isDir(String path) {
    if path.length() == 0 {
        return false
    }
    return pathKindRaw(path, 1) == 2
}

Bool isSymlink(String path) {
    if path.length() == 0 {
        return false
    }
    return pathKindRaw(path, 0) == 3
}

Result<Bytes, Error> readBytes(String path) {
    if path.length() == 0 {
        return Err(fsError(ErrorKind.InvalidArgument, "readBytes: 路径为空"))
    }
    Int kind = pathKindRaw(path, 1)
    if kind == 0 {
        return Err(fsPathError("readBytes", path))
    }
    if kind == 2 {
        return Err(fsError(ErrorKind.InvalidArgument, $"readBytes: 目标是目录 {path}"))
    }
    String hexadecimal = readFileHexRaw(path)
    if fsErrorRaw() != 0 {
        return Err(fsPathError("readBytes", path))
    }
    return Ok(fromHex(hexadecimal))
}

Result<String, Error> readText(String path) {
    Result<Bytes, Error> bytes = readBytes(path)
    if bytes.isErr() {
        return Err(bytes.error())
    }
    return Ok(bytes.value().toString())
}

Result<Long, Error> writeBytes(String path, Bytes data) {
    if path.length() == 0 {
        return Err(fsError(ErrorKind.InvalidArgument, "writeBytes: 路径为空"))
    }
    Int rc = writeFileHexRaw(path, toHex(data), false)
    if rc != 0 {
        return Err(fsPathError("writeBytes", path))
    }
    return Ok(data.length() as Long)
}

Result<Long, Error> writeText(String path, String text) {
    if path.length() == 0 {
        return Err(fsError(ErrorKind.InvalidArgument, "writeText: 路径为空"))
    }
    Int rc = writeFileTextRaw(path, text)
    if rc != 0 {
        return Err(fsPathError("writeText", path))
    }
    return Ok(text.length() as Long)
}

Result<Long, Error> writeBytesAtomic(String path, Bytes data) {
    if path.length() == 0 {
        return Err(fsError(ErrorKind.InvalidArgument, "writeBytesAtomic: 路径为空"))
    }
    Int rc = writeFileAtomicRaw(path, toHex(data))
    if rc != 0 {
        return Err(fsPathError("writeBytesAtomic", path))
    }
    return Ok(data.length() as Long)
}

Result<Long, Error> writeTextAtomic(String path, String text) {
    Bytes data = Bytes.fromString(text)
    Result<Long, Error> written = writeBytesAtomic(path, data)
    if written.isErr() {
        return Err(written.error())
    }
    return Ok(text.length() as Long)
}

// ---------- 目录与文件操作 ----------

Result<Unit, Error> removeFile(String path) {
    if path.length() == 0 {
        return Err(fsError(ErrorKind.InvalidArgument, "removeFile: 路径为空"))
    }
    Int rc = fileRemoveRaw(path)
    if rc != 0 {
        return Err(fsPathError("removeFile", path))
    }
    return Ok()
}

Result<Unit, Error> renameFile(String sourcePath, String targetPath) {
    if sourcePath.length() == 0 || targetPath.length() == 0 {
        return Err(fsError(ErrorKind.InvalidArgument, "renameFile: 路径为空"))
    }
    Int rc = fileRenameRaw(sourcePath, targetPath)
    if rc != 0 {
        return Err(fsPathError("renameFile", sourcePath))
    }
    return Ok()
}

Result<Unit, Error> copyFile(String sourcePath, String targetPath) {
    Result<Bytes, Error> content = readBytes(sourcePath)
    if content.isErr() {
        return Err(content.error())
    }
    Result<Long, Error> written = writeBytes(targetPath, content.value())
    if written.isErr() {
        return Err(written.error())
    }
    return Ok()
}

Result<Unit, Error> makeDir(String path) {
    if path.length() == 0 {
        return Err(fsError(ErrorKind.InvalidArgument, "makeDir: 路径为空"))
    }
    Int rc = dirMakeRaw(path)
    if rc != 0 {
        return Err(fsPathError("makeDir", path))
    }
    return Ok()
}

Result<Unit, Error> removeDir(String path) {
    if path.length() == 0 {
        return Err(fsError(ErrorKind.InvalidArgument, "removeDir: 路径为空"))
    }
    Int rc = dirRemoveRaw(path)
    if rc != 0 {
        return Err(fsPathError("removeDir", path))
    }
    return Ok()
}

Result<Unit, Error> mkdirAll(String path) {
    if path.length() == 0 {
        return Err(fsError(ErrorKind.InvalidArgument, "mkdirAll: 路径为空"))
    }
    if exists(path) {
        if isDir(path) {
            return Ok()
        }
        return Err(fsError(ErrorKind.AlreadyExists, $"mkdirAll: 已存在非目录 {path}"))
    }
    Result<Unit, Error> made = makeDir(path)
    if made.isOk() {
        return Ok()
    }
    Path parsedPath = new Path(path)
    String parentPath = parsedPath.parent().toString()
    if parentPath == path || parentPath == "." || parentPath == "/" {
        return Err(made.error())
    }
    if parentPath == ".." {
        return Err(made.error())
    }
    Result<Unit, Error> parentMade = mkdirAll(parentPath)
    if parentMade.isErr() {
        return Err(parentMade.error())
    }
    return makeDir(path)
}

// 递归删除目录树；缺失视为成功（便于 TempDir 幂等关闭）。
Result<Unit, Error> removeDirAll(String path) {
    Result<Metadata, Error> info = linkMetadata(path)
    if info.isErr() {
        if info.error().kind() == ErrorKind.NotFound {
            return Ok()
        }
        return Err(info.error())
    }
    if !info.value().isDirectory() {
        return removeFile(path)
    }
    Result<Dir, Error> opened = openDir(path)
    if opened.isErr() {
        return Err(opened.error())
    }
    Dir directory = opened.value()
    while true {
        Result<String?, Error> next = directory.next()
        if next.isErr() {
            Result<Unit, Error> ignored = directory.close()
            return Err(next.error())
        }
        if next.value() == null {
            break
        }
        String name = next.value() as String
        String child = pathJoin(path, name)
        Result<Unit, Error> removed = removeDirAll(child)
        if removed.isErr() {
            Result<Unit, Error> ignored = directory.close()
            return Err(removed.error())
        }
    }
    Result<Unit, Error> closed = directory.close()
    if closed.isErr() {
        return Err(closed.error())
    }
    return removeDir(path)
}

// ---------- 元数据、权限、链接 ----------

static Result<Metadata, Error> metadataOf(String path, Bool followLink) {
    if path.length() == 0 {
        return Err(fsError(ErrorKind.InvalidArgument, "metadata: 路径为空"))
    }
    Int follow = 0
    if followLink {
        follow = 1
    }
    Int kindCode = pathKindRaw(path, follow)
    if kindCode == 0 {
        return Err(fsPathError("metadata", path))
    }
    Long size = pathSizeRaw(path, follow)
    if fsErrorRaw() != 0 {
        return Err(fsPathError("metadata", path))
    }
    Long modifiedMillis = pathMtimeRaw(path, follow)
    if fsErrorRaw() != 0 {
        return Err(fsPathError("metadata", path))
    }
    Int mode = pathModeRaw(path, follow)
    if mode < 0 {
        return Err(fsPathError("metadata", path))
    }
    return Ok(new Metadata(entryKindFromCode(kindCode), size, modifiedMillis, mode))
}

Result<Metadata, Error> metadata(String path) {
    return metadataOf(path, true)
}

Result<Metadata, Error> linkMetadata(String path) {
    return metadataOf(path, false)
}

Result<Int, Error> permissions(String path) {
    if path.length() == 0 {
        return Err(fsError(ErrorKind.InvalidArgument, "permissions: 路径为空"))
    }
    Int mode = pathModeRaw(path, 1)
    if mode < 0 {
        return Err(fsPathError("permissions", path))
    }
    return Ok(mode)
}

Result<Unit, Error> setPermissions(String path, Int mode) {
    if path.length() == 0 {
        return Err(fsError(ErrorKind.InvalidArgument, "setPermissions: 路径为空"))
    }
    if mode < 0 {
        return Err(fsError(ErrorKind.InvalidArgument, "setPermissions: 模式为负"))
    }
    Int rc = pathChmodRaw(path, mode)
    if rc != 0 {
        return Err(fsPathError("setPermissions", path))
    }
    return Ok()
}

Result<Unit, Error> createSymlink(String target, String linkPath) {
    if target.length() == 0 || linkPath.length() == 0 {
        return Err(fsError(ErrorKind.InvalidArgument, "createSymlink: 路径为空"))
    }
    Int rc = pathSymlinkRaw(target, linkPath)
    if rc != 0 {
        return Err(fsPathError("createSymlink", linkPath))
    }
    return Ok()
}

Result<Unit, Error> createHardLink(String target, String linkPath) {
    if target.length() == 0 || linkPath.length() == 0 {
        return Err(fsError(ErrorKind.InvalidArgument, "createHardLink: 路径为空"))
    }
    Int rc = pathHardlinkRaw(target, linkPath)
    if rc != 0 {
        return Err(fsPathError("createHardLink", linkPath))
    }
    return Ok()
}

Result<String, Error> readLink(String path) {
    if path.length() == 0 {
        return Err(fsError(ErrorKind.InvalidArgument, "readLink: 路径为空"))
    }
    String target = pathReadlinkRaw(path)
    if fsErrorRaw() != 0 {
        return Err(fsPathError("readLink", path))
    }
    return Ok(target)
}

Result<String, Error> canonicalPath(String path) {
    if path.length() == 0 {
        return Err(fsError(ErrorKind.InvalidArgument, "canonicalPath: 路径为空"))
    }
    String resolved = pathRealpathRaw(path)
    if fsErrorRaw() != 0 {
        return Err(fsPathError("canonicalPath", path))
    }
    return Ok(resolved)
}

// ---------- 路径、遍历、glob ----------

String pathJoin(String basePath, String childName) {
    if basePath.length() == 0 {
        return childName
    }
    if childName.length() == 0 {
        return basePath
    }
    if childName.substring(0, 1) == "/" {
        return childName
    }
    if basePath.substring(basePath.length() - 1, 1) == "/" {
        return $"{basePath}{childName}"
    }
    return $"{basePath}/{childName}"
}

static Result<Unit, Error> walkInto(String root, List<String> result) {
    Result<Dir, Error> opened = openDir(root)
    if opened.isErr() {
        return Err(opened.error())
    }
    Dir directory = opened.value()
    while true {
        Result<String?, Error> next = directory.next()
        if next.isErr() {
            Result<Unit, Error> ignored = directory.close()
            return Err(next.error())
        }
        if next.value() == null {
            break
        }
        String name = next.value() as String
        String child = pathJoin(root, name)
        Result<Metadata, Error> info = linkMetadata(child)
        if info.isErr() {
            Result<Unit, Error> ignored = directory.close()
            return Err(info.error())
        }
        if info.value().isDirectory() {
            Result<Unit, Error> sub = walkInto(child, result)
            if sub.isErr() {
                Result<Unit, Error> ignored = directory.close()
                return Err(sub.error())
            }
        } else {
            result.push(child)
        }
    }
    return directory.close()
}

// 深度优先返回 root 下的全部非目录条目；不跟随符号链接目录。
Result<List<String>, Error> walk(String root) {
    if root.length() == 0 {
        return Err(fsError(ErrorKind.InvalidArgument, "walk: 路径为空"))
    }
    Result<Metadata, Error> info = metadata(root)
    if info.isErr() {
        return Err(info.error())
    }
    if !info.value().isDirectory() {
        return Err(fsError(ErrorKind.InvalidArgument, $"walk: 不是目录 {root}"))
    }
    List<String> result = []
    Result<Unit, Error> completed = walkInto(root, result)
    if completed.isErr() {
        return Err(completed.error())
    }
    return Ok(result)
}

static Bool globMatchAt(String text, String pattern, Int textIndex, Int patternIndex) {
    if patternIndex >= pattern.length() {
        return textIndex >= text.length()
    }
    String token = pattern.substring(patternIndex, 1)
    if token == "*" {
        if patternIndex + 1 < pattern.length() && pattern.substring(patternIndex + 1, 1) == "*" {
            Int nextPattern = patternIndex + 2
            if nextPattern < pattern.length() && pattern.substring(nextPattern, 1) == "/" {
                if globMatchAt(text, pattern, textIndex, nextPattern + 1) {
                    return true
                }
                Int index = textIndex
                while index < text.length() {
                    if text.substring(index, 1) == "/" {
                        if globMatchAt(text, pattern, index + 1, nextPattern + 1) {
                            return true
                        }
                    }
                    index = index + 1
                }
                return false
            }
            Int anyIndex = textIndex
            while anyIndex <= text.length() {
                if globMatchAt(text, pattern, anyIndex, nextPattern) {
                    return true
                }
                anyIndex = anyIndex + 1
            }
            return false
        }
        Int starIndex = textIndex
        while starIndex <= text.length() {
            if globMatchAt(text, pattern, starIndex, patternIndex + 1) {
                return true
            }
            if starIndex < text.length() && text.substring(starIndex, 1) == "/" {
                break
            }
            starIndex = starIndex + 1
        }
        return false
    }
    if textIndex >= text.length() {
        return false
    }
    if token == "?" {
        if text.substring(textIndex, 1) == "/" {
            return false
        }
        return globMatchAt(text, pattern, textIndex + 1, patternIndex + 1)
    }
    if text.substring(textIndex, 1) == token {
        return globMatchAt(text, pattern, textIndex + 1, patternIndex + 1)
    }
    return false
}

Bool globMatch(String text, String pattern) {
    return globMatchAt(text, pattern, 0, 0)
}

static Void collectGlob(String openRoot, String displayPrefix, String pattern, List<String> result) {
    Result<Dir, Error> opened = openDir(openRoot)
    if opened.isErr() {
        return
    }
    Dir directory = opened.value()
    while true {
        Result<String?, Error> next = directory.next()
        if next.isErr() {
            Result<Unit, Error> ignored = directory.close()
            return
        }
        if next.value() == null {
            break
        }
        String name = next.value() as String
        String childOpen = pathJoin(openRoot, name)
        String childDisplay = $"{displayPrefix}{name}"
        if globMatch(childDisplay, pattern) {
            result.push(childDisplay)
        }
        Result<Metadata, Error> info = linkMetadata(childOpen)
        if info.isOk() && info.value().isDirectory() {
            collectGlob(childOpen, $"{childDisplay}/", pattern, result)
        }
    }
    Result<Unit, Error> ignoredClose = directory.close()
}

// POSIX glob 子集：`*`、`?`、`**`；不跟随符号链接目录，结果顺序不承诺。
Result<List<String>, Error> glob(String pattern) {
    if pattern.length() == 0 {
        return Err(fsError(ErrorKind.InvalidArgument, "glob: 模式为空"))
    }
    Int wildcard = -1
    Int index = 0
    while index < pattern.length() {
        String token = pattern.substring(index, 1)
        if token == "*" || token == "?" {
            wildcard = index
            break
        }
        index = index + 1
    }
    List<String> result = []
    if wildcard < 0 {
        Result<Metadata, Error> info = metadata(pattern)
        if info.isOk() {
            result.push(pattern)
        }
        return Ok(result)
    }
    Int slash = -1
    Int back = wildcard - 1
    while back >= 0 {
        if pattern.substring(back, 1) == "/" {
            slash = back
            break
        }
        back = back - 1
    }
    String openRoot = "."
    String displayPrefix = ""
    if slash >= 0 {
        displayPrefix = pattern.substring(0, slash + 1)
        if displayPrefix == "/" {
            openRoot = "/"
        } else {
            openRoot = displayPrefix.substring(0, displayPrefix.length() - 1)
        }
    }
    collectGlob(openRoot, displayPrefix, pattern, result)
    return Ok(result)
}

// ---------- 临时文件 ----------

Result<TempFile, Error> createTempFile(String prefix) {
    String path = tempFileRaw(prefix)
    if fsErrorRaw() != 0 || path.length() == 0 {
        return Err(fsOperationError("createTempFile"))
    }
    return Ok(new TempFile(path))
}

Result<TempDir, Error> createTempDir(String prefix) {
    String path = tempDirRaw(prefix)
    if fsErrorRaw() != 0 || path.length() == 0 {
        return Err(fsOperationError("createTempDir"))
    }
    return Ok(new TempDir(path))
}
