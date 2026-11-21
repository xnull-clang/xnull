# `Format`

| 项 | 值 |
| --- | --- |
| 类型 | `class Format` |
| 包 | `xdk.text` |
| 稳定性 | `stable` |
| 依赖 | `TextAlign` |

---

## 1. 定位

链式格式化构造器：把值转成文本，再按宽度/填充/对齐/大小写生成字符串。

不做：数字精度（用 `formatFloat/Double`）、locale、printf 全格式。

---

## 2. 设计逻辑

- 不可变；`width/pad/align/upper/lower` 返回新实例。
- `_align`：`TextAlign.Left`/`Right`/`Center`；默认左。
- `build` 先按对齐填充到 width，再应用大小写。
- 精度/千分位/locale 不在本类；避免 Format 变成 printf。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_text` | `String` | 已字符串化的值 |
| `_width` | `Int` | 目标宽度 ≥0 |
| `_pad` | `Char` | 填充字符 |
| `_align` | `TextAlign` | 对齐方式 |
| `_isUpper` | `Bool` | 是否转大写 |

不变量：width ≥0；align 是合法 `TextAlign`；不可变。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

构造器内部；公共入口是静态工厂。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

### 7.1 工厂

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `Format.int` | 整数 | `Int value` | `Format` | 无 |
| `Format.long` | Long | `Long value` | `Format` | 无 |
| `Format.float` | Float | `Double value` | `Format` | 无 |
| `Format.double` | Double | `Double value` | `Format` | 无 |
| `Format.bool` | 布尔 | `Bool value` | `Format` | 无 |
| `Format.char` | 字符 | `Char value` | `Format` | 无 |
| `Format.string` | 字符串 | `String value` | `Format` | null → panic |
| `Format.hex` | hex | `Long value` | `Format` | 无 |
| `Format.binary` | 二进制 | `Long value` | `Format` | 无 |

### 7.2 选项/构建

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `width` | 目标宽度 | `Int width` | `Format` | 负值 → panic |
| `pad` | 填充字符 | `Char padding` | `Format` | 无 |
| `align` | 设置对齐 | `TextAlign alignment` | `Format` | null → panic |
| `alignLeft` | 左对齐 | 无 | `Format` | 无 |
| `alignRight` | 右对齐 | 无 | `Format` | 无 |
| `alignCenter` | 居中 | 无 | `Format` | 无 |
| `upper` | 大写 | 无 | `Format` | 无 |
| `lower` | 小写 | 无 | `Format` | 无 |
| `zeroPad` | 0 填充右对齐 | 无 | `Format` | 无 |
| `build` | 生成 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 不可变链式构造；
- 字符填充；
- 对齐计算；
- 大小写变换。

---

## 9. 需要的支撑

- 语言：class、String、Char、Int、Long、Double、Bool、TextAlign；
- 运行时：字符串拼接；
- 接口：`TextAlign`、`toUpper`/`toLower`（Unicode）。

---

## 10. 依赖的特性/接口/类

`TextAlign`、`toUpper`、`toLower`。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`Format.int(7).width(4).pad('0').alignRight().build()` → `0007`。  
反例：负宽度；期望 Format 做精度/千分位；用 Format 做 locale 数字。

---

## 13. 测试/场景义务

工厂；左/右/中；填充；width 小于文本；upper/lower；zeroPad；build 独立性。

---

## 14. XNull 伪代码

```xnull
class Format {
    String _text
    Int _width
    Char _pad
    TextAlign _align
    Bool _isUpper

    Format(String text, Int width, Char padding, TextAlign align, Bool isUpper) {
        _text = text
        _width = width
        _pad = padding
        _align = align
        _isUpper = isUpper
    }

    static Format int(Int value) {
        return new Format(str(value), 0, ' ', TextAlign.Left, false)
    }

    static Format long(Long value) {
        return new Format(str(value), 0, ' ', TextAlign.Left, false)
    }

    static Format float(Double value) {
        return new Format(str(value), 0, ' ', TextAlign.Left, false)
    }

    static Format double(Double value) {
        return new Format(str(value), 0, ' ', TextAlign.Left, false)
    }

    static Format bool(Bool value) {
        if value {
            return new Format("true", 0, ' ', TextAlign.Left, false)
        }
        return new Format("false", 0, ' ', TextAlign.Left, false)
    }

    static Format char(Char value) {
        return new Format(str(value), 0, ' ', TextAlign.Left, false)
    }

    static Format string(String value) {
        if value == null {
            throw "Format.string: null"
        }
        return new Format(value, 0, ' ', TextAlign.Left, false)
    }

    static Format hex(Long value) {
        return new Format(formatHex(value), 0, ' ', TextAlign.Left, false)
    }

    static Format binary(Long value) {
        return new Format(formatBinary(value), 0, ' ', TextAlign.Left, false)
    }

    Format width(Int width) {
        if width < 0 {
            throw "Format.width: negative"
        }
        return new Format(_text, width, _pad, _align, _isUpper)
    }

    Format pad(Char padding) {
        return new Format(_text, _width, padding, _align, _isUpper)
    }

    Format align(TextAlign alignment) {
        if alignment == null {
            throw "Format.align: null"
        }
        return new Format(_text, _width, _pad, alignment, _isUpper)
    }

    Format alignLeft() {
        return self.align(TextAlign.Left)
    }

    Format alignRight() {
        return self.align(TextAlign.Right)
    }

    Format alignCenter() {
        return self.align(TextAlign.Center)
    }

    Format upper() {
        return new Format(_text, _width, _pad, _align, true)
    }

    Format lower() {
        return new Format(_text, _width, _pad, _align, false)
    }

    Format zeroPad() {
        return new Format(_text, _width, '0', TextAlign.Right, _isUpper)
    }

    String build() {
        String text = _text
        if text.length() < _width {
            Int missing = _width - text.length()
            Int left = 0
            Int right = 0
            if _align == TextAlign.Left {
                right = missing
            } else if _align == TextAlign.Right {
                left = missing
            } else {
                left = missing / 2
                right = missing - left
            }
            Int index = 0
            while index < left {
                text = str(_pad) + text
                index = index + 1
            }
            index = 0
            while index < right {
                text = text + str(_pad)
                index = index + 1
            }
        }
        if _isUpper {
            return toUpper(text)
        }
        return text
    }
}
```
