// Tier: T0；依赖：xdk.errors；稳定性：preview。
// xdk.math —— 对标 Go math + Python math/statistics/random 的基础数学包。
// 超越函数与随机数经 ext_raw 桥接 libm / xorshift64*；统计与数论为纯源码实现。
// 约定：Double 版函数沿用脑图命名；整数版加 I 后缀（absI/minI/maxI/clampI）。
package xdk.math
import xdk.errors
Double PI() {
    return 3.141592653589793
}

Double E() {
    return 2.718281828459045
}

Double TAU() {
    return 6.283185307179586
}

Double Inf() {
    return mathInfRaw()
}

Double NaN() {
    return mathNanRaw()
}

Bool isNaN(Double x) {
    return mathIsNanRaw(x) != 0
}

Bool isInf(Double x) {
    return mathIsInfRaw(x) != 0
}

// ---------- 基础运算 ----------

Double abs(Double x) {
    if x < 0.0 {
        return -x
    }
    return x
}

Int absI(Int x) {
    if x < 0 {
        return -x
    }
    return x
}

Double sign(Double x) {
    if x > 0.0 {
        return 1.0
    }
    if x < 0.0 {
        return -1.0
    }
    return x
}

Double min(Double a, Double b) {
    if a < b {
        return a
    }
    return b
}

Double max(Double a, Double b) {
    if a > b {
        return a
    }
    return b
}

Int minI(Int a, Int b) {
    if a < b {
        return a
    }
    return b
}

Int maxI(Int a, Int b) {
    if a > b {
        return a
    }
    return b
}

Double clamp(Double x, Double lo, Double hi) {
    if x < lo {
        return lo
    }
    if x > hi {
        return hi
    }
    return x
}

Int clampI(Int x, Int lo, Int hi) {
    if x < lo {
        return lo
    }
    if x > hi {
        return hi
    }
    return x
}

Double floor(Double x) {
    return mathFloorRaw(x)
}

Double ceil(Double x) {
    return mathCeilRaw(x)
}

Double round(Double x) {
    return mathRoundRaw(x)
}

Double trunc(Double x) {
    return mathTruncRaw(x)
}

Int floorToInt(Double x) {
    Double f = mathFloorRaw(x)
    return f as Int
}

Int ceilToInt(Double x) {
    Double c = mathCeilRaw(x)
    return c as Int
}

Int roundToInt(Double x) {
    Double r = mathRoundRaw(x)
    return r as Int
}

Int truncToInt(Double x) {
    Double t = mathTruncRaw(x)
    return t as Int
}

Double mod(Double a, Double b) {
    return mathModRaw(a, b)
}

// ---------- 幂指对与三角 ----------

Double pow(Double x, Double y) {
    return mathPowRaw(x, y)
}

Double sqrt(Double x) {
    return mathSqrtRaw(x)
}

Double cbrt(Double x) {
    return mathCbrtRaw(x)
}

Double exp(Double x) {
    return mathExpRaw(x)
}

Double log(Double x) {
    return mathLogRaw(x)
}

Double log2(Double x) {
    return mathLog2Raw(x)
}

Double log10(Double x) {
    return mathLog10Raw(x)
}

Double sin(Double x) {
    return mathSinRaw(x)
}

Double cos(Double x) {
    return mathCosRaw(x)
}

Double tan(Double x) {
    return mathTanRaw(x)
}

Double asin(Double x) {
    return mathAsinRaw(x)
}

Double acos(Double x) {
    return mathAcosRaw(x)
}

Double atan(Double x) {
    return mathAtanRaw(x)
}

Double atan2(Double y, Double x) {
    return mathAtan2Raw(y, x)
}

Double sinh(Double x) {
    return mathSinhRaw(x)
}

Double cosh(Double x) {
    return mathCoshRaw(x)
}

Double tanh(Double x) {
    return mathTanhRaw(x)
}

Double deg2rad(Double deg) {
    return deg * PI() / 180.0
}

Double rad2deg(Double rad) {
    return rad * 180.0 / PI()
}

// ---------- 插值 ----------

Double lerp(Double a, Double b, Double t) {
    return a + (b - a) * t
}

Double mapRange(Double x, Double a, Double b, Double c, Double d) {
    if b == a {
        return c
    }
    return c + (x - a) * (d - c) / (b - a)
}

// ---------- 数论 ----------

Int gcd(Int a, Int b) {
    Int x = absI(a)
    Int y = absI(b)
    while y != 0 {
        Int t = y
        y = x % y
        x = t
    }
    return x
}

Int lcm(Int a, Int b) {
    if a == 0 || b == 0 {
        return 0
    }
    return absI(a) / gcd(a, b) * absI(b)
}

Bool isPrime(Int n) {
    if n < 2 {
        return false
    }
    if n < 4 {
        return true
    }
    if n % 2 == 0 {
        return false
    }
    Int i = 3
    while i * i <= n {
        if n % i == 0 {
            return false
        }
        i = i + 2
    }
    return true
}

Result<Int, Error> factorial(Int n) {
    if n < 0 {
        return Err(int128Error("factorial: negative input"))
    }
    if n > 12 {
        return Err(int128Error("factorial: result exceeds Int"))
    }
    Int r = 1
    Int i = 2
    while i <= n {
        r = r * i
        i = i + 1
    }
    return Ok(r)
}


// ---------- Int128（checked 128 位算术） ----------

Int128 int128Max() {
    return 170141183460469231731687303715884105727
}

Int128 int128Min() {
    return -int128Max() - 1
}

Error int128Error(String message) {
    return new BasicError(ErrorKind.InvalidArgument, message)
}

Result<Int128, Error> addI128Checked(Int128 left, Int128 right) {
    if right > 0 && left > int128Max() - right {
        return Err(int128Error("addI128Checked: overflow"))
    }
    if right < 0 && left < int128Min() - right {
        return Err(int128Error("addI128Checked: underflow"))
    }
    return Ok(left + right)
}

Result<Int128, Error> subI128Checked(Int128 left, Int128 right) {
    if right > 0 && left < int128Min() + right {
        return Err(int128Error("subI128Checked: underflow"))
    }
    if right < 0 && left > int128Max() + right {
        return Err(int128Error("subI128Checked: overflow"))
    }
    return Ok(left - right)
}

Result<Int128, Error> mulI128Checked(Int128 left, Int128 right) {
    if left == 0 || right == 0 {
        return Ok(0)
    }
    if left > 0 {
        if right > 0 && left > int128Max() / right {
            return Err(int128Error("mulI128Checked: overflow"))
        }
        if right < 0 && right < int128Min() / left {
            return Err(int128Error("mulI128Checked: underflow"))
        }
    } else {
        if right > 0 && left < int128Min() / right {
            return Err(int128Error("mulI128Checked: underflow"))
        }
        if right < 0 && left < int128Max() / right {
            return Err(int128Error("mulI128Checked: overflow"))
        }
    }
    return Ok(left * right)
}

Result<Int128, Error> divI128Checked(Int128 left, Int128 right) {
    if right == 0 {
        return Err(int128Error("divI128Checked: division by zero"))
    }
    if left == int128Min() && right == -1 {
        return Err(int128Error("divI128Checked: overflow"))
    }
    return Ok(left / right)
}

Result<Int128, Error> modI128Checked(Int128 left, Int128 right) {
    if right == 0 {
        return Err(int128Error("modI128Checked: modulo by zero"))
    }
    if left == int128Min() && right == -1 {
        return Ok(0)
    }
    return Ok(left % right)
}

Result<Int128, Error> negI128Checked(Int128 value) {
    if value == int128Min() {
        return Err(int128Error("negI128Checked: overflow"))
    }
    return Ok(-value)
}

Result<Int128, Error> absI128Checked(Int128 value) {
    if value == int128Min() {
        return Err(int128Error("absI128Checked: overflow"))
    }
    if value < 0 {
        return Ok(-value)
    }
    return Ok(value)
}


// ---------- Int / Long checked 与 saturating ----------

Int maxIntValue() {
    return 2147483647
}

Int minIntValue() {
    return -maxIntValue() - 1
}

Long maxLongValue() {
    return 9223372036854775807
}

Long minLongValue() {
    return -maxLongValue() - 1
}

Result<Int, Error> addIntChecked(Int left, Int right) {
    Long sum = (left as Long) + (right as Long)
    Long upper = maxIntValue() as Long
    Long lower = minIntValue() as Long
    if sum > upper {
        return Err(int128Error("addIntChecked: overflow"))
    }
    if lower > sum {
        return Err(int128Error("addIntChecked: underflow"))
    }
    return Ok(sum as Int)
}

Result<Int, Error> subIntChecked(Int left, Int right) {
    Long diff = (left as Long) - (right as Long)
    Long upper = maxIntValue() as Long
    Long lower = minIntValue() as Long
    if diff > upper {
        return Err(int128Error("subIntChecked: overflow"))
    }
    if lower > diff {
        return Err(int128Error("subIntChecked: underflow"))
    }
    return Ok(diff as Int)
}

Result<Int, Error> mulIntChecked(Int left, Int right) {
    Long product = (left as Long) * (right as Long)
    Long upper = maxIntValue() as Long
    Long lower = minIntValue() as Long
    if product > upper {
        return Err(int128Error("mulIntChecked: overflow"))
    }
    if lower > product {
        return Err(int128Error("mulIntChecked: underflow"))
    }
    return Ok(product as Int)
}

Result<Int, Error> divIntChecked(Int left, Int right) {
    if right == 0 {
        return Err(int128Error("divIntChecked: division by zero"))
    }
    if left == minIntValue() && right == -1 {
        return Err(int128Error("divIntChecked: overflow"))
    }
    return Ok(left / right)
}

Result<Int, Error> modIntChecked(Int left, Int right) {
    if right == 0 {
        return Err(int128Error("modIntChecked: modulo by zero"))
    }
    if left == minIntValue() && right == -1 {
        return Ok(0)
    }
    return Ok(left % right)
}

Result<Int, Error> negIntChecked(Int value) {
    if value == minIntValue() {
        return Err(int128Error("negIntChecked: overflow"))
    }
    return Ok(-value)
}

Result<Int, Error> absIntChecked(Int value) {
    if value == minIntValue() {
        return Err(int128Error("absIntChecked: overflow"))
    }
    if value < 0 {
        return Ok(-value)
    }
    return Ok(value)
}

Result<Long, Error> addLongChecked(Long left, Long right) {
    Int128 wide = (left as Int128) + (right as Int128)
    Int128 upper = maxLongValue() as Int128
    Int128 lower = minLongValue() as Int128
    if wide > upper {
        return Err(int128Error("addLongChecked: overflow"))
    }
    if lower > wide {
        return Err(int128Error("addLongChecked: underflow"))
    }
    return Ok(wide as Long)
}

Result<Long, Error> subLongChecked(Long left, Long right) {
    Int128 wide = (left as Int128) - (right as Int128)
    Int128 upper = maxLongValue() as Int128
    Int128 lower = minLongValue() as Int128
    if wide > upper {
        return Err(int128Error("subLongChecked: overflow"))
    }
    if lower > wide {
        return Err(int128Error("subLongChecked: underflow"))
    }
    return Ok(wide as Long)
}

Result<Long, Error> mulLongChecked(Long left, Long right) {
    Int128 wide = (left as Int128) * (right as Int128)
    Int128 upper = maxLongValue() as Int128
    Int128 lower = minLongValue() as Int128
    if wide > upper {
        return Err(int128Error("mulLongChecked: overflow"))
    }
    if lower > wide {
        return Err(int128Error("mulLongChecked: underflow"))
    }
    return Ok(wide as Long)
}

Result<Long, Error> divLongChecked(Long left, Long right) {
    if right == 0 {
        return Err(int128Error("divLongChecked: division by zero"))
    }
    if left == minLongValue() && right == -1 {
        return Err(int128Error("divLongChecked: overflow"))
    }
    return Ok(left / right)
}

Result<Long, Error> modLongChecked(Long left, Long right) {
    if right == 0 {
        return Err(int128Error("modLongChecked: modulo by zero"))
    }
    if left == minLongValue() && right == -1 {
        return Ok(0)
    }
    return Ok(left % right)
}

Result<Long, Error> negLongChecked(Long value) {
    if value == minLongValue() {
        return Err(int128Error("negLongChecked: overflow"))
    }
    return Ok(-value)
}

Result<Long, Error> absLongChecked(Long value) {
    if value == minLongValue() {
        return Err(int128Error("absLongChecked: overflow"))
    }
    if value < 0 {
        return Ok(-value)
    }
    return Ok(value)
}

Int addIntSaturating(Int left, Int right) {
    Result<Int, Error> checked = addIntChecked(left, right)
    if checked.isErr() {
        if right > 0 {
            return maxIntValue()
        }
        return minIntValue()
    }
    return checked.value()
}

Int subIntSaturating(Int left, Int right) {
    Result<Int, Error> checked = subIntChecked(left, right)
    if checked.isErr() {
        if right > 0 {
            return minIntValue()
        }
        return maxIntValue()
    }
    return checked.value()
}

Int mulIntSaturating(Int left, Int right) {
    Result<Int, Error> checked = mulIntChecked(left, right)
    if checked.isErr() {
        if (left > 0 && right > 0) || (left < 0 && right < 0) {
            return maxIntValue()
        }
        return minIntValue()
    }
    return checked.value()
}

Long addLongSaturating(Long left, Long right) {
    Int128 wide = (left as Int128) + (right as Int128)
    Int128 upper = maxLongValue() as Int128
    Int128 lower = minLongValue() as Int128
    if wide > upper {
        return maxLongValue()
    }
    if lower > wide {
        return minLongValue()
    }
    return wide as Long
}

Long subLongSaturating(Long left, Long right) {
    Int128 wide = (left as Int128) - (right as Int128)
    Int128 upper = maxLongValue() as Int128
    Int128 lower = minLongValue() as Int128
    if wide > upper {
        return maxLongValue()
    }
    if lower > wide {
        return minLongValue()
    }
    return wide as Long
}

Long mulLongSaturating(Long left, Long right) {
    Int128 wide = (left as Int128) * (right as Int128)
    Int128 upper = maxLongValue() as Int128
    Int128 lower = minLongValue() as Int128
    if wide > upper {
        return maxLongValue()
    }
    if lower > wide {
        return minLongValue()
    }
    return wide as Long
}

Result<Long, Error> permutations(Int totalCount, Int selectedCount) {
    if totalCount < 0 || selectedCount < 0 || selectedCount > totalCount {
        return Err(int128Error("permutations: invalid arguments"))
    }
    Long result = 1
    Int i = 0
    while i < selectedCount {
        Result<Long, Error> step = mulLongChecked(result, (totalCount - i) as Long)
        if step.isErr() {
            return Err(step.error())
        }
        result = step.value()
        i = i + 1
    }
    return Ok(result)
}

Result<Long, Error> combinations(Int totalCount, Int selectedCount) {
    if totalCount < 0 || selectedCount < 0 || selectedCount > totalCount {
        return Err(int128Error("combinations: invalid arguments"))
    }
    Long result = 1
    Int i = 1
    while i <= selectedCount {
        Result<Long, Error> mul = mulLongChecked(result, (totalCount - selectedCount + i) as Long)
        if mul.isErr() {
            return Err(mul.error())
        }
        Result<Long, Error> div = divLongChecked(mul.value(), i as Long)
        if div.isErr() {
            return Err(div.error())
        }
        result = div.value()
        i = i + 1
    }
    return Ok(result)
}


// ---------- 统计（List<Double>） ----------

Double sum(List<Double> xs) {
    Double s = 0.0
    Int i = 0
    while i < xs.length() {
        s = s + xs.get(i)
        i = i + 1
    }
    return s
}

Double mean(List<Double> xs) {
    if xs.length() == 0 {
        return NaN()
    }
    return sum(xs) / xs.length()
}

// 升序副本（插入排序，输入不受影响）。
List<Double> sortedCopy(List<Double> xs) {
    List<Double> out = []
    Int i = 0
    while i < xs.length() {
        Double v = xs.get(i)
        Int j = out.length()
        while j > 0 && out.get(j - 1) > v {
            j = j - 1
        }
        out.insert(j, v)
        i = i + 1
    }
    return out
}

Double median(List<Double> xs) {
    Int n = xs.length()
    if n == 0 {
        return NaN()
    }
    List<Double> s = sortedCopy(xs)
    if n % 2 == 1 {
        return s.get(n / 2)
    }
    return (s.get(n / 2 - 1) + s.get(n / 2)) / 2.0
}

Double variance(List<Double> xs) {
    Int n = xs.length()
    if n == 0 {
        return NaN()
    }
    Double m = mean(xs)
    Double acc = 0.0
    Int i = 0
    while i < n {
        Double d = xs.get(i) - m
        acc = acc + d * d
        i = i + 1
    }
    return acc / n
}

Double stddev(List<Double> xs) {
    return sqrt(variance(xs))
}

// 分位数（线性插值，q∈[0,1]；与 numpy 默认口径一致）。
Double quantile(List<Double> xs, Double q) {
    Int n = xs.length()
    if n == 0 {
        return NaN()
    }
    if q <= 0.0 {
        List<Double> s0 = sortedCopy(xs)
        return s0.get(0)
    }
    if q >= 1.0 {
        List<Double> s1 = sortedCopy(xs)
        return s1.get(n - 1)
    }
    List<Double> s = sortedCopy(xs)
    Double pos = q * (n - 1)
    Int lo = truncToInt(pos)
    Int hi = lo + 1
    if hi > n - 1 {
        return s.get(lo)
    }
    Double frac = pos - lo
    return s.get(lo) + (s.get(hi) - s.get(lo)) * frac
}
