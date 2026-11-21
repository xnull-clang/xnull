# `DirEntry`

| 项 | 值 |
| --- | --- |
| 类型 | `class DirEntry` |
| 包 | `xdk.fs` |
| 稳定性 | `preview` |
| 依赖 | `Path`、`Metadata` |

---

## 1. 定位

目录项值对象：名称、路径、类型、大小、元数据。

不做：文件内容、递归、权限修改。

---

## 2. 设计逻辑

- 不可变快照；字段 `_path`、`_name`、`_isFile`、`_isDirectory`、`_isSymlink`、`_size`、`_metadata`。
- `metadata` 可为 null（未读取）；需要时调用方再 stat。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_path` | `Path` | 完整路径 |
| `_name` | `String` | 名称 |
| `_isFile` | `Bool` | 文件 |
| `_isDirectory` | `Bool` | 目录 |
| `_isSymlink` | `Bool` | 链接 |
| `_size` | `Long` | 大小 |
| `_metadata` | `Metadata?` | 可选元数据 |

不变量：name 非空；path 非 null；不可变。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

构造器内部；由 `Dir.next`/`FileSystem` 创建。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `path` | 路径 | 无 | `Path` | 无 |
| `name` | 名称 | 无 | `String` | 无 |
| `isFile` | 文件 | 无 | `Bool` | 无 |
| `isDirectory` | 目录 | 无 | `Bool` | 无 |
| `isSymlink` | 链接 | 无 | `Bool` | 无 |
| `size` | 大小 | 无 | `Long` | 无 |
| `metadata` | 元数据 | 无 | `Metadata?` | 无 |
| `describe` | 摘要 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 不可变快照；
- 路径/名称；
- 类型标记。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Long；
- 运行时：目录读取；
- 接口：`Path`、`Metadata`。

---

## 10. 依赖的特性/接口/类

`Path`、`Metadata`。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`entry.isDirectory()`；`entry.path()`。  
反例：用 DirEntry 读内容；依赖 metadata 一定非 null；修改快照。

---

## 13. 测试/场景义务

文件/目录/链接；name/path；size；metadata 有无；describe。

---

## 14. XNull 伪代码

```xnull
class DirEntry {
    final Path _path
    final String _name
    final Bool _isFile
    final Bool _isDirectory
    final Bool _isSymlink
    final Long _size
    final Metadata? _metadata

    DirEntry(Path path, String name, Bool isFile, Bool isDirectory, Bool isSymlink, Long size, Metadata? metadata) {
        _path = path
        _name = name
        _isFile = isFile
        _isDirectory = isDirectory
        _isSymlink = isSymlink
        _size = size
        _metadata = metadata
    }

    Path path() { return _path }
    String name() { return _name }
    Bool isFile() { return _isFile }
    Bool isDirectory() { return _isDirectory }
    Bool isSymlink() { return _isSymlink }
    Long size() { return _size }
    Metadata? metadata() { return _metadata }

    String describe() {
        return _name + " size=" + str(_size)
            + " file=" + str(_isFile)
            + " dir=" + str(_isDirectory)
    }
}
```
