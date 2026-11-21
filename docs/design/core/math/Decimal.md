# `Decimal`

| 项 | 值 |
| --- | --- |
| 类型 | `class Decimal` |
| 包 | `xdk.math` |
| 稳定性 | `preview` |
| 依赖 | `RoundingMode`、`Int128`、`errors` |

---

## 1. 定位

固定精度十进制数：64 位系数字 + 0..18 小数位；用于金额、税率、精确小数。

不做：任意精度 BigDecimal、科学计算、locale 格式、货币单位。

---

## 2. 设计逻辑

- 值 = `_unscaled / 10^_scale`；`_scale` 0..18；`_unscaled` 是 `Long`。
- 加减对齐 scale；乘 scale 相加；除显式给结果 scale + 舍入模式。
- 中间运算用 `Int128` 防溢出；结果超出 `Long` → `InvalidArgument`。
- 不可变；`add/sub/mul/div/setScale` 返回新实例或 `Result`。
- `equals` 是数值相等（1.0 == 1.00）；`toString` 保留 scale。
- 无全局舍入模式；每次显式传 `RoundingMode`。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_unscaled` | `Long` | 系数，可负 |
| `_scale` | `Int` | 小数位 0..18 |

不变量：0 ≤ scale ≤ 18；unscaled 在 Long 范围；值 = unscaled/10^scale。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

构造器内部；公共入口：

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Decimal.parse(text)` | 文本 | `[+-]digits[.digits][e[+-]digits]` | `InvalidArgument` |
| `Decimal.fromInt(value)` | Int | 任意 | 无 |
| `Decimal.fromLong(value)` | Long | 任意 | 无 |
| `Decimal.fromDouble(value)` | Double | 有限 | NaN/Inf → `InvalidArgument` |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `add` | 加 | `Decimal other` | `Result<Decimal, Error>` | 溢出/scale>18 |
| `sub` | 减 | `Decimal other` | `Result<Decimal, Error>` | 溢出/scale>18 |
| `mul` | 乘 | `Decimal other` | `Result<Decimal, Error>` | 溢出/scale>18 |
| `div` | 除 | `Decimal other, Int scale, RoundingMode mode` | `Result<Decimal, Error>` | 除零/非法 scale/溢出 |
| `negate` | 取负 | 无 | `Result<Decimal, Error>` | MIN 系数 |
| `abs` | 绝对值 | 无 | `Result<Decimal, Error>` | MIN 系数 |
| `compare` | 比较 | `Decimal other` | `Int` | 无 |
| `equals` | 数值相等 | `Decimal other` | `Bool` | 无 |
| `scale` | 小数位 | 无 | `Int` | 无 |
| `setScale` | 改 scale | `Int scale, RoundingMode mode` | `Result<Decimal, Error>` | 非法/溢出 |
| `round` | 舍入 | `Int scale, RoundingMode mode` | `Result<Decimal, Error>` | 同上 |
| `floor` | 向下取整 | 无 | `Decimal` | 无 |
| `ceil` | 向上取整 | 无 | `Decimal` | 无 |
| `truncate` | 向零取整 | 无 | `Decimal` | 无 |
| `toInt` | 转 Int | 无 | `Result<Int, Error>` | 溢出/非整数？按 Down |
| `toLong` | 转 Long | 无 | `Result<Long, Error>` | 溢出 |
| `toDouble` | 转 Double | 无 | `Double` | 无 |
| `isZero` | 是否 0 | 无 | `Bool` | 无 |
| `isNegative` | 是否负 | 无 | `Bool` | 无 |
| `toString` | 文本 | 无 | `String` | 无 |
| `copy` | 复制 | 无 | `Decimal` | 无 |

> `toInt/toLong` 先 `truncate()`，再检查目标范围；不静默回绕。

---

## 8. 使用的技术

- 64 位系数 + scale；
- 10 的幂（内部 `pow10`）；
- Int128 中间值；
- 舍入模式；
- 字符串解析/格式化；
- 数值比较（对齐 scale）。

---

## 9. 需要的支撑

- 语言：class、Long、Int、Bool、String、Result；
- 运行时：64/128 位算术、字符串；
- 接口：`RoundingMode`、`Int128`、`BasicError`、`ErrorKind`、内部 `pow10` 辅助。

---

## 10. 依赖的特性/接口/类

`RoundingMode`、`Int128`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`Decimal.parse("1.25").add(Decimal.parse("0.05"))` → `1.30`；`setScale(1, HalfEven)` → `1.2`。  
反例：期望任意精度；`div` 不给 scale；用 Double 做金额；忽略 `Result`。

---

## 13. 测试/场景义务

解析正负/小数/指数/溢出；add/sub 对齐；mul scale；div 各模式；setScale/round；floor/ceil/truncate；compare/equals；toInt/toLong 边界；toString。

---

## 14. XNull 伪代码

```xnull
class Decimal {
    Long _unscaled
    Int _scale

    Decimal(Long unscaled, Int scale) {
        if scale < 0 || scale > 18 {
            throw "Decimal: scale out of range"
        }
        _unscaled = unscaled
        _scale = scale
    }

    static Result<Decimal, Error> parse(String text) {
        if text == null || text == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument, "empty decimal"))
        }
        Int index = 0
        Bool negative = false
        if text.charAt(0) == '-' {
            negative = true
            index = 1
        } else if text.charAt(0) == '+' {
            index = 1
        }
        Long unscaled = 0
        Int scale = 0
        Bool sawDigit = false
        Bool sawDot = false
        while index < text.length() {
            Char character = text.charAt(index)
            if character >= '0' && character <= '9' {
                Int digit = character as Int - 48
                if unscaled > 922337203685477580 {
                    return Err(new BasicError(ErrorKind.InvalidArgument, "decimal overflow"))
                }
                unscaled = unscaled * 10 + digit
                if sawDot {
                    scale = scale + 1
                    if scale > 18 {
                        return Err(new BasicError(ErrorKind.InvalidArgument, "scale out of range"))
                    }
                }
                sawDigit = true
                index = index + 1
            } else if character == '.' && !sawDot {
                sawDot = true
                index = index + 1
            } else if character == 'e' || character == 'E' {
                if !sawDigit {
                    return Err(new BasicError(ErrorKind.InvalidArgument, "invalid decimal"))
                }
                Result<Int, Error> exponent = parseInt(text.substring(index + 1, text.length() - index - 1))
                if exponent.isErr() {
                    return Err(exponent.error())
                }
                Int shift = exponent.value()
                if shift > 0 {
                    if scale < shift {
                        Int remaining = shift - scale
                        Int count = 0
                        while count < remaining {
                            if unscaled > 922337203685477580 {
                                return Err(new BasicError(ErrorKind.InvalidArgument, "decimal overflow"))
                            }
                            unscaled = unscaled * 10
                            count = count + 1
                        }
                        scale = 0
                    } else {
                        scale = scale - shift
                    }
                } else {
                    scale = scale - shift
                    if scale > 18 {
                        return Err(new BasicError(ErrorKind.InvalidArgument, "scale out of range"))
                    }
                }
                index = text.length()
            } else {
                return Err(new BasicError(ErrorKind.InvalidArgument, "invalid decimal"))
            }
        }
        if !sawDigit {
            return Err(new BasicError(ErrorKind.InvalidArgument, "no digits"))
        }
        if negative {
            unscaled = 0 - unscaled
        }
        return Ok(new Decimal(unscaled, scale))
    }

    static Decimal fromInt(Int value) {
        return new Decimal(value as Long, 0)
    }

    static Decimal fromLong(Long value) {
        return new Decimal(value, 0)
    }

    static Result<Decimal, Error> fromDouble(Double value) {
        if isNaN(value) || isInf(value) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "non-finite decimal"))
        }
        return Decimal.parse(str(value))
    }

    Int scale() { return _scale }
    Bool isZero() { return _unscaled == 0 }
    Bool isNegative() { return _unscaled < 0 }

    Int compare(Decimal other) {
        Int target = _scale
        if other._scale > target { target = other._scale }
        Int128 left = (_unscaled as Int128) * pow10(target - _scale)
        Int128 right = (other._unscaled as Int128) * pow10(target - other._scale)
        if left < right { return -1 }
        if left > right { return 1 }
        return 0
    }

    Bool equals(Decimal other) {
        if other == null { return false }
        return self.compare(other) == 0
    }

    Result<Decimal, Error> add(Decimal other) {
        if other == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "null decimal"))
        }
        Int target = _scale
        if other._scale > target { target = other._scale }
        Int128 left = (_unscaled as Int128) * pow10(target - _scale)
        Int128 right = (other._unscaled as Int128) * pow10(target - other._scale)
        Int128 sum = left + right
        if sum > 9223372036854775807 || sum < -9223372036854775808 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "decimal overflow"))
        }
        return Ok(new Decimal(sum as Long, target))
    }

    Result<Decimal, Error> sub(Decimal other) {
        if other == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "null decimal"))
        }
        Result<Decimal, Error> negated = other.negate()
        if negated.isErr() {
            return Err(negated.error())
        }
        return self.add(negated.value())
    }

    Result<Decimal, Error> mul(Decimal other) {
        if other == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "null decimal"))
        }
        if _scale + other._scale > 18 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "scale out of range"))
        }
        Int128 product = (_unscaled as Int128) * (other._unscaled as Int128)
        if product > 9223372036854775807 || product < -9223372036854775808 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "decimal overflow"))
        }
        return Ok(new Decimal(product as Long, _scale + other._scale))
    }

    Result<Decimal, Error> div(Decimal other, Int scale, RoundingMode mode) {
        if other == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "null decimal"))
        }
        if other.isZero() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "division by zero"))
        }
        if scale < 0 || scale > 18 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "scale out of range"))
        }
        if mode == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "null rounding mode"))
        }
        Int exponent = scale + other._scale - _scale
        Int128 numerator = _unscaled as Int128
        Int128 denominator = other._unscaled as Int128
        if exponent >= 0 {
            numerator = numerator * pow10(exponent)
        } else {
            denominator = denominator * pow10(0 - exponent)
        }
        Int128 quotient = numerator / denominator
        Int128 remainder = numerator % denominator
        if remainder == 0 || mode == RoundingMode.Down {
            if quotient > 9223372036854775807 || quotient < -9223372036854775808 {
                return Err(new BasicError(ErrorKind.InvalidArgument, "decimal overflow"))
            }
            return Ok(new Decimal(quotient as Long, scale))
        }
        if mode == RoundingMode.Unnecessary {
            return Err(new BasicError(ErrorKind.InvalidArgument, "rounding required"))
        }
        Bool negative = (numerator < 0) != (denominator < 0)
        Int128 absoluteRemainder = remainder
        if absoluteRemainder < 0 { absoluteRemainder = 0 - absoluteRemainder }
        Int128 absoluteDenominator = denominator
        if absoluteDenominator < 0 { absoluteDenominator = 0 - absoluteDenominator }
        Bool roundAway = false
        if mode == RoundingMode.Up {
            roundAway = true
        } else if mode == RoundingMode.Ceiling {
            roundAway = !negative
        } else if mode == RoundingMode.Floor {
            roundAway = negative
        } else {
            Int128 doubled = absoluteRemainder * 2
            if doubled > absoluteDenominator {
                roundAway = true
            } else if doubled == absoluteDenominator {
                if mode == RoundingMode.HalfUp {
                    roundAway = true
                } else if mode == RoundingMode.HalfEven {
                    roundAway = (quotient % 2) != 0
                }
            }
        }
        if roundAway {
            if negative {
                quotient = quotient - 1
            } else {
                quotient = quotient + 1
            }
        }
        if quotient > 9223372036854775807 || quotient < -9223372036854775808 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "decimal overflow"))
        }
        return Ok(new Decimal(quotient as Long, scale))
    }

    Result<Decimal, Error> negate() {
        if _unscaled == -9223372036854775808 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "decimal overflow"))
        }
        return Ok(new Decimal(0 - _unscaled, _scale))
    }

    Result<Decimal, Error> abs() {
        if _unscaled >= 0 {
            return Ok(self.copy())
        }
        return self.negate()
    }

    Result<Decimal, Error> setScale(Int scale, RoundingMode mode) {
        if scale < 0 || scale > 18 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "scale out of range"))
        }
        if mode == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "null rounding mode"))
        }
        if scale >= _scale {
            Int difference = scale - _scale
            Int128 value = (_unscaled as Int128) * pow10(difference)
            if value > 9223372036854775807 || value < -9223372036854775808 {
                return Err(new BasicError(ErrorKind.InvalidArgument, "decimal overflow"))
            }
            return Ok(new Decimal(value as Long, scale))
        }
        Int difference = _scale - scale
        Int128 divisor = pow10(difference)
        Int128 quotient = (_unscaled as Int128) / divisor
        Int128 remainder = (_unscaled as Int128) % divisor
        if remainder == 0 {
            return Ok(new Decimal(quotient as Long, scale))
        }
        if mode == RoundingMode.Unnecessary {
            return Err(new BasicError(ErrorKind.InvalidArgument, "rounding required"))
        }
        Bool negative = _unscaled < 0
        Int128 absoluteRemainder = remainder
        if absoluteRemainder < 0 { absoluteRemainder = 0 - absoluteRemainder }
        Bool roundAway = false
        if mode == RoundingMode.Up {
            roundAway = true
        } else if mode == RoundingMode.Ceiling {
            roundAway = !negative
        } else if mode == RoundingMode.Floor {
            roundAway = negative
        } else if mode == RoundingMode.HalfUp || mode == RoundingMode.HalfDown || mode == RoundingMode.HalfEven {
            Int128 half = divisor / 2
            if absoluteRemainder > half {
                roundAway = true
            } else if absoluteRemainder == half {
                if mode == RoundingMode.HalfUp {
                    roundAway = true
                } else if mode == RoundingMode.HalfEven {
                    roundAway = (quotient % 2) != 0
                }
            }
        }
        if roundAway {
            if negative {
                quotient = quotient - 1
            } else {
                quotient = quotient + 1
            }
        }
        if quotient > 9223372036854775807 || quotient < -9223372036854775808 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "decimal overflow"))
        }
        return Ok(new Decimal(quotient as Long, scale))
    }

    Result<Decimal, Error> round(Int scale, RoundingMode mode) {
        return self.setScale(scale, mode)
    }

    Decimal floor() {
        return self.setScale(0, RoundingMode.Floor).value()
    }

    Decimal ceil() {
        return self.setScale(0, RoundingMode.Ceiling).value()
    }

    Decimal truncate() {
        return self.setScale(0, RoundingMode.Down).value()
    }

    Result<Int, Error> toInt() {
        Result<Decimal, Error> truncated = self.setScale(0, RoundingMode.Down)
        if truncated.isErr() { return Err(truncated.error()) }
        Long value = truncated.value()._unscaled
        if value > 2147483647 || value < -2147483648 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "int overflow"))
        }
        return Ok(value as Int)
    }

    Result<Long, Error> toLong() {
        Result<Decimal, Error> truncated = self.setScale(0, RoundingMode.Down)
        if truncated.isErr() { return Err(truncated.error()) }
        return Ok(truncated.value()._unscaled)
    }

    Double toDouble() {
        Double divisor = 1.0
        Int index = 0
        while index < _scale {
            divisor = divisor * 10.0
            index = index + 1
        }
        return (_unscaled as Double) / divisor
    }

    String toString() {
        String digits = str(_unscaled)
        Bool negative = false
        if _unscaled < 0 {
            negative = true
            digits = digits.substring(1, digits.length() - 1)
        }
        while digits.length() <= _scale {
            digits = "0" + digits
        }
        Int split = digits.length() - _scale
        String result = digits
        if _scale > 0 {
            result = digits.substring(0, split) + "." + digits.substring(split, digits.length() - split)
        }
        if negative {
            return "-" + result
        }
        return result
    }

    Decimal copy() {
        return new Decimal(_unscaled, _scale)
    }
}
```

> `pow10(Int) -> Int128` 是 math 包内部 10 的幂辅助；`parseInt` 是 text 包函数；Decimal 构造器内部，公共入口是静态工厂。
