# `RegexOptions`

| 项 | 值 |
| --- | --- |
| 类型 | `class RegexOptions` |
| 包 | `xdk.text` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

正则编译选项：大小写、多行、dotAll、Unicode、扩展模式、锚定。

不做：引擎实现、匹配结果、替换。

---

## 2. 设计逻辑

- 不可变；`with*` 返回新实例。
- 选项可组合；`merge` 取并集。
- 默认全关。
- 选项只影响编译/匹配，不改变 pattern 文本。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_caseInsensitive` | `Bool` | 忽略大小写 |
| `_multiline` | `Bool` | `^/$` 按行 |
| `_dotAll` | `Bool` | `.` 匹配换行 |
| `_unicode` | `Bool` | Unicode 字符类 |
| `_extended` | `Bool` | 忽略空白/注释 |
| `_anchored` | `Bool` | 只从开头匹配 |

不变量：布尔字段；不可变；可共享。

---

## 4. 生命周期

不可变；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `RegexOptions()` | 无 | 全 false | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `caseInsensitive` | 读 | 无 | `Bool` | 无 |
| `multiline` | 读 | 无 | `Bool` | 无 |
| `dotAll` | 读 | 无 | `Bool` | 无 |
| `unicode` | 读 | 无 | `Bool` | 无 |
| `extended` | 读 | 无 | `Bool` | 无 |
| `anchored` | 读 | 无 | `Bool` | 无 |
| `withCaseInsensitive` | 派生 | `Bool` | `RegexOptions` | 无 |
| `withMultiline` | 派生 | `Bool` | `RegexOptions` | 无 |
| `withDotAll` | 派生 | `Bool` | `RegexOptions` | 无 |
| `withUnicode` | 派生 | `Bool` | `RegexOptions` | 无 |
| `withExtended` | 派生 | `Bool` | `RegexOptions` | 无 |
| `withAnchored` | 派生 | `Bool` | `RegexOptions` | 无 |
| `merge` | 并集 | `RegexOptions other` | `RegexOptions` | null → panic |
| `describe` | 摘要 | 无 | `String` | 无 |
| `copy` | 复制 | 无 | `RegexOptions` | 无 |

---

## 8. 使用的技术

- 不可变位标志；
- 选项并集；
- 字符串摘要。

---

## 9. 需要的支撑

- 语言：class、Bool、String；
- 运行时：无；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`new RegexOptions().withCaseInsensitive(true).withMultiline(true)`。  
反例：在多处修改同一 options 期望生效；用 options 替代 pattern 内容。

---

## 13. 测试/场景义务

每个 with*；merge；默认值；describe；复制独立性。

---

## 14. XNull 伪代码

```xnull
class RegexOptions {
    Bool _caseInsensitive = false
    Bool _multiline = false
    Bool _dotAll = false
    Bool _unicode = false
    Bool _extended = false
    Bool _anchored = false

    RegexOptions() {
    }

    Bool caseInsensitive() { return _caseInsensitive }
    Bool multiline() { return _multiline }
    Bool dotAll() { return _dotAll }
    Bool unicode() { return _unicode }
    Bool extended() { return _extended }
    Bool anchored() { return _anchored }

    RegexOptions withCaseInsensitive(Bool value) {
        RegexOptions result = self.copy()
        result._caseInsensitive = value
        return result
    }

    RegexOptions withMultiline(Bool value) {
        RegexOptions result = self.copy()
        result._multiline = value
        return result
    }

    RegexOptions withDotAll(Bool value) {
        RegexOptions result = self.copy()
        result._dotAll = value
        return result
    }

    RegexOptions withUnicode(Bool value) {
        RegexOptions result = self.copy()
        result._unicode = value
        return result
    }

    RegexOptions withExtended(Bool value) {
        RegexOptions result = self.copy()
        result._extended = value
        return result
    }

    RegexOptions withAnchored(Bool value) {
        RegexOptions result = self.copy()
        result._anchored = value
        return result
    }

    RegexOptions merge(RegexOptions other) {
        if other == null {
            throw "RegexOptions.merge: null"
        }
        RegexOptions result = self.copy()
        result._caseInsensitive = _caseInsensitive || other._caseInsensitive
        result._multiline = _multiline || other._multiline
        result._dotAll = _dotAll || other._dotAll
        result._unicode = _unicode || other._unicode
        result._extended = _extended || other._extended
        result._anchored = _anchored || other._anchored
        return result
    }

    String describe() {
        return "case=" + str(_caseInsensitive)
            + " multiline=" + str(_multiline)
            + " dotAll=" + str(_dotAll)
            + " unicode=" + str(_unicode)
            + " extended=" + str(_extended)
            + " anchored=" + str(_anchored)
    }

    RegexOptions copy() {
        RegexOptions result = new RegexOptions()
        result._caseInsensitive = _caseInsensitive
        result._multiline = _multiline
        result._dotAll = _dotAll
        result._unicode = _unicode
        result._extended = _extended
        result._anchored = _anchored
        return result
    }
}
```
