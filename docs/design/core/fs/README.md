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
| `EntryKind` | enum | 条目类型 | [`EntryKind.md`](EntryKind.md) |
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
| `walk` | 递归遍历 | `String root` | `Result<List<Path>, Error>` | `NotFound`/`Io` |
| `glob` | 通配遍历 | `String pattern` | `Result<List<Path>, Error>` | `InvalidArgument`/`Io` |
| `fileSize` | 大小 | `String path` | `Result<Long, Error>` | `NotFound`/`Io` |
| `fileMtime` | 修改时间 | `String path` | `Result<Long, Error>` | `NotFound`/`Io` |
| `metadata` | 元数据 | `String path` | `Result<Metadata, Error>` | `NotFound`/`Io` |
| `linkMetadata` | 链接元数据 | `String path` | `Result<Metadata, Error>` | `NotFound`/`Io` |
| `permissions` | 读权限位 | `String path` | `Result<Int, Error>` | `NotFound`/`Io` |
| `globMatch` | 单路径 glob | `String text, String pattern` | `Bool` | 非法 pattern → panic |
| `entryKindName` | 条目类型稳定名 | `EntryKind kind` | `String` | null → `"unknown"` |
| `entryKindFromName` | 条目类型解析 | `String name` | `EntryKind?` | 未知 → null |
| `canonicalize` | 规范化 | `String path` | `Result<String, Error>` | `NotFound`/`Io` |
| `symlink` | 创建链接 | `String target, String link` | `Result<Unit, Error>` | `PermissionDenied`/`Io` |
| `hardLink` | 创建硬链接 | `String target, String link` | `Result<Unit, Error>` | `AlreadyExists`/`Io` |
| `readLink` | 读链接 | `String path` | `Result<String, Error>` | `NotFound`/`Io` |
| `setPermissions` | 设置权限 | `String path, Permissions permissions` | `Result<Unit, Error>` | `NotFound`/`PermissionDenied` |
| `writeTextAtomic` | 原子写文本 | `String path, String text` | `Result<Unit, Error>` | `Io` |
| `writeBytesAtomic` | 原子写字节 | `String path, Bytes data` | `Result<Unit, Error>` | `Io` |
| `withTempFile` | 临时文件作用域 | `String prefix, String suffix, Result<T,Error>(TempFile)` | `Result<T, Error>` | `Io` |
| `withTempDir` | 临时目录作用域 | `String prefix, Result<T,Error>(TempDir)` | `Result<T, Error>` | `Io` |

### 4.1 技术/支撑/依赖

- 技术：路径解析、文件句柄、目录迭代、临时文件、rename、权限位、glob。
- 支撑：OS 文件 API、`Bytes`、`Context`、`Result`。
- 依赖：`errors`、`bytes`、`io`、`Path`、`OpenOptions`、`Permissions`、`Metadata`、`EntryKind`、`DirEntry`、`File`、`Dir`、`TempFile`、`TempDir`、`FileSystem`、`PathMatcher`、`FileLock`。

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

## 7. 1.x 兼容合同（C7）

| 1.x API | 2.x 合同 | 失败/边界 |
| --- | --- | --- |
| `readText` / `readBytes` | `FileSystem.readAllText/readAllBytes`（README 顶层同名 `readText/readBytes`） | `NotFound`/`PermissionDenied`/`DataCorrupted`/`Io` |
| `writeText` / `writeBytes` | `writeAllText/writeAllBytes`；返回 `Long` | 覆盖写；返回字节数 |
| `FileMode` / `openFile*` | `OpenOptions` + `File.open` | 1.x `FileMode` 迁移到 `OpenOptions` |
| `Dir.next(): String?` | `Dir.next(): DirEntry?` | 1.x 字符串用 `dirEntry.name()` 迁移 |
| `Path.parent(): Path` / `pathJoin(base, child)` | `Path.parent(): String` / `Path.join(child)` | 1.x `Path` 结果用 `new Path(parentText)`；绝对 child 见 `Path.join` |
| `TempFile.remove()` / `isRemoved()` | `TempFile.close()` / `isOpen()` | close 删除租约；无独立 remove |
| `metadata` / `linkMetadata` | `FileSystem.metadata`；`linkMetadata` 新增 | `NotFound`/`Io`；linkMetadata 不跟随 |
| `Metadata.kind` / `EntryKind` | [`EntryKind.md`](EntryKind.md) + `Metadata.kind/isOther` | 五成员；`Missing` 不是错误 |
| `permissions(path)` | `FileSystem.permissions` 新增；`Metadata.permissions()` 已有 | `mode & 07777`；2.x `Permissions` 已扩展低 12 位 |
| `createSymlink` / `createHardLink` / `readLink` / `canonicalPath` | `symlink` / `hardLink` 新增 / `readLink` / `canonicalize` | 已存在 `AlreadyExists`；空目标 `InvalidArgument` |
| `walk` / `glob` / `globMatch` | `FileSystem.walk/glob` 返回 `List<Path>`；`globMatch` 新增 | 1.x `List<String>` 用 `path.text()` 迁移；`walk` 不跟随链接目录；`glob` 无匹配 `Ok([])` |
| `createTempFile(String)` / `createTempDir` | `createTempFile(prefix, suffix)` / `createTempDir(prefix)`；`TempFile/TempDir` | close 删除租约；幂等 |
| `writeTextAtomic` / `writeBytesAtomic` | `FileSystem.writeTextAtomic/writeBytesAtomic` | 同目录临时文件 + rename；失败不留半文件 |
| `removeFile/renameFile/copyFile/makeDir/removeDir/mkdirAll/removeDirAll` | `remove/move/copy/createDir/removeDir/createDirs/removeTree` | 名称迁移；`removeTree` 缺失路径返回 `NotFound`（1.x 部分为 success） |

示例：

```xnull
Result<String, Error> text = readText("config.conf")
Result<Metadata, Error> meta = FileSystem.metadata("config.conf")
EntryKind kind = meta.value().kind()
Result<Unit, Error> linked = FileSystem.hardLink("a.txt", "b.txt")
Bool matched = FileSystem.globMatch("a/b.txt", "a/**/*.txt")
```

测试义务：读写/追加；`FileMode`→`OpenOptions` 迁移；`metadata`/`linkMetadata`/`kind`；权限 12 位（含 setuid/setgid/sticky）；`hardLink`/`symlink`/`readLink`/`canonicalize`；`walk`/`glob`/`globMatch`；temp 租约；原子写不留半文件；1.x 名称迁移。

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | 无领域注解 |
| 本包消费 | `@Value`、`@Builder`、`@Override` |
| 处理器 | 标准 A8 / 编译器内建 |
| 生成物 | 路径/元数据/权限值语义、OpenOptions builder |
| 状态 | 无领域注解；A8 派生 planned；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `Path`/`Metadata`/`Permissions`/`DirEntry` | `@Value` | 值语义成员 |
| `OpenOptions` | — | 已是显式 with* builder，不叠加 `@Builder` |
| `FileSystem` 实现 | `@Override` | 签名校验 |

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
