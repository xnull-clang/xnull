# `StringBuilder`

| 项 | 值 |
| --- | --- |
| 类型 | `class StringBuilder` |
| 包 | `xdk.text` |
| 稳定性 | `stable` |
| 依赖 | 无 |

---

## 1. 定位

可变字符串构建器：追加/插入/删除/替换/反转，最后 `build`。

不做：流式 I/O、线程安全、格式化（用 `Format`）。

---

## 2. 设计逻辑

- 内部用片段列表 + 长度，避免频繁字符串拼接。
- `build` 返回新字符串；builder 可继续使用。
- `charAt/setCharAt/substring` 需要先物化；`setCharAt` 重建片段。
- 容量只增不减；`clear` 长度归零。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_parts` | `List<String>` | 片段 |
| `_length` | `Int` | 总字符数 |
| `_capacity` | `Int` | 预留容量 |

不变量：length = 片段长度和；capacity ≥ length；非线程安全。

---

## 4. 生命周期

- 构造空；无 close；可重复 build；非线程安全。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `StringBuilder()` | 无 | 空 | 无 |
| `StringBuilder(Int capacity)` | capacity | ≥0 | 负值 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `append` | 追加文本 | `String text` | `StringBuilder` | null → panic |
| `appendChar` | 追加字符 | `Char character` | `StringBuilder` | 无 |
| `appendInt` | 追加整数 | `Int value` | `StringBuilder` | 无 |
| `appendLong` | 追加 Long | `Long value` | `StringBuilder` | 无 |
| `appendDouble` | 追加 Double | `Double value` | `StringBuilder` | 无 |
| `appendBool` | 追加 Bool | `Bool value` | `StringBuilder` | 无 |
| `appendLine` | 追加文本+换行 | `String text` | `StringBuilder` | null → panic |
| `appendFormat` | 追加 Format | `Format format` | `StringBuilder` | null → panic |
| `insert` | 定位插入 | `Int index, String text` | `StringBuilder` | 越界 → panic |
| `delete` | 删除区间 | `Int start, Int end` | `StringBuilder` | 越界 → panic |
| `replace` | 替换区间 | `Int start, Int end, String text` | `StringBuilder` | 越界 → panic |
| `reverse` | 反转 | 无 | `StringBuilder` | 无 |
| `length` | 长度 | 无 | `Int` | 无 |
| `capacity` | 容量 | 无 | `Int` | 无 |
| `charAt` | 取字符 | `Int index` | `Char` | 越界 → panic |
| `setCharAt` | 设字符 | `Int index, Char character` | `void` | 越界 → panic |
| `substring` | 子串 | `Int start, Int end` | `String` | 越界 → panic |
| `ensureCapacity` | 预留 | `Int minimumCapacity` | `void` | 负值 → panic |
| `clear` | 清空 | 无 | `void` | 无 |
| `build` | 生成字符串 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 片段列表；
- 长度跟踪；
- 懒物化；
- 容量预留；
- 字符数组重建（setCharAt）。

---

## 9. 需要的支撑

- 语言：class、String、Char、Int、Long、Double、Bool、List；
- 运行时：字符串拼接/字符访问；
- 接口：`Format`。

---

## 10. 依赖的特性/接口/类

`Format`（`appendFormat`）。

---

## 11. 所有权与并发

- 可变；非线程安全。
- `build` 返回新字符串；不共享内部片段。
- 无资源、无 close。

---

## 12. 示例与反例

正确：多次 append 后 build；insert/delete 按字符索引。  
反例：负容量；越界 insert；多任务共享不加锁；build 后修改期望旧字符串变化。

---

## 13. 测试/场景义务

空/追加/插入/删除/替换/反转；charAt/setCharAt 边界；capacity；build 独立性；appendFormat。

---

## 14. XNull 伪代码

```xnull
class StringBuilder {
    List<String> _parts
    Int _length
    Int _capacity

    StringBuilder() {
        _parts = []
        _length = 0
        _capacity = 0
    }

    StringBuilder(Int capacity) {
        if capacity < 0 {
            throw "StringBuilder: negative capacity"
        }
        _parts = []
        _length = 0
        _capacity = capacity
    }

    StringBuilder append(String text) {
        if text == null {
            throw "StringBuilder.append: null"
        }
        _parts.push(text)
        _length = _length + text.length()
        if _length > _capacity {
            _capacity = _length
        }
        return self
    }

    StringBuilder appendChar(Char character) {
        return self.append(str(character))
    }

    StringBuilder appendInt(Int value) {
        return self.append(str(value))
    }

    StringBuilder appendLong(Long value) {
        return self.append(str(value))
    }

    StringBuilder appendDouble(Double value) {
        return self.append(str(value))
    }

    StringBuilder appendBool(Bool value) {
        if value {
            return self.append("true")
        }
        return self.append("false")
    }

    StringBuilder appendLine(String text) {
        self.append(text)
        return self.append("\n")
    }

    StringBuilder appendFormat(Format format) {
        if format == null {
            throw "StringBuilder.appendFormat: null"
        }
        return self.append(format.build())
    }

    StringBuilder insert(Int index, String text) {
        if index < 0 || index > _length {
            throw "StringBuilder.insert: out of range"
        }
        String current = self.build()
        String result = current.substring(0, index) + text + current.substring(index, current.length() - index)
        _parts = [result]
        _length = result.length()
        return self
    }

    StringBuilder delete(Int start, Int end) {
        if start < 0 || end > _length || start > end {
            throw "StringBuilder.delete: out of range"
        }
        String current = self.build()
        String result = current.substring(0, start) + current.substring(end, current.length() - end)
        _parts = [result]
        _length = result.length()
        return self
    }

    StringBuilder replace(Int start, Int end, String text) {
        self.delete(start, end)
        return self.insert(start, text)
    }

    StringBuilder reverse() {
        String current = self.build()
        String result = ""
        Int index = current.length() - 1
        while index >= 0 {
            result = result + current.substring(index, 1)
            index = index - 1
        }
        _parts = [result]
        _length = result.length()
        return self
    }

    Int length() { return _length }
    Int capacity() { return _capacity }

    Char charAt(Int index) {
        if index < 0 || index >= _length {
            throw "StringBuilder.charAt: out of range"
        }
        return self.build().charAt(index)
    }

    void setCharAt(Int index, Char character) {
        if index < 0 || index >= _length {
            throw "StringBuilder.setCharAt: out of range"
        }
        String current = self.build()
        String result = current.substring(0, index) + str(character) + current.substring(index + 1, current.length() - index - 1)
        _parts = [result]
        _length = result.length()
    }

    String substring(Int start, Int end) {
        if start < 0 || end > _length || start > end {
            throw "StringBuilder.substring: out of range"
        }
        return self.build().substring(start, end - start)
    }

    void ensureCapacity(Int minimumCapacity) {
        if minimumCapacity < 0 {
            throw "StringBuilder.ensureCapacity: negative"
        }
        if minimumCapacity > _capacity {
            _capacity = minimumCapacity
        }
    }

    void clear() {
        _parts = []
        _length = 0
    }

    String build() {
        String result = ""
        Int index = 0
        while index < _parts.length() {
            result = result + _parts.get(index)
            index = index + 1
        }
        return result
    }
}
```
