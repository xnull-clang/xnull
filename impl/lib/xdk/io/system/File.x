// xdk.sys 完整实现（源码层过渡单元，仅 XNULL_XDK_SOURCE=1 编入）
//
// 与 impl/lib/xdk/io/base/Sys.x（编译器/默认构建使用的精简面）保持同包语义；默认构建
// 不加载本单元，避免改变冻结 golden。资源 API 见 io/resource/Resource.x。
//
// 依赖矩阵（S6 §2）：sys → errors；运行时服务：handle、ffi-contract。
// 稳定性：@preview。
//
// 实现口径（当前编译器 之前的编译面约束）：
//   - File 为**直接落盘**模型：write 立即写，不缓冲；二进制经 hex 桥传输，
//     文本经 append 原语传输；read 每次按 offset 重新读取。
//   - Dir 用运行时句柄表索引迭代；顺序依文件系统，不排序。
//   - 资源读取按 S6 §4.8：合法路径/只读/不回退 FS/缺失 NotFound。
//   - Context 首参为 S6 §3 惯例；单线程运行时无挂起点，取消面随调度器切片补齐。
//   - 当前产品编译器不支持类静态方法调用，工厂以顶层函数提供：
//     openFileRead/openFileWrite/openFileAppend/openDir/spawnProcess。
package xdk.sys
import xdk.errors

// ---------- 错误映射 ----------





















































































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
