# `Integration`

| 项 | 值 |
| --- | --- |
| 类型 | `class Integration`（静态算子） |
| 包 | `xdk.numerics` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Pair`、`BasicError`、`ErrorKind` |

---

## 1. 定位

一维数值积分：自适应 Gauss-Kronrod（G7-K15）、自适应 Simpson、固定阶 Gauss-Legendre、tanh-sinh（端点奇异）、无穷区间变换。

不做：多维积分、Monte Carlo、振荡积分、Cauchy 主值、已知奇点分割、误差证明、并行。

---

## 2. 设计逻辑

- 全部静态；无状态；每次调用只看输入与被积函数。
- 默认 `integrate` 用 G7-K15：15 点 Kronrod 估计 + 7 点 Gauss 误差估计；区间二分直到总误差达标或达到区间上限。
- `integrateSimpson` 用自适应 Simpson，适合平滑函数；`integrateGaussLegendre` 用固定阶，适合已知光滑、需要固定计算量的场景。
- `integrateTanhSinh` 用双指数变换处理端点奇异；`integrateInfinite` 先把无穷区间映射到有限区间，再调用 tanh-sinh。
- 被积函数在任意采样点返回 NaN/±Inf 时立即 `InvalidArgument`，不继续累加。
- 积分结果是近似值；不附带严格误差证书，只保证“总误差估计 ≤ tolerance”或返回错误。
- 所有长操作首参 `Context`；每个新区间/每个 level 检查取消。

---

## 3. 表示与不变量

无实例字段；类不可实例化。

不变量：

- 有限区间方法要求 `lower < upper`；`lower == upper` 返回 `0.0`；`lower > upper` 是 `InvalidArgument`。
- `tolerance` 必须有限且 `> 0`。
- `maximumIntervals`/`maximumDepth` 必须 `>= 1`；`maximumLevel` 必须 `>= 2`。
- 被积函数非 null；回调在调用线程同步执行。
- 不保存被积函数或中间区间。

---

## 4. 生命周期

静态；无 close；无资源；无取消点之外的阻塞。`Context` 只用于取消查询。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Integration()` | 无 | 私有；禁止外部实例化 | 外部 `new` 不可用 |

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `integrate` | 默认自适应积分 | `Context context, Double(Double) integrand, Double lower, Double upper, Double tolerance, Int maximumIntervals` | `Result<Double, Error>` | 参数/非有限被积值/不收敛/取消 |
| `integrateSimpson` | 自适应 Simpson | `Context context, Double(Double) integrand, Double lower, Double upper, Double tolerance, Int maximumDepth` | `Result<Double, Error>` | 同上 |
| `integrateGaussLegendre` | 固定阶 Gauss-Legendre | `Context context, Double(Double) integrand, Double lower, Double upper, Int order` | `Result<Double, Error>` | `order` 不在 1..64/非有限 |
| `integrateTanhSinh` | 双指数积分 | `Context context, Double(Double) integrand, Double lower, Double upper, Double tolerance, Int maximumLevel` | `Result<Double, Error>` | 参数/非有限/不收敛/取消 |
| `integrateInfinite` | 无穷区间 | `Context context, Double(Double) integrand, Double lower, Double upper, Double tolerance, Int maximumLevel` | `Result<Double, Error>` | 参数/非有限/不收敛/取消 |

### 7.2 语义

- `integrate` 的停止条件：`totalError <= tolerance * max(1.0, abs(totalEstimate))`。
- 达到 `maximumIntervals` 仍未达标：`InvalidArgument`，消息含 “did not converge”。
- `integrateSimpson` 的递归深度达到 `maximumDepth` 仍未达标：错误。
- `integrateGaussLegendre` 的节点/权重在运行时由 Legendre 递推 + Newton 求根得到；`order` 上限 64。
- `integrateTanhSinh` 在 level 间比较两次总和；差值不超过相对容差即停止。
- `integrateInfinite` 要求至少一个端点为 ±Inf；两端都有限时委托 `integrate`。

---

## 8. 使用的技术

- G7-K15 节点/权重与误差估计；
- 自适应区间二分；
- Simpson 复合公式与 Richardson 修正；
- Legendre 递推、Newton 求根、Gauss-Legendre 权重；
- tanh-sinh 双指数变换与 Jacobian；
- 无穷区间有理变换；
- 相对/绝对混合容差；
- 协作取消。

---

## 9. 需要的支撑

- 语言：class、`Int`、`Double`、`Bool`、`List`、`Result`；
- 数学：`abs`、`sqrt`、`sin`、`cos`、`tanh`、`sinh`、`cosh`、`exp`、`log`、`pow`、`PI`、`isNaN`、`isInf`、`isFinite`、`max`；
- 执行：`Context.isCancelled`；
- 错误：`BasicError`、`ErrorKind.InvalidArgument`、`ErrorKind.Cancelled`；
- 容器：`Pair`。

---

## 10. 依赖的特性/接口/类

[`Context`](../../core/execution/Context.md)、[`Pair`](../../core/collections/Pair.md)、[`BasicError`](../../core/errors/BasicError.md)、[`ErrorKind`](../../core/errors/ErrorKind.md)。

---

## 11. 所有权与并发

静态；无共享可变状态；可并发调用。输入只借用；输出是 `Double`。无 close；`Context` 不保存。类不可实例化，无相等语义。

---

## 12. 示例与反例

正确：`Integration.integrate(context, integrand, 0.0, 1.0, 1e-12, 200)`；`integrateTanhSinh` 处理 `1/sqrt(x)`；`integrateGaussLegendre(context, integrand, 0.0, 1.0, 32)`；`integrateInfinite` 处理高斯积分。  
反例：对 `lower > upper` 期望自动交换；被积函数返回 NaN 却期望继续；把 `maximumIntervals` 设为 0；用固定阶 Gauss-Legendre 处理端点奇异；忽略不收敛错误。

---

## 13. 测试/场景义务

常数/线性/二次/高次多项式；`sin`/`exp`/`1/(1+x^2)`；端点奇异 `1/sqrt(x)`；无穷区间；被积函数在端点/内部返回 NaN/Inf；`lower == upper`；`lower > upper`；tolerance 为 0/负/NaN；maximum 为 0；Gauss-Legendre 的 1/2/3/32/64 阶；tanh-sinh 的 level 上限；取消；结果与解析值/高精度参考对比。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class Integration {
    private Integration() {}

    static Result<Double, Error> integrate(Context context,
        Double(Double) integrand, Double lower, Double upper,
        Double tolerance, Int maximumIntervals) {
        if context == null {
            throw "Integration.integrate: null context"
        }
        if integrand == null {
            throw "Integration.integrate: null integrand"
        }
        Result<Unit, Error> validation = _validateFiniteInterval(lower, upper,
            tolerance, maximumIntervals, "Integration.integrate")
        if validation.isErr() {
            return Err(validation.error())
        }
        if lower == upper {
            return Ok(0.0)
        }
        Pair<Double, Double> initial = _gaussKronrod15(integrand, lower, upper)
        if !isFinite(initial.first) || !isFinite(initial.second) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Integration.integrate: non-finite integrand"))
        }
        List<Double> lowerBounds = [lower]
        List<Double> upperBounds = [upper]
        List<Double> estimates = [initial.first]
        List<Double> errors = [initial.second]
        Double totalEstimate = initial.first
        Double totalError = initial.second
        Int intervalCount = 1
        while totalError > tolerance * max(1.0, abs(totalEstimate)) {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "Integration.integrate: cancelled"))
            }
            if intervalCount >= maximumIntervals {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "Integration.integrate: did not converge"))
            }
            Int bestIndex = 0
            Double bestError = errors.get(0)
            Int index = 1
            while index < errors.length() {
                if errors.get(index) > bestError {
                    bestError = errors.get(index)
                    bestIndex = index
                }
                index = index + 1
            }
            Double leftBound = lowerBounds.get(bestIndex)
            Double rightBound = upperBounds.get(bestIndex)
            Double middle = 0.5 * (leftBound + rightBound)
            Pair<Double, Double> leftPart =
                _gaussKronrod15(integrand, leftBound, middle)
            Pair<Double, Double> rightPart =
                _gaussKronrod15(integrand, middle, rightBound)
            if !isFinite(leftPart.first) || !isFinite(leftPart.second)
                || !isFinite(rightPart.first) || !isFinite(rightPart.second) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "Integration.integrate: non-finite integrand"))
            }
            totalError = totalError - errors.get(bestIndex)
                + leftPart.second + rightPart.second
            totalEstimate = totalEstimate - estimates.get(bestIndex)
                + leftPart.first + rightPart.first
            lowerBounds.set(bestIndex, middle)
            upperBounds.set(bestIndex, rightBound)
            estimates.set(bestIndex, rightPart.first)
            errors.set(bestIndex, rightPart.second)
            lowerBounds.push(leftBound)
            upperBounds.push(middle)
            estimates.push(leftPart.first)
            errors.push(leftPart.second)
            intervalCount = intervalCount + 1
        }
        if !isFinite(totalEstimate) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Integration.integrate: non-finite result"))
        }
        return Ok(totalEstimate)
    }

    static Result<Double, Error> integrateSimpson(Context context,
        Double(Double) integrand, Double lower, Double upper,
        Double tolerance, Int maximumDepth) {
        if context == null {
            throw "Integration.integrateSimpson: null context"
        }
        if integrand == null {
            throw "Integration.integrateSimpson: null integrand"
        }
        Result<Unit, Error> validation = _validateFiniteInterval(lower, upper,
            tolerance, maximumDepth, "Integration.integrateSimpson")
        if validation.isErr() {
            return Err(validation.error())
        }
        if lower == upper {
            return Ok(0.0)
        }
        Double middle = 0.5 * (lower + upper)
        Double whole = _simpson(integrand, lower, upper, lower, middle, upper)
        if !isFinite(whole) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Integration.integrateSimpson: non-finite integrand"))
        }
        return _adaptiveSimpson(context, integrand, lower, upper, whole,
            tolerance, 0, maximumDepth)
    }

    static Result<Double, Error> integrateGaussLegendre(Context context,
        Double(Double) integrand, Double lower, Double upper, Int order) {
        if context == null {
            throw "Integration.integrateGaussLegendre: null context"
        }
        if integrand == null {
            throw "Integration.integrateGaussLegendre: null integrand"
        }
        if order < 1 || order > 64 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Integration.integrateGaussLegendre: order out of range"))
        }
        if !isFinite(lower) || !isFinite(upper) || lower > upper {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Integration.integrateGaussLegendre: invalid interval"))
        }
        if lower == upper {
            return Ok(0.0)
        }
        Double center = 0.5 * (lower + upper)
        Double halfWidth = 0.5 * (upper - lower)
        Double sum = 0.0
        Int index = 0
        while index < order {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "Integration.integrateGaussLegendre: cancelled"))
            }
            Double node = cos(PI() * (index as Double + 0.75)
                / (order as Double + 0.5))
            Int iteration = 0
            Double derivative = 0.0
            while iteration < 100 {
                Pair<Double, Double> pair = _legendrePair(order, node)
                derivative = pair.second
                if derivative == 0.0 {
                    break
                }
                Double step = pair.first / derivative
                node = node - step
                if abs(step) <= 1e-15 {
                    break
                }
                iteration = iteration + 1
            }
            Pair<Double, Double> finalPair = _legendrePair(order, node)
            derivative = finalPair.second
            if derivative == 0.0 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "Integration.integrateGaussLegendre: zero derivative"))
            }
            Double weight = 2.0 / ((1.0 - node * node) * derivative * derivative)
            Double point = center + halfWidth * node
            Double value = integrand(point)
            if !isFinite(value) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "Integration.integrateGaussLegendre: non-finite integrand"))
            }
            sum = sum + weight * value
            index = index + 1
        }
        Double result = halfWidth * sum
        if !isFinite(result) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Integration.integrateGaussLegendre: non-finite result"))
        }
        return Ok(result)
    }

    static Result<Double, Error> integrateTanhSinh(Context context,
        Double(Double) integrand, Double lower, Double upper,
        Double tolerance, Int maximumLevel) {
        if context == null {
            throw "Integration.integrateTanhSinh: null context"
        }
        if integrand == null {
            throw "Integration.integrateTanhSinh: null integrand"
        }
        Result<Unit, Error> validation = _validateFiniteInterval(lower, upper,
            tolerance, maximumLevel, "Integration.integrateTanhSinh")
        if validation.isErr() {
            return Err(validation.error())
        }
        if maximumLevel < 2 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Integration.integrateTanhSinh: maximum level must be at least 2"))
        }
        if lower == upper {
            return Ok(0.0)
        }
        Double center = 0.5 * (lower + upper)
        Double halfWidth = 0.5 * (upper - lower)
        Double previous = 0.0
        Double step = 1.0
        Int level = 0
        while level < maximumLevel {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "Integration.integrateTanhSinh: cancelled"))
            }
            Int limit = 8 * (level + 1)
            Double sum = 0.0
            Int index = 0 - limit
            while index <= limit {
                Double parameter = (index as Double) * step
                Double hyperbolic = sinh(parameter)
                Double argument = 0.5 * PI() * hyperbolic
                Double cosine = cosh(argument)
                if !isInf(cosine) {
                    Double point = center + halfWidth * tanh(argument)
                    Double weight = halfWidth * 0.5 * PI() * cosh(parameter)
                        / (cosine * cosine)
                    Double value = integrand(point)
                    if !isFinite(value) {
                        return Err(new BasicError(ErrorKind.InvalidArgument,
                            "Integration.integrateTanhSinh: non-finite integrand"))
                    }
                    sum = sum + weight * value
                }
                index = index + 1
            }
            if level > 0 && abs(sum - previous)
                <= tolerance * max(1.0, abs(sum)) {
                return Ok(sum)
            }
            previous = sum
            step = step / 2.0
            level = level + 1
        }
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "Integration.integrateTanhSinh: did not converge"))
    }

    static Result<Double, Error> integrateInfinite(Context context,
        Double(Double) integrand, Double lower, Double upper,
        Double tolerance, Int maximumLevel) {
        if context == null {
            throw "Integration.integrateInfinite: null context"
        }
        if integrand == null {
            throw "Integration.integrateInfinite: null integrand"
        }
        if isNaN(lower) || isNaN(upper) || lower >= upper {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Integration.integrateInfinite: invalid interval"))
        }
        if !isInf(lower) && !isInf(upper) {
            return Integration.integrate(context, integrand, lower, upper,
                tolerance, maximumLevel)
        }
        if isInf(lower) && isInf(upper) {
            Double(Double) transformed = (Double parameter) -> {
                Double denominator = 1.0 - parameter * parameter
                if denominator == 0.0 {
                    return NaN()
                }
                Double point = parameter / denominator
                Double weight = (1.0 + parameter * parameter)
                    / (denominator * denominator)
                return integrand(point) * weight
            }
            return Integration.integrateTanhSinh(context, transformed,
                -1.0, 1.0, tolerance, maximumLevel)
        }
        if isInf(upper) {
            Double(Double) transformed = (Double parameter) -> {
                Double denominator = 1.0 - parameter
                if denominator == 0.0 {
                    return NaN()
                }
                Double point = lower + parameter / denominator
                Double weight = 1.0 / (denominator * denominator)
                return integrand(point) * weight
            }
            return Integration.integrateTanhSinh(context, transformed,
                0.0, 1.0, tolerance, maximumLevel)
        }
        Double(Double) transformed = (Double parameter) -> {
            Double denominator = 1.0 - parameter
            if denominator == 0.0 {
                return NaN()
            }
            Double point = upper - parameter / denominator
            Double weight = 1.0 / (denominator * denominator)
            return integrand(point) * weight
        }
        return Integration.integrateTanhSinh(context, transformed,
            0.0, 1.0, tolerance, maximumLevel)
    }

    static Result<Unit, Error> _validateFiniteInterval(Double lower,
        Double upper, Double tolerance, Int maximumCount, String algorithm) {
        if !isFinite(lower) || !isFinite(upper) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                algorithm + ": non-finite bound"))
        }
        if lower > upper {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                algorithm + ": lower bound is greater than upper bound"))
        }
        if isNaN(tolerance) || isInf(tolerance) || tolerance <= 0.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                algorithm + ": invalid tolerance"))
        }
        if maximumCount < 1 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                algorithm + ": invalid maximum count"))
        }
        return Ok(unit)
    }

    static Pair<Double, Double> _gaussKronrod15(Double(Double) integrand,
        Double lower, Double upper) {
        List<Double> nodes = [0.9914553711208126, 0.9491079123427585,
            0.8648644233597691, 0.7415311855993945,
            0.5860872354676911, 0.4058451513773972,
            0.2077849550078985, 0.0]
        List<Double> kronrodWeights = [0.02293532201052922,
            0.06309209262997855, 0.1047900103222502,
            0.1406532597155259, 0.1690047266392679,
            0.1903505780647854, 0.2044329400752989,
            0.2094821410847278]
        List<Double> gaussWeights = [0.1294849661688697,
            0.2797053914892766, 0.3818300505051189,
            0.4179591836734694]
        Double center = 0.5 * (lower + upper)
        Double halfWidth = 0.5 * (upper - lower)
        Double kronrodSum = 0.0
        Double gaussSum = 0.0
        Int index = 0
        while index < 7 {
            Double offset = halfWidth * nodes.get(index)
            Double leftValue = integrand(center - offset)
            Double rightValue = integrand(center + offset)
            kronrodSum = kronrodSum + kronrodWeights.get(index)
                * (leftValue + rightValue)
            if index == 1 || index == 3 || index == 5 {
                gaussSum = gaussSum + gaussWeights.get((index - 1) / 2)
                    * (leftValue + rightValue)
            }
            index = index + 1
        }
        Double centerValue = integrand(center)
        kronrodSum = kronrodSum + kronrodWeights.get(7) * centerValue
        gaussSum = gaussSum + gaussWeights.get(3) * centerValue
        Double estimate = halfWidth * kronrodSum
        Double error = abs(halfWidth * (kronrodSum - gaussSum))
        return new Pair<Double, Double>(estimate, error)
    }

    static Double _simpson(Double(Double) integrand, Double lower,
        Double upper, Double leftPoint, Double middlePoint,
        Double rightPoint) {
        return (upper - lower) / 6.0 * (integrand(leftPoint)
            + 4.0 * integrand(middlePoint) + integrand(rightPoint))
    }

    static Result<Double, Error> _adaptiveSimpson(Context context,
        Double(Double) integrand, Double lower, Double upper, Double whole,
        Double tolerance, Int depth, Int maximumDepth) {
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled,
                "Integration.integrateSimpson: cancelled"))
        }
        Double middle = 0.5 * (lower + upper)
        Double leftMiddle = 0.5 * (lower + middle)
        Double rightMiddle = 0.5 * (middle + upper)
        Double left = _simpson(integrand, lower, middle, lower, leftMiddle, middle)
        Double right = _simpson(integrand, middle, upper, middle, rightMiddle, upper)
        if !isFinite(left) || !isFinite(right) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Integration.integrateSimpson: non-finite integrand"))
        }
        Double delta = left + right - whole
        if depth >= maximumDepth {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Integration.integrateSimpson: did not converge"))
        }
        if abs(delta) <= 15.0 * tolerance {
            Double result = left + right + delta / 15.0
            if !isFinite(result) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "Integration.integrateSimpson: non-finite result"))
            }
            return Ok(result)
        }
        Result<Double, Error> leftResult = _adaptiveSimpson(context, integrand,
            lower, middle, left, tolerance / 2.0, depth + 1, maximumDepth)
        if leftResult.isErr() {
            return Err(leftResult.error())
        }
        Result<Double, Error> rightResult = _adaptiveSimpson(context, integrand,
            middle, upper, right, tolerance / 2.0, depth + 1, maximumDepth)
        if rightResult.isErr() {
            return Err(rightResult.error())
        }
        return Ok(leftResult.value() + rightResult.value())
    }

    static Pair<Double, Double> _legendrePair(Int order, Double value) {
        Double previous = 1.0
        Double current = value
        if order == 1 {
            Double derivativeValue = 1.0
            return new Pair<Double, Double>(current, derivativeValue)
        }
        Int index = 2
        while index <= order {
            Double next = ((2 * index - 1) as Double * value * current
                - (index - 1) as Double * previous) / (index as Double)
            previous = current
            current = next
            index = index + 1
        }
        Double derivativeValue = (order as Double)
            * (value * current - previous) / (value * value - 1.0)
        return new Pair<Double, Double>(current, derivativeValue)
    }
}
```
