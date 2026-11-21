# `BigInt`

| 项 | 值 |
| --- | --- |
| 类型 | `class BigInt` |
| 包 | `xdk.numerics` |
| 稳定性 | `preview` |
| 依赖 | `BasicError`、`ErrorKind`、`Context`、`Pair` |

---

## 1. 定位

任意精度有符号整数：精确加减乘除、余数、模、幂、模幂、模逆、最大公约数、最小公倍数、位移、位测试、整数开方与字符串转换。

不做：有理数、浮点、模环类型、素数判定、随机数、密码学协议；不做从 `Double` 的隐式转换。

---

## 2. 设计逻辑

- 不可变值对象；符号与绝对值分离，绝对值用小端 16 位 limb 列表存储。
- 所有算术精确；没有溢出回绕，只有分配失败或参数错误。
- 除法采用“向零截断”语义：商向零取整，余数与被除数同号；另提供 `mod` 返回非负余数。
- `divideAndRemainder` 一次遍历同时得到商和余数；`divide`/`remainder` 委托它，避免两套除法。
- 需要迭代或可能极慢的操作 `pow`/`modPow`/`sqrt` 首参 `Context`；普通加减乘除是单次操作，不接 `Context`。
- 不从 `Double` 隐式构造；`fromDoubleExact` 只接受 Long 范围内的整数值 `Double`，且不做舍入。
- 所有公开入口复制输入列表；内部 limb 列表不逃逸。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_negative` | `Bool` | 符号；零为 `false` |
| `_limbs` | `List<Long>` | 小端绝对值，基数 65536；每个元素 0..65535 |

不变量：

- 零当且仅当 `_limbs` 为空；零的 `_negative` 必须为 `false`。
- 非零时最高 limb 不能为 0；构造器统一裁剪前导零。
- 值 = `(-1)^_negative * Σ _limbs[index] * 65536^index`。
- 列表不可变；没有任何方法原地修改 `_limbs`。
- limb 索引与位索引都使用 `Int`；位长用 `Long` 返回，避免大数位长溢出。

---

## 4. 生命周期

不可变；无 close；无资源句柄；可跨任务共享。构造后不再改变。

---

## 5. 构造契约

构造器私有；公共入口如下。`null` 参数是合同错误（panic）；非法文本/域是 `InvalidArgument`。

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `BigInt.zero()` | 无 | 0 | 无 |
| `BigInt.one()` | 无 | 1 | 无 |
| `BigInt.fromInt(Int value)` | `value` | 任意 `Int` | 无 |
| `BigInt.fromLong(Long value)` | `value` | 任意 `Long`，含 `Long.MIN` | 无 |
| `BigInt.fromDoubleExact(Double value)` | `value` | 有限、整数值、在 Long 范围 | `InvalidArgument` |
| `BigInt.parse(String text, Int maximumDigits)` | `text` 为 `[+-]digits`；`maximumDigits >= 1` | 非空、只含十进制数字 | `InvalidArgument` |

`parse` 的 `maximumDigits` 是安全上限：数字个数超过该值立即失败，避免不可信文本造成超大分配。

---

## 6. 字段表

见 §3；字段全部私有、构造后只读。

---

## 7. 方法总表 / 详表

### 7.1 方法总表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `signum` | 符号 | 无 | `Int` | 无 |
| `isZero` | 是否零 | 无 | `Bool` | 无 |
| `isNegative` | 是否负 | 无 | `Bool` | 无 |
| `bitLength` | 二进制位长 | 无 | `Long` | 无 |
| `add` | 加 | `BigInt other` | `BigInt` | null → panic |
| `subtract` | 减 | `BigInt other` | `BigInt` | null → panic |
| `multiply` | 乘 | `BigInt other` | `BigInt` | null → panic |
| `negate` | 取负 | 无 | `BigInt` | 无 |
| `abs` | 绝对值 | 无 | `BigInt` | 无 |
| `divide` | 商（向零） | `BigInt divisor` | `Result<BigInt, Error>` | null → panic；除零 → `InvalidArgument` |
| `remainder` | 余数（与被除数同号） | `BigInt divisor` | `Result<BigInt, Error>` | 同上 |
| `divideAndRemainder` | 商与余数 | `BigInt divisor` | `Result<Pair<BigInt, BigInt>, Error>` | 同上 |
| `mod` | 非负余数 | `BigInt modulus` | `Result<BigInt, Error>` | null → panic；`modulus <= 0` → `InvalidArgument` |
| `pow` | 非负整数幂 | `Context context, Int exponent` | `Result<BigInt, Error>` | null context → panic；负指数/取消 → `InvalidArgument`/`Cancelled` |
| `modPow` | 模幂 | `Context context, BigInt exponent, BigInt modulus` | `Result<BigInt, Error>` | 负指数/非正模/取消 |
| `modInverse` | 模逆 | `BigInt modulus` | `Result<BigInt, Error>` | 非正模/不可逆 |
| `gcd` | 最大公约数 | `BigInt other` | `BigInt` | null → panic |
| `lcm` | 最小公倍数 | `BigInt other` | `BigInt` | null → panic |
| `shiftLeft` | 左移 | `Int bitCount` | `Result<BigInt, Error>` | 负值/过大 → `InvalidArgument` |
| `shiftRight` | 右移（向零截断） | `Int bitCount` | `Result<BigInt, Error>` | 负值 → `InvalidArgument` |
| `testBit` | 位测试 | `Int bitIndex` | `Bool` | 负索引 → panic |
| `sqrt` | 整数平方根（floor） | `Context context` | `Result<BigInt, Error>` | 负数/取消 |
| `compare` | 比较 | `BigInt other` | `Int` | null → panic |
| `equals` | 值相等 | `BigInt other` | `Bool` | null → false |
| `toInt` | 转 `Int` | 无 | `Result<Int, Error>` | 超出范围 → `InvalidArgument` |
| `toLong` | 转 `Long` | 无 | `Result<Long, Error>` | 超出范围 → `InvalidArgument` |
| `toDouble` | 转 `Double` | 无 | `Double` | 无；可能舍入或 `Inf` |
| `toString` | 十进制文本 | 无 | `String` | 无 |

### 7.2 关键语义

- `divide`/`remainder`：`(-7).divide(3)` 得 `-2`，`(-7).remainder(3)` 得 `-1`。
- `mod`：`(-7).mod(3)` 得 `2`；`modulus` 必须为正。
- `pow`：`0^0` 得 `1`；`exponent < 0` 失败。
- `modPow`：`exponent >= 0`，`modulus > 0`；结果在 `[0, modulus)`。
- `shiftRight` 对负值向零截断，例如 `(-5).shiftRight(1)` 得 `-2`。
- `toDouble` 可能丢失精度或溢出为 `Inf`；需要精确值时必须用 `toString`/`toLong`。
- `compare` 返回 `-1`/`0`/`1`。

---

## 8. 使用的技术

- 符号-绝对值表示；
- 小端 16 位 limb 与基数 65536；
- 学校乘法；
- 二进制长除法；
- 平方-乘幂与模幂；
- 扩展欧几里得求模逆；
- 牛顿法整数开方；
- 十进制分块转换；
- 协作取消检查。

---

## 9. 需要的支撑

- 语言：class、`Bool`、`Int`、`Long`、`List`、`String`、`Result`；
- 数学：`floor`、`isNaN`、`isInf`；
- 错误：`BasicError`、`ErrorKind.InvalidArgument`、`ErrorKind.Cancelled`；
- 执行：`Context.isCancelled`；
- 容器：`Pair`、`List.copy`、`List.push`、`List.remove`、`List.set`。

---

## 10. 依赖的特性/接口/类

[`Context`](../../core/execution/Context.md)、[`Pair`](../../core/collections/Pair.md)、[`BasicError`](../../core/errors/BasicError.md)、[`ErrorKind`](../../core/errors/ErrorKind.md)。

---

## 11. 所有权与并发

不可变值对象；构造时复制 limb 列表；访问器不暴露内部列表。可跨任务共享；无锁；无 close。`Context` 只用于取消查询，不保存。相等是数值相等，可作 `Map` 键（实现方需提供稳定哈希）。

---

## 12. 示例与反例

正确：`BigInt.parse("12345678901234567890", 32)`；`left.add(right)`；`left.divideAndRemainder(right)` 处理 `Err`；`left.modPow(context, exponent, modulus)`。  
反例：把 `Double` 直接赋给 `BigInt`；期望 `divide` 对负数向负无穷取整；忽略 `divide` 的 `Err`；用 `toDouble` 做精确比较；把 `maximumDigits` 设为 0。

---

## 13. 测试/场景义务

零/正/负/`Long.MIN`；构造与裁剪前导零；parse 的符号/前导零/空串/非法字符/超长；加减乘的符号组合与进位；乘法的长进位；除法/余数的正负组合与除零；`mod` 的非负性；`divideAndRemainder` 恒等式；`pow` 的 0 次/1 次/大指数/负指数；`modPow` 与手算一致；`modInverse` 的乘积模 1；`gcd`/`lcm` 的零与负数；位移的边界与符号；`testBit`；`sqrt` 的完全平方与非完全平方；`toInt`/`toLong` 溢出；`toDouble` 的舍入；`toString` 往返；取消。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class BigInt {
    final Bool _negative
    final List<Long> _limbs

    private BigInt(Bool negative, List<Long> limbs) {
        if limbs == null {
            throw "BigInt: null limbs"
        }
        List<Long> copied = limbs.copy()
        while copied.length() > 0 {
            if copied.get(copied.length() - 1) != 0 {
                break
            }
            copied.remove(copied.length() - 1)
        }
        Bool negativeValue = negative
        if copied.length() == 0 {
            negativeValue = false
        }
        _negative = negativeValue
        _limbs = copied
    }

    static BigInt zero() {
        return new BigInt(false, [])
    }

    static BigInt one() {
        return new BigInt(false, [1])
    }

    static BigInt fromInt(Int value) {
        return BigInt.fromLong(value as Long)
    }

    static BigInt fromLong(Long value) {
        if value == -9223372036854775808 {
            return new BigInt(true, [0, 0, 0, 32768])
        }
        Bool negative = value < 0
        Long magnitude = value
        if negative {
            magnitude = 0 - value
        }
        List<Long> limbs = []
        while magnitude > 0 {
            limbs.push(magnitude % 65536)
            magnitude = magnitude / 65536
        }
        return new BigInt(negative, limbs)
    }

    static Result<BigInt, Error> fromDoubleExact(Double value) {
        if isNaN(value) || isInf(value) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.fromDoubleExact: non-finite value"))
        }
        if value != floor(value) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.fromDoubleExact: non-integral value"))
        }
        if value >= 9223372036854775808.0 || value < -9223372036854775808.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.fromDoubleExact: out of long range"))
        }
        return Ok(BigInt.fromLong(value as Long))
    }

    static Result<BigInt, Error> parse(String text, Int maximumDigits) {
        if text == null || text == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.parse: empty text"))
        }
        if maximumDigits < 1 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.parse: invalid maximum digits"))
        }
        Int index = 0
        Bool negative = false
        if text.charAt(0) == '-' {
            negative = true
            index = 1
        } else if text.charAt(0) == '+' {
            index = 1
        }
        if index >= text.length() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.parse: missing digits"))
        }
        List<Long> limbs = []
        Int digitCount = 0
        while index < text.length() {
            Char character = text.charAt(index)
            if character < '0' || character > '9' {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "BigInt.parse: invalid character"))
            }
            digitCount = digitCount + 1
            if digitCount > maximumDigits {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "BigInt.parse: too many digits"))
            }
            Long digit = ((character as Int) - 48) as Long
            limbs = BigInt._multiplyAddMagnitude(limbs, 10, digit)
            index = index + 1
        }
        return Ok(new BigInt(negative, limbs))
    }

    Int signum() {
        if _limbs.length() == 0 {
            return 0
        }
        if _negative {
            return -1
        }
        return 1
    }

    Bool isZero() {
        return _limbs.length() == 0
    }

    Bool isNegative() {
        return _negative
    }

    Long bitLength() {
        return BigInt._bitLengthMagnitude(_limbs)
    }

    BigInt add(BigInt other) {
        if other == null {
            throw "BigInt.add: null other"
        }
        if _negative == other._negative {
            return new BigInt(_negative,
                BigInt._addMagnitude(_limbs, other._limbs))
        }
        Int comparison = BigInt._compareMagnitude(_limbs, other._limbs)
        if comparison == 0 {
            return BigInt.zero()
        }
        if comparison > 0 {
            return new BigInt(_negative,
                BigInt._subtractMagnitude(_limbs, other._limbs))
        }
        return new BigInt(other._negative,
            BigInt._subtractMagnitude(other._limbs, _limbs))
    }

    BigInt subtract(BigInt other) {
        if other == null {
            throw "BigInt.subtract: null other"
        }
        return self.add(other.negate())
    }

    BigInt multiply(BigInt other) {
        if other == null {
            throw "BigInt.multiply: null other"
        }
        if isZero() || other.isZero() {
            return BigInt.zero()
        }
        Int leftCount = _limbs.length()
        Int rightCount = other._limbs.length()
        Long totalCount = (leftCount as Long) + (rightCount as Long)
        if totalCount > 2147483647 {
            throw "BigInt.multiply: result too large"
        }
        List<Long> result = []
        Long clearIndex = 0
        while clearIndex < totalCount {
            result.push(0)
            clearIndex = clearIndex + 1
        }
        Int leftIndex = 0
        while leftIndex < leftCount {
            Long carry = 0
            Int rightIndex = 0
            while rightIndex < rightCount {
                Int position = leftIndex + rightIndex
                Long product = result.get(position)
                    + _limbs.get(leftIndex) * other._limbs.get(rightIndex)
                    + carry
                result.set(position, product % 65536)
                carry = product / 65536
                rightIndex = rightIndex + 1
            }
            Int position = leftIndex + rightCount
            while carry != 0 {
                if position >= result.length() {
                    result.push(carry % 65536)
                    carry = carry / 65536
                } else {
                    Long sum = result.get(position) + carry
                    result.set(position, sum % 65536)
                    carry = sum / 65536
                }
                position = position + 1
            }
            leftIndex = leftIndex + 1
        }
        return new BigInt(_negative != other._negative, result)
    }

    BigInt negate() {
        if isZero() {
            return BigInt.zero()
        }
        return new BigInt(!_negative, _limbs.copy())
    }

    BigInt abs() {
        if _negative {
            return self.negate()
        }
        return self
    }

    Result<BigInt, Error> divide(BigInt divisor) {
        Result<Pair<BigInt, BigInt>, Error> result =
            self.divideAndRemainder(divisor)
        if result.isErr() {
            return Err(result.error())
        }
        return Ok(result.value().first)
    }

    Result<BigInt, Error> remainder(BigInt divisor) {
        Result<Pair<BigInt, BigInt>, Error> result =
            self.divideAndRemainder(divisor)
        if result.isErr() {
            return Err(result.error())
        }
        return Ok(result.value().second)
    }

    Result<Pair<BigInt, BigInt>, Error> divideAndRemainder(BigInt divisor) {
        if divisor == null {
            throw "BigInt.divideAndRemainder: null divisor"
        }
        if divisor.isZero() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.divideAndRemainder: division by zero"))
        }
        if self.bitLength() > 2147483647 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.divideAndRemainder: dividend too large"))
        }
        Pair<List<Long>, List<Long>> magnitude =
            BigInt._divideMagnitude(_limbs, divisor._limbs)
        BigInt quotient = new BigInt(_negative != divisor._negative,
            magnitude.first)
        BigInt remainder = new BigInt(_negative, magnitude.second)
        return Ok(new Pair<BigInt, BigInt>(quotient, remainder))
    }

    Result<BigInt, Error> mod(BigInt modulus) {
        if modulus == null {
            throw "BigInt.mod: null modulus"
        }
        if modulus.signum() <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.mod: modulus must be positive"))
        }
        Result<BigInt, Error> remainderResult = self.remainder(modulus)
        if remainderResult.isErr() {
            return Err(remainderResult.error())
        }
        BigInt remainderValue = remainderResult.value()
        if remainderValue.isNegative() {
            return Ok(remainderValue.add(modulus))
        }
        return Ok(remainderValue)
    }

    Result<BigInt, Error> pow(Context context, Int exponent) {
        if context == null {
            throw "BigInt.pow: null context"
        }
        if exponent < 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.pow: negative exponent"))
        }
        BigInt result = BigInt.one()
        BigInt base = self
        Int remaining = exponent
        while remaining > 0 {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "BigInt.pow: cancelled"))
            }
            if remaining % 2 == 1 {
                result = result.multiply(base)
            }
            remaining = remaining / 2
            if remaining > 0 {
                base = base.multiply(base)
            }
        }
        return Ok(result)
    }

    Result<BigInt, Error> modPow(Context context, BigInt exponent,
        BigInt modulus) {
        if context == null {
            throw "BigInt.modPow: null context"
        }
        if exponent == null || modulus == null {
            throw "BigInt.modPow: null argument"
        }
        if exponent.isNegative() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.modPow: negative exponent"))
        }
        if modulus.signum() <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.modPow: modulus must be positive"))
        }
        Long exponentBits = exponent.bitLength()
        if exponentBits > 2147483647 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.modPow: exponent too large"))
        }
        Result<BigInt, Error> baseResult = self.mod(modulus)
        if baseResult.isErr() {
            return Err(baseResult.error())
        }
        BigInt result = BigInt.one().mod(modulus).value()
        BigInt base = baseResult.value()
        Int exponentBitCount = exponentBits as Int
        Int bitIndex = 0
        while bitIndex < exponentBitCount {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "BigInt.modPow: cancelled"))
            }
            if exponent.testBit(bitIndex) {
                result = result.multiply(base).mod(modulus).value()
            }
            base = base.multiply(base).mod(modulus).value()
            bitIndex = bitIndex + 1
        }
        return Ok(result)
    }

    Result<BigInt, Error> modInverse(BigInt modulus) {
        if modulus == null {
            throw "BigInt.modInverse: null modulus"
        }
        if modulus.signum() <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.modInverse: modulus must be positive"))
        }
        BigInt oldRemainder = self.mod(modulus).value()
        BigInt currentRemainder = modulus
        BigInt oldCoefficient = BigInt.one()
        BigInt currentCoefficient = BigInt.zero()
        while !currentRemainder.isZero() {
            Result<Pair<BigInt, BigInt>, Error> division =
                oldRemainder.divideAndRemainder(currentRemainder)
            if division.isErr() {
                return Err(division.error())
            }
            BigInt quotient = division.value().first
            BigInt nextRemainder = division.value().second
            BigInt nextCoefficient = oldCoefficient.subtract(
                quotient.multiply(currentCoefficient))
            oldRemainder = currentRemainder
            currentRemainder = nextRemainder
            oldCoefficient = currentCoefficient
            currentCoefficient = nextCoefficient
        }
        if oldRemainder.compare(BigInt.one()) != 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.modInverse: not invertible"))
        }
        return oldCoefficient.mod(modulus)
    }

    BigInt gcd(BigInt other) {
        if other == null {
            throw "BigInt.gcd: null other"
        }
        BigInt left = self.abs()
        BigInt right = other.abs()
        while !right.isZero() {
            BigInt next = left.mod(right).value()
            left = right
            right = next
        }
        return left
    }

    BigInt lcm(BigInt other) {
        if other == null {
            throw "BigInt.lcm: null other"
        }
        if isZero() || other.isZero() {
            return BigInt.zero()
        }
        BigInt divisor = self.gcd(other)
        Result<BigInt, Error> quotient = self.abs().divide(divisor)
        if quotient.isErr() {
            throw "BigInt.lcm: internal division failure"
        }
        return quotient.value().multiply(other.abs())
    }

    Result<BigInt, Error> shiftLeft(Int bitCount) {
        if bitCount < 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.shiftLeft: negative bit count"))
        }
        Long newBitLength = self.bitLength() + (bitCount as Long)
        if newBitLength > 2147483647 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.shiftLeft: result too large"))
        }
        List<Long> shifted = BigInt._shiftLeftMagnitude(_limbs, bitCount)
        return Ok(new BigInt(_negative, shifted))
    }

    Result<BigInt, Error> shiftRight(Int bitCount) {
        if bitCount < 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.shiftRight: negative bit count"))
        }
        if bitCount as Long >= self.bitLength() {
            return Ok(BigInt.zero())
        }
        List<Long> shifted = BigInt._shiftRightMagnitude(_limbs, bitCount)
        return Ok(new BigInt(_negative, shifted))
    }

    Bool testBit(Int bitIndex) {
        if bitIndex < 0 {
            throw "BigInt.testBit: negative index"
        }
        return BigInt._testBitMagnitude(_limbs, bitIndex)
    }

    Result<BigInt, Error> sqrt(Context context) {
        if context == null {
            throw "BigInt.sqrt: null context"
        }
        if self.isNegative() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.sqrt: negative value"))
        }
        if self.isZero() {
            return Ok(BigInt.zero())
        }
        if self.bitLength() > 2147483647 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.sqrt: value too large"))
        }
        Int initialShift = ((self.bitLength() as Int) + 1) / 2
        Result<BigInt, Error> initial = BigInt.one().shiftLeft(initialShift)
        if initial.isErr() {
            return Err(initial.error())
        }
        BigInt current = initial.value()
        while true {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "BigInt.sqrt: cancelled"))
            }
            Result<BigInt, Error> division = self.divide(current)
            if division.isErr() {
                return Err(division.error())
            }
            Result<BigInt, Error> shifted = current.add(division.value()).shiftRight(1)
            if shifted.isErr() {
                return Err(shifted.error())
            }
            BigInt next = shifted.value()
            if next.compare(current) >= 0 {
                return Ok(current)
            }
            current = next
        }
    }

    Int compare(BigInt other) {
        if other == null {
            throw "BigInt.compare: null other"
        }
        if _negative != other._negative {
            if _negative {
                return -1
            }
            return 1
        }
        Int magnitude = BigInt._compareMagnitude(_limbs, other._limbs)
        if _negative {
            return 0 - magnitude
        }
        return magnitude
    }

    Bool equals(BigInt other) {
        if other == null {
            return false
        }
        return self.compare(other) == 0
    }

    Result<Int, Error> toInt() {
        Result<Long, Error> result = self.toLong()
        if result.isErr() {
            return Err(result.error())
        }
        Long value = result.value()
        if value > 2147483647 || value < -2147483648 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.toInt: out of int range"))
        }
        return Ok(value as Int)
    }

    Result<Long, Error> toLong() {
        if _negative {
            List<Long> minimumMagnitude = [0, 0, 0, 32768]
            if BigInt._compareMagnitude(_limbs, minimumMagnitude) == 0 {
                return Ok(-9223372036854775808)
            }
        }
        Long magnitude = 0
        Int index = _limbs.length() - 1
        while index >= 0 {
            Long limb = _limbs.get(index)
            if magnitude > (9223372036854775807 - limb) / 65536 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "BigInt.toLong: out of long range"))
            }
            magnitude = magnitude * 65536 + limb
            index = index - 1
        }
        if _negative {
            return Ok(0 - magnitude)
        }
        return Ok(magnitude)
    }

    Double toDouble() {
        Double result = 0.0
        Int index = _limbs.length() - 1
        while index >= 0 {
            result = result * 65536.0 + (_limbs.get(index) as Double)
            index = index - 1
        }
        if _negative {
            return 0.0 - result
        }
        return result
    }

    String toString() {
        if isZero() {
            return "0"
        }
        List<Long> remaining = _limbs.copy()
        List<Long> chunks = []
        while remaining.length() > 0 {
            Long remainder = 0
            List<Long> next = []
            Int index = remaining.length() - 1
            while index >= 0 {
                Long current = remainder * 65536 + remaining.get(index)
                Long digit = current / 1000000000
                remainder = current % 1000000000
                next.push(digit)
                index = index - 1
            }
            chunks.push(remainder)
            List<Long> normalized = []
            index = next.length() - 1
            while index >= 0 {
                normalized.push(next.get(index))
                index = index - 1
            }
            while normalized.length() > 0 {
                if normalized.get(normalized.length() - 1) != 0 {
                    break
                }
                normalized.remove(normalized.length() - 1)
            }
            remaining = normalized
        }
        String text = str(chunks.get(chunks.length() - 1))
        Int chunkIndex = chunks.length() - 2
        while chunkIndex >= 0 {
            String part = str(chunks.get(chunkIndex))
            while part.length() < 9 {
                part = "0" + part
            }
            text = text + part
            chunkIndex = chunkIndex - 1
        }
        if _negative {
            return "-" + text
        }
        return text
    }

    static List<Long> _multiplyAddMagnitude(List<Long> limbs, Long multiplier,
        Long addend) {
        List<Long> result = []
        Long carry = addend
        Int index = 0
        while index < limbs.length() || carry != 0 {
            Long limb = 0
            if index < limbs.length() {
                limb = limbs.get(index)
            }
            Long product = limb * multiplier + carry
            result.push(product % 65536)
            carry = product / 65536
            index = index + 1
        }
        return result
    }

    static List<Long> _addMagnitude(List<Long> left, List<Long> right) {
        List<Long> result = []
        Long carry = 0
        Int index = 0
        while index < left.length() || index < right.length() || carry != 0 {
            Long leftLimb = 0
            Long rightLimb = 0
            if index < left.length() {
                leftLimb = left.get(index)
            }
            if index < right.length() {
                rightLimb = right.get(index)
            }
            Long sum = leftLimb + rightLimb + carry
            result.push(sum % 65536)
            carry = sum / 65536
            index = index + 1
        }
        return result
    }

    static List<Long> _subtractMagnitude(List<Long> left, List<Long> right) {
        List<Long> result = []
        Long borrow = 0
        Int index = 0
        while index < left.length() {
            Long rightLimb = 0
            if index < right.length() {
                rightLimb = right.get(index)
            }
            Long difference = left.get(index) - rightLimb - borrow
            if difference < 0 {
                difference = difference + 65536
                borrow = 1
            } else {
                borrow = 0
            }
            result.push(difference)
            index = index + 1
        }
        return result
    }

    static Int _compareMagnitude(List<Long> left, List<Long> right) {
        if left.length() != right.length() {
            if left.length() < right.length() {
                return -1
            }
            return 1
        }
        Int index = left.length() - 1
        while index >= 0 {
            if left.get(index) < right.get(index) {
                return -1
            }
            if left.get(index) > right.get(index) {
                return 1
            }
            index = index - 1
        }
        return 0
    }

    static Long _bitLengthMagnitude(List<Long> limbs) {
        if limbs.length() == 0 {
            return 0
        }
        Long top = limbs.get(limbs.length() - 1)
        Long topBits = 0
        while top > 0 {
            top = top / 2
            topBits = topBits + 1
        }
        return (limbs.length() - 1) as Long * 16 + topBits
    }

    static Bool _testBitMagnitude(List<Long> limbs, Int bitIndex) {
        Int limbIndex = bitIndex / 16
        if limbIndex >= limbs.length() {
            return false
        }
        Long mask = BigInt._powerOfTwo(bitIndex % 16)
        Long limb = limbs.get(limbIndex)
        return (limb / mask) % 2 == 1
    }

    static void _setBitMagnitude(List<Long> limbs, Int bitIndex) {
        Int limbIndex = bitIndex / 16
        while limbs.length() <= limbIndex {
            limbs.push(0)
        }
        Long mask = BigInt._powerOfTwo(bitIndex % 16)
        limbs.set(limbIndex, limbs.get(limbIndex) + mask)
    }

    static Long _powerOfTwo(Int exponent) {
        Long result = 1
        Int index = 0
        while index < exponent {
            result = result * 2
            index = index + 1
        }
        return result
    }

    static void _shiftLeftOne(List<Long> limbs) {
        Long carry = 0
        Int index = 0
        while index < limbs.length() {
            Long value = limbs.get(index) * 2 + carry
            limbs.set(index, value % 65536)
            carry = value / 65536
            index = index + 1
        }
        if carry != 0 {
            limbs.push(carry)
        }
    }

    static Pair<List<Long>, List<Long>> _divideMagnitude(List<Long> dividend,
        List<Long> divisor) {
        List<Long> quotient = []
        Int quotientIndex = 0
        while quotientIndex < dividend.length() {
            quotient.push(0)
            quotientIndex = quotientIndex + 1
        }
        List<Long> remainder = []
        Long bitLength = BigInt._bitLengthMagnitude(dividend)
        Long bitIndex = bitLength - 1
        while bitIndex >= 0 {
            BigInt._shiftLeftOne(remainder)
            if BigInt._testBitMagnitude(dividend, bitIndex as Int) {
                if remainder.length() == 0 {
                    remainder.push(1)
                } else {
                    remainder.set(0, remainder.get(0) + 1)
                }
            }
            if BigInt._compareMagnitude(remainder, divisor) >= 0 {
                remainder = BigInt._subtractMagnitude(remainder, divisor)
                BigInt._setBitMagnitude(quotient, bitIndex as Int)
            }
            bitIndex = bitIndex - 1
        }
        return new Pair<List<Long>, List<Long>>(quotient, remainder)
    }

    static List<Long> _shiftLeftMagnitude(List<Long> limbs, Int bitCount) {
        Int limbShift = bitCount / 16
        Int bitShift = bitCount % 16
        List<Long> result = []
        Int index = 0
        while index < limbShift {
            result.push(0)
            index = index + 1
        }
        Long factor = BigInt._powerOfTwo(bitShift)
        Long carry = 0
        index = 0
        while index < limbs.length() {
            Long value = limbs.get(index) * factor + carry
            result.push(value % 65536)
            carry = value / 65536
            index = index + 1
        }
        while carry != 0 {
            result.push(carry % 65536)
            carry = carry / 65536
        }
        return result
    }

    static List<Long> _shiftRightMagnitude(List<Long> limbs, Int bitCount) {
        Int limbShift = bitCount / 16
        Int bitShift = bitCount % 16
        if limbShift >= limbs.length() {
            return []
        }
        Long divisor = BigInt._powerOfTwo(bitShift)
        List<Long> bigEndian = []
        Long carry = 0
        Int index = limbs.length() - 1
        while index >= limbShift {
            Long current = carry * 65536 + limbs.get(index)
            bigEndian.push(current / divisor)
            carry = current % divisor
            index = index - 1
        }
        List<Long> result = []
        index = bigEndian.length() - 1
        while index >= 0 {
            result.push(bigEndian.get(index))
            index = index - 1
        }
        return result
    }
}
```
