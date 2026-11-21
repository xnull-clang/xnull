# `Path`

| 项 | 值 |
| --- | --- |
| 类型 | `class Path` |
| 包 | `xdk.fs` |
| 稳定性 | `stable` |
| 依赖 | 无 |

---

## 1. 定位

路径字符串视图：拼接/拆分/规范化；不访问文件系统。

不做：存在性/读写（FileSystem）、符号链接解析、URI 完整语义。

---

## 2. 设计逻辑

- 唯一字段 `_text: String`；不可变。
- 分隔符按平台； 保证 `/` 和原生分隔符。
- `name/stem/extension/parent` 纯字符串操作。
- `normalize` 处理 `.`/`..`/重复分隔符；不解析符号链接。
- `resolve` 相对路径拼接；`relativize` 计算相对路径。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_text` | `String` | 原始路径 |

不变量：不可变；不做 FS 访问。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Path(String text)` | text | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `text` | 原始文本 | 无 | `String` | 无 |
| `toString` | 文本 | 无 | `String` | 无 |
| `isAbsolute` | 绝对 | 无 | `Bool` | 无 |
| `isRelative` | 相对 | 无 | `Bool` | 无 |
| `name` | 最后一段 | 无 | `String` | 无 |
| `stem` | 去扩展名 | 无 | `String` | 无 |
| `extension` | 扩展名 | 无 | `String` | 无 |
| `parent` | 父目录 | 无 | `String` | 无 |
| `join` | 拼接 | `String child` | `Path` | null → panic |
| `resolve` | 相对解析 | `Path other` | `Path` | null → panic |
| `normalize` | 规范化 | 无 | `Path` | 无 |
| `relativize` | 相对化 | `Path other` | `Path` | null → panic |
| `components` | 组件 | 无 | `List<String>` | 无 |
| `startsWith` | 前缀 | `Path other` | `Bool` | null → panic |
| `endsWith` | 后缀 | `Path other` | `Bool` | null → panic |
| `equals` | 值相等 | `Path other` | `Bool` | 无 |
| `compare` | 排序 | `Path other` | `Int` | null → panic |

---

## 8. 使用的技术

- 字符串拆分；
- 平台分隔符；
- `.`/`..` 规范化；
- 相对路径计算。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Int、List；
- 运行时：路径分隔符常量；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`new Path("/a/b.txt").name()` → `b.txt`。  
反例：用 Path 判断存在；依赖 normalize 解析符号链接；传 null。

---

## 13. 测试/场景义务

绝对/相对；name/stem/extension；parent；join/resolve；normalize；relativize；分隔符。

---

## 14. XNull 伪代码

```xnull
class Path {
    final String _text

    Path(String text) {
        if text == null { throw "Path: null text" }
        _text = text
    }

    String text() { return _text }
    String toString() { return _text }
    Bool isAbsolute() { return _text.startsWith("/") }
    Bool isRelative() { return !self.isAbsolute() }

    String name() {
        String value = _text
        while value.length() > 1 && value.endsWith("/") {
            value = value.substring(0, value.length() - 1)
        }
        Int index = value.lastIndexOf("/")
        if index < 0 { return value }
        return value.substring(index + 1, value.length() - index - 1)
    }

    String stem() {
        String value = self.name()
        Int index = value.lastIndexOf(".")
        if index <= 0 { return value }
        return value.substring(0, index)
    }

    String extension() {
        String value = self.name()
        Int index = value.lastIndexOf(".")
        if index <= 0 { return "" }
        return value.substring(index + 1, value.length() - index - 1)
    }

    String parent() {
        String value = _text
        while value.length() > 1 && value.endsWith("/") {
            value = value.substring(0, value.length() - 1)
        }
        Int index = value.lastIndexOf("/")
        if index < 0 { return "." }
        if index == 0 { return "/" }
        return value.substring(0, index)
    }

    Path join(String child) {
        if child == null { throw "Path.join: null" }
        if _text == "" { return new Path(child) }
        if _text.endsWith("/") { return new Path(_text + child) }
        return new Path(_text + "/" + child)
    }

    Path resolve(Path other) {
        if other == null { throw "Path.resolve: null" }
        if other.isAbsolute() { return other }
        return self.join(other._text).normalize()
    }

    Path normalize() {
        Bool absolute = self.isAbsolute()
        List<String> parts = _text.split("/")
        List<String> stack = []
        Int index = 0
        while index < parts.length() {
            String part = parts.get(index)
            if part == "" || part == "." {
            } else if part == ".." {
                if stack.length() > 0 && stack.get(stack.length() - 1) != ".." {
                    stack.remove(stack.length() - 1)
                } else if !absolute {
                    stack.push("..")
                }
            } else {
                stack.push(part)
            }
            index = index + 1
        }
        String result = ""
        index = 0
        while index < stack.length() {
            if index > 0 { result = result + "/" }
            result = result + stack.get(index)
            index = index + 1
        }
        if absolute { result = "/" + result }
        if result == "" { return new Path(".") }
        return new Path(result)
    }

    Path relativize(Path other) {
        if other == null { throw "Path.relativize: null" }
        if self.isAbsolute() != other.isAbsolute() {
            throw "Path.relativize: mixed absolute/relative"
        }
        List<String> base = self.normalize().components()
        List<String> target = other.normalize().components()
        Int common = 0
        while common < base.length() && common < target.length()
            && base.get(common) == target.get(common) {
            common = common + 1
        }
        String result = ""
        Int index = common
        while index < base.length() {
            if result != "" { result = result + "/" }
            result = result + ".."
            index = index + 1
        }
        index = common
        while index < target.length() {
            if result != "" { result = result + "/" }
            result = result + target.get(index)
            index = index + 1
        }
        if result == "" { return new Path(".") }
        return new Path(result)
    }

    List<String> components() {
        List<String> result = []
        List<String> parts = _text.split("/")
        Int index = 0
        while index < parts.length() {
            String part = parts.get(index)
            if part != "" && part != "." {
                result.push(part)
            }
            index = index + 1
        }
        return result
    }

    Bool startsWith(Path other) {
        if other == null { throw "Path.startsWith: null" }
        List<String> left = self.components()
        List<String> right = other.components()
        if right.length() > left.length() { return false }
        Int index = 0
        while index < right.length() {
            if left.get(index) != right.get(index) { return false }
            index = index + 1
        }
        return true
    }

    Bool endsWith(Path other) {
        if other == null { throw "Path.endsWith: null" }
        List<String> left = self.components()
        List<String> right = other.components()
        if right.length() > left.length() { return false }
        Int offset = left.length() - right.length()
        Int index = 0
        while index < right.length() {
            if left.get(offset + index) != right.get(index) { return false }
            index = index + 1
        }
        return true
    }

    Bool equals(Path other) {
        if other == null { return false }
        return _text == other._text
    }

    Int compare(Path other) {
        if other == null { throw "Path.compare: null" }
        if _text < other._text { return -1 }
        if _text > other._text { return 1 }
        return 0
    }
}
```

> `String.split` 是 text 包函数；Path 内部可使用。
