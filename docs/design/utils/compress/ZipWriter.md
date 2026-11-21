# `ZipWriter`

| 项 | 值 |
| --- | --- |
| 类型 | `class ZipWriter` |
| 包 | `xdk.compress` |
| 稳定性 | `preview` |
| 依赖 | `ZipOptions`、`Bytes`、`FileSystem`、`Error` |

---

## 1. 定位

zip 写出器：添加文件/目录、完成归档、输出字节或写文件。

不做：读取、ZIP64、加密、分卷、符号链接、追加到已有归档。

---

## 2. 设计逻辑

- 构造时复制 `ZipOptions`；后续修改 options 不影响写出。
- `addFile`/`addDirectory` 只接受相对、安全名称；重名返回 `AlreadyExists`。
- 条目内容在内存中；写入时按 `CompressionLevel` 压缩。
- 单条目/总量超过 `ZipOptions` 上限时返回 `InvalidArgument`。
- `finish` 只能成功一次，后续调用返回同一字节结果；`close` 幂等。
- `finish` 后不能再添加；`close` 未 finish 时丢弃内容。
- 非线程安全；同一 writer 不并发使用。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_handle` | `ZipWriterRaw` | 运行时写出句柄 |
| `_options` | `ZipOptions` | 选项副本 |
| `_closed` | `Bool` | 是否关闭 |
| `_finished` | `Bool` | 是否完成 |
| `_result` | `Bytes?` | 完成后的缓存 |

不变量：名称唯一且安全；`_finished` 后 `_result` 非 null；`_closed` 后不可添加；close 幂等。

---

## 4. 生命周期

构造；添加；`finish` 完成；`close` 释放；close 幂等；无 `deinit` 依赖。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ZipWriter(ZipOptions options)` | options | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `addFile` | 添加文件 | `String name, Bytes content` | `Result<Unit, Error>` | `AlreadyExists`/`InvalidArgument`/`Unavailable` |
| `addDirectory` | 添加目录 | `String name` | `Result<Unit, Error>` | 同上 |
| `finish` | 完成归档 | 无 | `Result<Bytes, Error>` | `Unavailable`/`InvalidArgument` |
| `writeTo` | 完成并写文件 | `String path` | `Result<Unit, Error>` | `Io`/`Unavailable`/`InvalidArgument` |
| `entryCount` | 条目数 | 无 | `Int` | 无 |
| `isFinished` | 是否完成 | 无 | `Bool` | 无 |
| `isClosed` | 是否关闭 | 无 | `Bool` | 无 |
| `close` | 释放 | 无 | `void` | 无；幂等 |

说明：

- `addDirectory("a")` 与 `addDirectory("a/")` 等价，归档名为 `a/`。
- `addFile` 名称不能以 `/` 结尾；空内容合法。
- `finish` 空归档合法，生成只有中央目录的空 zip。
- `writeTo` 先 `finish`，再 `FileSystem.writeAllBytes`；写失败不撤销已生成字节。

---

## 8. 使用的技术

- ZIP 本地头/中央目录；
- DEFLATE 压缩；
- CRC32；
- 名称校验/去重；
- 内存缓冲。

---

## 9. 需要的支撑

- 语言：class、String、Bytes、Int、Bool、Result、Unit；
- 运行时：`zipWriterCreateRaw`、`zipWriterAddFileRaw`、`zipWriterAddDirectoryRaw`、`zipWriterFinishRaw`、`zipWriterCloseRaw`、`ZipWriterRaw`；
- 接口：`ZipOptions`、`FileSystem`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`ZipOptions`、`FileSystem`、`Error`、ZIP 写出运行时原语。

---

## 11. 所有权与并发

引用语义；非线程安全；writer 独占；close 幂等；无资源泄漏。

---

## 12. 示例与反例

正确：`new ZipWriter(options)`；`addFile("a.txt", data)`；`finish()`。  
反例：finish 后 addFile；重复名称；绝对路径/`..`；并发添加；close 后 finish。

---

## 13. 测试/场景义务

空归档；单/多文件；目录；重名；非法名；大小上限；总量上限；finish 幂等；close 后操作；writeTo；压缩级别；CRC 正确。

---

## 14. XNull 伪代码

```xnull
class ZipWriter {
    final ZipWriterRaw _handle
    final ZipOptions _options
    Bool _closed = false
    Bool _finished = false
    Bytes? _result = null

    ZipWriter(ZipOptions options) {
        if options == null { throw "ZipWriter: null options" }
        _options = options.copy()
        _handle = zipWriterCreateRaw(_options)
    }

    Result<Unit, Error> addFile(String name, Bytes content) {
        if name == null || content == null {
            throw "ZipWriter.addFile: null argument"
        }
        if _closed || _finished {
            return Err(new BasicError(ErrorKind.Unavailable, "zip writer is not writable"))
        }
        if name == "" || name.endsWith("/") {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid file name"))
        }
        if content.length() > _options.getMaxEntryBytes() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "entry exceeds limit"))
        }
        return zipWriterAddFileRaw(_handle, name, content, _options)
    }

    Result<Unit, Error> addDirectory(String name) {
        if name == null { throw "ZipWriter.addDirectory: null name" }
        if _closed || _finished {
            return Err(new BasicError(ErrorKind.Unavailable, "zip writer is not writable"))
        }
        if name == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument, "empty directory name"))
        }
        String normalized = name
        if !normalized.endsWith("/") { normalized = normalized + "/" }
        return zipWriterAddDirectoryRaw(_handle, normalized, _options)
    }

    Result<Bytes, Error> finish() {
        if _closed {
            return Err(new BasicError(ErrorKind.Unavailable, "zip writer is closed"))
        }
        if _finished {
            return Ok(_result as Bytes)
        }
        Result<Bytes, Error> result = zipWriterFinishRaw(_handle, _options)
        if result.isErr() { return result }
        _result = result.value()
        _finished = true
        return result
    }

    Result<Unit, Error> writeTo(String path) {
        if path == null { throw "ZipWriter.writeTo: null path" }
        Result<Bytes, Error> result = self.finish()
        if result.isErr() { return Err(result.error()) }
        Result<Long, Error> written = FileSystem.writeAllBytes(path, result.value())
        if written.isErr() { return Err(written.error()) }
        return Ok(unit)
    }

    Int entryCount() { return zipWriterEntryCountRaw(_handle) }
    Bool isFinished() { return _finished }
    Bool isClosed() { return _closed }

    void close() {
        if !_closed {
            _closed = true
            zipWriterCloseRaw(_handle)
        }
    }
}
```

> `ZipWriterRaw` 与 `zipWriter*Raw` 是运行时 zip 原语；不是 XDK 公共类型。
