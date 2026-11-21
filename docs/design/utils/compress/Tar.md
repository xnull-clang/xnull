# `Tar`

| 项 | 值 |
| --- | --- |
| 类型 | `class Tar` |
| 包 | `xdk.compress` |
| 稳定性 | `preview` |
| 依赖 | `TarEntry`、`Bytes`、`Path`、`FileSystem`、`Error` |

---

## 1. 定位

tar 归档静态入口：写 ustar、读 ustar/PAX 名称、按上限读取、解压到目录、格式探测。

不做：符号链接/设备/稀疏文件、加密、分卷、流式 tar（X）、GNU 长名写出。

---

## 2. 设计逻辑

- 无状态；构造器私有。
- `write` 只写 ustar；名称超过 ustar 字段时返回 `InvalidArgument`。
- `read` 支持 ustar 和 PAX 长名称/长路径；其他扩展类型返回 `Unsupported` 或跳过（按实现明确）。
- 默认读取上限：10000 条目、总内容 256 MiB；`readWithLimits` 显式覆盖。
- 写出去重名称；读入允许重复名称，`extractTo` 后者覆盖前者。
- `isTar` 只做头/魔数启发式判断，不是完整性或安全性校验。
- 无 close；可并发。

---

## 3. 表示与不变量

无实例字段。

不变量：写出的每个条目名称安全且唯一；总内容不超过上限；读取不返回超过上限的条目/内容。

---

## 4. 生命周期

静态命名空间；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Tar()` | 无 | 私有 | 外部构造 → 编译错误 |

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `write` | 写 tar 字节 | `List<TarEntry> entries` | `Result<Bytes, Error>` | `InvalidArgument`/`Unsupported` |
| `writeTo` | 写 tar 文件 | `String path, List<TarEntry> entries` | `Result<Unit, Error>` | `Io`/`InvalidArgument` |
| `read` | 读 tar 字节 | `Bytes data` | `Result<List<TarEntry>, Error>` | `DataCorrupted`/`Unsupported` |
| `readWithLimits` | 限额读取 | `Bytes data, Int maxEntries, Int maxTotalBytes` | `Result<List<TarEntry>, Error>` | 同上/`InvalidArgument` |
| `readFrom` | 读 tar 文件 | `String path` | `Result<List<TarEntry>, Error>` | `NotFound`/`Io`/`DataCorrupted` |
| `extractTo` | 解压到目录 | `String directory, List<TarEntry> entries` | `Result<Unit, Error>` | `Io`/`InvalidArgument` |
| `isTar` | 格式探测 | `Bytes data` | `Bool` | null → panic |

说明：

- `write` 空列表生成两个 512 字节全零块（结束标记）。
- `read` 遇到结束标记停止；尾部垃圾忽略还是报错由实现明确， 选择忽略全零块后数据。
- `extractTo` 目录条目创建目录；文件条目写文件；部分失败不回滚。
- `readWithLimits` 的 `maxEntries`、`maxTotalBytes` 必须 >0。

---

## 8. 使用的技术

- ustar 头/校验和；
- 512 字节块；
- PAX 扩展读取；
- 路径安全；
- 资源上限。

---

## 9. 需要的支撑

- 语言：class、Bytes、String、Int、Long、List、Bool、Result、Unit；
- 运行时：`tarWriteRaw`、`tarReadRaw`、`tarIsRaw`；
- 接口：`TarEntry`、`Path`、`FileSystem`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`TarEntry`、`Path`、`FileSystem`、`Error`、tar 运行时原语。

---

## 11. 所有权与并发

无状态；无资源；可并发；每次调用独立。

---

## 12. 示例与反例

正确：`Tar.write(entries)`；`Tar.extractTo("out", entries)`。  
反例：用 `isTar` 做认证；解压不可信 `../` 名称；无上限读取；期望符号链接被还原。

---

## 13. 测试/场景义务

空归档；单/多文件；目录；长名称/PAX；截断；校验和错误；重复名称；上限；路径逃逸；文件读写；`isTar` 假阳性/假阴性。

---

## 14. XNull 伪代码

```xnull
class Tar {
    private Tar() {
    }

    static Result<Bytes, Error> write(List<TarEntry> entries) {
        if entries == null { throw "Tar.write: null entries" }
        return tarWriteRaw(entries, 268435456)
    }

    static Result<Unit, Error> writeTo(String path, List<TarEntry> entries) {
        if path == null { throw "Tar.writeTo: null path" }
        Result<Bytes, Error> data = Tar.write(entries)
        if data.isErr() { return Err(data.error()) }
        Result<Long, Error> written = FileSystem.writeAllBytes(path, data.value())
        if written.isErr() { return Err(written.error()) }
        return Ok(unit)
    }

    static Result<List<TarEntry>, Error> read(Bytes data) {
        return Tar.readWithLimits(data, 10000, 268435456)
    }

    static Result<List<TarEntry>, Error> readWithLimits(Bytes data, Int maxEntries, Int maxTotalBytes) {
        if data == null { throw "Tar.readWithLimits: null data" }
        if maxEntries <= 0 || maxTotalBytes <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid tar limit"))
        }
        return tarReadRaw(data, maxEntries, maxTotalBytes)
    }

    static Result<List<TarEntry>, Error> readFrom(String path) {
        if path == null { throw "Tar.readFrom: null path" }
        Result<Bytes, Error> data = FileSystem.readAllBytes(path)
        if data.isErr() { return Err(data.error()) }
        return Tar.read(data.value())
    }

    static Result<Unit, Error> extractTo(String directory, List<TarEntry> entries) {
        if directory == null || entries == null {
            throw "Tar.extractTo: null argument"
        }
        Result<Unit, Error> created = FileSystem.createDirs(directory)
        if created.isErr() { return created }
        Int index = 0
        while index < entries.length() {
            TarEntry entry = entries.get(index)
            Path target = new Path(directory).join(entry.name())
            if entry.isDirectory() {
                Result<Unit, Error> made = FileSystem.createDirs(target.text())
                if made.isErr() { return made }
            } else {
                Result<Long, Error> written = FileSystem.writeAllBytes(target.text(), entry.content())
                if written.isErr() { return Err(written.error()) }
            }
            index = index + 1
        }
        return Ok(unit)
    }

    static Bool isTar(Bytes data) {
        if data == null { throw "Tar.isTar: null data" }
        return tarIsRaw(data)
    }
}
```

> `tar*Raw` 是运行时 tar 原语；不是 XDK 公共类型。
