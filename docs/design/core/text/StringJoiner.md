# `StringJoiner`

| 项 | 值 |
| --- | --- |
| 类型 | `class StringJoiner` |
| 包 | `xdk.text` |
| 稳定性 | `stable` |
| 依赖 | 无 |

---

## 1. 定位

用分隔符连接字符串，可带前后缀。用于日志/配置/路径/列表输出。

不做：流式 I/O、线程安全、自动转义。

---

## 2. 设计逻辑

- 保存 parts 和长度；`build` 时拼接。
- prefix/suffix 只在 build 时加；空 parts 时输出 prefix+suffix。
- `add(null)` panic；`add("")` 保留空段。
- `merge` 合并另一个 joiner 的 parts。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_separator` | `String` | 分隔符 |
| `_prefix` | `String` | 前缀 |
| `_suffix` | `String` | 后缀 |
| `_parts` | `List<String>` | 元素 |
| `_length` | `Int` | 字符数（含分隔/前后缀） |

不变量：length 与 build 结果一致；非线程安全。

---

## 4. 生命周期

构造后使用；无 close；可 clear 重用。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `StringJoiner(String separator)` | separator | 非 null | null → panic |
| `StringJoiner(String separator, String prefix, String suffix)` | separator/prefix/suffix | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `add` | 追加元素 | `String text` | `StringJoiner` | null → panic |
| `addAll` | 追加多个 | `List<String> texts` | `StringJoiner` | 非法 → panic |
| `merge` | 合并 | `StringJoiner other` | `StringJoiner` | null → panic |
| `length` | 字符数 | 无 | `Int` | 无 |
| `isEmpty` | 是否无元素 | 无 | `Bool` | 无 |
| `build` | 生成字符串 | 无 | `String` | 无 |
| `clear` | 清空 | 无 | `void` | 无 |

---

## 8. 使用的技术

- 分隔符拼接；
- 前后缀；
- 长度跟踪；
- 合并。

---

## 9. 需要的支撑

- 语言：class、String、Int、Bool、List；
- 运行时：字符串拼接；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

- 可变；非线程安全。
- `build` 返回新字符串。
- 无资源。

---

## 12. 示例与反例

正确：`new StringJoiner(",","[","]").add("a").add("b").build()`。  
反例：null 元素；期望空 parts 输出空串（实际 prefix+suffix）；多任务共享。

---

## 13. 测试/场景义务

空/单/多；空串元素；prefix/suffix；separator 空；merge；length；clear。

---

## 14. XNull 伪代码

```xnull
class StringJoiner {
    String _separator
    String _prefix
    String _suffix
    List<String> _parts
    Int _length

    StringJoiner(String separator) {
        if separator == null {
            throw "StringJoiner: null separator"
        }
        _separator = separator
        _prefix = ""
        _suffix = ""
        _parts = []
        _length = 0
    }

    StringJoiner(String separator, String prefix, String suffix) {
        if separator == null || prefix == null || suffix == null {
            throw "StringJoiner: null part"
        }
        _separator = separator
        _prefix = prefix
        _suffix = suffix
        _parts = []
        _length = prefix.length() + suffix.length()
    }

    StringJoiner add(String text) {
        if text == null {
            throw "StringJoiner.add: null"
        }
        if _parts.length() > 0 {
            _length = _length + _separator.length()
        }
        _parts.push(text)
        _length = _length + text.length()
        return self
    }

    StringJoiner addAll(List<String> texts) {
        Int index = 0
        while index < texts.length() {
            self.add(texts.get(index))
            index = index + 1
        }
        return self
    }

    StringJoiner merge(StringJoiner other) {
        if other == null {
            throw "StringJoiner.merge: null"
        }
        return self.addAll(other._parts)
    }

    Int length() { return _length }
    Bool isEmpty() { return _parts.length() == 0 }

    String build() {
        String result = _prefix
        Int index = 0
        while index < _parts.length() {
            if index > 0 {
                result = result + _separator
            }
            result = result + _parts.get(index)
            index = index + 1
        }
        return result + _suffix
    }

    void clear() {
        _parts = []
        _length = _prefix.length() + _suffix.length()
    }
}
```
