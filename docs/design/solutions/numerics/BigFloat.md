# `BigFloat`

| 项 | 值 |
| --- | --- |
| 类型 | `class BigFloat` |
| 包 | `xdk.numerics` |
| 稳定性 | `preview` |
| 依赖 | `BigInt`、`RoundingMode`、`Context`、`BasicError`、`ErrorKind` |

---

## 1. 定位

任意精度二进制浮点：每个值携带精度位数；加减乘除、开方、指数、对数、幂都用显式目标精度与显式舍入模式。

不做：NaN/±Inf、子正规数、任意精度三角/特殊函数、有理数、区间/球算术、隐式从 `Double` 构造。

---

## 2. 设计逻辑

- 值 = `(-1)^_negative * _significand * 2^_exponent`；`_significand` 是非负 `BigInt`，`_precisionBits` 是该值的最大有效位数。
- 所有值有限；没有 NaN/Inf。溢出指数范围、除零、负数开方、非正数取对数都是 `InvalidArgument`，不产生伪值。
- 每个算术方法显式接收 `Int precisionBits` 与 `RoundingMode mode`；不存在全局舍入模式。
- 先算精确中间值（`BigInt` 或高一位的整数商），再按目标精度舍入；舍入保留 guard/sticky 信息，避免“先截断再判断”。
- `Context` 只出现在可能长时间运行的转换、开方、指数、对数、幂上；普通四则运算不接 `Context`。
- 指数范围固定为 `[-1000000000, 1000000000]`；加减法指数差超过 `1000000` 时返回 `InvalidArgument`，避免为不可表示的低位分配巨量内存。
- 不从 `Double` 隐式构造；`fromDouble` 是显式命名工厂，必须给精度与舍入。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_negative` | `Bool` | 符号；零为 `false` |
| `_significand` | `BigInt` | 非负有效数字 |
| `_exponent` | `Long` | 二进制指数 |
| `_precisionBits` | `Int` | 值的最大有效位数，2..1048576 |

不变量：

- 零：`_significand.isZero()`、`_negative == false`、`_exponent == 0`。
- 非零：`_significand.bitLength() <= _precisionBits`；指数在 `[-1000000000, 1000000000]`。
- 值 = `(-1)^_negative * _significand * 2^_exponent`。
- 不要求 significand 为奇数；等价表示通过 `compare`/`equals` 归一。
- 不可变；任何运算返回新对象。

---

## 4. 生命周期

不可变；无 close；无资源句柄；可跨任务共享。构造后不再改变。

---

## 5. 构造契约

构造器私有；公共入口如下。`null` 参数是合同错误（panic）；非法域是 `InvalidArgument`。

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `BigFloat.zero(Int precisionBits)` | `precisionBits` | 2..1048576 | `InvalidArgument` |
| `BigFloat.one(Int precisionBits)` | 同上 | 同上 | 同上 |
| `BigFloat.fromInt(Int value, Int precisionBits, RoundingMode mode)` | `value` | 任意 `Int` | 精度/舍入 |
| `BigFloat.fromLong(Long value, Int precisionBits, RoundingMode mode)` | `value` | 任意 `Long` | 精度/舍入 |
| `BigFloat.fromBigInt(Context context, BigInt value, Int precisionBits, RoundingMode mode)` | `value` | 任意 `BigInt` | null/精度/舍入/取消 |
| `BigFloat.fromDouble(Double value, Int precisionBits, RoundingMode mode)` | `value` | 有限 `Double` | NaN/Inf/精度/舍入 |
| `BigFloat.parse(String text, Int precisionBits, RoundingMode mode, Int maximumDigits)` | `text` | 十进制科学计数法 | 文本/指数/精度/舍入/超长 |

`fromDouble` 按 IEEE 754 的二进制值精确转换，再做目标精度舍入；不是按最短十进制字符串转换。

---

## 6. 字段表

见 §3；字段全部私有、构造后只读。

---

## 7. 方法总表 / 详表

### 7.1 方法总表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `precisionBits` | 精度位数 | 无 | `Int` | 无 |
| `signum` | 符号 | 无 | `Int` | 无 |
| `isZero` | 是否零 | 无 | `Bool` | 无 |
| `isNegative` | 是否负 | 无 | `Bool` | 无 |
| `add` | 加 | `BigFloat other, Int precisionBits, RoundingMode mode` | `Result<BigFloat, Error>` | 指数差过大/精度/舍入 |
| `subtract` | 减 | 同上 | 同上 | 同上 |
| `multiply` | 乘 | 同上 | 同上 | 指数溢出/精度/舍入 |
| `divide` | 除 | 同上 | 同上 | 除零/指数溢出/精度/舍入 |
| `negate` | 取负 | 无 | `BigFloat` | 无 |
| `abs` | 绝对值 | 无 | `BigFloat` | 无 |
| `round` | 改精度 | `Int precisionBits, RoundingMode mode` | `Result<BigFloat, Error>` | 精度/舍入/`Unnecessary` |
| `sqrt` | 平方根 | `Context context, Int precisionBits, RoundingMode mode` | `Result<BigFloat, Error>` | 负数/取消/精度/舍入 |
| `exp` | 指数函数 | 同上 | 同上 | 溢出/下溢/取消 |
| `log` | 自然对数 | 同上 | 同上 | 非正数/取消 |
| `pow` | 幂 | `Context context, BigFloat exponent, Int precisionBits, RoundingMode mode` | 同上 | 定义域/溢出/取消 |
| `compare` | 比较 | `BigFloat other` | `Int` | null → panic |
| `equals` | 值相等 | `BigFloat other` | `Bool` | null → false |
| `isInteger` | 是否整数值 | 无 | `Bool` | 无 |
| `toDouble` | 显式转 `Double` | 无 | `Double` | 无；可能舍入或 `Inf` |
| `toBigInt` | 显式转 `BigInt` | `Context context, RoundingMode mode` | `Result<BigInt, Error>` | 舍入/范围/取消 |
| `toDecimalString` | 十进制文本 | `Context context, Int fractionalDigits, RoundingMode mode` | `Result<String, Error>` | 参数/舍入/取消 |
| `toString` | 精确结构文本 | 无 | `String` | 无 |

### 7.2 语义

- 目标精度可以与操作数精度不同；结果精度始终等于 `precisionBits`。
- `Unnecessary` 在发生任何有效位丢失时失败；完全精确时成功。
- `sqrt`、`exp`、`log`、`pow` 先用 `precisionBits + 8` 位工作精度，再按目标舍入；guard 位不暴露。
- `exp` 的参数限制在 `[-1000000, 1000000]`；超出视为指数溢出/下溢并失败。
- `pow` 的整数指数走平方-乘；非整数指数要求底数为正。
- `toString` 返回 `"<significand>p<exponent>"`，例如 `3p-1` 表示 `3 * 2^-1`；这是精确结构文本，不是十进制展示。
- `equals` 是数值相等；`compare` 返回 `-1`/`0`/`1`。

---

## 8. 使用的技术

- 符号 + 任意精度整数 significand + 二进制指数；
- 目标精度舍入，保留 half/sticky；
- 指数对齐与 guard 位；
- 整数商/余数实现除法与有理数转换；
- Newton 整数开方；
- 参数约减 + Taylor 级数实现 `exp`；
- atanh 级数实现 `log` 与 `ln 2`；
- 平方-乘整数幂；
- 显式十进制格式化。

---

## 9. 需要的支撑

- 语言：class、`Bool`、`Int`、`Long`、`List`、`String`、`Result`；
- 数学：`isNaN`、`isInf`、`floor`、`pow`；
- 任意精度：`BigInt` 的加减乘除、余数、位移、开方、比较、位测试；
- 舍入：`RoundingMode` 全部成员；
- 执行：`Context.isCancelled`；
- 错误：`BasicError`、`ErrorKind.InvalidArgument`、`ErrorKind.Cancelled`；
- 运行时：`decodeDouble(Double) -> Pair<Long, Int>`，把有限 Double 分解为 `significand * 2^exponent`（significand 为正整数，subnormal 也支持）。

---

## 10. 依赖的特性/接口/类

[`BigInt`](BigInt.md)、[`RoundingMode`](../../core/math/RoundingMode.md)、[`Context`](../../core/execution/Context.md)、[`Pair`](../../core/collections/Pair.md)、[`BasicError`](../../core/errors/BasicError.md)、[`ErrorKind`](../../core/errors/ErrorKind.md)。

---

## 11. 所有权与并发

不可变值对象；可跨任务共享；无锁；无 close。运算不修改操作数；返回新对象。`Context` 只用于取消查询，不保存。相等是数值相等，可作 `Map` 键（实现方需提供稳定哈希）。

---

## 12. 示例与反例

正确：`BigFloat.parse("0.1", 256, RoundingMode.HalfEven, 64)`；`left.add(right, 256, RoundingMode.HalfEven)`；`value.sqrt(context, 256, RoundingMode.HalfEven)`；`value.toDecimalString(30, RoundingMode.HalfEven)`。  
反例：期望 `BigFloat` 自动沿用左操作数精度；期望默认舍入；把 `Double` 直接赋给 `BigFloat`；用 `equals` 比较两个不同精度的近似值；在 `pow` 中对负数底数传非整数指数。

---

## 13. 测试/场景义务

零/正/负；精度 2/53/256/1048576；`fromInt`/`fromLong` 的 `Long.MIN`；`fromDouble` 的普通值/subnormal/最大有限值/NaN/Inf；parse 的小数/指数/符号/超长/非法；加法的指数对齐与抵消；乘法的指数和溢出；除法的循环小数与 sticky；每个舍入模式的正负/半值/奇偶；`Unnecessary`；`round` 升/降精度；`sqrt` 完全平方与非完全平方；`exp(0)`/`exp(1)`/溢出/下溢；`log(1)`/`log(e)`/非正数；`pow` 整数/负指数/非整数；`toBigInt` 各模式；`toDecimalString` 的进位与补零；`toString` 往返；取消。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class BigFloat {
    final Bool _negative
    final BigInt _significand
    final Long _exponent
    final Int _precisionBits

    private BigFloat(Bool negative, BigInt significand, Long exponent,
        Int precisionBits) {
        if precisionBits < 2 || precisionBits > 1048576 {
            throw "BigFloat: precision out of range"
        }
        if significand == null {
            throw "BigFloat: null significand"
        }
        if significand.isNegative() {
            throw "BigFloat: negative significand"
        }
        Bool negativeValue = negative
        Long exponentValue = exponent
        if significand.isZero() {
            negativeValue = false
            exponentValue = 0
        } else {
            if exponentValue < -1000000000 || exponentValue > 1000000000 {
                throw "BigFloat: exponent out of range"
            }
            if significand.bitLength() > precisionBits as Long {
                throw "BigFloat: significand exceeds precision"
            }
        }
        _negative = negativeValue
        _significand = significand
        _exponent = exponentValue
        _precisionBits = precisionBits
    }

    static Result<BigFloat, Error> zero(Int precisionBits) {
        if precisionBits < 2 || precisionBits > 1048576 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigFloat.zero: precision out of range"))
        }
        return Ok(new BigFloat(false, BigInt.zero(), 0, precisionBits))
    }

    static Result<BigFloat, Error> one(Int precisionBits) {
        if precisionBits < 2 || precisionBits > 1048576 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigFloat.one: precision out of range"))
        }
        return Ok(new BigFloat(false, BigInt.one(), 0, precisionBits))
    }

    static Result<BigFloat, Error> fromInt(Int value, Int precisionBits,
        RoundingMode mode) {
        return BigFloat.fromLong(value as Long, precisionBits, mode)
    }

    static Result<BigFloat, Error> fromLong(Long value, Int precisionBits,
        RoundingMode mode) {
        if precisionBits < 2 || precisionBits > 1048576 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigFloat.fromLong: precision out of range"))
        }
        if mode == null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigFloat.fromLong: null rounding mode"))
        }
        BigInt magnitude = BigInt.fromLong(value).abs()
        return BigFloat._round(value < 0, magnitude, 0, precisionBits,
            mode, false)
    }

    static Result<BigFloat, Error> fromBigInt(Context context, BigInt value,
        Int precisionBits, RoundingMode mode) {
        if context == null {
            throw "BigFloat.fromBigInt: null context"
        }
        if value == null {
            throw "BigFloat.fromBigInt: null value"
        }
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled,
                "BigFloat.fromBigInt: cancelled"))
        }
        return BigFloat._round(value.isNegative(), value.abs(), 0,
            precisionBits, mode, false)
    }

    static Result<BigFloat, Error> fromDouble(Double value, Int precisionBits,
        RoundingMode mode) {
        if isNaN(value) || isInf(value) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigFloat.fromDouble: non-finite value"))
        }
        if precisionBits < 2 || precisionBits > 1048576 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigFloat.fromDouble: precision out of range"))
        }
        if mode == null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigFloat.fromDouble: null rounding mode"))
        }
        if value == 0.0 {
            return BigFloat.zero(precisionBits)
        }
        Pair<Long, Int> decoded = decodeDouble(value)
        BigInt magnitude = BigInt.fromLong(decoded.first).abs()
        return BigFloat._round(value < 0.0, magnitude, decoded.second as Long,
            precisionBits, mode, false)
    }

    static Result<BigFloat, Error> parse(String text, Int precisionBits,
        RoundingMode mode, Int maximumDigits) {
        if text == null || text == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigFloat.parse: empty text"))
        }
        if maximumDigits < 1 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigFloat.parse: invalid maximum digits"))
        }
        if precisionBits < 2 || precisionBits > 1048576 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigFloat.parse: precision out of range"))
        }
        if mode == null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigFloat.parse: null rounding mode"))
        }
        Int index = 0
        Bool negative = false
        if text.charAt(0) == '-' {
            negative = true
            index = 1
        } else if text.charAt(0) == '+' {
            index = 1
        }
        BigInt coefficient = BigInt.zero()
        Int digitCount = 0
        Int fractionDigits = 0
        Bool sawDot = false
        Bool sawDigit = false
        while index < text.length() {
            Char character = text.charAt(index)
            if character >= '0' && character <= '9' {
                digitCount = digitCount + 1
                if digitCount > maximumDigits {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "BigFloat.parse: too many digits"))
                }
                Result<BigInt, Error> multiplied = coefficient.multiply(
                    BigInt.fromInt(10))
                if multiplied.isErr() {
                    return Err(multiplied.error())
                }
                coefficient = multiplied.value().add(
                    BigInt.fromInt((character as Int) - 48))
                if sawDot {
                    fractionDigits = fractionDigits + 1
                }
                sawDigit = true
                index = index + 1
            } else if character == '.' && !sawDot {
                sawDot = true
                index = index + 1
            } else if character == 'e' || character == 'E' {
                if !sawDigit {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "BigFloat.parse: missing mantissa"))
                }
                Result<Int, Error> exponentResult =
                    parseInt(text.substring(index + 1, text.length() - index - 1))
                if exponentResult.isErr() {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "BigFloat.parse: invalid exponent"))
                }
                Int decimalExponent = exponentResult.value() - fractionDigits
                if decimalExponent > 1000000 || decimalExponent < -1000000 {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "BigFloat.parse: exponent out of range"))
                }
                return BigFloat._fromDecimal(negative, coefficient,
                    decimalExponent, precisionBits, mode)
            } else {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "BigFloat.parse: invalid character"))
            }
        }
        if !sawDigit {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigFloat.parse: no digits"))
        }
        return BigFloat._fromDecimal(negative, coefficient,
            0 - fractionDigits, precisionBits, mode)
    }

    Int precisionBits() {
        return _precisionBits
    }

    Int signum() {
        if _significand.isZero() {
            return 0
        }
        if _negative {
            return -1
        }
        return 1
    }

    Bool isZero() {
        return _significand.isZero()
    }

    Bool isNegative() {
        return _negative
    }

    Result<BigFloat, Error> add(BigFloat other, Int precisionBits,
        RoundingMode mode) {
        if other == null {
            throw "BigFloat.add: null other"
        }
        if isZero() {
            return other.round(precisionBits, mode)
        }
        if other.isZero() {
            return self.round(precisionBits, mode)
        }
        Long commonExponent = _exponent
        if other._exponent < commonExponent {
            commonExponent = other._exponent
        }
        Long leftDifference = _exponent - commonExponent
        Long rightDifference = other._exponent - commonExponent
        if leftDifference > 1000000 || rightDifference > 1000000 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigFloat.add: exponent difference too large"))
        }
        Result<BigInt, Error> leftShifted =
            _significand.shiftLeft(leftDifference as Int)
        if leftShifted.isErr() {
            return Err(leftShifted.error())
        }
        Result<BigInt, Error> rightShifted =
            other._significand.shiftLeft(rightDifference as Int)
        if rightShifted.isErr() {
            return Err(rightShifted.error())
        }
        BigInt left = leftShifted.value()
        BigInt right = rightShifted.value()
        if _negative == other._negative {
            return BigFloat._round(_negative, left.add(right), commonExponent,
                precisionBits, mode, false)
        }
        Int comparison = left.compare(right)
        if comparison == 0 {
            return BigFloat.zero(precisionBits)
        }
        if comparison > 0 {
            return BigFloat._round(_negative, left.subtract(right),
                commonExponent, precisionBits, mode, false)
        }
        return BigFloat._round(other._negative, right.subtract(left),
            commonExponent, precisionBits, mode, false)
    }

    Result<BigFloat, Error> subtract(BigFloat other, Int precisionBits,
        RoundingMode mode) {
        if other == null {
            throw "BigFloat.subtract: null other"
        }
        return self.add(other.negate(), precisionBits, mode)
    }

    Result<BigFloat, Error> multiply(BigFloat other, Int precisionBits,
        RoundingMode mode) {
        if other == null {
            throw "BigFloat.multiply: null other"
        }
        if isZero() || other.isZero() {
            return BigFloat.zero(precisionBits)
        }
        Long exponent = _exponent + other._exponent
        if exponent < -1000000000 || exponent > 1000000000 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigFloat.multiply: exponent out of range"))
        }
        BigInt magnitude = _significand.multiply(other._significand)
        return BigFloat._round(_negative != other._negative, magnitude,
            exponent, precisionBits, mode, false)
    }

    Result<BigFloat, Error> divide(BigFloat other, Int precisionBits,
        RoundingMode mode) {
        if other == null {
            throw "BigFloat.divide: null other"
        }
        if other.isZero() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigFloat.divide: division by zero"))
        }
        if isZero() {
            return BigFloat.zero(precisionBits)
        }
        Long exponent = _exponent - other._exponent
        if exponent < -1000000000 || exponent > 1000000000 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigFloat.divide: exponent out of range"))
        }
        Long lengthDifference = other._significand.bitLength()
            - _significand.bitLength()
        Int extra = 0
        if lengthDifference > 0 {
            extra = lengthDifference as Int
        }
        Int shift = precisionBits + 4 + extra
        Result<BigInt, Error> scaled = _significand.shiftLeft(shift)
        if scaled.isErr() {
            return Err(scaled.error())
        }
        Result<Pair<BigInt, BigInt>, Error> division =
            scaled.value().divideAndRemainder(other._significand)
        if division.isErr() {
            return Err(division.error())
        }
        Bool sticky = !division.value().second.isZero()
        Long resultExponent = exponent - (shift as Long)
        return BigFloat._round(_negative != other._negative,
            division.value().first, resultExponent,
            precisionBits, mode, sticky)
    }

    BigFloat negate() {
        if isZero() {
            return self
        }
        return new BigFloat(!_negative, _significand, _exponent, _precisionBits)
    }

    BigFloat abs() {
        if _negative {
            return self.negate()
        }
        return self
    }

    Result<BigFloat, Error> round(Int precisionBits, RoundingMode mode) {
        return BigFloat._round(_negative, _significand, _exponent,
            precisionBits, mode, false)
    }

    Result<BigFloat, Error> sqrt(Context context, Int precisionBits,
        RoundingMode mode) {
        if context == null {
            throw "BigFloat.sqrt: null context"
        }
        if isNegative() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigFloat.sqrt: negative value"))
        }
        if isZero() {
            return BigFloat.zero(precisionBits)
        }
        Int guardBits = precisionBits + 4
        Long halfExponent = _exponent / 2
        if _exponent < 0 && _exponent % 2 != 0 {
            halfExponent = halfExponent - 1
        }
        Long oddFactor = _exponent - halfExponent * 2
        Int scaleBits = guardBits * 2 + (oddFactor as Int)
        Result<BigInt, Error> scaled = _significand.shiftLeft(scaleBits)
        if scaled.isErr() {
            return Err(scaled.error())
        }
        Result<BigInt, Error> root = scaled.value().sqrt(context)
        if root.isErr() {
            return Err(root.error())
        }
        BigInt squared = root.value().multiply(root.value())
        Bool sticky = squared.compare(scaled.value()) != 0
        Long resultExponent = halfExponent - (guardBits as Long)
        return BigFloat._round(false, root.value(), resultExponent,
            precisionBits, mode, sticky)
    }

    Result<BigFloat, Error> exp(Context context, Int precisionBits,
        RoundingMode mode) {
        if context == null {
            throw "BigFloat.exp: null context"
        }
        if isZero() {
            return BigFloat.one(precisionBits)
        }
        Double approximate = self.toDouble()
        if approximate > 1000000.0 || approximate < -1000000.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigFloat.exp: exponent overflow"))
        }
        Int working = precisionBits + 8
        if working > 1048576 {
            working = 1048576
        }
        Result<BigFloat, Error> logTwo = BigFloat._lnTwo(context, working)
        if logTwo.isErr() {
            return Err(logTwo.error())
        }
        Result<BigFloat, Error> quotient = self.divide(logTwo.value(),
            working, RoundingMode.HalfEven)
        if quotient.isErr() {
            return Err(quotient.error())
        }
        Result<BigInt, Error> integerPart = quotient.value().toBigInt(
            context, RoundingMode.HalfEven)
        if integerPart.isErr() {
            return Err(integerPart.error())
        }
        Result<Int, Error> shiftResult = integerPart.value().toInt()
        if shiftResult.isErr() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigFloat.exp: exponent too large"))
        }
        Int shift = shiftResult.value()
        Result<BigFloat, Error> shiftValue = BigFloat.fromInt(shift, working,
            RoundingMode.HalfEven)
        if shiftValue.isErr() {
            return Err(shiftValue.error())
        }
        Result<BigFloat, Error> multiple = logTwo.value().multiply(
            shiftValue.value(), working, RoundingMode.HalfEven)
        if multiple.isErr() {
            return Err(multiple.error())
        }
        Result<BigFloat, Error> reduced = self.subtract(multiple.value(),
            working, RoundingMode.HalfEven)
        if reduced.isErr() {
            return Err(reduced.error())
        }
        Result<BigFloat, Error> series = BigFloat._expSeries(context,
            reduced.value(), working)
        if series.isErr() {
            return Err(series.error())
        }
        return series.value().scaleByPowerOfTwo(shift, precisionBits, mode)
    }

    Result<BigFloat, Error> log(Context context, Int precisionBits,
        RoundingMode mode) {
        if context == null {
            throw "BigFloat.log: null context"
        }
        if signum() <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigFloat.log: non-positive value"))
        }
        Int working = precisionBits + 8
        if working > 1048576 {
            working = 1048576
        }
        Long significandBits = _significand.bitLength()
        Long binaryExponent = _exponent + significandBits - 1
        Result<BigFloat, Error> mantissa = BigFloat._round(false,
            _significand, 0 - (significandBits - 1), working,
            RoundingMode.HalfEven, false)
        if mantissa.isErr() {
            return Err(mantissa.error())
        }
        Result<BigFloat, Error> logMantissa = BigFloat._logSeries(context,
            mantissa.value(), working)
        if logMantissa.isErr() {
            return Err(logMantissa.error())
        }
        Result<BigFloat, Error> logTwo = BigFloat._lnTwo(context, working)
        if logTwo.isErr() {
            return Err(logTwo.error())
        }
        Result<BigFloat, Error> scaledLogTwo = logTwo.value()
            .multiply(BigFloat.fromLong(binaryExponent, working,
                RoundingMode.HalfEven).value(),
                working, RoundingMode.HalfEven)
        if scaledLogTwo.isErr() {
            return Err(scaledLogTwo.error())
        }
        return logMantissa.value().add(scaledLogTwo.value(), precisionBits, mode)
    }

    Result<BigFloat, Error> pow(Context context, BigFloat exponent,
        Int precisionBits, RoundingMode mode) {
        if context == null {
            throw "BigFloat.pow: null context"
        }
        if exponent == null {
            throw "BigFloat.pow: null exponent"
        }
        if exponent.isZero() {
            return BigFloat.one(precisionBits)
        }
        if isZero() {
            if exponent.isNegative() {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "BigFloat.pow: zero to negative exponent"))
            }
            return BigFloat.zero(precisionBits)
        }
        if exponent.isInteger() {
            Result<BigInt, Error> integerValue = exponent.toBigInt(context,
                RoundingMode.HalfEven)
            if integerValue.isOk() {
                Result<Int, Error> integerResult = integerValue.value().toInt()
                if integerResult.isOk() {
                    return self.powInteger(context, integerResult.value(),
                        precisionBits, mode)
                }
            }
        }
        if isNegative() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigFloat.pow: negative base with non-integer exponent"))
        }
        Int working = precisionBits + 8
        if working > 1048576 {
            working = 1048576
        }
        Result<BigFloat, Error> logarithm = self.log(context, working,
            RoundingMode.HalfEven)
        if logarithm.isErr() {
            return Err(logarithm.error())
        }
        Result<BigFloat, Error> product = exponent.multiply(logarithm.value(),
            working, RoundingMode.HalfEven)
        if product.isErr() {
            return Err(product.error())
        }
        return product.value().exp(context, precisionBits, mode)
    }

    Bool isInteger() {
        if isZero() {
            return true
        }
        if _exponent >= 0 {
            return true
        }
        Long neededBits = 0 - _exponent
        if neededBits > _significand.bitLength() {
            return false
        }
        Result<BigInt, Error> mask = BigInt.one().shiftLeft(neededBits as Int)
        if mask.isErr() {
            return false
        }
        Result<BigInt, Error> remainder = _significand.mod(mask.value())
        if remainder.isErr() {
            return false
        }
        return remainder.value().isZero()
    }

    Double toDouble() {
        Double magnitude = _significand.toDouble()
        Double result = magnitude * pow(2.0, _exponent as Double)
        if _negative {
            return 0.0 - result
        }
        return result
    }

    Result<BigInt, Error> toBigInt(Context context, RoundingMode mode) {
        if context == null {
            throw "BigFloat.toBigInt: null context"
        }
        if mode == null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigFloat.toBigInt: null rounding mode"))
        }
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled,
                "BigFloat.toBigInt: cancelled"))
        }
        if isZero() {
            return Ok(BigInt.zero())
        }
        if _exponent >= 0 {
            Result<BigInt, Error> shifted = _significand.shiftLeft(
                _exponent as Int)
            if shifted.isErr() {
                return Err(shifted.error())
            }
            if _negative {
                return Ok(shifted.value().negate())
            }
            return Ok(shifted.value())
        }
        Result<BigInt, Error> divisor = BigInt.one().shiftLeft(
            (0 - _exponent) as Int)
        if divisor.isErr() {
            return Err(divisor.error())
        }
        Result<Pair<BigInt, BigInt>, Error> division =
            _significand.divideAndRemainder(divisor.value())
        if division.isErr() {
            return Err(division.error())
        }
        BigInt quotient = division.value().first
        BigInt remainder = division.value().second
        Result<BigInt, Error> rounded = BigFloat._roundIntegerQuotient(
            quotient, remainder, divisor.value(), _negative, mode)
        if rounded.isErr() {
            return Err(rounded.error())
        }
        if _negative {
            return Ok(rounded.value().negate())
        }
        return Ok(rounded.value())
    }

    Result<String, Error> toDecimalString(Context context,
        Int fractionalDigits, RoundingMode mode) {
        if context == null {
            throw "BigFloat.toDecimalString: null context"
        }
        if fractionalDigits < 0 || fractionalDigits > 10000 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigFloat.toDecimalString: fractional digits out of range"))
        }
        if mode == null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigFloat.toDecimalString: null rounding mode"))
        }
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled,
                "BigFloat.toDecimalString: cancelled"))
        }
        BigInt powerOfFive = BigInt.one()
        Int index = 0
        while index < fractionalDigits {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "BigFloat.toDecimalString: cancelled"))
            }
            powerOfFive = powerOfFive.multiply(BigInt.fromInt(5))
            index = index + 1
        }
        BigInt numerator = _significand.multiply(powerOfFive)
        Long binaryExponent = _exponent + (fractionalDigits as Long)
        BigInt denominator = BigInt.one()
        if binaryExponent >= 0 {
            Result<BigInt, Error> shifted = numerator.shiftLeft(
                binaryExponent as Int)
            if shifted.isErr() {
                return Err(shifted.error())
            }
            numerator = shifted.value()
        } else {
            Result<BigInt, Error> shifted = denominator.shiftLeft(
                (0 - binaryExponent) as Int)
            if shifted.isErr() {
                return Err(shifted.error())
            }
            denominator = shifted.value()
        }
        Result<Pair<BigInt, BigInt>, Error> division =
            numerator.divideAndRemainder(denominator)
        if division.isErr() {
            return Err(division.error())
        }
        Result<BigInt, Error> rounded = BigFloat._roundIntegerQuotient(
            division.value().first, division.value().second, denominator,
            _negative, mode)
        if rounded.isErr() {
            return Err(rounded.error())
        }
        if rounded.value().isZero() {
            return Ok("0")
        }
        String digits = rounded.value().toString()
        while digits.length() <= fractionalDigits {
            digits = "0" + digits
        }
        Int split = digits.length() - fractionalDigits
        String result = digits
        if fractionalDigits > 0 {
            result = digits.substring(0, split) + "."
                + digits.substring(split, digits.length() - split)
        }
        if _negative {
            return Ok("-" + result)
        }
        return Ok(result)
    }

    String toString() {
        if isZero() {
            return "0p0"
        }
        String text = _significand.toString() + "p" + str(_exponent)
        if _negative {
            return "-" + text
        }
        return text
    }

    Int compare(BigFloat other) {
        if other == null {
            throw "BigFloat.compare: null other"
        }
        if isZero() {
            if other.isZero() {
                return 0
            }
            if other._negative {
                return 1
            }
            return -1
        }
        if other.isZero() {
            if _negative {
                return -1
            }
            return 1
        }
        if _negative != other._negative {
            if _negative {
                return -1
            }
            return 1
        }
        Long leftTop = _significand.bitLength() + _exponent
        Long rightTop = other._significand.bitLength() + other._exponent
        Int magnitude = 0
        if leftTop < rightTop {
            magnitude = -1
        } else if leftTop > rightTop {
            magnitude = 1
        } else {
            Long commonExponent = _exponent
            if other._exponent < commonExponent {
                commonExponent = other._exponent
            }
            Result<BigInt, Error> left = _significand.shiftLeft(
                (_exponent - commonExponent) as Int)
            Result<BigInt, Error> right = other._significand.shiftLeft(
                (other._exponent - commonExponent) as Int)
            if left.isErr() || right.isErr() {
                throw "BigFloat.compare: exponent difference too large"
            }
            magnitude = left.value().compare(right.value())
        }
        if _negative {
            return 0 - magnitude
        }
        return magnitude
    }

    Bool equals(BigFloat other) {
        if other == null {
            return false
        }
        return self.compare(other) == 0
    }

    Result<BigFloat, Error> powInteger(Context context, Int exponent,
        Int precisionBits, RoundingMode mode) {
        if context == null {
            throw "BigFloat.powInteger: null context"
        }
        Bool negativeExponent = exponent < 0
        Long remaining = exponent as Long
        if negativeExponent {
            remaining = 0L - remaining
        }
        Int working = precisionBits + 8
        if working > 1048576 {
            working = 1048576
        }
        BigFloat result = BigFloat.one(working).value()
        BigFloat base = self.round(working, RoundingMode.HalfEven).value()
        while remaining > 0 {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "BigFloat.powInteger: cancelled"))
            }
            if remaining % 2 == 1 {
                result = result.multiply(base, working,
                    RoundingMode.HalfEven).value()
            }
            remaining = remaining / 2
            if remaining > 0 {
                base = base.multiply(base, working,
                    RoundingMode.HalfEven).value()
            }
        }
        if negativeExponent {
            result = BigFloat.one(working).value().divide(result, working,
                RoundingMode.HalfEven).value()
        }
        return result.round(precisionBits, mode)
    }

    Result<BigFloat, Error> scaleByPowerOfTwo(Int shift, Int precisionBits,
        RoundingMode mode) {
        if isZero() {
            return BigFloat.zero(precisionBits)
        }
        Long exponent = _exponent + (shift as Long)
        if exponent < -1000000000 || exponent > 1000000000 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigFloat.scaleByPowerOfTwo: exponent out of range"))
        }
        return BigFloat._round(_negative, _significand, exponent,
            precisionBits, mode, false)
    }

    static Result<BigFloat, Error> _round(Bool negative, BigInt magnitude,
        Long exponent, Int precisionBits, RoundingMode mode, Bool sticky) {
        if precisionBits < 2 || precisionBits > 1048576 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigFloat: precision out of range"))
        }
        if mode == null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigFloat: null rounding mode"))
        }
        if magnitude == null {
            throw "BigFloat: null magnitude"
        }
        if magnitude.isZero() {
            return BigFloat.zero(precisionBits)
        }
        BigInt kept = magnitude
        Long keptExponent = exponent
        Bool discardedNonZero = sticky
        Bool half = false
        Bool aboveHalf = false
        Long bitLength = magnitude.bitLength()
        if bitLength > (precisionBits as Long) {
            Long dropLong = bitLength - (precisionBits as Long)
            if dropLong > 2147483647 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "BigFloat: significand too large to round"))
            }
            Int dropBits = dropLong as Int
            Result<BigInt, Error> shifted = magnitude.shiftRight(dropBits)
            if shifted.isErr() {
                return Err(shifted.error())
            }
            kept = shifted.value()
            Result<BigInt, Error> restored = kept.shiftLeft(dropBits)
            if restored.isErr() {
                return Err(restored.error())
            }
            BigInt discarded = magnitude.subtract(restored.value())
            discardedNonZero = !discarded.isZero() || sticky
            Result<BigInt, Error> halfValue = BigInt.one().shiftLeft(dropBits - 1)
            if halfValue.isErr() {
                return Err(halfValue.error())
            }
            Int comparison = discarded.compare(halfValue.value())
            if comparison > 0 {
                half = true
                aboveHalf = true
            } else if comparison == 0 {
                half = true
                aboveHalf = sticky
            }
            keptExponent = exponent + (dropBits as Long)
        }
        Bool roundAway = false
        if mode == RoundingMode.Down {
            roundAway = false
        } else if mode == RoundingMode.Up {
            roundAway = discardedNonZero
        } else if mode == RoundingMode.Ceiling {
            roundAway = discardedNonZero && !negative
        } else if mode == RoundingMode.Floor {
            roundAway = discardedNonZero && negative
        } else if mode == RoundingMode.HalfUp {
            roundAway = half
        } else if mode == RoundingMode.HalfDown {
            roundAway = aboveHalf
        } else if mode == RoundingMode.HalfEven {
            if aboveHalf {
                roundAway = true
            } else if half {
                roundAway = kept.testBit(0)
            }
        } else {
            if discardedNonZero {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "BigFloat: rounding required"))
            }
        }
        if roundAway {
            kept = kept.add(BigInt.one())
            if kept.bitLength() > (precisionBits as Long) {
                Result<BigInt, Error> shifted = kept.shiftRight(1)
                if shifted.isErr() {
                    return Err(shifted.error())
                }
                kept = shifted.value()
                keptExponent = keptExponent + 1
            }
        }
        if keptExponent < -1000000000 || keptExponent > 1000000000 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigFloat: exponent out of range"))
        }
        return Ok(new BigFloat(negative, kept, keptExponent, precisionBits))
    }

    static Result<BigFloat, Error> _fromDecimal(Bool negative,
        BigInt coefficient, Int decimalExponent, Int precisionBits,
        RoundingMode mode) {
        if coefficient.isZero() {
            return BigFloat.zero(precisionBits)
        }
        BigInt numerator = coefficient
        BigInt denominator = BigInt.one()
        Int remaining = decimalExponent
        if remaining >= 0 {
            while remaining > 0 {
                numerator = numerator.multiply(BigInt.fromInt(10))
                remaining = remaining - 1
            }
        } else {
            remaining = 0 - remaining
            while remaining > 0 {
                denominator = denominator.multiply(BigInt.fromInt(10))
                remaining = remaining - 1
            }
        }
        return BigFloat._fromRational(negative, numerator, denominator,
            precisionBits, mode)
    }

    static Result<BigFloat, Error> _fromRational(Bool negative,
        BigInt numerator, BigInt denominator, Int precisionBits,
        RoundingMode mode) {
        if numerator.isZero() {
            return BigFloat.zero(precisionBits)
        }
        Long lengthDifference = denominator.bitLength() - numerator.bitLength()
        Int extra = 0
        if lengthDifference > 0 {
            extra = lengthDifference as Int
        }
        Int shift = precisionBits + 4 + extra
        Result<BigInt, Error> scaled = numerator.shiftLeft(shift)
        if scaled.isErr() {
            return Err(scaled.error())
        }
        Result<Pair<BigInt, BigInt>, Error> division =
            scaled.value().divideAndRemainder(denominator)
        if division.isErr() {
            return Err(division.error())
        }
        Bool sticky = !division.value().second.isZero()
        return BigFloat._round(negative, division.value().first,
            0L - (shift as Long), precisionBits, mode, sticky)
    }

    static Result<BigFloat, Error> _expSeries(Context context,
        BigFloat value, Int working) {
        BigFloat sum = BigFloat.one(working).value()
        BigFloat term = BigFloat.one(working).value()
        Int index = 1
        while index <= 100000 {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "BigFloat.exp: cancelled"))
            }
            Result<BigFloat, Error> nextTerm = term.multiply(value, working,
                RoundingMode.HalfEven)
            if nextTerm.isErr() {
                return Err(nextTerm.error())
            }
            term = nextTerm.value().divide(BigFloat.fromInt(index, working,
                RoundingMode.HalfEven).value(),
                working, RoundingMode.HalfEven).value()
            Result<BigFloat, Error> nextSum = sum.add(term, working,
                RoundingMode.HalfEven)
            if nextSum.isErr() {
                return Err(nextSum.error())
            }
            sum = nextSum.value()
            Result<BigFloat, Error> threshold = BigFloat.one(working).value()
                .scaleByPowerOfTwo(0 - working - 4, working,
                    RoundingMode.HalfEven)
            if threshold.isErr() {
                return Err(threshold.error())
            }
            if term.abs().compare(threshold.value()) < 0 {
                return Ok(sum)
            }
            index = index + 1
        }
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "BigFloat.exp: series did not converge"))
    }

    static Result<BigFloat, Error> _atanhSeries(Context context,
        BigFloat value, Int working) {
        BigFloat sum = value
        BigFloat term = value
        Result<BigFloat, Error> squared = value.multiply(value, working,
            RoundingMode.HalfEven)
        if squared.isErr() {
            return Err(squared.error())
        }
        Int index = 1
        while index <= 100000 {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "BigFloat.log: cancelled"))
            }
            Result<BigFloat, Error> nextTerm = term.multiply(squared.value(),
                working, RoundingMode.HalfEven)
            if nextTerm.isErr() {
                return Err(nextTerm.error())
            }
            term = nextTerm.value()
            Result<BigFloat, Error> addend = term.divide(
                BigFloat.fromInt(index * 2 + 1, working,
                    RoundingMode.HalfEven).value(), working,
                RoundingMode.HalfEven)
            if addend.isErr() {
                return Err(addend.error())
            }
            Result<BigFloat, Error> nextSum = sum.add(addend.value(), working,
                RoundingMode.HalfEven)
            if nextSum.isErr() {
                return Err(nextSum.error())
            }
            sum = nextSum.value()
            Result<BigFloat, Error> threshold = BigFloat.one(working).value()
                .scaleByPowerOfTwo(0 - working - 4, working,
                    RoundingMode.HalfEven)
            if threshold.isErr() {
                return Err(threshold.error())
            }
            if addend.value().abs().compare(threshold.value()) < 0 {
                return Ok(sum)
            }
            index = index + 1
        }
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "BigFloat.log: series did not converge"))
    }

    static Result<BigFloat, Error> _lnTwo(Context context, Int working) {
        Int halfWorking = working + 4
        if halfWorking > 1048576 {
            halfWorking = 1048576
        }
        Result<BigFloat, Error> oneThird = BigFloat._fromRational(false,
            BigInt.one(), BigInt.fromInt(3), halfWorking,
            RoundingMode.HalfEven)
        if oneThird.isErr() {
            return Err(oneThird.error())
        }
        Result<BigFloat, Error> series = BigFloat._atanhSeries(context,
            oneThird.value(), halfWorking)
        if series.isErr() {
            return Err(series.error())
        }
        Result<BigFloat, Error> doubled = series.value().multiply(
            BigFloat.fromInt(2, halfWorking, RoundingMode.HalfEven).value(),
            halfWorking,
            RoundingMode.HalfEven)
        if doubled.isErr() {
            return Err(doubled.error())
        }
        return doubled.value().round(working, RoundingMode.HalfEven)
    }

    static Result<BigFloat, Error> _logSeries(Context context,
        BigFloat value, Int working) {
        Result<BigFloat, Error> numerator = value.subtract(
            BigFloat.one(working).value(), working, RoundingMode.HalfEven)
        if numerator.isErr() {
            return Err(numerator.error())
        }
        Result<BigFloat, Error> denominator = value.add(
            BigFloat.one(working).value(), working, RoundingMode.HalfEven)
        if denominator.isErr() {
            return Err(denominator.error())
        }
        Result<BigFloat, Error> ratio = numerator.value().divide(
            denominator.value(), working, RoundingMode.HalfEven)
        if ratio.isErr() {
            return Err(ratio.error())
        }
        Result<BigFloat, Error> series = BigFloat._atanhSeries(context,
            ratio.value(), working)
        if series.isErr() {
            return Err(series.error())
        }
        return series.value().multiply(
            BigFloat.fromInt(2, working, RoundingMode.HalfEven).value(),
            working,
            RoundingMode.HalfEven)
    }

    static Result<BigInt, Error> _roundIntegerQuotient(BigInt quotient,
        BigInt remainder, BigInt divisor, Bool negative, RoundingMode mode) {
        if remainder.isZero() {
            return Ok(quotient)
        }
        if mode == RoundingMode.Down {
            return Ok(quotient)
        }
        if mode == RoundingMode.Unnecessary {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigFloat: rounding required"))
        }
        BigInt doubled = remainder.multiply(BigInt.fromInt(2))
        Int comparison = doubled.compare(divisor)
        Bool roundAway = false
        if mode == RoundingMode.Up {
            roundAway = true
        } else if mode == RoundingMode.Ceiling {
            roundAway = !negative
        } else if mode == RoundingMode.Floor {
            roundAway = negative
        } else if mode == RoundingMode.HalfUp {
            roundAway = comparison >= 0
        } else if mode == RoundingMode.HalfDown {
            roundAway = comparison > 0
        } else if mode == RoundingMode.HalfEven {
            if comparison > 0 {
                roundAway = true
            } else if comparison == 0 {
                roundAway = quotient.testBit(0)
            }
        }
        if roundAway {
            return Ok(quotient.add(BigInt.one()))
        }
        return Ok(quotient)
    }
}
```
