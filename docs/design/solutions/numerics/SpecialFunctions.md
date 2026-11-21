# `SpecialFunctions`

| 项 | 值 |
| --- | --- |
| 类型 | `class SpecialFunctions`（静态算子） |
| 包 | `xdk.numerics` |
| 稳定性 | `preview` |
| 依赖 | `BasicError`、`ErrorKind` |

---

## 1. 定位

双精度特殊函数：Gamma/Beta 族、正则化不完全 Gamma/Beta、误差函数与反函数、Bessel J/Y/I/K、Airy Ai/Bi、Riemann Zeta（`value > 1`）、Lambert W 主分支、完全椭圆积分 K/E。

不做：任意精度特殊函数、复参数、球谐、Coulomb 波、超几何一般情形、椭圆函数、Mathieu 函数、区间误差证明。

---

## 2. 设计逻辑

- 全部是静态纯函数；无实例状态、无缓存、无全局精度设置。
- 输入必须有限；非有限输入一律 `InvalidArgument`，不把 NaN/Inf 当合法输入。
- 定义域错误返回 `InvalidArgument`：Gamma/Digamma 的非正整数极点、Bessel Y/K 的 `value <= 0`、椭圆积分的 `parameter >= 1`、Zeta 的 `value <= 1` 等。
- 溢出返回 `Ok(Inf)` 并在方法表写明；下溢返回 `0.0`；算法内部产生 NaN 视为失败并返回 `InvalidArgument`。
- 正则化函数使用 `[0,1]` 值域；不完全 Gamma 用级数/连分式分段，不完全 Beta 用 Lentz 连分式。
- 误差函数复用正则化 Gamma：`erf(value) = sign(value) * P(0.5, value^2)`，避免另写一套近似。
- Bessel/Airy 在“小参数用级数、大参数用渐近”之间切换；切换点固定，保证同一输入走同一路径。
- 椭圆积分用算术-几何平均（AGM）；Zeta 用 Euler-Maclaurin；Lambert W 用 Halley 迭代。
- 所有迭代有固定上限；达到上限仍不收敛返回 `InvalidArgument`，不返回最后一轮值。
- 基线实现以 Double 精度为目标；Bessel/Airy 的级数/渐近切换与 Zeta 的截断阶数是 preview 实现细节，X 可替换内核而不改 API。

---

## 3. 表示与不变量

无实例字段；类不可实例化。

不变量：

- 所有方法不修改输入；
- 所有返回值是新的 `Double`/`Result`；
- 不保存调用间的中间状态；
- 不依赖线程局部或全局舍入模式；
- 常量以私有静态方法返回，避免可变静态列表逃逸。

---

## 4. 生命周期

类本身无生命周期；静态调用；无 close；无资源；无取消点。单次特殊函数调用是固定规模计算，不接 `Context`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `SpecialFunctions()` | 无 | 私有；禁止外部实例化 | 外部 `new` 不可用 |

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

### 7.1 方法总表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `gamma` | Gamma 函数 | `Double value` | `Result<Double, Error>` | 非正整数极点/非有限 |
| `logGamma` | 对数 Gamma | `Double value` | `Result<Double, Error>` | `value <= 0`/非有限 |
| `digamma` | Digamma | `Double value` | `Result<Double, Error>` | 非正整数极点/非有限 |
| `beta` | Beta 函数 | `Double left, Double right` | `Result<Double, Error>` | 非正/非有限 |
| `regularizedGammaP` | 正则化下不完全 Gamma | `Double shape, Double value` | `Result<Double, Error>` | `shape <= 0`/`value < 0`/非有限 |
| `regularizedGammaQ` | 正则化上不完全 Gamma | 同上 | 同上 | 同上 |
| `regularizedBeta` | 正则化不完全 Beta | `Double shapeA, Double shapeB, Double value` | `Result<Double, Error>` | 非正形状/`value` 不在 `[0,1]` |
| `erf` | 误差函数 | `Double value` | `Double` | 无（非有限输入由调用方保证或返回 NaN） |
| `erfc` | 互补误差函数 | `Double value` | `Double` | 无 |
| `inverseErf` | 逆误差函数 | `Double probability` | `Result<Double, Error>` | `probability` 不在 `(-1,1)` |
| `besselJ` | 第一类 Bessel | `Int order, Double value` | `Result<Double, Error>` | 非有限/溢出内部 NaN |
| `besselY` | 第二类 Bessel | `Int order, Double value` | `Result<Double, Error>` | `value <= 0`/非有限 |
| `besselI` | 第一类修正 Bessel | `Int order, Double value` | `Result<Double, Error>` | 非有限 |
| `besselK` | 第二类修正 Bessel | `Int order, Double value` | `Result<Double, Error>` | `value <= 0`/非有限 |
| `airyAi` | Airy Ai | `Double value` | `Double` | 无（非有限输入返回 NaN） |
| `airyBi` | Airy Bi | `Double value` | `Double` | 无（非有限输入返回 NaN） |
| `riemannZeta` | Riemann Zeta | `Double value` | `Result<Double, Error>` | `value <= 1`/非有限 |
| `lambertW` | Lambert W 主分支 | `Double value` | `Result<Double, Error>` | `value < -1/e`/非有限 |
| `ellipticK` | 第一类完全椭圆积分 | `Double parameter` | `Result<Double, Error>` | `parameter` 不在 `[0,1)`/非有限 |
| `ellipticE` | 第二类完全椭圆积分 | `Double parameter` | `Result<Double, Error>` | 同上 |

### 7.2 关键语义

- `gamma` 在非正整数处无定义；正数很大时溢出返回 `Inf`。
- `logGamma` 只接受 `value > 0`；负值的 `log|Γ|` 不在本方法范围。
- `regularizedGammaP/Q` 的 `shape > 0`、`value >= 0`；`P + Q == 1`（在浮点误差内）。
- `regularizedBeta` 的 `value` 是 `[0,1]` 上的正则化参数。
- `beta` 溢出返回 `Inf`。
- `erf(±Inf)` 返回 `±1`，`erfc(+Inf)` 返回 `0`，`erfc(-Inf)` 返回 `2`；这些是文档化的 IEEE 极限。
- `erf`/`erfc` 在内部正则化失败时返回 `NaN`；这是文档化的数值失败，不伪装成功。
- Bessel 的 `order` 允许负值；使用 `J_{-n} = (-1)^n J_n`、`Y_{-n} = (-1)^n Y_n`、`I_{-n} = I_n`、`K_{-n} = K_n`（整数阶）。
- `besselI`/`besselK` 溢出返回 `Inf`；`besselK` 下溢返回 `0.0`。
- `airyBi` 大正参数溢出返回 `Inf`；`airyAi` 大正参数下溢返回 `0.0`；非有限输入返回 `NaN`，属于文档化 IEEE 传播。
- `riemannZeta` 只实现 `value > 1`；解析延拓是 X 缺口；`value` 接近 1 时溢出返回 `Inf`。
- `lambertW` 只实现主分支 `W_0`；`value == -1/e` 返回 `-1`。
- 椭圆积分的 `parameter = m`，不是模数 `k`；要求 `0 <= parameter < 1`。

---

## 8. 使用的技术

- Lanczos 近似与反射公式（Gamma）；
- Stirling 级数与递推（logGamma/digamma）；
- 级数与 Lentz 连分式（不完全 Gamma/Beta）；
- 正则化 Gamma 复用（erf/erfc）；
- Newton 迭代（inverseErf）；
- 幂级数、渐近展开、递推（Bessel）；
- 幂级数与渐近（Airy）；
- Euler-Maclaurin（Zeta）；
- Halley 迭代（Lambert W）；
- AGM（椭圆积分）；
- 固定迭代上限与 NaN 检查。

---

## 9. 需要的支撑

- 语言：class、`Int`、`Double`、`Bool`、`List`、`Result`；
- 数学：`abs`、`sqrt`、`exp`、`log`、`sin`、`cos`、`tan`、`pow`、`floor`、`isNaN`、`isInf`、`PI`；
- 错误：`BasicError`、`ErrorKind.InvalidArgument`。

---

## 10. 依赖的特性/接口/类

[`BasicError`](../../core/errors/BasicError.md)、[`ErrorKind`](../../core/errors/ErrorKind.md)。

---

## 11. 所有权与并发

静态；无共享可变状态；纯函数；可并发调用。无 close；无取消点；无相等语义（类不可实例化）。

---

## 12. 示例与反例

正确：`SpecialFunctions.gamma(5.0)` 约为 `24.0`；`regularizedGammaP(0.5, 1.0)` 与 `erf(1.0)` 一致；`besselJ(0, 2.4048255577)` 接近 0；`lambertW(1.0)` 约为 `0.5671432904`。  
反例：对 `gamma(-1.0)` 期望有限值；对 `besselY(0, 0.0)` 期望 `0`；对 `riemannZeta(0.5)` 期望解析延拓；用 `erf` 的近似值判断收敛；忽略 `Result` 的 `Err`。

---

## 13. 测试/场景义务

Gamma 的正/负非整数/极点/大值溢出；logGamma 的 1/2/10/1e300；digamma 的极点与反射；Beta 的对称性与 1/2；不完全 Gamma 的 P+Q、shape 小/大、value 小/大；不完全 Beta 的 0/1 端点、对称性、连分式收敛；erf/erfc 的 0/±1/大值/互补性；inverseErf 的 0/±0.9/边界；Bessel 的 0 阶/高阶/负阶/负参数/大参数；Airy 的 0/正/负/大参数；Zeta 的 2/大值/接近 1；Lambert W 的 0/1/-1/e/大值/域外；椭圆积分的 0/接近 1/负参数；非有限输入；迭代上限。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class SpecialFunctions {
    private SpecialFunctions() {}

    static Result<Double, Error> gamma(Double value) {
        if isNaN(value) || isInf(value) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.gamma: non-finite value"))
        }
        if value <= 0.0 && value == floor(value) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.gamma: pole"))
        }
        if value < 0.5 {
            Result<Double, Error> reflected = gamma(1.0 - value)
            if reflected.isErr() {
                return Err(reflected.error())
            }
            Double sineValue = sin(PI() * value)
            if sineValue == 0.0 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "SpecialFunctions.gamma: pole"))
            }
            return Ok(PI() / (sineValue * reflected.value()))
        }
        Double result = _lanczosGamma(value)
        if isNaN(result) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.gamma: evaluation failed"))
        }
        return Ok(result)
    }

    static Result<Double, Error> logGamma(Double value) {
        if isNaN(value) || isInf(value) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.logGamma: non-finite value"))
        }
        if value <= 0.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.logGamma: non-positive value"))
        }
        Double result = _logGammaPositive(value)
        if isNaN(result) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.logGamma: evaluation failed"))
        }
        return Ok(result)
    }

    static Result<Double, Error> digamma(Double value) {
        if isNaN(value) || isInf(value) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.digamma: non-finite value"))
        }
        if value <= 0.0 && value == floor(value) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.digamma: pole"))
        }
        if value < 0.5 {
            Result<Double, Error> reflected = digamma(1.0 - value)
            if reflected.isErr() {
                return Err(reflected.error())
            }
            return Ok(reflected.value() - PI() / tan(PI() * value))
        }
        Double result = _digammaPositive(value)
        if isNaN(result) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.digamma: evaluation failed"))
        }
        return Ok(result)
    }

    static Result<Double, Error> beta(Double left, Double right) {
        if isNaN(left) || isInf(left) || isNaN(right) || isInf(right) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.beta: non-finite argument"))
        }
        if left <= 0.0 || right <= 0.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.beta: non-positive argument"))
        }
        Result<Double, Error> leftLog = logGamma(left)
        Result<Double, Error> rightLog = logGamma(right)
        Result<Double, Error> sumLog = logGamma(left + right)
        if leftLog.isErr() || rightLog.isErr() || sumLog.isErr() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.beta: log gamma failed"))
        }
        return Ok(exp(leftLog.value() + rightLog.value() - sumLog.value()))
    }

    static Result<Double, Error> regularizedGammaP(Double shape,
        Double value) {
        if isNaN(shape) || isInf(shape) || isNaN(value) || isInf(value) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.regularizedGammaP: non-finite input"))
        }
        if shape <= 0.0 || value < 0.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.regularizedGammaP: invalid domain"))
        }
        if value == 0.0 {
            return Ok(0.0)
        }
        if value < shape + 1.0 {
            Double lower = _gammaSeries(shape, value)
            if isNaN(lower) || lower < -1e-12 || lower > 1.0 + 1e-12 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "SpecialFunctions.regularizedGammaP: result out of range"))
            }
            if lower < 0.0 {
                return Ok(0.0)
            }
            if lower > 1.0 {
                return Ok(1.0)
            }
            return Ok(lower)
        }
        Result<Double, Error> upper = regularizedGammaQ(shape, value)
        if upper.isErr() {
            return Err(upper.error())
        }
        return Ok(1.0 - upper.value())
    }

    static Result<Double, Error> regularizedGammaQ(Double shape,
        Double value) {
        if isNaN(shape) || isInf(shape) || isNaN(value) || isInf(value) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.regularizedGammaQ: non-finite input"))
        }
        if shape <= 0.0 || value < 0.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.regularizedGammaQ: invalid domain"))
        }
        if value == 0.0 {
            return Ok(1.0)
        }
        if value < shape + 1.0 {
            Result<Double, Error> lower = regularizedGammaP(shape, value)
            if lower.isErr() {
                return Err(lower.error())
            }
            return Ok(1.0 - lower.value())
        }
        Double upper = _gammaContinuedFraction(shape, value)
        if isNaN(upper) || upper < -1e-12 || upper > 1.0 + 1e-12 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.regularizedGammaQ: result out of range"))
        }
        if upper < 0.0 {
            return Ok(0.0)
        }
        if upper > 1.0 {
            return Ok(1.0)
        }
        return Ok(upper)
    }

    static Result<Double, Error> regularizedBeta(Double shapeA,
        Double shapeB, Double value) {
        if isNaN(shapeA) || isInf(shapeA) || isNaN(shapeB) || isInf(shapeB)
            || isNaN(value) || isInf(value) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.regularizedBeta: non-finite input"))
        }
        if shapeA <= 0.0 || shapeB <= 0.0 || value < 0.0 || value > 1.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.regularizedBeta: invalid domain"))
        }
        if value == 0.0 {
            return Ok(0.0)
        }
        if value == 1.0 {
            return Ok(1.0)
        }
        Result<Double, Error> sumLog = logGamma(shapeA + shapeB)
        Result<Double, Error> firstLog = logGamma(shapeA)
        Result<Double, Error> secondLog = logGamma(shapeB)
        if sumLog.isErr() || firstLog.isErr() || secondLog.isErr() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.regularizedBeta: log gamma failed"))
        }
        Double front = exp(sumLog.value()
            - firstLog.value() - secondLog.value()
            + shapeA * log(value) + shapeB * log(1.0 - value))
        if isNaN(front) || isInf(front) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.regularizedBeta: evaluation failed"))
        }
        Double result = front * _betaContinuedFraction(shapeA, shapeB, value)
            / shapeA
        if isNaN(result) || result < -1e-12 || result > 1.0 + 1e-12 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.regularizedBeta: result out of range"))
        }
        if result < 0.0 {
            return Ok(0.0)
        }
        if result > 1.0 {
            return Ok(1.0)
        }
        return Ok(result)
    }

    static Double erf(Double value) {
        if isNaN(value) {
            return NaN()
        }
        if isInf(value) {
            if value > 0.0 {
                return 1.0
            }
            return -1.0
        }
        Result<Double, Error> result = regularizedGammaP(0.5, value * value)
        if result.isErr() {
            return NaN()
        }
        if value < 0.0 {
            return 0.0 - result.value()
        }
        return result.value()
    }

    static Double erfc(Double value) {
        if isNaN(value) {
            return NaN()
        }
        if isInf(value) {
            if value > 0.0 {
                return 0.0
            }
            return 2.0
        }
        Result<Double, Error> result = regularizedGammaQ(0.5, value * value)
        if result.isErr() {
            return NaN()
        }
        if value < 0.0 {
            return 2.0 - result.value()
        }
        return result.value()
    }

    static Result<Double, Error> inverseErf(Double probability) {
        if isNaN(probability) || isInf(probability) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.inverseErf: non-finite probability"))
        }
        if probability <= -1.0 || probability >= 1.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.inverseErf: probability out of range"))
        }
        if probability == 0.0 {
            return Ok(0.0)
        }
        Double value = 0.5 * sqrt(PI()) * probability
        Int iteration = 0
        while iteration < 100 {
            Double error = erf(value) - probability
            Double derivative = 2.0 / sqrt(PI()) * exp(0.0 - value * value)
            if derivative == 0.0 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "SpecialFunctions.inverseErf: zero derivative"))
            }
            Double step = error / derivative
            value = value - step
            if abs(step) <= 1e-15 * (1.0 + abs(value)) {
                return Ok(value)
            }
            iteration = iteration + 1
        }
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "SpecialFunctions.inverseErf: did not converge"))
    }

    static Result<Double, Error> besselJ(Int order, Double value) {
        if isNaN(value) || isInf(value) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.besselJ: non-finite value"))
        }
        Int absoluteOrder = order
        Bool negate = false
        if absoluteOrder == -2147483648 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.besselJ: order out of range"))
        }
        if absoluteOrder < 0 {
            absoluteOrder = 0 - absoluteOrder
            if absoluteOrder % 2 == 1 {
                negate = true
            }
        }
        Double argument = value
        if argument < 0.0 {
            argument = 0.0 - argument
            if absoluteOrder % 2 == 1 {
                negate = !negate
            }
        }
        Double result = 0.0
        if argument < 0.5 * (absoluteOrder as Double) + 5.0 {
            result = _besselJSeries(absoluteOrder, argument)
        } else {
            result = _besselJAsymptotic(absoluteOrder, argument)
        }
        if isNaN(result) || isInf(result) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.besselJ: evaluation failed"))
        }
        if negate {
            result = 0.0 - result
        }
        return Ok(result)
    }

    static Result<Double, Error> besselY(Int order, Double value) {
        if isNaN(value) || isInf(value) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.besselY: non-finite value"))
        }
        if value <= 0.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.besselY: non-positive value"))
        }
        Int absoluteOrder = order
        Bool negate = false
        if absoluteOrder == -2147483648 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.besselY: order out of range"))
        }
        if absoluteOrder < 0 {
            absoluteOrder = 0 - absoluteOrder
            if absoluteOrder % 2 == 1 {
                negate = true
            }
        }
        Double result = 0.0
        if value < 8.0 + absoluteOrder as Double {
            result = _besselYSeries(absoluteOrder, value)
        } else {
            result = _besselYAsymptotic(absoluteOrder, value)
        }
        if isNaN(result) || isInf(result) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.besselY: evaluation failed"))
        }
        if negate {
            result = 0.0 - result
        }
        return Ok(result)
    }

    static Result<Double, Error> besselI(Int order, Double value) {
        if isNaN(value) || isInf(value) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.besselI: non-finite value"))
        }
        Int absoluteOrder = order
        Bool negate = false
        if absoluteOrder == -2147483648 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.besselI: order out of range"))
        }
        if absoluteOrder < 0 {
            absoluteOrder = 0 - absoluteOrder
            negate = false
        }
        Double argument = value
        if argument < 0.0 {
            argument = 0.0 - argument
            if absoluteOrder % 2 == 1 {
                negate = true
            }
        }
        Double result = 0.0
        if argument < 0.5 * (absoluteOrder as Double) + 10.0 {
            result = _besselISeries(absoluteOrder, argument)
        } else {
            result = _besselIAsymptotic(absoluteOrder, argument)
        }
        if isNaN(result) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.besselI: evaluation failed"))
        }
        if negate {
            result = 0.0 - result
        }
        return Ok(result)
    }

    static Result<Double, Error> besselK(Int order, Double value) {
        if isNaN(value) || isInf(value) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.besselK: non-finite value"))
        }
        if value <= 0.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.besselK: non-positive value"))
        }
        Int absoluteOrder = order
        if absoluteOrder == -2147483648 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.besselK: order out of range"))
        }
        if absoluteOrder < 0 {
            absoluteOrder = 0 - absoluteOrder
        }
        Double result = 0.0
        if value < 2.0 + absoluteOrder as Double {
            result = _besselKSeries(absoluteOrder, value)
        } else {
            result = _besselKAsymptotic(absoluteOrder, value)
        }
        if isNaN(result) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.besselK: evaluation failed"))
        }
        return Ok(result)
    }

    static Double airyAi(Double value) {
        if isNaN(value) || isInf(value) {
            return NaN()
        }
        if abs(value) <= 8.0 {
            Pair<Double, Double> series = _airySeries(value)
            return 0.3550280538878172 * series.first
                + 0.0 - 0.2588194037928068 * series.second
        }
        return _airyAiAsymptotic(value)
    }

    static Double airyBi(Double value) {
        if isNaN(value) || isInf(value) {
            return NaN()
        }
        if abs(value) <= 8.0 {
            Pair<Double, Double> series = _airySeries(value)
            return 0.6149266274460007 * series.first
                + 0.4482883573538264 * series.second
        }
        return _airyBiAsymptotic(value)
    }

    static Result<Double, Error> riemannZeta(Double value) {
        if isNaN(value) || isInf(value) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.riemannZeta: non-finite value"))
        }
        if value <= 1.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.riemannZeta: domain requires value > 1"))
        }
        Double result = _zetaEulerMaclaurin(value)
        if isNaN(result) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.riemannZeta: evaluation failed"))
        }
        return Ok(result)
    }

    static Result<Double, Error> lambertW(Double value) {
        if isNaN(value) || isInf(value) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.lambertW: non-finite value"))
        }
        Double minimum = 0.0 - 1.0 / exp(1.0)
        if value < minimum {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.lambertW: value below -1/e"))
        }
        if value == 0.0 {
            return Ok(0.0)
        }
        if value == minimum {
            return Ok(-1.0)
        }
        Double current = 0.0
        if value > 0.0 {
            current = log(1.0 + value)
        } else {
            current = -1.0 + sqrt(2.0 * (exp(1.0) * value + 1.0))
        }
        Int iteration = 0
        while iteration < 100 {
            Double exponential = exp(current)
            Double difference = current * exponential - value
            Double denominator = exponential * (current + 1.0)
                - (current + 2.0) * difference / (2.0 * current + 2.0)
            if denominator == 0.0 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "SpecialFunctions.lambertW: zero denominator"))
            }
            Double step = difference / denominator
            current = current - step
            if abs(step) <= 1e-15 * (1.0 + abs(current)) {
                return Ok(current)
            }
            iteration = iteration + 1
        }
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "SpecialFunctions.lambertW: did not converge"))
    }

    static Result<Double, Error> ellipticK(Double parameter) {
        if isNaN(parameter) || isInf(parameter) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.ellipticK: non-finite parameter"))
        }
        if parameter < 0.0 || parameter >= 1.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.ellipticK: parameter must be in [0,1)"))
        }
        Double arithmetic = 1.0
        Double geometric = sqrt(1.0 - parameter)
        Int iteration = 0
        while iteration < 100 {
            Double nextArithmetic = 0.5 * (arithmetic + geometric)
            Double nextGeometric = sqrt(arithmetic * geometric)
            if abs(nextArithmetic - nextGeometric) <= 1e-15 * nextArithmetic {
                return Ok(PI() / (2.0 * nextArithmetic))
            }
            arithmetic = nextArithmetic
            geometric = nextGeometric
            iteration = iteration + 1
        }
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "SpecialFunctions.ellipticK: did not converge"))
    }

    static Result<Double, Error> ellipticE(Double parameter) {
        if isNaN(parameter) || isInf(parameter) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.ellipticE: non-finite parameter"))
        }
        if parameter < 0.0 || parameter >= 1.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SpecialFunctions.ellipticE: parameter must be in [0,1)"))
        }
        Double arithmetic = 1.0
        Double geometric = sqrt(1.0 - parameter)
        Double correction = sqrt(parameter)
        Double sum = 0.5 * correction * correction
        Double factor = 1.0
        Int iteration = 0
        while iteration < 100 {
            Double nextArithmetic = 0.5 * (arithmetic + geometric)
            Double nextGeometric = sqrt(arithmetic * geometric)
            Double nextCorrection = 0.5 * (arithmetic - geometric)
            factor = factor * 2.0
            sum = sum + factor * nextCorrection * nextCorrection
            if abs(nextCorrection) <= 1e-15 * nextArithmetic {
                Double complete = PI() / (2.0 * nextArithmetic)
                return Ok(complete * (1.0 - sum))
            }
            arithmetic = nextArithmetic
            geometric = nextGeometric
            iteration = iteration + 1
        }
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "SpecialFunctions.ellipticE: did not converge"))
    }

    static Double _lanczosGamma(Double value) {
        List<Double> coefficients = _lanczosCoefficients()
        Double shifted = value - 1.0
        Double series = coefficients.get(0)
        Int index = 1
        while index < coefficients.length() {
            series = series + coefficients.get(index) / (shifted + index)
            index = index + 1
        }
        Double base = shifted + 7.5
        return sqrt(2.0 * PI()) * pow(base, shifted + 0.5)
            * exp(0.0 - base) * series
    }

    static List<Double> _lanczosCoefficients() {
        return [0.99999999999980993, 676.5203681218851,
            -1259.1392167224028, 771.32342877765313,
            -176.61502916214059, 12.507343278686905,
            -0.13857109526572012, 9.9843695780195716e-6,
            1.5056327351493116e-7]
    }

    static Double _logGammaPositive(Double value) {
        if value < 10.0 {
            return _logGammaPositive(value + 1.0) - log(value)
        }
        Double inverse = 1.0 / value
        Double inverseSquared = inverse * inverse
        return (value - 0.5) * log(value) - value
            + 0.5 * log(2.0 * PI())
            + inverse * (1.0 / 12.0 - inverseSquared * (1.0 / 360.0
                - inverseSquared * (1.0 / 1260.0
                    - inverseSquared * (1.0 / 1680.0))))
    }

    static Double _digammaPositive(Double value) {
        Double result = 0.0
        Double shifted = value
        while shifted < 10.0 {
            result = result - 1.0 / shifted
            shifted = shifted + 1.0
        }
        Double inverse = 1.0 / shifted
        Double inverseSquared = inverse * inverse
        return result + log(shifted) - 0.5 * inverse
            - inverseSquared * (1.0 / 12.0
                - inverseSquared * (1.0 / 120.0
                    - inverseSquared * (1.0 / 252.0
                        - inverseSquared * (1.0 / 240.0
                            - inverseSquared / 132.0))))
    }

    static Double _gammaSeries(Double shape, Double value) {
        Result<Double, Error> logValue = logGamma(shape)
        if logValue.isErr() {
            return NaN()
        }
        Double term = 1.0 / shape
        Double sum = term
        Int index = 1
        while index < 1000 {
            term = term * value / (shape + (index as Double))
            sum = sum + term
            if abs(term) <= abs(sum) * 1e-16 {
                break
            }
            index = index + 1
        }
        return sum * exp(0.0 - value + shape * log(value) - logValue.value())
    }

    static Double _gammaContinuedFraction(Double shape, Double value) {
        Result<Double, Error> logValue = logGamma(shape)
        if logValue.isErr() {
            return NaN()
        }
        Double tiny = 1e-300
        Double betaTerm = value + 1.0 - shape
        Double continuedFraction = 1.0 / tiny
        Double denominatorTerm = 1.0 / betaTerm
        Double result = denominatorTerm
        Int index = 1
        while index < 1000 {
            Double numerator = 0.0 - (index as Double)
                * ((index as Double) - shape)
            betaTerm = betaTerm + 2.0
            denominatorTerm = numerator * denominatorTerm + betaTerm
            if abs(denominatorTerm) < tiny {
                denominatorTerm = tiny
            }
            continuedFraction = betaTerm + numerator / continuedFraction
            if abs(continuedFraction) < tiny {
                continuedFraction = tiny
            }
            denominatorTerm = 1.0 / denominatorTerm
            Double delta = denominatorTerm * continuedFraction
            result = result * delta
            if abs(delta - 1.0) <= 1e-16 {
                break
            }
            index = index + 1
        }
        return result * exp(0.0 - value + shape * log(value) - logValue.value())
    }

    static Double _betaContinuedFraction(Double shapeA, Double shapeB,
        Double value) {
        Double tiny = 1e-300
        Double qab = shapeA + shapeB
        Double qap = shapeA + 1.0
        Double qam = shapeA - 1.0
        Double continuedFraction = 1.0
        Double denominatorTerm = 1.0 - qab * value / qap
        if abs(denominatorTerm) < tiny {
            denominatorTerm = tiny
        }
        denominatorTerm = 1.0 / denominatorTerm
        Double result = denominatorTerm
        Int index = 1
        while index < 1000 {
            Int doubled = 2 * index
            Double numerator = (index as Double) * (shapeB - index as Double)
                * value / ((qam + doubled as Double) * (shapeA + doubled as Double))
            denominatorTerm = 1.0 + numerator * denominatorTerm
            if abs(denominatorTerm) < tiny {
                denominatorTerm = tiny
            }
            continuedFraction = 1.0 + numerator / continuedFraction
            if abs(continuedFraction) < tiny {
                continuedFraction = tiny
            }
            denominatorTerm = 1.0 / denominatorTerm
            result = result * denominatorTerm * continuedFraction
            numerator = 0.0 - (shapeA + index as Double)
                * (qab + index as Double) * value
                / ((shapeA + doubled as Double) * (qap + doubled as Double))
            denominatorTerm = 1.0 + numerator * denominatorTerm
            if abs(denominatorTerm) < tiny {
                denominatorTerm = tiny
            }
            continuedFraction = 1.0 + numerator / continuedFraction
            if abs(continuedFraction) < tiny {
                continuedFraction = tiny
            }
            denominatorTerm = 1.0 / denominatorTerm
            Double delta = denominatorTerm * continuedFraction
            result = result * delta
            if abs(delta - 1.0) <= 1e-16 {
                break
            }
            index = index + 1
        }
        return result
    }

    static Double _besselJSeries(Int order, Double value) {
        Double half = value / 2.0
        Double term = 1.0
        Int index = 0
        while index < order {
            term = term * half / ((index + 1) as Double)
            index = index + 1
        }
        Double sum = term
        index = 0
        while index < 1000 {
            index = index + 1
            term = 0.0 - term * half * half
                / ((index as Double) * (index + order as Double))
            sum = sum + term
            if abs(term) <= abs(sum) * 1e-16 {
                break
            }
        }
        return sum
    }

    static Double _besselJAsymptotic(Int order, Double value) {
        Double mu = 4.0 * (order as Double) * (order as Double)
        Double phase = value - (order as Double) * PI() / 2.0 - PI() / 4.0
        Double inverse = 1.0 / value
        Double correction = 1.0 - (mu - 1.0) * (mu - 9.0) * inverse * inverse
            / 128.0
        Double sineCorrection = (mu - 1.0) * inverse / 8.0
        return sqrt(2.0 / (PI() * value))
            * (cos(phase) * correction - sin(phase) * sineCorrection)
    }

    static Double _besselYSeries(Int order, Double value) {
        Double y0 = _besselY0Series(value)
        if order == 0 {
            return y0
        }
        Double y1 = _besselY1Series(value)
        if order == 1 {
            return y1
        }
        Double previous = y0
        Double current = y1
        Int index = 1
        while index < order {
            Double next = 2.0 * (index as Double) / value * current - previous
            previous = current
            current = next
            index = index + 1
        }
        return current
    }

    static Double _besselY0Series(Double value) {
        Double half = value / 2.0
        Double j0 = _besselJSeries(0, value)
        Double harmonic = 0.0
        Double power = 1.0
        Double denominator = 1.0
        Double sum = 0.0
        Int index = 1
        while index < 1000 {
            harmonic = harmonic + 1.0 / (index as Double)
            power = power * half * half
            denominator = denominator * (index as Double) * (index as Double)
            Double term = power / denominator * harmonic
            if index % 2 == 1 {
                sum = sum + term
            } else {
                sum = sum - term
            }
            if abs(term) <= (1.0 + abs(sum)) * 1e-16 {
                break
            }
            index = index + 1
        }
        return (2.0 / PI()) * (log(half) + _eulerGamma()) * j0
            + (2.0 / PI()) * sum
    }

    static Double _besselY1Series(Double value) {
        Double half = value / 2.0
        Double j1 = _besselJSeries(1, value)
        Double harmonic = 0.0
        Double nextHarmonic = 1.0
        Double power = half
        Double denominator = 1.0
        Double sum = 0.0
        Int index = 0
        while index < 1000 {
            Double term = (harmonic + nextHarmonic) * power / denominator
            if index % 2 == 0 {
                sum = sum + term
            } else {
                sum = sum - term
            }
            if abs(term) <= (1.0 + abs(sum)) * 1e-16 {
                break
            }
            index = index + 1
            harmonic = nextHarmonic
            nextHarmonic = nextHarmonic + 1.0 / ((index + 1) as Double)
            power = power * half * half
            denominator = denominator * (index as Double) * (index + 1 as Double)
        }
        return (2.0 / PI()) * (log(half) + _eulerGamma()) * j1
            - (2.0 / PI()) / value - (1.0 / PI()) * sum
    }

    static Double _besselYAsymptotic(Int order, Double value) {
        Double mu = 4.0 * (order as Double) * (order as Double)
        Double phase = value - (order as Double) * PI() / 2.0 - PI() / 4.0
        Double inverse = 1.0 / value
        Double correction = 1.0 - (mu - 1.0) * (mu - 9.0) * inverse * inverse
            / 128.0
        Double sineCorrection = (mu - 1.0) * inverse / 8.0
        return sqrt(2.0 / (PI() * value))
            * (sin(phase) * correction + cos(phase) * sineCorrection)
    }

    static Double _besselISeries(Int order, Double value) {
        Double half = value / 2.0
        Double term = 1.0
        Int index = 0
        while index < order {
            term = term * half / ((index + 1) as Double)
            index = index + 1
        }
        Double sum = term
        index = 0
        while index < 1000 {
            index = index + 1
            term = term * half * half
                / ((index as Double) * (index + order as Double))
            sum = sum + term
            if abs(term) <= abs(sum) * 1e-16 {
                break
            }
        }
        return sum
    }

    static Double _besselIAsymptotic(Int order, Double value) {
        Double mu = 4.0 * (order as Double) * (order as Double)
        Double inverse = 1.0 / value
        Double correction = 1.0 - (mu - 1.0) * inverse / 8.0
            + (mu - 1.0) * (mu - 9.0) * inverse * inverse / 128.0
        return exp(value) / sqrt(2.0 * PI() * value) * correction
    }

    static Double _besselKSeries(Int order, Double value) {
        Double k0 = _besselK0Series(value)
        if order == 0 {
            return k0
        }
        Double k1 = _besselK1Series(value)
        if order == 1 {
            return k1
        }
        Double previous = k0
        Double current = k1
        Int index = 1
        while index < order {
            Double next = previous + 2.0 * (index as Double) / value * current
            previous = current
            current = next
            index = index + 1
        }
        return current
    }

    static Double _besselK0Series(Double value) {
        Double half = value / 2.0
        Double i0 = _besselISeries(0, value)
        Double harmonic = 0.0
        Double power = 1.0
        Double denominator = 1.0
        Double sum = 0.0
        Int index = 1
        while index < 1000 {
            harmonic = harmonic + 1.0 / (index as Double)
            power = power * half * half
            denominator = denominator * (index as Double) * (index as Double)
            Double term = power / denominator * harmonic
            sum = sum + term
            if abs(term) <= (1.0 + abs(sum)) * 1e-16 {
                break
            }
            index = index + 1
        }
        return 0.0 - (log(half) + _eulerGamma()) * i0 + sum
    }

    static Double _besselK1Series(Double value) {
        Double half = value / 2.0
        Double i1 = _besselISeries(1, value)
        Double harmonic = 0.0
        Double nextHarmonic = 1.0
        Double power = half
        Double denominator = 1.0
        Double sum = 0.0
        Int index = 0
        while index < 1000 {
            Double term = (harmonic + nextHarmonic) * power / denominator
            sum = sum + term
            if abs(term) <= (1.0 + abs(sum)) * 1e-16 {
                break
            }
            index = index + 1
            harmonic = nextHarmonic
            nextHarmonic = nextHarmonic + 1.0 / ((index + 1) as Double)
            power = power * half * half
            denominator = denominator * (index as Double) * (index + 1 as Double)
        }
        Double logTerm = log(value / 2.0) + _eulerGamma()
        return logTerm * i1 + 1.0 / value - 0.5 * sum
    }

    static Double _besselKAsymptotic(Int order, Double value) {
        Double mu = 4.0 * (order as Double) * (order as Double)
        Double inverse = 1.0 / value
        Double correction = 1.0 + (mu - 1.0) * inverse / 8.0
            + (mu - 1.0) * (mu - 9.0) * inverse * inverse / 128.0
        return sqrt(PI() / (2.0 * value)) * exp(0.0 - value) * correction
    }

    static Pair<Double, Double> _airySeries(Double value) {
        Double cube = value * value * value
        Double firstSeries = 1.0
        Double firstTerm = 1.0
        Double secondSeries = value
        Double secondTerm = value
        Int index = 1
        while index < 200 {
            firstTerm = firstTerm * cube
                / (((3 * index - 1) as Double) * (3 * index as Double))
            firstSeries = firstSeries + firstTerm
            secondTerm = secondTerm * cube
                / ((3 * index as Double) * (3 * index + 1 as Double))
            secondSeries = secondSeries + secondTerm
            if abs(firstTerm) + abs(secondTerm) <= (1.0 + abs(firstSeries) + abs(secondSeries)) * 1e-16 {
                break
            }
            index = index + 1
        }
        return new Pair<Double, Double>(firstSeries, secondSeries)
    }

    static Double _airyAiAsymptotic(Double value) {
        if value > 0.0 {
            Double zeta = 2.0 / 3.0 * pow(value, 1.5)
            return exp(0.0 - zeta)
                / (2.0 * sqrt(PI()) * pow(value, 0.25))
        }
        Double zeta = 2.0 / 3.0 * pow(0.0 - value, 1.5)
        return sin(zeta + PI() / 4.0)
            / (sqrt(PI()) * pow(0.0 - value, 0.25))
    }

    static Double _airyBiAsymptotic(Double value) {
        if value > 0.0 {
            Double zeta = 2.0 / 3.0 * pow(value, 1.5)
            return exp(zeta) / (sqrt(PI()) * pow(value, 0.25))
        }
        Double zeta = 2.0 / 3.0 * pow(0.0 - value, 1.5)
        return cos(zeta + PI() / 4.0)
            / (sqrt(PI()) * pow(0.0 - value, 0.25))
    }

    static Double _zetaEulerMaclaurin(Double value) {
        Double sum = 0.0
        Int index = 1
        while index < 20 {
            sum = sum + pow(index as Double, 0.0 - value)
            index = index + 1
        }
        Double summationLimit = 20.0
        sum = sum + pow(summationLimit, 1.0 - value) / (value - 1.0)
            + 0.5 * pow(summationLimit, 0.0 - value)
        List<Double> coefficients = [1.0 / 12.0, -1.0 / 720.0,
            1.0 / 30240.0, -1.0 / 1209600.0, 1.0 / 47900160.0]
        Double term = value
        Int coefficientIndex = 0
        while coefficientIndex < coefficients.length() {
            if coefficientIndex > 0 {
                term = term * (value + (2 * coefficientIndex - 1) as Double)
                    * (value + (2 * coefficientIndex) as Double)
            }
            sum = sum + coefficients.get(coefficientIndex) * term
                * pow(summationLimit, 0.0 - value - (2 * coefficientIndex + 1) as Double)
            coefficientIndex = coefficientIndex + 1
        }
        return sum
    }

    static Double _eulerGamma() {
        return 0.5772156649015329
    }
}
```
