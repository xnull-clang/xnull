# `xdk.fs` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.fs` |
| 层 | `xdk.core` / L3 |
| 依赖 | `xdk.errors`、`xdk.bytes`、`xdk.io` |
| 被依赖 | `config`、`cli`、`log`、`net` |
| 稳定性 | 基础 `stable`；原子/临时/锁 `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

`xdk.fs` 提供文件系统能力：

- 路径、打开选项、权限；
- 文件句柄读写/定位/关闭；
- 目录遍历/创建/删除；
- 元数据/目录项；
- 临时文件/目录、原子写；
- 递归遍历/glob；
- 文件锁（X）。

不做：网络文件系统、内存映射、符号链接完整语义、权限模型。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 显式 close | File/Dir/TempFile/TempDir/FileLock 必须 close |
| close 幂等 | 第二次 Ok；关闭失败只诊断 |
| Long 偏移/大小 | 文件大小/偏移用 Long，避免 Int 截断 |
| Result | 所有可恢复失败返回 Result；越界/非法参数 panic |
| Path 不访问 FS | Path 只是字符串视图 |
| 原子写 | 写临时文件 + rename；失败不留半文件 |
| 权限 | 最小模型；不承诺 ACL/扩展属性 |
| 非线程安全 | 句柄单任务；共享需外部同步 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `Path` | class | 路径视图/拼接/规范化 | [`Path.md`](Path.md) |
| `OpenOptions` | class | 打开选项 | [`OpenOptions.md`](OpenOptions.md) |
| `Permissions` | class | 权限位 | [`Permissions.md`](Permissions.md) |
| `Metadata` | class | 文件元数据 | [`Metadata.md`](Metadata.md) |
| `DirEntry` | class | 目录项 | [`DirEntry.md`](DirEntry.md) |
| `File` | class | 文件句柄 | [`File.md`](File.md) |
| `Dir` | class | 目录句柄 | [`Dir.md`](Dir.md) |
| `TempFile` | class | 临时文件 | [`TempFile.md`](TempFile.md) |
| `TempDir` | class | 临时目录 | [`TempDir.md`](TempDir.md) |
| `FileSystem` | class | 静态文件系统操作 | [`FileSystem.md`](FileSystem.md) |
| `PathMatcher` | class | glob/通配匹配 | [`PathMatcher.md`](PathMatcher.md) |
| `FileLock` | class | 文件锁（X） | [`FileLock.md`](FileLock.md) |

---

## 4. 顶层函数

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `exists` | 存在性 | `String path` | `Bool` | 无 |
| `isFile` | 是否文件 | `String path` | `Bool` | 无 |
| `isDir` | 是否目录 | `String path` | `Bool` | 无 |
| `isSymlink` | 是否链接 | `String path` | `Bool` | 无 |
| `readText` | 读文本 | `String path` | `Result<String, Error>` | `NotFound`/`PermissionDenied`/`DataCorrupted` |
| `readBytes` | 读字节 | `String path` | `Result<Bytes, Error>` | `NotFound`/`Io` |
| `writeText` | 覆盖写文本 | `String path, String text` | `Result<Long, Error>` | `PermissionDenied`/`Io` |
| `writeBytes` | 覆盖写字节 | `String path, Bytes data` | `Result<Long, Error>` | `PermissionDenied`/`Io` |
| `appendText` | 追加文本 | `String path, String text` | `Result<Long, Error>` | `PermissionDenied`/`Io` |
| `appendBytes` | 追加字节 | `String path, Bytes data` | `Result<Long, Error>` | `PermissionDenied`/`Io` |
| `copyFile` | 复制文件 | `String from, String to` | `Result<Long, Error>` | `NotFound`/`Io` |
| `copyTree` | 复制目录 | `String from, String to` | `Result<Unit, Error>` | `NotFound`/`Io` |
| `renameFile` | 重命名 | `String from, String to` | `Result<Unit, Error>` | `NotFound`/`AlreadyExists` |
| `removeFile` | 删除文件 | `String path` | `Result<Unit, Error>` | `NotFound`/`PermissionDenied` |
| `removeTree` | 递归删除 | `String path` | `Result<Unit, Error>` | `NotFound`/`Io` |
| `makeDir` | 创建目录 | `String path` | `Result<Unit, Error>` | `AlreadyExists`/`Io` |
| `makeDirs` | 递归创建 | `String path` | `Result<Unit, Error>` | `Io` |
| `removeDir` | 删除空目录 | `String path` | `Result<Unit, Error>` | `NotFound`/`Io` |
| `walk` | 递归遍历 | `String root` | `Result<List<String>, Error>` | `NotFound`/`Io` |
| `glob` | 通配遍历 | `String pattern` | `Result<List<String>, Error>` | `InvalidArgument`/`Io` |
| `fileSize` | 大小 | `String path` | `Result<Long, Error>` | `NotFound`/`Io` |
| `fileMtime` | 修改时间 | `String path` | `Result<Long, Error>` | `NotFound`/`Io` |
| `canonicalize` | 规范化 | `String path` | `Result<String, Error>` | `NotFound`/`Io` |
| `symlink` | 创建链接 | `String target, String link` | `Result<Unit, Error>` | `PermissionDenied`/`Io` |
| `readLink` | 读链接 | `String path` | `Result<String, Error>` | `NotFound`/`Io` |
| `setPermissions` | 设置权限 | `String path, Permissions permissions` | `Result<Unit, Error>` | `NotFound`/`PermissionDenied` |
| `writeTextAtomic` | 原子写文本 | `String path, String text` | `Result<Unit, Error>` | `Io` |
| `writeBytesAtomic` | 原子写字节 | `String path, Bytes data` | `Result<Unit, Error>` | `Io` |
| `withTempFile` | 临时文件作用域 | `String prefix, String suffix, Result<T,Error>(TempFile)` | `Result<T, Error>` | `Io` |
| `withTempDir` | 临时目录作用域 | `String prefix, Result<T,Error>(TempDir)` | `Result<T, Error>` | `Io` |

### 4.1 技术/支撑/依赖

- 技术：路径解析、文件句柄、目录迭代、临时文件、rename、权限位、glob。
- 支撑：OS 文件 API、`Bytes`、`Context`、`Result`。
- 依赖：`errors`、`bytes`、`io`、`Path`、`OpenOptions`、`Permissions`、`Metadata`、`DirEntry`、`File`、`Dir`、`TempFile`、`TempDir`、`FileSystem`、`PathMatcher`、`FileLock`。

### 4.2 关键伪代码

```xnull
Result<Long, Error> writeText(String path, String text) {
    return writeBytes(path, fromUtf8(text))
}

Result<Long, Error> writeBytes(String path, Bytes data) {
    Result<File, Error> opened = File.open(new Path(path), OpenOptions.write())
    if opened.isErr() { return Err(opened.error()) }
    File file = opened.value()
    Result<Long, Error> written = file.writeAll(null, data)
    Result<Unit, Error> closed = file.close()
    if written.isErr() { return Err(written.error()) }
    if closed.isErr() { return Err(closed.error()) }
    return written
}

Result<Unit, Error> writeTextAtomic(String path, String text) {
    Path target = new Path(path)
    Result<TempFile, Error> temporary = TempFile.create("atomic-", ".tmp")
    if temporary.isErr() { return Err(temporary.error()) }
    TempFile file = temporary.value()
    Result<Long, Error> written = file.file().writeAll(null, fromUtf8(text))
    if written.isErr() {
        file.close()
        return Err(written.error())
    }
    Result<Unit, Error> persisted = file.persist(target.text())
    if persisted.isErr() { return Err(persisted.error()) }
    return file.close()
}
```

---

## 5. 场景

### F1：配置读写

`readText`/`writeTextAtomic`；缺失 `NotFound`；权限 `PermissionDenied`；原子写不留半文件。

### F2：日志/数据分块

`File` + `io.BufferedWriter`/`Reader`；Long 偏移；close 幂等。

### F3：目录扫描

`Dir.next`/`walk`/`glob`；顺序不承诺；权限错误。

### F4：上传/下载

`File` + `io.Reader/Writer`；流式；临时文件；原子 rename。

### F5：元数据/权限

`Metadata`/`Permissions`；`fileMtime`；权限位。

### F6：并发保护

`FileLock`（X）；跨进程锁；超时/取消。

---

## 6. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 网络 FS | 不做 |
| 内存映射 | X |
| ACL/扩展属性 | 不承诺 |
| 符号链接完整语义 |  只 basic |
| 文件锁 | X |
| 权限模型 | 最小 POSIX 位；Windows 映射有限 |
| 原子写 | 临时文件 + rename；跨设备失败 |
| 目录顺序 | 不承诺；排序由调用方 |
| 大文件 | Long 偏移/大小 |
