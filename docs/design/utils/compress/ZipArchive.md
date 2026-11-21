# `ZipArchive`

| 项 | 值 |
| --- | --- |
| 类型 | `class ZipArchive` |
| 包 | `xdk.compress` |
| 稳定性 | `preview` |
| 依赖 | `ZipEntry`、`ZipOptions`、`Bytes`、`Path`、`FileSystem`、`Error` |

---

## 1. 定位

只读 zip 归档：打开、列条目、按条目读取、解压到目录。

不做：写出（`ZipWriter`）、ZIP64、加密、分卷、符号链接、流式随机读（X）。

---

## 2. 设计逻辑

- 打开时解析中央目录，保存条目快照与运行时读取句柄。
- `open` 读取整个文件；`openBytes` 直接使用内存数据；两者都受 `ZipOptions` 上限约束。
- `entries`/`getOrNull` 在 close 后仍可读元数据；`readEntry`/`extractTo` 在 close 后返回 `Unavailable`。
- 读取条目时校验声明大小、实际输出、CRC32（`verifyCrc`）。
- `extractTo` 拒绝路径逃逸；条目名在 `ZipEntry` 构造时已校验，写出前再次检查规范化路径。
- 解压失败可能留下已写出的文件； 不提供事务回滚。
- close 幂等；无全局状态。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_handle` | `ZipArchiveRaw` | 运行时读取句柄 |
| `_entries` | `List<ZipEntry>` | 打开时快照 |
| `_options` | `ZipOptions` | 选项副本 |
| `_open` | `Bool` | 是否可读 |

不变量：`_handle`/`_entries`/`_options` 非 null；`_entries` 只读快照；close 后 `_open=false`；条目名安全。

---

## 4. 生命周期

`open`/`openBytes` 创建；`close` 释放运行时句柄；close 幂等；无 `deinit` 依赖。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ZipArchive(ZipArchiveRaw, List<ZipEntry>, ZipOptions)` | 全部 | 非 null | 私有；null → panic |

业务使用 `open`/`openBytes`。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `open` | 打开文件 | `String path, ZipOptions options` | `Result<ZipArchive, Error>` | `NotFound`/`Io`/`DataCorrupted` |
| `openBytes` | 打开内存 | `Bytes data, ZipOptions options` | `Result<ZipArchive, Error>` | `DataCorrupted`/`InvalidArgument` |
| `openBytes` | 默认选项 | `Bytes data` | `Result<ZipArchive, Error>` | 同上 |
| `entries` | 条目快照 | 无 | `List<ZipEntry>` | 无 |
| `getOrNull` | 按名查找 | `String name` | `ZipEntry?` | null → panic |
| `readEntry` | 读取条目 | `ZipEntry entry` | `Result<Bytes, Error>` | `NotFound`/`InvalidArgument`/`DataCorrupted`/`Unavailable` |
| `readEntryByName` | 按名读取 | `String name` | `Result<Bytes, Error>` | `NotFound`/`InvalidArgument`/`DataCorrupted`/`Unavailable` |
| `extractTo` | 解压到目录 | `String directory` | `Result<Unit, Error>` | `Io`/`DataCorrupted`/`Unavailable` |
| `isOpen` | 是否可读 | 无 | `Bool` | 无 |
| `close` | 释放句柄 | 无 | `void` | 无；幂等 |

说明：

- 重名条目保留全部；`getOrNull`/`readEntryByName` 返回第一个匹配。
- `readEntry` 必须传入本归档的条目；外来条目返回 `NotFound`。
- 声明大小超过 `maxEntryBytes` 或总量超过 `maxTotalBytes` 时打开失败。
- `extractTo` 目录不存在时创建；已存在文件覆盖。

---

## 8. 使用的技术

- ZIP 中央目录解析；
- DEFLATE 解压；
- CRC32 校验；
- 路径规范化/防逃逸；
- 资源上限。

---

## 9. 需要的支撑

- 语言：class、Bytes、String、Bool、List、Result、Unit；
- 运行时：`zipArchiveOpenRaw`、`zipArchiveReadEntryRaw`、`zipArchiveCloseRaw`、`ZipArchiveRaw`；
- 接口：`ZipEntry`、`ZipOptions`、`Path`、`FileSystem`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`ZipEntry`、`ZipOptions`、`Path`、`FileSystem`、`Error`、ZIP 运行时原语。

---

## 11. 所有权与并发

引用语义；`readEntry` 可并发（每次独立解压）；`close` 与读取并发时读取可能失败；无资源泄漏；close 幂等。

---

## 12. 示例与反例

正确：`ZipArchive.open("a.zip", options)`；`archive.extractTo("out")`；`defer archive.close()`。  
反例：close 后 readEntry；信任 `../` 条目；无上限打开不可信归档；并发 close/解压期望全部成功。

---

## 13. 测试/场景义务

正常 zip；空 zip；目录条目；重名；CRC 错误；截断；声明大小超限；实际大小超限；路径逃逸；close 幂等；close 后读取；并发读取；文件/内存打开。

---

## 14. XNull 伪代码

```xnull
class ZipArchive {
    final ZipArchiveRaw _handle
    final List<ZipEntry> _entries
    final ZipOptions _options
    Bool _open = true

    private ZipArchive(ZipArchiveRaw handle, List<ZipEntry> entries, ZipOptions options) {
        if handle == null || entries == null || options == null {
            throw "ZipArchive: null argument"
        }
        _handle = handle
        _entries = entries.copy()
        _options = options
    }

    static Result<ZipArchive, Error> open(String path, ZipOptions options) {
        if path == null || options == null {
            throw "ZipArchive.open: null argument"
        }
        Result<Bytes, Error> data = FileSystem.readAllBytes(path)
        if data.isErr() { return Err(data.error()) }
        return ZipArchive.openBytes(data.value(), options)
    }

    static Result<ZipArchive, Error> openBytes(Bytes data, ZipOptions options) {
        if data == null || options == null {
            throw "ZipArchive.openBytes: null argument"
        }
        ZipOptions copied = options.copy()
        Result<ZipArchiveRaw, Error> opened = zipArchiveOpenRaw(data, copied)
        if opened.isErr() { return Err(opened.error()) }
        return Ok(new ZipArchive(opened.value(), opened.value().entries(), copied))
    }

    static Result<ZipArchive, Error> openBytes(Bytes data) {
        return ZipArchive.openBytes(data, new ZipOptions())
    }

    List<ZipEntry> entries() {
        List<ZipEntry> result = []
        Int index = 0
        while index < _entries.length() {
            result.push(_entries.get(index))
            index = index + 1
        }
        return result
    }

    ZipEntry? getOrNull(String name) {
        if name == null { throw "ZipArchive.getOrNull: null name" }
        Int index = 0
        while index < _entries.length() {
            ZipEntry entry = _entries.get(index)
            if entry.name() == name { return entry }
            index = index + 1
        }
        return null
    }

    Result<Bytes, Error> readEntry(ZipEntry entry) {
        if entry == null { throw "ZipArchive.readEntry: null entry" }
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "zip archive is closed"))
        }
        Bool found = false
        Int index = 0
        while index < _entries.length() {
            if _entries.get(index) == entry { found = true }
            index = index + 1
        }
        if !found {
            return Err(new BasicError(ErrorKind.NotFound, "zip entry not found"))
        }
        if entry.isDirectory() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "cannot read a directory entry"))
        }
        return zipArchiveReadEntryRaw(_handle, entry, _options)
    }

    Result<Bytes, Error> readEntryByName(String name) {
        if name == null { throw "ZipArchive.readEntryByName: null name" }
        ZipEntry? entry = self.getOrNull(name)
        if entry == null {
            return Err(new BasicError(ErrorKind.NotFound, "zip entry not found"))
        }
        return self.readEntry(entry as ZipEntry)
    }

    Result<Unit, Error> extractTo(String directory) {
        if directory == null { throw "ZipArchive.extractTo: null directory" }
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "zip archive is closed"))
        }
        Result<Unit, Error> created = FileSystem.createDirs(directory)
        if created.isErr() { return created }
        Int index = 0
        while index < _entries.length() {
            ZipEntry entry = _entries.get(index)
            Path target = new Path(directory).join(entry.name())
            if entry.isDirectory() {
                Result<Unit, Error> made = FileSystem.createDirs(target.text())
                if made.isErr() { return made }
            } else {
                Result<Bytes, Error> content = self.readEntry(entry)
                if content.isErr() { return Err(content.error()) }
                Result<Long, Error> written = FileSystem.writeAllBytes(target.text(), content.value())
                if written.isErr() { return Err(written.error()) }
            }
            index = index + 1
        }
        return Ok(unit)
    }

    Bool isOpen() { return _open }

    void close() {
        if _open {
            _open = false
            zipArchiveCloseRaw(_handle)
        }
    }
}
```

> `ZipArchiveRaw` 与 `zipArchive*Raw` 是运行时 zip 原语；不是 XDK 公共类型。
