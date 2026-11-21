// xdk.text 完整实现（源码层过渡单元，仅 XNULL_XDK_SOURCE=1 编入）
//
// printf 风格格式化：%[flags][width][.precision]conversion。
// 支持 d/i/x/X/o/f/e/E/g/G/s/c/b/%%；flags 为 - + 空格 0 #；不支持 * 和长度修饰符。
// 参数按类型显式包装（FormatArgument），失败返回 InvalidArgument，不 panic。
package xdk.text
import xdk.errors

static Error printfError(String message) {
    BasicError error = new BasicError(ErrorKind.InvalidArgument, message)
    return error
}

static Bool printfIsDigit(Int value) {
    return value >= 48 && value <= 57
}

static Int digitValue(Int value) {
    if value >= 48 && value <= 57 { return value - 48 }
    if value >= 97 && value <= 102 { return value - 87 }
    if value >= 65 && value <= 70 { return value - 55 }
    return -1
}

static String repeatUnit(String unitText, Int count) {
    String result = ""
    Int index = 0
    while index < count {
        result = result + unitText
        index = index + 1
    }
    return result
}

static String incrementDigits(String digits) {
    String result = ""
    Int carry = 1
    Int index = digits.length() - 1
    while index >= 0 {
        Int value = digitValue(digits.get(index)) + carry
        if value >= 10 {
            value = 0
            carry = 1
        } else {
            carry = 0
        }
        result = str(value) + result
        index = index - 1
    }
    if carry > 0 {
        result = "1" + result
    }
    return result
}

static String digitsFor(Long value, Int base, Bool isUpper) {
    String lowerDigits = "0123456789abcdef"
    String upperDigits = "0123456789ABCDEF"
    String table = lowerDigits
    if isUpper {
        table = upperDigits
    }
    if value == 0 {
        return "0"
    }
    Long current = value
    String result = ""
    Long baseValue = base as Long
    while current > 0 {
        Int digit = (current % baseValue) as Int
        result = table.substring(digit, 1) + result
        current = current / baseValue
    }
    return result
}

class FormatArgument {
    final Int kind
    final Long integerValue
    final Double floatValue
    final String textValue
    final Bool boolValue

    FormatArgument(Int kind, Long integerValue, Double floatValue, String textValue, Bool boolValue) {
        self.kind = kind
        self.integerValue = integerValue
        self.floatValue = floatValue
        self.textValue = textValue
        self.boolValue = boolValue
    }

    static FormatArgument ofInt(Int value) {
        return new FormatArgument(0, value as Long, 0.0, "", false)
    }

    static FormatArgument ofLong(Long value) {
        return new FormatArgument(1, value, 0.0, "", false)
    }

    static FormatArgument ofFloat(Double value) {
        return new FormatArgument(2, 0, value, "", false)
    }

    static FormatArgument ofText(String value) {
        return new FormatArgument(3, 0, 0.0, value, false)
    }

    static FormatArgument ofBool(Bool value) {
        return new FormatArgument(4, 0, 0.0, "", value)
    }

    static FormatArgument ofChar(Char value) {
        return new FormatArgument(5, 0, 0.0, $"{value}", false)
    }
}

static String padFormatted(String sign, String prefix, String body, Int width, Bool zeroPad, Bool leftAlign) {
    String result = sign + prefix + body
    if result.length() >= width {
        return result
    }
    Int missing = width - result.length()
    if leftAlign {
        return result + repeatUnit(" ", missing)
    }
    if zeroPad {
        return sign + prefix + repeatUnit("0", missing) + body
    }
    return repeatUnit(" ", missing) + result
}

static String takeCodePoints(String text, Int maximumCount) {
    String result = ""
    Int index = 0
    Int count = 0
    while index < text.length() && count < maximumCount {
        Int length = codePointLen(text, index)
        if length < 0 {
            length = 1
        }
        result = result + text.substring(index, length)
        index = index + length
        count = count + 1
    }
    return result
}

static Result<String, Error> renderInteger(FormatArgument argument, String conversion, Bool leftAlign,
    Bool plusSign, Bool spaceSign, Bool zeroPad, Bool alternate, Bool hasPrecision, Int precision, Int width) {
    Long value = argument.integerValue
    Bool negative = value < 0
    Int base = 10
    Bool isUpper = false
    Bool signedConversion = false
    if conversion == "d" || conversion == "i" {
        signedConversion = true
    } else if conversion == "x" {
        base = 16
    } else if conversion == "X" {
        base = 16
        isUpper = true
    } else if conversion == "o" {
        base = 8
    } else {
        return Err(printfError("printf: 整数转换不支持 " + conversion))
    }
    String body = ""
    if signedConversion {
        if negative {
            body = $"{value}"
            body = body.substring(1, body.length() - 1)
        } else {
            body = $"{value}"
        }
    } else {
        if negative {
            return Err(printfError("printf: x/o 只接受非负整数"))
        }
        body = digitsFor(value, base, isUpper)
    }
    if hasPrecision {
        while body.length() < precision {
            body = "0" + body
        }
        if precision == 0 && body == "0" {
            body = ""
        }
    }
    String prefix = ""
    if alternate {
        if base == 16 && body != "" {
            if isUpper {
                prefix = "0X"
            } else {
                prefix = "0x"
            }
        } else if base == 8 && (body == "" || body.substring(0, 1) != "0") {
            prefix = "0"
        }
    }
    String sign = ""
    if negative && signedConversion {
        sign = "-"
    } else if plusSign && signedConversion {
        sign = "+"
    } else if spaceSign && signedConversion {
        sign = " "
    }
    return Ok(padFormatted(sign, prefix, body, width, zeroPad, leftAlign))
}

static String floatScientificDigits(Double value, Int precision, Bool isUpper, Bool alternate) {
    String raw = $"{value}"
    if raw == "nan" || raw == "inf" || raw == "infinity" {
        return raw
    }
    Int exponentIndex = raw.indexOf("e")
    if exponentIndex < 0 {
        exponentIndex = raw.indexOf("E")
    }
    String mantissa = raw
    Int exponent = 0
    if exponentIndex >= 0 {
        mantissa = raw.substring(0, exponentIndex)
        String exponentText = raw.substring(exponentIndex + 1, raw.length() - exponentIndex - 1)
        Result<Int, Error> parsed = parseInt(exponentText)
        if parsed.isOk() {
            exponent = parsed.value()
        }
    }
    Int pointIndex = mantissa.indexOf(".")
    String digits = mantissa
    if pointIndex >= 0 {
        digits = mantissa.substring(0, pointIndex) + mantissa.substring(pointIndex + 1, mantissa.length() - pointIndex - 1)
    } else {
        pointIndex = mantissa.length()
    }
    Int firstNonZero = 0
    while firstNonZero < digits.length() && digits.get(firstNonZero) == 48 {
        firstNonZero = firstNonZero + 1
    }
    if firstNonZero >= digits.length() {
        String zero = "0"
        if precision > 0 {
            zero = zero + "." + repeatUnit("0", precision)
        }
        return zero
    }
    Int scientificExponent = exponent + pointIndex - firstNonZero - 1
    String significant = digits.substring(firstNonZero, digits.length() - firstNonZero)
    Int keep = precision + 1
    if significant.length() > keep {
        Bool roundUp = shouldRoundUp(significant.substring(keep, 1))
        significant = significant.substring(0, keep)
        if roundUp {
            significant = incrementDigits(significant)
            if significant.length() > keep {
                significant = significant.substring(0, keep)
                scientificExponent = scientificExponent + 1
            }
        }
    }
    while significant.length() < keep {
        significant = significant + "0"
    }
    String result = significant.substring(0, 1)
    if precision > 0 {
        result = result + "." + significant.substring(1, keep - 1)
    } else if alternate {
        result = result + "."
    }
    String marker = "e"
    if isUpper {
        marker = "E"
    }
    String exponentSign = "+"
    Int shownExponent = scientificExponent
    if shownExponent < 0 {
        exponentSign = "-"
        shownExponent = 0 - shownExponent
    }
    String exponentDigits = str(shownExponent)
    while exponentDigits.length() < 2 {
        exponentDigits = "0" + exponentDigits
    }
    return result + marker + exponentSign + exponentDigits
}

static Bool shouldRoundUp(String digit) {
    if digit.length() == 0 {
        return false
    }
    return digit.get(0) >= 53
}

static String trimFractionZeros(String text) {
    Int point = text.indexOf(".")
    if point < 0 {
        return text
    }
    Int end = text.length()
    while end > point + 1 && text.get(end - 1) == 48 {
        end = end - 1
    }
    if end == point + 1 {
        end = point
    }
    return text.substring(0, end)
}

static String floatFixedDigits(Double value, Int precision) {
    String raw = $"{value}"
    if raw == "nan" || raw == "inf" || raw == "infinity" {
        return raw
    }
    Int exponentIndex = raw.indexOf("e")
    if exponentIndex < 0 {
        exponentIndex = raw.indexOf("E")
    }
    String mantissa = raw
    Int exponent = 0
    if exponentIndex >= 0 {
        mantissa = raw.substring(0, exponentIndex)
        String exponentText = raw.substring(exponentIndex + 1, raw.length() - exponentIndex - 1)
        Result<Int, Error> parsed = parseInt(exponentText)
        if parsed.isOk() {
            exponent = parsed.value()
        }
    }
    Int pointIndex = mantissa.indexOf(".")
    String digits = mantissa
    if pointIndex >= 0 {
        digits = mantissa.substring(0, pointIndex) + mantissa.substring(pointIndex + 1, mantissa.length() - pointIndex - 1)
    } else {
        pointIndex = mantissa.length()
    }
    Int scale = exponent - (digits.length() - pointIndex)
    String integerPart = ""
    String fractionPart = ""
    if scale >= 0 {
        integerPart = digits + repeatUnit("0", scale)
    } else {
        Int cut = digits.length() + scale
        if cut > 0 {
            integerPart = digits.substring(0, cut)
            fractionPart = digits.substring(cut, digits.length() - cut)
        } else {
            integerPart = "0"
            fractionPart = repeatUnit("0", 0 - cut) + digits
        }
    }
    if precision == 0 {
        if fractionPart.length() > 0 && shouldRoundUp(fractionPart.substring(0, 1)) {
            integerPart = incrementDigits(integerPart)
        }
        return integerPart
    }
    String combined = integerPart + fractionPart
    while combined.length() < integerPart.length() + precision {
        combined = combined + "0"
    }
    if fractionPart.length() > precision {
        Bool roundUp = shouldRoundUp(combined.substring(integerPart.length() + precision, 1))
        combined = combined.substring(0, integerPart.length() + precision)
        if roundUp {
            combined = incrementDigits(combined)
        }
    }
    Int point = combined.length() - precision
    return combined.substring(0, point) + "." + combined.substring(point, combined.length() - point)
}

static String floatDigits(Double value, String conversion, Int precision, Bool alternate) {
    if conversion == "e" || conversion == "E" {
        return floatScientificDigits(value, precision, conversion == "E", alternate)
    }
    if conversion == "g" || conversion == "G" {
        String raw = $"{value}"
        Int marker = raw.indexOf("e")
        if marker < 0 {
            marker = raw.indexOf("E")
        }
        String mantissa = raw
        Int exponent = 0
        if marker >= 0 {
            mantissa = raw.substring(0, marker)
            Result<Int, Error> parsed = parseInt(raw.substring(marker + 1, raw.length() - marker - 1))
            if parsed.isOk() {
                exponent = parsed.value()
            }
        }
        Int point = mantissa.indexOf(".")
        Int integerDigits = mantissa.length()
        if point >= 0 {
            integerDigits = point
        }
        Int valueExponent = exponent + integerDigits - 1
        if valueExponent < -4 || valueExponent >= precision {
            String scientific = floatScientificDigits(value, precision - 1, conversion == "G", alternate)
            if alternate {
                return scientific
            }
            return trimFractionZeros(scientific)
        }
        String fixed = floatFixedDigits(value, precision - 1 - valueExponent)
        if alternate {
            return fixed
        }
        return trimFractionZeros(fixed)
    }
    return floatFixedDigits(value, precision)
}

static Result<String, Error> renderFloat(FormatArgument argument, String conversion, Bool leftAlign,
    Bool plusSign, Bool spaceSign, Bool zeroPad, Bool alternate, Bool hasPrecision, Int precision, Int width) {
    if conversion != "f" && conversion != "e" && conversion != "E" &&
        conversion != "g" && conversion != "G" {
        return Err(printfError("printf: 浮点转换不支持 " + conversion))
    }
    Int effectivePrecision = 6
    if hasPrecision {
        effectivePrecision = precision
    }
    if (conversion == "g" || conversion == "G") && effectivePrecision == 0 {
        effectivePrecision = 1
    }
    Double value = argument.floatValue
    Bool negative = value < 0.0
    Double magnitude = value
    if negative {
        magnitude = 0.0 - magnitude
    }
    String body = floatDigits(magnitude, conversion, effectivePrecision, alternate)
    String sign = ""
    if negative {
        sign = "-"
    } else if plusSign {
        sign = "+"
    } else if spaceSign {
        sign = " "
    }
    return Ok(padFormatted(sign, "", body, width, zeroPad, leftAlign))
}

static Result<String, Error> renderArgument(FormatArgument argument, String conversion, Bool leftAlign,
    Bool plusSign, Bool spaceSign, Bool zeroPad, Bool alternate, Bool hasPrecision, Int precision, Int width) {
    if argument.kind == 0 || argument.kind == 1 {
        return renderInteger(argument, conversion, leftAlign, plusSign, spaceSign, zeroPad, alternate,
            hasPrecision, precision, width)
    }
    if argument.kind == 2 {
        return renderFloat(argument, conversion, leftAlign, plusSign, spaceSign, zeroPad, alternate,
            hasPrecision, precision, width)
    }
    if argument.kind == 3 {
        if conversion != "s" {
            return Err(printfError("printf: 文本参数需要 %s"))
        }
        String body = argument.textValue
        if hasPrecision {
            body = takeCodePoints(body, precision)
        }
        Int missing = width - body.length()
        if missing <= 0 {
            return Ok(body)
        }
        if leftAlign {
            return Ok(body + repeatUnit(" ", missing))
        }
        return Ok(repeatUnit(" ", missing) + body)
    }
    if argument.kind == 4 {
        if conversion != "b" {
            return Err(printfError("printf: 布尔参数需要 %b"))
        }
        String body = "false"
        if argument.boolValue {
            body = "true"
        }
        Int missing = width - body.length()
        if missing <= 0 {
            return Ok(body)
        }
        if leftAlign {
            return Ok(body + repeatUnit(" ", missing))
        }
        return Ok(repeatUnit(" ", missing) + body)
    }
    if argument.kind == 5 {
        if conversion != "c" {
            return Err(printfError("printf: 字符参数需要 %c"))
        }
        String body = argument.textValue
        Int missing = width - body.length()
        if missing <= 0 {
            return Ok(body)
        }
        if leftAlign {
            return Ok(body + repeatUnit(" ", missing))
        }
        return Ok(repeatUnit(" ", missing) + body)
    }
    return Err(printfError("printf: 未知参数类型"))
}

// printf：按 pattern 依次消费 arguments；成功返回渲染文本。
Result<String, Error> printf(String pattern, List<FormatArgument> arguments) {
    String output = ""
    Int index = 0
    Int argumentIndex = 0
    while index < pattern.length() {
        String character = pattern.substring(index, 1)
        if character != "%" {
            output = output + character
            index = index + 1
            continue
        }
        index = index + 1
        if index >= pattern.length() {
            return Err(printfError("printf: 模式以 % 结尾"))
        }
        if pattern.substring(index, 1) == "%" {
            output = output + "%"
            index = index + 1
            continue
        }
        Bool leftAlign = false
        Bool plusSign = false
        Bool spaceSign = false
        Bool zeroPad = false
        Bool alternate = false
        Bool readingFlags = true
        while readingFlags && index < pattern.length() {
            String flag = pattern.substring(index, 1)
            if flag == "-" {
                leftAlign = true
            } else if flag == "+" {
                plusSign = true
            } else if flag == " " {
                spaceSign = true
            } else if flag == "0" {
                zeroPad = true
            } else if flag == "#" {
                alternate = true
            } else {
                readingFlags = false
                continue
            }
            index = index + 1
        }
        Int width = 0
        while index < pattern.length() && printfIsDigit(pattern.get(index)) {
            if width > 214748364 {
                return Err(printfError("printf: 宽度溢出"))
            }
            width = width * 10 + (pattern.get(index) - 48)
            index = index + 1
        }
        Bool hasPrecision = false
        Int precision = 0
        if index < pattern.length() && pattern.substring(index, 1) == "." {
            hasPrecision = true
            index = index + 1
            while index < pattern.length() && printfIsDigit(pattern.get(index)) {
                if precision > 214748364 {
                    return Err(printfError("printf: 精度溢出"))
                }
                precision = precision * 10 + (pattern.get(index) - 48)
                index = index + 1
            }
        }
        if index >= pattern.length() {
            return Err(printfError("printf: 缺少转换字符"))
        }
        String conversion = pattern.substring(index, 1)
        index = index + 1
        if argumentIndex >= arguments.length() {
            return Err(printfError("printf: 参数数量不足"))
        }
        Result<String, Error> rendered = renderArgument(arguments.get(argumentIndex), conversion,
            leftAlign, plusSign, spaceSign, zeroPad, alternate, hasPrecision, precision, width)
        if rendered.isErr() {
            return rendered
        }
        output = output + rendered.value()
        argumentIndex = argumentIndex + 1
    }
    if argumentIndex != arguments.length() {
        return Err(printfError("printf: 参数数量过多"))
    }
    return Ok(output)
}
