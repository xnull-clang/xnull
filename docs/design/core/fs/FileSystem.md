# `FileSystem`

| 项 | 值 |
| --- | --- |
| 类型 | `class FileSystem` |
| 包 | `xdk.fs` |
| 稳定性 | `stable` |
| 依赖 | `Path`、`File`、`Dir`、`Metadata`、`Permissions`、`PathMatcher` |

---

## 1. 定位

文件系统静态操作入口：存在性/读写/复制/移动/删除/目录/遍历/元数据/链接/权限。

不做：挂载/网络 FS、内存映射、ACL、文件锁。

---

## 2. 设计逻辑

- 静态类；无实例状态。
- 所有可恢复失败返回 `Result`。
- 读写用 `File` + `io`；复制分块。
- `writeTextAtomic` 用 `TempFile` + persist。
- `walk` 递归；`glob` 用 `PathMatcher`。
- 顺序不承诺；路径规范化由 `Path`。

---

## 3. 表示与不变量

无实例字段。

---

## 4. 生命周期

静态；无 close。

---

## 5. 构造契约

静态类，不公开构造。

---

## 6. 字段表

无。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `exists` | 存在 | `String path` | `Bool` | 无 |
| `isFile` | 文件 | `String path` | `Bool` | 无 |
| `isDir` | 目录 | `String path` | `Bool` | 无 |
| `isSymlink` | 链接 | `String path` | `Bool` | 无 |
| `readAllBytes` | 读字节 | `String path` | `Result<Bytes, Error>` | `NotFound`/`Io` |
| `readAllText` | 读文本 | `String path` | `Result<String, Error>` | `NotFound`/`DataCorrupted` |
| `writeAllBytes` | 写字节 | `String path, Bytes data` | `Result<Long, Error>` | `Io` |
| `writeAllText` | 写文本 | `String path, String text` | `Result<Long, Error>` | `Io` |
| `appendText` | 追加文本 | `String path, String text` | `Result<Long, Error>` | `Io` |
| `copy` | 复制文件 | `String from, String to` | `Result<Long, Error>` | `Io` |
| `copyTree` | 复制目录 | `String from, String to` | `Result<Unit, Error>` | `Io` |
| `move` | 移动/重命名 | `String from, String to` | `Result<Unit, Error>` | `AlreadyExists`/`Io` |
| `remove` | 删除文件 | `String path` | `Result<Unit, Error>` | `NotFound`/`Io` |
| `removeTree` | 递归删除 | `String path` | `Result<Unit, Error>` | `NotFound`/`Io` |
| `createDir` | 创建目录 | `String path` | `Result<Unit, Error>` | `AlreadyExists`/`Io` |
| `createDirs` | 递归创建 | `String path` | `Result<Unit, Error>` | `Io` |
| `createTempFile` | 临时文件 | `String prefix, String suffix` | `Result<TempFile, Error>` | `Io` |
| `createTempDir` | 临时目录 | `String prefix` | `Result<TempDir, Error>` | `Io` |
| `walk` | 递归遍历 | `String root` | `Result<List<Path>, Error>` | `NotFound`/`Io` |
| `glob` | 通配 | `String pattern` | `Result<List<Path>, Error>` | `InvalidArgument`/`Io` |
| `metadata` | 元数据 | `String path` | `Result<Metadata, Error>` | `NotFound`/`Io` |
| `canonicalize` | 规范化 | `String path` | `Result<String, Error>` | `NotFound`/`Io` |
| `symlink` | 创建链接 | `String target, String link` | `Result<Unit, Error>` | `PermissionDenied`/`Io` |
| `readLink` | 读链接 | `String path` | `Result<String, Error>` | `NotFound`/`Io` |
| `setPermissions` | 设置权限 | `String path, Permissions permissions` | `Result<Unit, Error>` | `NotFound`/`PermissionDenied` |
| `writeTextAtomic` | 原子写文本 | `String path, String text` | `Result<Unit, Error>` | `Io` |
| `writeBytesAtomic` | 原子写字节 | `String path, Bytes data` | `Result<Unit, Error>` | `Io` |

---

## 8. 使用的技术

- OS 文件 API；
- 流复制；
- 临时文件 + rename；
- 递归遍历；
- glob 匹配；
- 权限位。

---

## 9. 需要的支撑

- 语言：class、String、Bytes、Long、Bool、Result、List；
- 运行时/OS：文件/目录/stat/link/rename；
- 接口：`Path`、`File`、`Dir`、`Metadata`、`Permissions`、`PathMatcher`、`TempFile`、`TempDir`。

---

## 10. 依赖的特性/接口/类

`Path`、`File`、`Dir`、`Metadata`、`Permissions`、`PathMatcher`、`TempFile`、`TempDir`、`io.copy`。

---

## 11. 所有权与并发

静态无状态；句柄由调用方 close；线程安全由底层 OS 决定，不承诺。

---

## 12. 示例与反例

正确：`writeTextAtomic(path,text)`；`walk(root)`；`metadata(path)`。  
反例：用 exists 区分权限；`removeTree` 删错根；跨设备 rename；忽略 Result。

---

## 13. 测试/场景义务

存在/类型；读写/追加；复制/移动/删除；递归创建/删除；walk/glob；元数据；链接；原子写；权限错误。

---

## 14. XNull 伪代码

```xnull
class FileSystem {
    static Result<String, Error> readAllText(String path) {
        Result<Bytes, Error> data = readAllBytes(path)
        if data.isErr() { return Err(data.error()) }
        return Ok(toUtf8(data.value()))
    }

    static Result<Bytes, Error> readAllBytes(String path) {
        Result<File, Error> opened = File.open(new Path(path), OpenOptions.read())
        if opened.isErr() { return Err(opened.error()) }
        File file = opened.value()
        Result<Bytes, Error> data = file.readAll(null)
        Result<Unit, Error> closed = file.close()
        if data.isErr() { return Err(data.error()) }
        if closed.isErr() { return Err(closed.error()) }
        return data
    }

    static Result<Long, Error> writeAllBytes(String path, Bytes data) {
        Result<File, Error> opened = File.open(new Path(path), OpenOptions.write())
        if opened.isErr() { return Err(opened.error()) }
        File file = opened.value()
        Result<Unit, Error> written = file.writeAll(null, data)
        Result<Unit, Error> closed = file.close()
        if written.isErr() { return Err(written.error()) }
        if closed.isErr() { return Err(closed.error()) }
        return Ok(data.length() as Long)
    }

    static Result<Unit, Error> createDirs(String path) {
        if exists(path) { return Ok(unit) }
        String parent = new Path(path).parent()
        if parent != "." && parent != "/" && parent != path {
            Result<Unit, Error> created = createDirs(parent)
            if created.isErr() { return Err(created.error()) }
        }
        return makeDirRaw(path)
    }

    static Result<Unit, Error> writeTextAtomic(String path, String text) {
        Result<TempFile, Error> temporary = TempFile.create("atomic-", ".tmp")
        if temporary.isErr() { return Err(temporary.error()) }
        TempFile file = temporary.value()
        Result<Unit, Error> written = file.file().writeAll(null, fromUtf8(text))
        if written.isErr() {
            file.close()
            return Err(written.error())
        }
        return file.persist(path)
    }
}
```

> `makeDirRaw/removeTreeRaw/renameRaw/statRaw/...` 是 OS/运行时文件原语。
