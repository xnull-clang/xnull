# `TarEntry`

| 项 | 值 |
| --- | --- |
| 类型 | `class TarEntry` |
| 包 | `xdk.compress` |
| 稳定性 | `preview` |
| 依赖 | `Bytes` |

---

## 1. 定位

tar 条目：名称、内容、权限位、修改时间、目录标志。

不做：符号链接/硬链接、设备文件、PAX 扩展头、稀疏文件、所有权用户/组名。

---

## 2. 设计逻辑

- 不可变；`content` 构造时复制，读取时返回副本。
- 文件条目名称不以 `/` 结尾；目录条目名称以 `/` 结尾。
- 名称必须是相对路径，拒绝 NUL、反斜杠、绝对路径和 `..` 段。
- `mode` 为 0..4095（八进制 07777）；`modifiedSeconds` 为 Unix epoch 秒。
- 目录条目内容必须为空。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | 归档内名称 |
| `_content` | `Bytes` | 文件内容 |
| `_mode` | `Int` | 权限位 |
| `_modifiedSeconds` | `Long` | epoch 秒 |
| `_directory` | `Bool` | 是否目录 |

不变量：名称非空、相对、安全；目录名以 `/` 结尾；文件名为不以 `/` 结尾；`mode` 0..4095；时间非负；目录内容为空。

---

## 4. 生命周期

不可变；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `TarEntry(String name, Bytes content, Int mode, Long modifiedSeconds, Bool directory)` | 全部 | 见不变量 | 非法 → panic |
| `TarEntry.file(String name, Bytes content, Int mode, Long modifiedSeconds)` | 文件工厂 | 见不变量 | 非法 → panic |
| `TarEntry.directory(String name, Int mode, Long modifiedSeconds)` | 目录工厂 | 名称非空 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `file` | 文件工厂 | `String name, Bytes content, Int mode, Long modifiedSeconds` | `TarEntry` | 非法 → panic |
| `directory` | 目录工厂 | `String name, Int mode, Long modifiedSeconds` | `TarEntry` | 非法 → panic |
| `name` | 名称 | 无 | `String` | 无 |
| `content` | 内容副本 | 无 | `Bytes` | 无 |
| `size` | 内容字节数 | 无 | `Long` | 无 |
| `mode` | 权限位 | 无 | `Int` | 无 |
| `modifiedSeconds` | 修改时间 | 无 | `Long` | 无 |
| `isDirectory` | 是否目录 | 无 | `Bool` | 无 |
| `toString` | 名称 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 不可变值对象；
- 路径安全校验；
- 内容防御性复制；
- tar 类型约定。

---

## 9. 需要的支撑

- 语言：class、String、Bytes、Int、Long、Bool；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

`Bytes`。

---

## 11. 所有权与并发

不可变；`content()` 返回副本；可共享；无资源。

---

## 12. 示例与反例

正确：`TarEntry.file("a.txt", data, 420, 1700000000)`。  
反例：`../x`；绝对路径；目录内容非空；目录名无 `/`；mode 超过 07777。

---

## 13. 测试/场景义务

文件/目录；空文件；内容副本；名称非法；mode 边界；时间 0；`size`；目录 content 空。

---

## 14. XNull 伪代码

```xnull
class TarEntry {
    final String _name
    final Bytes _content
    final Int _mode
    final Long _modifiedSeconds
    final Bool _directory

    TarEntry(String name, Bytes content, Int mode, Long modifiedSeconds, Bool directory) {
        if name == null || name == "" { throw "TarEntry: empty name" }
        if name.contains("\u0000") || name.contains("\\") {
            throw "TarEntry: invalid name"
        }
        if name.startsWith("/") { throw "TarEntry: absolute name" }
        List<String> parts = name.split("/")
        Int index = 0
        while index < parts.length() {
            if parts.get(index) == ".." { throw "TarEntry: parent segment" }
            index = index + 1
        }
        if directory && !name.endsWith("/") {
            throw "TarEntry: directory name must end with slash"
        }
        if !directory && name.endsWith("/") {
            throw "TarEntry: file name must not end with slash"
        }
        if mode < 0 || mode > 4095 { throw "TarEntry: mode out of range" }
        if modifiedSeconds < 0 { throw "TarEntry: negative time" }
        if content == null { throw "TarEntry: null content" }
        if directory && content.length() > 0 {
            throw "TarEntry: directory content must be empty"
        }
        _name = name
        _content = content.copy()
        _mode = mode
        _modifiedSeconds = modifiedSeconds
        _directory = directory
    }

    static TarEntry file(String name, Bytes content, Int mode, Long modifiedSeconds) {
        return new TarEntry(name, content, mode, modifiedSeconds, false)
    }

    static TarEntry directory(String name, Int mode, Long modifiedSeconds) {
        if name == null || name == "" { throw "TarEntry.directory: empty name" }
        String normalized = name
        if !normalized.endsWith("/") { normalized = normalized + "/" }
        return new TarEntry(normalized, Bytes.empty(), mode, modifiedSeconds, true)
    }

    String name() { return _name }
    Bytes content() { return _content.copy() }
    Long size() { return _content.length() as Long }
    Int mode() { return _mode }
    Long modifiedSeconds() { return _modifiedSeconds }
    Bool isDirectory() { return _directory }
    String toString() { return _name }
}
```
