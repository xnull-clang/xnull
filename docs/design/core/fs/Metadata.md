# `Metadata`

| 项 | 值 |
| --- | --- |
| 类型 | `class Metadata` |
| 包 | `xdk.fs` |
| 稳定性 | `preview` |
| 依赖 | `Permissions` |

---

## 1. 定位

文件元数据快照：大小、类型、时间、权限、owner/group。

不做：ACL、扩展属性、inode、设备号。

---

## 2. 设计逻辑

- 不可变快照；字段由 `FileSystem.metadata` 创建。
- `size` 用 `Long`。
- 时间用 epoch 毫秒 `Long`；不可用为 0。
- `permissions` 是 `Permissions`；owner/group 是字符串（可为空）。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_size` | `Long` | 字节 |
| `_kind` | `EntryKind` | 条目类型 |
| `_isFile` | `Bool` | 文件 |
| `_isDirectory` | `Bool` | 目录 |
| `_isSymlink` | `Bool` | 链接 |
| `_createdMillis` | `Long` | 创建时间 |
| `_modifiedMillis` | `Long` | 修改时间 |
| `_accessedMillis` | `Long` | 访问时间 |
| `_permissions` | `Permissions` | 权限 |
| `_owner` | `String` | owner |
| `_group` | `String` | group |

不变量：size ≥0；时间 ≥0；不可变。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

构造器内部；由 `FileSystem.metadata` 创建。测试可用内部工厂。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `size` | 大小 | 无 | `Long` | 无 |
| `kind` | 条目类型 | 无 | `EntryKind` | 无 |
| `isFile` | 文件 | 无 | `Bool` | 无 |
| `isDirectory` | 目录 | 无 | `Bool` | 无 |
| `isSymlink` | 链接 | 无 | `Bool` | 无 |
| `isOther` | 其他类型 | 无 | `Bool` | 无 |
| `createdMillis` | 创建时间 | 无 | `Long` | 无 |
| `modifiedMillis` | 修改时间 | 无 | `Long` | 无 |
| `accessedMillis` | 访问时间 | 无 | `Long` | 无 |
| `permissions` | 权限 | 无 | `Permissions` | 无 |
| `owner` | owner | 无 | `String` | 无 |
| `group` | group | 无 | `String` | 无 |
| `describe` | 摘要 | 无 | `String` | 无 |
| `copy` | 复制 | 无 | `Metadata` | 无 |

---

## 8. 使用的技术

- 不可变快照；
- 位/类型判定；
- 时间字段。

---

## 9. 需要的支撑

- 语言：class、Long、Bool、String；
- 运行时：OS stat；
- 接口：`Permissions`、`EntryKind`。

---

## 10. 依赖的特性/接口/类

`Permissions`、`EntryKind`。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`metadata.size()`；`metadata.modifiedMillis()`。  
反例：用 Metadata 读内容；修改快照期望 FS 变化；依赖 owner/group 在所有平台可用。

---

## 13. 测试/场景义务

文件/目录/链接/缺失；`kind` 与 `isFile/isDirectory/isSymlink/isOther` 一致；大小；时间；权限；owner/group 空值；copy。

---

## 14. XNull 伪代码

```xnull
class Metadata {
    final Long _size
    final EntryKind _kind
    final Bool _isFile
    final Bool _isDirectory
    final Bool _isSymlink
    final Long _createdMillis
    final Long _modifiedMillis
    final Long _accessedMillis
    final Permissions _permissions
    final String _owner
    final String _group

    Metadata(Long size, EntryKind kind, Bool isFile, Bool isDirectory, Bool isSymlink,
             Long createdMillis, Long modifiedMillis, Long accessedMillis,
             Permissions permissions, String owner, String group) {
        _size = size
        _kind = kind
        _isFile = isFile
        _isDirectory = isDirectory
        _isSymlink = isSymlink
        _createdMillis = createdMillis
        _modifiedMillis = modifiedMillis
        _accessedMillis = accessedMillis
        _permissions = permissions
        _owner = owner
        _group = group
    }

    Long size() { return _size }
    EntryKind kind() { return _kind }
    Bool isFile() { return _isFile }
    Bool isDirectory() { return _isDirectory }
    Bool isSymlink() { return _isSymlink }
    Bool isOther() { return _kind == EntryKind.Other }
    Long createdMillis() { return _createdMillis }
    Long modifiedMillis() { return _modifiedMillis }
    Long accessedMillis() { return _accessedMillis }
    Permissions permissions() { return _permissions }
    String owner() { return _owner }
    String group() { return _group }

    String describe() {
        return "size=" + str(_size)
            + " file=" + str(_isFile)
            + " dir=" + str(_isDirectory)
            + " symlink=" + str(_isSymlink)
            + " mode=" + _permissions.toOctal()
    }

    Metadata copy() {
        return new Metadata(_size, _kind, _isFile, _isDirectory, _isSymlink,
            _createdMillis, _modifiedMillis, _accessedMillis,
            _permissions, _owner, _group)
    }
}
```
