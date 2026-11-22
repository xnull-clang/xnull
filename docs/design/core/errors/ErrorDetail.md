# `ErrorDetail`

> 注解合同（A8，implemented；限制见 S3 §5.7）：`@Value` 生成 `equals`/`toString`/`copy`（不生成 `hash`）；字段保持 `final`；引用字段按值语义比较。实现由处理器生成，不手写；实现时删除同名手写成员，避免生成冲突；伪代码中的 `equals`/`toString`/`copy` 只描述生成物行为，不是手写实现。

## 1. 定位

不可变 key/value 诊断细节；用于路径、字段名、请求 ID、配置键。

### 2. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_key` | `String` | final | 非空；`[a-z0-9_.-]` |
| `_value` | `String` | final | 可为空；无换行/制表/NUL |

不变量：key 合法；value 无控制字符；不可变；可共享。

### 3. 使用的技术

- 不可变值对象；
- 字符级校验；
- key/value 比较。

### 4. 需要的支撑

- 语言：class、final 字段、String、Int、Bool；
- 运行时：无；
- 接口：内部辅助 `isLowerAsciiLetter`、`isAsciiDigit`（字符校验）；
- 伪代码中的 `toLowerAscii` 用于 `errorKindFromName`，属于本包内部辅助。

### 5. 依赖的特性/接口/类

无公共类型依赖；只依赖 String/Int 等语言原语和本包内部字符辅助函数。

### 6. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `ErrorDetail(key,value)` | 构造 | key/value | `ErrorDetail` | 非法 → panic |
| `key()` | 读 key | 无 | `String` | 无 |
| `value()` | 读 value | 无 | `String` | 无 |
| `withValue(value)` | 派生 | 新 value | `ErrorDetail` | 非法 → panic |
| `describe()` | `key=value` | 无 | `String` | 无 |
| `equals(other)` | 值相等 | other | `Bool` | 无 |
| `compare(other)` | 排序 | other | `Int` | 无 |
| `toString()` | 文本 | 无 | `String` | 无 |

### 7. XNull 伪代码

```xnull
@Value
class ErrorDetail {
    final String _key
    final String _value

    ErrorDetail(String key, String value) {
        if !isValidDetailKey(key) {
            throw "ErrorDetail: invalid key"
        }
        if !isValidDetailValue(value) {
            throw "ErrorDetail: invalid value"
        }
        _key = key
        _value = value
    }

    String key() { return _key }
    String value() { return _value }

    ErrorDetail withValue(String value) {
        if !isValidDetailValue(value) {
            throw "ErrorDetail.withValue: invalid value"
        }
        return new ErrorDetail(_key, value)
    }

    String describe() {
        return _key + "=" + _value
    }

    Bool equals(ErrorDetail other) {
        if other == null {
            return false
        }
        return _key == other._key && _value == other._value
    }

    Int compare(ErrorDetail other) {
        if _key < other._key { return -1 }
        if _key > other._key { return 1 }
        if _value < other._value { return -1 }
        if _value > other._value { return 1 }
        return 0
    }

    String toString() {
        return self.describe()
    }
}

Bool isValidDetailKey(String key) {
    if key == "" {
        return false
    }
    Int index = 0
    while index < key.length() {
        String character = key.substring(index, 1)
        if !isLowerAsciiLetter(character)
            && !isAsciiDigit(character)
            && character != "_"
            && character != "."
            && character != "-" {
            return false
        }
        index = index + 1
    }
    return true
}

Bool isValidDetailValue(String value) {
    if value.indexOf("\n") >= 0 { return false }
    if value.indexOf("\r") >= 0 { return false }
    if value.indexOf("\t") >= 0 { return false }
    return true
}

Bool isLowerAsciiLetter(String character) {
    return character == "a" || character == "b" || character == "c"
        || character == "d" || character == "e" || character == "f"
        || character == "g" || character == "h" || character == "i"
        || character == "j" || character == "k" || character == "l"
        || character == "m" || character == "n" || character == "o"
        || character == "p" || character == "q" || character == "r"
        || character == "s" || character == "t" || character == "u"
        || character == "v" || character == "w" || character == "x"
        || character == "y" || character == "z"
}

Bool isAsciiDigit(String character) {
    return character == "0" || character == "1" || character == "2"
        || character == "3" || character == "4" || character == "5"
        || character == "6" || character == "7" || character == "8"
        || character == "9"
}

String toLowerAscii(String text) {
    String result = ""
    Int index = 0
    while index < text.length() {
        String character = text.substring(index, 1)
        if character == "A" { result = result + "a" }
        else if character == "B" { result = result + "b" }
        else if character == "C" { result = result + "c" }
        else if character == "D" { result = result + "d" }
        else if character == "E" { result = result + "e" }
        else if character == "F" { result = result + "f" }
        else if character == "G" { result = result + "g" }
        else if character == "H" { result = result + "h" }
        else if character == "I" { result = result + "i" }
        else if character == "J" { result = result + "j" }
        else if character == "K" { result = result + "k" }
        else if character == "L" { result = result + "l" }
        else if character == "M" { result = result + "m" }
        else if character == "N" { result = result + "n" }
        else if character == "O" { result = result + "o" }
        else if character == "P" { result = result + "p" }
        else if character == "Q" { result = result + "q" }
        else if character == "R" { result = result + "r" }
        else if character == "S" { result = result + "s" }
        else if character == "T" { result = result + "t" }
        else if character == "U" { result = result + "u" }
        else if character == "V" { result = result + "v" }
        else if character == "W" { result = result + "w" }
        else if character == "X" { result = result + "x" }
        else if character == "Y" { result = result + "y" }
        else if character == "Z" { result = result + "z" }
        else { result = result + character }
        index = index + 1
    }
    return result
}
```

---
