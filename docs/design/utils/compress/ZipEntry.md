# `ZipEntry`

| 项 | 值 |
| --- | --- |
| 类型 | `class ZipEntry` |
| 包 | `xdk.compress` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

zip 条目元数据：名称、大小、压缩大小、CRC32、修改时间、目录标志、注释。

不做：条目内容、解压执行、路径写盘、ZIP64 扩展字段。

---

## 2. 设计逻辑

- 不可变值对象；字段构造后只读。
- `name` 是归档内名称，使用 `/` 分隔；目录名以 `/` 结尾。
- `isDirectory == true` 时 `name` 必须以 `/` 结尾，且 `size == 0`。
- `size`/`compressedSize` 为非负字节数；`crc32` 为 32 位无符号值，用 `Long` 承载。
- `modifiedMillis` 为 Unix epoch 毫秒；0 表示未提供。
- 名称拒绝 NUL、绝对路径、反斜杠和 `..` 段，避免解压路径逃逸。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | 归档内名称 |
| `_size` | `Long` | 原始字节数 |
| `_compressedSize` | `Long` | 压缩字节数 |
| `_crc32` | `Long` | 0..4294967295 |
| `_modifiedMillis` | `Long` | epoch 毫秒，0 表示无 |
| `_directory` | `Bool` | 是否目录 |
| `_comment` | `String?` | 条目注释 |

不变量：名称非空、相对、无 NUL/反斜杠/`..`；目录名以 `/` 结尾；`size/compressedSize/crc32/modifiedMillis` 非负；`crc32 <= 4294967295`；目录 `size == 0`。

---

## 4. 生命周期

不可变；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ZipEntry(String name, Long size, Long compressedSize, Long crc32, Long modifiedMillis, Bool directory, String? comment)` | 全部 | 见不变量 | 非法 → panic |

构造器由 `ZipArchive`/`ZipWriter` 使用；应用通常只读。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | 名称 | 无 | `String` | 无 |
| `size` | 原始大小 | 无 | `Long` | 无 |
| `compressedSize` | 压缩大小 | 无 | `Long` | 无 |
| `crc32` | CRC32 | 无 | `Long` | 无 |
| `modifiedMillis` | 修改时间 | 无 | `Long` | 无 |
| `isDirectory` | 是否目录 | 无 | `Bool` | 无 |
| `comment` | 注释/无 | 无 | `String?` | 无 |
| `toString` | 名称 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 不可变值对象；
- 归档名称校验；
- 无符号 32 位用 `Long`；
- 目录约定。

---

## 9. 需要的支撑

- 语言：class、String、Long、Bool；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

不可变；可共享；无资源；字段引用只读。

---

## 12. 示例与反例

正确：`new ZipEntry("docs/a.txt", 12, 10, 123, 0, false, null)`。  
反例：`../etc/passwd`；`/abs/path`；目录条目不以 `/` 结尾；`crc32` 负数。

---

## 13. 测试/场景义务

普通/目录；空文件；最大 CRC；时间 0；注释；非法名称；大小边界；目录 size 非零。

---

## 14. XNull 伪代码

```xnull
class ZipEntry {
    final String _name
    final Long _size
    final Long _compressedSize
    final Long _crc32
    final Long _modifiedMillis
    final Bool _directory
    final String? _comment

    ZipEntry(String name, Long size, Long compressedSize, Long crc32,
             Long modifiedMillis, Bool directory, String? comment) {
        if name == null || name == "" { throw "ZipEntry: empty name" }
        if name.contains("\u0000") || name.contains("\\") {
            throw "ZipEntry: invalid name"
        }
        if name.startsWith("/") { throw "ZipEntry: absolute name" }
        List<String> parts = name.split("/")
        Int index = 0
        while index < parts.length() {
            if parts.get(index) == ".." { throw "ZipEntry: parent segment" }
            index = index + 1
        }
        if directory && !name.endsWith("/") {
            throw "ZipEntry: directory name must end with slash"
        }
        if !directory && name.endsWith("/") {
            throw "ZipEntry: file name must not end with slash"
        }
        if size < 0 || compressedSize < 0 || modifiedMillis < 0 {
            throw "ZipEntry: negative size/time"
        }
        if crc32 < 0 || crc32 > 4294967295 {
            throw "ZipEntry: crc32 out of range"
        }
        if directory && size != 0 {
            throw "ZipEntry: directory size must be zero"
        }
        if comment != null && comment.length() > 65535 {
            throw "ZipEntry: comment too long"
        }
        _name = name
        _size = size
        _compressedSize = compressedSize
        _crc32 = crc32
        _modifiedMillis = modifiedMillis
        _directory = directory
        _comment = comment
    }

    String name() { return _name }
    Long size() { return _size }
    Long compressedSize() { return _compressedSize }
    Long crc32() { return _crc32 }
    Long modifiedMillis() { return _modifiedMillis }
    Bool isDirectory() { return _directory }
    String? comment() { return _comment }
    String toString() { return _name }
}
```
