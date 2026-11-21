# `File`

| 项 | 值 |
| --- | --- |
| 类型 | `class File implements Reader, Writer, Seekable, Closer` |
| 包 | `xdk.fs` |
| 稳定性 | `stable` |
| 依赖 | `Path`、`OpenOptions`、`Permissions`、`Metadata`、`io` |

---

## 1. 定位

文件句柄：打开/读/写/定位/刷新/元数据/关闭。

不做：网络文件、内存映射、异步、文件锁。

---

## 2. 设计逻辑

- 字段 `_path`、`_options`、`_handle`、`_position`、`_open`。
- `open` 工厂返回 `Result<File,Error>`；非法组合 `InvalidArgument`。
- 读/写遵循 `Reader/Writer` 语义：read 0=EOF，write 可短写。
- 偏移用 `Long`；写模式按 OpenOptions（append 写末尾）。
- close 幂等；关闭后操作 `Unavailable`。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_path` | `Path` | 路径 |
| `_options` | `OpenOptions` | 打开选项 |
| `_handle` | 运行时句柄 | OS 文件 |
| `_position` | `Long` | 当前偏移 |
| `_open` | `Bool` | 可用 |

不变量：position ≥0；open=false 后 I/O 失败。

---

## 4. 生命周期

`open` 创建；必须 close；close 幂等；关闭后 I/O `Unavailable`。

---

## 5. 构造契约

构造器内部；公共入口 `File.open(Path, OpenOptions)`。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 组 | 方法 |
| --- | --- |
| 打开 | `open`、`isOpen`、`isReadable`、`isWritable`、`isSeekable` |
| 读 | `read`、`readAll`、`readText`、`readLine`、`readFully` |
| 写 | `write`、`writeAll`、`writeText`、`writeLine`、`append`、`truncate`、`flush`、`sync` |
| 定位 | `seek`、`position`、`skip` |
| 元数据 | `size`、`metadata`、`permissions`、`setPermissions`、`path` |
| 关闭 | `close` |

详细：

- `open` 参数 `Path path, OpenOptions options`；失败 `NotFound`/`AlreadyExists`/`PermissionDenied`/`InvalidArgument`。
- `read`/`write` 带 `Context`；`write` 可短写。
- `readText` 从当前位置读到末尾；非法 UTF-8 `DataCorrupted`。
- `truncate(Long size)` 需要写权限。
- `seek(Long offset, SeekOrigin origin)` 返回新位置。
- `metadata` 返回 `Result<Metadata,Error>`。

---

## 8. 使用的技术

- OS 文件句柄；
- Long 偏移；
- 读写模式；
- append/truncate；
- 句柄关闭。

---

## 9. 需要的支撑

- 语言：class、Path、OpenOptions、Permissions、Metadata、Context、Bytes、Long、Result；
- 运行时/OS：open/read/write/seek/stat/fsync/close；
- 接口：`Reader`、`Writer`、`Seekable`、`Closer`。

---

## 10. 依赖的特性/接口/类

`Path`、`OpenOptions`、`Permissions`、`Metadata`、`Reader`、`Writer`、`Seekable`、`Closer`、`SeekOrigin`。

---

## 11. 所有权与并发

持有 OS 句柄；必须 close；单任务；非线程安全。

---

## 12. 示例与反例

正确：open read → readAll → close。  
反例：close 后读；append 模式 seek 写；用 Int 偏移；忽略 Result。

---

## 13. 测试/场景义务

打开模式；读/写/追加/截断；seek 三种 origin；size；close 幂等；权限错误；取消。

---

## 14. XNull 伪代码

```xnull
class File implements Reader, Writer, Seekable, Closer {
    Path _path
    OpenOptions _options
    FileHandle _handle
    Long _position
    Bool _open

    static Result<File, Error> open(Path path, OpenOptions options) {
        if path == null || options == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "null open argument"))
        }
        Result<Unit, Error> valid = options.validate()
        if valid.isErr() { return Err(valid.error()) }
        Result<FileHandle, Error> handle = openFileRaw(path.text(), options)
        if handle.isErr() { return Err(handle.error()) }
        File result = new File()
        result._path = path
        result._options = options
        result._handle = handle.value()
        result._position = 0
        result._open = true
        return Ok(result)
    }

    Bool isOpen() { return _open }
    Bool isReadable() { return _options.isRead() }
    Bool isWritable() { return _options.isWrite() || _options.isAppend() }
    Bool isSeekable() { return true }

    Result<Int, Error> read(Context context, Bytes buffer) {
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "file closed"))
        }
        if !self.isReadable() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "file not readable"))
        }
        return readFileRaw(_handle, _position, buffer)
    }

    Result<Int, Error> write(Context context, Bytes data) {
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "file closed"))
        }
        if !self.isWritable() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "file not writable"))
        }
        Long position = _position
        if _options.isAppend() {
            position = sizeFileRaw(_handle)
        }
        Result<Int, Error> written = writeFileRaw(_handle, position, data)
        if written.isErr() { return Err(written.error()) }
        _position = position + written.value() as Long
        return written
    }

    Result<Unit, Error> writeAll(Context context, Bytes data) {
        Int total = 0
        while total < data.length() {
            Bytes part = slice(data, total, data.length())
            Result<Int, Error> written = self.write(context, part)
            if written.isErr() { return Err(written.error()) }
            if written.value() == 0 {
                return Err(new BasicError(ErrorKind.Io, "short write"))
            }
            total = total + written.value()
        }
        return Ok(unit)
    }

    Result<Bytes, Error> readAll(Context context) {
        Bytes result = Bytes.empty()
        Bytes buffer = Bytes.alloc(32768)
        while true {
            Result<Int, Error> read = self.read(context, buffer)
            if read.isErr() { return Err(read.error()) }
            if read.value() == 0 { break }
            result.pushAll(slice(buffer, 0, read.value()))
        }
        return Ok(result)
    }

    Result<String, Error> readText(Context context) {
        Result<Bytes, Error> data = self.readAll(context)
        if data.isErr() { return Err(data.error()) }
        return Ok(toUtf8(data.value()))
    }

    Result<Unit, Error> seek(Long offset, SeekOrigin origin) {
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "file closed"))
        }
        Long base = 0
        if origin == SeekOrigin.Current { base = _position }
        if origin == SeekOrigin.End {
            Result<Long, Error> size = self.size()
            if size.isErr() { return Err(size.error()) }
            base = size.value()
        }
        Long target = base + offset
        if target < 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "negative position"))
        }
        _position = target
        return Ok(unit)
    }

    Long position() { return _position }

    Result<Long, Error> size() {
        return sizeFileRaw(_handle)
    }

    Result<Metadata, Error> metadata() {
        return statFileRaw(_path.text())
    }

    Result<Unit, Error> flush() {
        return flushFileRaw(_handle)
    }

    Result<Unit, Error> sync() {
        return syncFileRaw(_handle)
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        return closeFileRaw(_handle)
    }
}
```

> `FileHandle`、`openFileRaw/readFileRaw/writeFileRaw/sizeFileRaw/statFileRaw/flushFileRaw/syncFileRaw/closeFileRaw` 是 OS/运行时文件原语。
