// Tier: T0；依赖：xdk.errors、xdk.bytes；稳定性：preview。
// xdk.text 完整实现（源码层过渡单元，仅 XNULL_XDK_SOURCE=1 编入）
//
// 与 src/xdk/text.x（默认构建面）同源；追加顶层工厂与 Utf16 包装。
// 默认构建不加载本单元，避免改变冻结 golden。
//
// 依赖：xdk.errors（错误值）；C 原语对应 src/runtime/rt_std_text.c
// （parse_int/parse_float/utf8_to_utf16/utf16_to_utf8/regex_match；解释器路径由等价源码执行）。
// 稳定性：@preview。
// 合同：可失败操作返回 Result；Regex 动态编译失败是可恢复错误，不 panic。
package xdk.text
import xdk.errors

// ---------- 格式化 builder ----------

// 顶层工厂（当前产品编译器尚不支持类静态方法调用；`Format.int(...)` 由 编译器修复）。
Format formatInt(Int value) {
    return new Format(str(value), 0, ' ')
}

Format formatFloat(Double value) {
    return new Format($"{value}", 0, ' ')
}

Format formatString(String value) {
    return new Format(value, 0, ' ')
}

Format formatBool(Bool value) {
    if value {
        return new Format("true", 0, ' ')
    }
    return new Format("false", 0, ' ')
}

// ---------- 解析 ----------

static Int digitOf(String character) {
    if character == "0" { return 0 }
    if character == "1" { return 1 }
    if character == "2" { return 2 }
    if character == "3" { return 3 }
    if character == "4" { return 4 }
    if character == "5" { return 5 }
    if character == "6" { return 6 }
    if character == "7" { return 7 }
    if character == "8" { return 8 }
    if character == "9" { return 9 }
    return -1
}

static Double digitOfD(String character) {
    if character == "0" { return 0.0 }
    if character == "1" { return 1.0 }
    if character == "2" { return 2.0 }
    if character == "3" { return 3.0 }
    if character == "4" { return 4.0 }
    if character == "5" { return 5.0 }
    if character == "6" { return 6.0 }
    if character == "7" { return 7.0 }
    if character == "8" { return 8.0 }
    if character == "9" { return 9.0 }
    return -1.0
}

static Error textErr(String message) {
    BasicError be = new BasicError(ErrorKind.InvalidArgument, message)
    return be
}

// parseInt：全串消费、十进制、可选正负号；溢出/非法返回 Err。
Result<Int, Error> parseInt(String text) {
    Int length = text.length()
    if length == 0 { return Err(textErr("parseInt: 空串")) }
    Int index = 0
    Bool negative = false
    if text.substring(0, 1) == "-" { negative = true; index = 1 }
    else if text.substring(0, 1) == "+" { index = 1 }
    if index >= length { return Err(textErr("parseInt: 缺少数字")) }
    Int value = 0
    Bool any = false
    while index < length {
        Int digit = digitOf(text.substring(index, 1))
        if digit < 0 { return Err(textErr("parseInt: 非法字符")) }
        any = true
        Int limit = 214748364
        if value > limit { return Err(textErr("parseInt: 溢出")) }
        value = value * 10 + digit
        if !negative && value < 0 { return Err(textErr("parseInt: 溢出")) }
        index = index + 1
    }
    if !any { return Err(textErr("parseInt: 缺少数字")) }
    if negative { return Ok(0 - value) }
    return Ok(value)
}

// parseFloat：十进制整数/小数/指数，全串消费；非法或溢出返回 Err。
Result<Double, Error> parseFloat(String text) {
    Int length = text.length()
    if length == 0 { return Err(textErr("parseFloat: 空串")) }
    Int index = 0
    Bool negative = false
    if text.substring(0, 1) == "-" { negative = true; index = 1 }
    else if text.substring(0, 1) == "+" { index = 1 }
    Double value = 0.0
    Bool any = false
    while index < length {
        String character = text.substring(index, 1)
        if character == "." { break }
        if character == "e" || character == "E" { break }
        Double digit = digitOfD(character)
        if digit < 0.0 { return Err(textErr("parseFloat: 非法字符")) }
        value = value * 10.0 + digit
        any = true
        index = index + 1
    }
    if index < length && text.substring(index, 1) == "." {
        index = index + 1
        Double scale = 0.1
        while index < length {
            String character = text.substring(index, 1)
            if character == "e" || character == "E" { break }
            Double digit = digitOfD(character)
            if digit < 0.0 { return Err(textErr("parseFloat: 非法小数")) }
            value = value + digit * scale
            scale = scale * 0.1
            any = true
            index = index + 1
        }
    }
    if !any { return Err(textErr("parseFloat: 缺少数字")) }
    if index < length && (text.substring(index, 1) == "e" || text.substring(index, 1) == "E") {
        index = index + 1
        Bool exponentNegative = false
        if index < length && text.substring(index, 1) == "-" { exponentNegative = true; index = index + 1 }
        else if index < length && text.substring(index, 1) == "+" { index = index + 1 }
        if index >= length { return Err(textErr("parseFloat: 指数缺少数字")) }
        Int exponent = 0
        while index < length {
            Int digit = digitOf(text.substring(index, 1))
            if digit < 0 { return Err(textErr("parseFloat: 非法指数")) }
            exponent = exponent * 10 + digit
            index = index + 1
        }
        Int step = 0
        while step < exponent {
            if exponentNegative { value = value / 10.0 } else { value = value * 10.0 }
            step = step + 1
        }
    }
    if index != length { return Err(textErr("parseFloat: 未消费完整字符串")) }
    if negative { return Ok(0.0 - value) }
    return Ok(value)
}

// ---------- UTF-8 ↔ UTF-16 ----------

// UTF-8 续字节判定（0x80..0xBF）。
static Bool isContinuationByte(Int value) {
    return (value & 0xC0) == 0x80
}

// 把一个码点追加为 UTF-16 码元；BMP 外字符写成代理对。
static Void appendUtf16(List<UInt16> units, Int codePoint) {
    if codePoint < 0x10000 {
        units.push(codePoint)
        return
    }
    Int offset = codePoint - 0x10000
    units.push((0xD800 + (offset >> 10)) as Int)
    units.push((0xDC00 + (offset & 0x3FF)) as Int)
}

// utf8ToUtf16：把 UTF-8 字节解码为 UTF-16 码元序列；非法 UTF-8 单字节替换为 U+FFFD。
Result<Utf16, Error> utf8ToUtf16(Bytes source) {
    List<UInt16> units = []
    String text = source.toString()
    Int index = 0
    while index < text.length() {
        Int codePoint = decodeCodePoint(text, index)
        if codePoint < 0 {
            codePoint = 0xFFFD
            index = index + 1
        } else {
            index = index + codePointLen(text, index)
        }
        appendUtf16(units, codePoint)
    }
    return Ok(new Utf16(units))
}

// utf16ToUtf8：把 UTF-16 码元编码为 UTF-8 字节；代理对按 BMP 外字符处理，孤立代理返回 DataCorrupted。
Result<Bytes, Error> utf16ToUtf8(List<UInt16> units) {
    Bytes result = Bytes.fromString("")
    Int index = 0
    while index < units.length() {
        UInt16 unit = units.get(index)
        if unit < 0x80 {
            result.push(unit as Int)
            index = index + 1
        } else if unit < 0x800 {
            result.push((0xC0 | (unit >> 6)) as Int)
            result.push((0x80 | (unit & 0x3F)) as Int)
            index = index + 1
        } else if unit >= 0xD800 && unit <= 0xDBFF {
            if index + 1 >= units.length() {
                return Err(textErr("utf16ToUtf8: 孤立的高代理"))
            }
            UInt16 low = units.get(index + 1)
            if low < 0xDC00 || low > 0xDFFF {
                return Err(textErr("utf16ToUtf8: 高代理后缺低代理"))
            }
            Int codePoint = 0x10000 + (((unit as Int) - 0xD800) << 10) + ((low as Int) - 0xDC00)
            result.push((0xF0 | (codePoint >> 18)) as Int)
            result.push((0x80 | ((codePoint >> 12) & 0x3F)) as Int)
            result.push((0x80 | ((codePoint >> 6) & 0x3F)) as Int)
            result.push((0x80 | (codePoint & 0x3F)) as Int)
            index = index + 2
        } else if unit >= 0xDC00 && unit <= 0xDFFF {
            return Err(textErr("utf16ToUtf8: 孤立的低代理"))
        } else {
            result.push((0xE0 | (unit >> 12)) as Int)
            result.push((0x80 | ((unit >> 6) & 0x3F)) as Int)
            result.push((0x80 | (unit & 0x3F)) as Int)
            index = index + 1
        }
    }
    return Ok(result)
}

// utf16ToText：UTF-16 码元序列 → UTF-8 字符串；孤立代理返回 DataCorrupted。
Result<String, Error> utf16ToText(Utf16 source) {
    Result<Bytes, Error> encoded = utf16ToUtf8(source.units)
    if encoded.isErr() {
        return Err(encoded.error())
    }
    return Ok(encoded.value().toString())
}

// textToUtf16：UTF-8 字符串 → UTF-16 码元序列；非法 UTF-8 单字节替换为 U+FFFD。
Utf16 textToUtf16(String text) {
    Result<Utf16, Error> converted = utf8ToUtf16(Bytes.fromString(text))
    return converted.value()
}

// ---------- Regex（回溯引擎：字面量、.、* + ?、[] 类、分组捕获、| 、转义、^ $）----------
//
// AST 用扁平数组表示（避免自引用类）：seq/alt/group 的孩子为连续下标区间；
// 量词节点持单孩子与 min/max；类节点持区间/singles 与取反标志。
// 匹配器为递归回溯；分支失败时快照/恢复分组捕获栈。
// 约定：^/$ 为锚（字面量需转义）；{m,n} 量词与命名组暂不支持。

// 字节 → 单字节字符串（0..255）。
String stringOfByte(Int value) {
    Bytes buffer = Bytes.fromString("")
    buffer.push(value)
    return buffer.toString()
}

// 码点 → UTF-8 字符串；非法码点返回替换符（U+FFFD）。
String stringOfCodePoint(Int codePoint) {
    return fromCodePoint(codePoint)
}

// 类节点按码点匹配（字符类范围为码点，ASCII 之外同样可用）。
Bool regexClassMatch(RegexTree tree, Int nodeIndex, Int codePoint) {
    Int classStart = tree.clsStart.get(nodeIndex)
    Int classCount = tree.clsCount.get(nodeIndex)
    Bool hit = false
    Int index = 0
    while index < classCount {
        Int entry = classStart + index
        Int single = tree.singles.get(entry)
        if single >= 0 {
            if single == codePoint {
                hit = true
            }
        } else {
            if codePoint >= tree.lo.get(entry) && codePoint <= tree.hi.get(entry) {
                hit = true
            }
        }
        index = index + 1
    }
    if tree.negated.get(nodeIndex) == 1 {
        return !hit
    }
    return hit
}

// 顶层工厂（静态方法调用待 当前编译器修复）。
Result<Regex, Error> regexCompile(String pattern) {
    RegexParser p = new RegexParser(pattern)
    if p.pattern.length() > 0 && p.pattern.get(0) == 94 {
        p.anchored = true
        p.pos = 1
    }
    Result<Int, Error> root = p.parseAlt()
    if root.isErr() {
        Error rerr = root.error()
        return Err(rerr)
    }
    if p.pos != p.pattern.length() {
        return Err(textErr("regexCompile: 存在未消费字符"))
    }
    Regex rx = new Regex(pattern)
    rx.t = p.t
    rx.groupCount = p.groupCount
    rx.anchored = p.anchored
    rx.root = root.value()
    return Ok(rx)
}

// ---------- 旧种子辅助（保留兼容）----------

String repeatText(String text, Int repetitions) {
    if repetitions <= 0 { return "" }
    return text + repeatText(text, repetitions - 1)
}

String repeatJoined(String text, String separator, Int repetitions) {
    if repetitions <= 0 { return "" }
    if repetitions == 1 { return text }
    return text + separator + repeatJoined(text, separator, repetitions - 1)
}

Bool isPositive(Int value) {
    return value > 0
}

// ---------- Strings 工具（S6 §4.1 扩展面）----------

Bool contains(String text, String searchText) {
    return text.indexOf(searchText) >= 0
}

// compareText：按 UTF-8 字节字典序比较；left < right 返回负数，相等返回 0，
// left > right 返回正数。String 不支持 < > 运算符（S1 §2.8），排序用本函数。
Int compareText(String left, String right) {
    Int n = left.length()
    if right.length() < n {
        n = right.length()
    }
    Int i = 0
    while i < n {
        Int a = left.get(i)
        Int b = right.get(i)
        if a < b {
            return -1
        }
        if a > b {
            return 1
        }
        i = i + 1
    }
    if left.length() < right.length() {
        return -1
    }
    if left.length() > right.length() {
        return 1
    }
    return 0
}

Int count(String text, String searchText) {
    if searchText.length() == 0 {
        return 0
    }
    Int total = 0
    Int index = 0
    while index + searchText.length() <= text.length() {
        if text.substring(index, searchText.length()) == searchText {
            total = total + 1
            index = index + searchText.length()
            continue
        }
        index = index + 1
    }
    return total
}

String repeat(String text, Int repetitions) {
    String result = ""
    Int index = 0
    while index < repetitions {
        result = result + text
        index = index + 1
    }
    return result
}

String padLeft(String text, Int width, String padding) {
    String result = text
    while result.length() < width {
        result = padding + result
    }
    return result
}

String padRight(String text, Int width, String padding) {
    String result = text
    while result.length() < width {
        result = result + padding
    }
    return result
}

String reverse(String text) {
    Bytes buffer = Bytes.fromString("")
    Int index = text.length() - 1
    while index >= 0 {
        buffer.push(text.get(index))
        index = index - 1
    }
    return buffer.toString()
}

Bool isEmpty(String text) {
    return text.length() == 0
}

Bool isBlank(String text) {
    String trimmed = text.trim()
    return trimmed.length() == 0
}

Bool equalsIgnoreCase(String left, String right) {
    return left.toUpper() == right.toUpper()
}

String capitalize(String text) {
    if text.length() == 0 {
        return text
    }
    return text.substring(0, 1).toUpper() + text.substring(1, text.length() - 1)
}

String truncate(String text, Int maximumLength) {
    if text.length() <= maximumLength {
        return text
    }
    return text.substring(0, maximumLength) + "..."
}

Int levenshtein(String left, String right) {
    Int leftLength = left.length()
    Int rightLength = right.length()
    List<Int> previous = []
    Int column = 0
    while column <= rightLength {
        previous.push(column)
        column = column + 1
    }
    Int row = 1
    while row <= leftLength {
        List<Int> current = []
        current.push(row)
        column = 1
        while column <= rightLength {
            Int cost = left.get(row - 1) == right.get(column - 1) ? 0 : 1
            Int deletion = previous.get(column) + 1
            Int insertion = current.get(column - 1) + 1
            Int substitution = previous.get(column - 1) + cost
            Int best = deletion
            if insertion < best {
                best = insertion
            }
            if substitution < best {
                best = substitution
            }
            current.push(best)
            column = column + 1
        }
        previous = current
        row = row + 1
    }
    return previous.get(rightLength)
}

// ---------- Char 分类（单字符 String 语义）----------

Bool isDigit(String character) {
    if character.length() != 1 {
        return false
    }
    Int value = character.get(0)
    return value >= 48 && value <= 57
}

Bool isAlpha(String character) {
    if character.length() != 1 {
        return false
    }
    Int value = character.get(0)
    return (value >= 65 && value <= 90) || (value >= 97 && value <= 122)
}

Bool isAlnum(String character) {
    return isAlpha(character) || isDigit(character)
}

Bool isSpace(String character) {
    if character.length() != 1 {
        return false
    }
    Int value = character.get(0)
    return value == 32 || value == 9 || value == 10 || value == 13 || value == 11 || value == 12
}

Bool isUpper(String character) {
    if character.length() != 1 {
        return false
    }
    Int value = character.get(0)
    return value >= 65 && value <= 90
}

Bool isLower(String character) {
    if character.length() != 1 {
        return false
    }
    Int value = character.get(0)
    return value >= 97 && value <= 122
}

Bool isHexDigit(String character) {
    if character.length() != 1 {
        return false
    }
    Int value = character.get(0)
    return (value >= 48 && value <= 57) || (value >= 97 && value <= 102) || (value >= 65 && value <= 70)
}

// ---------- CodePoint（UTF-8）----------

// 从 UTF-8 字节串的 byteIndex 处解码一个码点；非法序列返回 -1。
// 拒绝过长编码、代理区码点和超出 U+10FFFF 的码点。
Int decodeCodePoint(String text, Int byteIndex) {
    Int length = text.length()
    if byteIndex < 0 || byteIndex >= length {
        return -1
    }
    Int first = text.get(byteIndex)
    if first < 0x80 {
        return first
    }
    if first >= 0xC2 && first <= 0xDF {
        if byteIndex + 1 >= length {
            return -1
        }
        Int second = text.get(byteIndex + 1)
        if !isContinuationByte(second) {
            return -1
        }
        return ((first & 0x1F) << 6) | (second & 0x3F)
    }
    if first >= 0xE0 && first <= 0xEF {
        if byteIndex + 2 >= length {
            return -1
        }
        Int second = text.get(byteIndex + 1)
        Int third = text.get(byteIndex + 2)
        if !isContinuationByte(second) || !isContinuationByte(third) {
            return -1
        }
        if first == 0xE0 && second < 0xA0 {
            return -1
        }
        if first == 0xED && second > 0x9F {
            return -1
        }
        return ((first & 0x0F) << 12) | ((second & 0x3F) << 6) | (third & 0x3F)
    }
    if first >= 0xF0 && first <= 0xF4 {
        if byteIndex + 3 >= length {
            return -1
        }
        Int second = text.get(byteIndex + 1)
        Int third = text.get(byteIndex + 2)
        Int fourth = text.get(byteIndex + 3)
        if !isContinuationByte(second) || !isContinuationByte(third) || !isContinuationByte(fourth) {
            return -1
        }
        if first == 0xF0 && second < 0x90 {
            return -1
        }
        if first == 0xF4 && second > 0x8F {
            return -1
        }
        return ((first & 0x07) << 18) | ((second & 0x3F) << 12) | ((third & 0x3F) << 6) | (fourth & 0x3F)
    }
    return -1
}

// byteIndex 处合法 UTF-8 序列的长度；非法返回 -1。
Int codePointLen(String text, Int byteIndex) {
    if byteIndex < 0 || byteIndex >= text.length() {
        return -1
    }
    if decodeCodePoint(text, byteIndex) < 0 {
        return -1
    }
    Int first = text.get(byteIndex)
    if first < 0x80 {
        return 1
    }
    if first < 0xE0 {
        return 2
    }
    if first < 0xF0 {
        return 3
    }
    return 4
}

// 文本的码点序列；非法 UTF-8 单字节替换为 U+FFFD。
List<Int> codePoints(String text) {
    List<Int> result = []
    Int byteIndex = 0
    while byteIndex < text.length() {
        Int codePoint = decodeCodePoint(text, byteIndex)
        if codePoint < 0 {
            result.push(0xFFFD)
            byteIndex = byteIndex + 1
            continue
        }
        result.push(codePoint)
        byteIndex = byteIndex + codePointLen(text, byteIndex)
    }
    return result
}

// 文本的码点数量；非法 UTF-8 单字节按一个替换符计数。
Int codePointCount(String text) {
    return codePoints(text).length()
}

// 码点 → UTF-8 String；越界或代理区码点返回替换符（U+FFFD）。
String fromCodePoint(Int codePoint) {
    Bytes buffer = Bytes.fromString("")
    if codePoint < 0 || codePoint > 0x10FFFF || (codePoint >= 0xD800 && codePoint <= 0xDFFF) {
        codePoint = 0xFFFD
    }
    if codePoint < 0x80 {
        buffer.push(codePoint)
        return buffer.toString()
    }
    if codePoint < 0x800 {
        buffer.push(0xC0 | (codePoint >> 6))
        buffer.push(0x80 | (codePoint & 0x3F))
        return buffer.toString()
    }
    if codePoint < 0x10000 {
        buffer.push(0xE0 | (codePoint >> 12))
        buffer.push(0x80 | ((codePoint >> 6) & 0x3F))
        buffer.push(0x80 | (codePoint & 0x3F))
        return buffer.toString()
    }
    buffer.push(0xF0 | (codePoint >> 18))
    buffer.push(0x80 | ((codePoint >> 12) & 0x3F))
    buffer.push(0x80 | ((codePoint >> 6) & 0x3F))
    buffer.push(0x80 | (codePoint & 0x3F))
    return buffer.toString()
}

// 第 byteIndex 字节处的码点；非法返回 -1。
Int codePointAt(String text, Int byteIndex) {
    return decodeCodePoint(text, byteIndex)
}
