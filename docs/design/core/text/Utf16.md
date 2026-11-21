# `Utf16`

| 项 | 值 |
| --- | --- |
| 类型 | `class Utf16` |
| 包 | `xdk.text` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

UTF-16 码元序列包装，避开 `Result<List<...>>` 的类型折叠；用于 UTF-8/UTF-16 转换。

不做：自动校验代理对、Unicode 规范化、流式编码。

---

## 2. 设计逻辑

- 持有 `List<UInt16>`；长度是码元数，不是码点数。
- 不可变包装；`units` 返回快照。
- `fromString` 按 UTF-16 码元拆分；`toString` 按码元拼接。
- 非法代理对由转换函数返回 `DataCorrupted`，本类不做校验。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_units` | `List<UInt16>` | 码元序列 |

不变量：每个码元 0..65535；不可变；长度 = 码元数。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Utf16(List<UInt16> units)` | units | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `length` | 码元数 | 无 | `Int` | 无 |
| `get` | 取码元 | `Int index` | `UInt16` | 越界 → panic |
| `units` | 快照 | 无 | `List<UInt16>` | 无 |
| `toList` | 快照 | 无 | `List<UInt16>` | 无 |
| `fromString` | 字符串→码元 | `String text` | `Utf16` | 无 |
| `toString` | 码元→字符串 | 无 | `String` | 无 |

---

## 8. 使用的技术

- UTF-16 码元；
- 代理对保留；
- 列表快照。

---

## 9. 需要的支撑

- 语言：class、List、UInt16、String、Int；
- 运行时：字符串码元访问/拼接；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

不可变；`units()` 返回快照；可共享；无资源。

---

## 12. 示例与反例

正确：`utf8ToUtf16(bytes)` 返回 `Utf16`；`length()` 按码元。  
反例：把码元数当码点数；修改 `units()` 期望原对象变化；用 Utf16 做规范化。

---

## 13. 测试/场景义务

空/ASCII/BMP/代理对；length/get；units 快照；fromString/toString 往返；非法代理对由转换函数处理。

---

## 14. XNull 伪代码

```xnull
class Utf16 {
    List<UInt16> _units

    Utf16(List<UInt16> units) {
        if units == null {
            throw "Utf16: null units"
        }
        _units = []
        Int index = 0
        while index < units.length() {
            _units.push(units.get(index))
            index = index + 1
        }
    }

    Int length() { return _units.length() }

    UInt16 get(Int index) {
        if index < 0 || index >= _units.length() {
            throw "Utf16.get: out of range"
        }
        return _units.get(index)
    }

    List<UInt16> units() {
        List<UInt16> result = []
        Int index = 0
        while index < _units.length() {
            result.push(_units.get(index))
            index = index + 1
        }
        return result
    }

    List<UInt16> toList() {
        return self.units()
    }

    static Utf16 fromString(String text) {
        List<UInt16> units = []
        Int index = 0
        while index < text.length() {
            units.push(text.charAt(index) as UInt16)
            index = index + 1
        }
        return new Utf16(units)
    }

    String toString() {
        String result = ""
        Int index = 0
        while index < _units.length() {
            result = result + str(_units.get(index) as Char)
            index = index + 1
        }
        return result
    }
}
```
