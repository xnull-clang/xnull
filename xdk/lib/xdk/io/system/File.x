// Tier: T0；依赖：xdk.bytes、xdk.errors；稳定性：preview。
// xdk.sys —— 文件句柄（兼容面；规范实现见 xdk.fs）。所有 OS 资源必须 close；close 幂等。
package xdk.sys
import xdk.bytes
import xdk.errors

class File {
    final String path
    Long handle
    Int modeCode
    Bool opened

    File(String path) {
        self.path = path
        self.handle = 0
        self.modeCode = 0
        self.opened = false
    }

    Result<Unit, Error> open(FileMode mode) {
        if self.opened {
            return Err(sysError(ErrorKind.InvalidArgument, "File.open: 文件已打开"))
        }
        if self.path.length() == 0 {
            return Err(sysError(ErrorKind.InvalidArgument, "File.open: 路径为空"))
        }
        Int code = fileModeCode(mode)
        Long openedHandle = fileOpenHandleRaw(self.path, code)
        if openedHandle == 0 {
            return Err(sysPathError("File.open", self.path))
        }
        self.handle = openedHandle
        self.modeCode = code
        self.opened = true
        return Ok()
    }

    Bool isOpen() {
        return self.opened
    }

    Bool isWritable() {
        return self.modeCode == 1 || self.modeCode == 2 || self.modeCode == 3
    }

    Bool isReadable() {
        return self.modeCode == 0 || self.modeCode == 3
    }

    Result<Long, Error> position() {
        if !self.opened {
            return Err(sysError(ErrorKind.Unavailable, "File.position: 文件未打开"))
        }
        Long current = fileTellHandleRaw(self.handle)
        if current < 0 {
            return Err(sysPathError("File.position", self.path))
        }
        return Ok(current)
    }

    Result<Long, Error> size() {
        if !self.opened {
            return Err(sysError(ErrorKind.Unavailable, "File.size: 文件未打开"))
        }
        Long length = fileSizeHandleRaw(self.handle)
        if length < 0 {
            return Err(sysPathError("File.size", self.path))
        }
        return Ok(length)
    }

    Result<Unit, Error> seek(Long offset) {
        if offset < 0 {
            return Err(sysError(ErrorKind.InvalidArgument, "File.seek: 偏移为负"))
        }
        if !self.opened {
            return Err(sysError(ErrorKind.Unavailable, "File.seek: 文件未打开"))
        }
        Long position = fileSeekHandleRaw(self.handle, offset)
        if position < 0 {
            return Err(sysPathError("File.seek", self.path))
        }
        return Ok()
    }

    Result<Bytes, Error> read(Long maximumBytes) {
        if maximumBytes < 0 {
            return Err(sysError(ErrorKind.InvalidArgument, "File.read: 读取长度为负"))
        }
        if !self.opened {
            return Err(sysError(ErrorKind.Unavailable, "File.read: 文件未打开"))
        }
        if !self.isReadable() {
            return Err(sysError(ErrorKind.InvalidArgument, "File.read: 当前模式不可读"))
        }
        String hexadecimal = fileReadHexHandleRaw(self.handle, maximumBytes)
        if fsErrorRaw() != 0 {
            return Err(sysPathError("File.read", self.path))
        }
        return Ok(hexDecode(hexadecimal))
    }

    Result<Bytes, Error> readAll() {
        Result<Long, Error> length = self.size()
        if length.isErr() {
            return Err(length.error())
        }
        Result<Long, Error> position = self.position()
        if position.isErr() {
            return Err(position.error())
        }
        Long remaining = length.value() - position.value()
        if remaining <= 0 {
            return Ok(Bytes.fromString(""))
        }
        return self.read(remaining)
    }

    Result<String, Error> readText() {
        Result<Bytes, Error> content = self.readAll()
        if content.isErr() {
            return Err(content.error())
        }
        return Ok(content.value().toString())
    }

    Result<Long, Error> write(Bytes data) {
        if !self.opened {
            return Err(sysError(ErrorKind.Unavailable, "File.write: 文件未打开"))
        }
        if !self.isWritable() {
            return Err(sysError(ErrorKind.InvalidArgument, "File.write: 当前模式不可写"))
        }
        Long written = fileWriteHexHandleRaw(self.handle, hexEncode(data))
        if written < 0 {
            return Err(sysPathError("File.write", self.path))
        }
        return Ok(written)
    }

    Result<Long, Error> writeText(String text) {
        Bytes data = Bytes.fromString(text)
        return self.write(data)
    }

    Result<Long, Error> writeLine(String line) {
        return self.writeText($"{line}\n")
    }

    Result<Unit, Error> flush() {
        if !self.opened {
            return Err(sysError(ErrorKind.Unavailable, "File.flush: 文件未打开"))
        }
        Int rc = fileFlushHandleRaw(self.handle)
        if rc != 0 {
            return Err(sysPathError("File.flush", self.path))
        }
        return Ok()
    }

    Result<Unit, Error> close() {
        if !self.opened {
            return Ok()
        }
        self.opened = false
        Long closedHandle = self.handle
        self.handle = 0
        Int rc = fileCloseHandleRaw(closedHandle)
        if rc != 0 {
            return Err(sysPathError("File.close", self.path))
        }
        return Ok()
    }
}

Result<File, Error> openFile(String path, FileMode mode) {
    File file = new File(path)
    Result<Unit, Error> opened = file.open(mode)
    if opened.isErr() {
        return Err(opened.error())
    }
    return Ok(file)
}

Result<File, Error> openFileRead(String path) {
    return openFile(path, FileMode.Read)
}

Result<File, Error> openFileWrite(String path) {
    return openFile(path, FileMode.Write)
}

Result<File, Error> openFileAppend(String path) {
    return openFile(path, FileMode.Append)
}

Result<File, Error> openFileReadWrite(String path) {
    return openFile(path, FileMode.ReadWrite)
}
