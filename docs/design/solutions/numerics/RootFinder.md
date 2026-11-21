# `RootFinder`

| 项 | 值 |
| --- | --- |
| 类型 | `class RootFinder`（静态算子） |
| 包 | `xdk.numerics` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`BasicError`、`ErrorKind` |

---

## 1. 定位

一维实函数求根：二分、Brent、Newton、割线；要求调用方给出括根区间或初值。

不做：多维求根、复根、区间算术、保证全局唯一根、符号求根、自动微分、多项式专用求根（用 `Polynomial.roots`）。

---

## 2. 设计逻辑

- 全部静态；无状态；函数由调用方提供。
- `bisect`/`brent` 要求 `function(lower) * function(upper) <= 0`；端点为零直接返回端点。
- `newton` 需要解析导数；导数为零或非有限时立即 `InvalidArgument`，不退化成不可控的随机步。
- `secant` 需要两个不同初值；斜率分母为零时失败。
- 收敛条件统一为 `abs(step) <= tolerance * (1 + abs(point))`；达到迭代上限仍未收敛返回 `InvalidArgument`。
- 函数值出现 NaN/±Inf 时立即失败，不继续迭代。
- `find` 是默认入口，委托 `brent`；需要固定算法时直接调具体方法。
- 所有长操作首参 `Context`；每轮迭代检查取消。

---

## 3. 表示与不变量

无实例字段；类不可实例化。

不变量：

- 函数/导数非 null；区间/初值有限。
- `lower < upper`；`tolerance > 0` 且有限；`maximumIterations >= 1`。
- 括根区间两端函数值必须异号或至少一端为零。
- Newton 初值处导数不能为零；割线两初值不能相等。
- 不保存函数、迭代历史或最后一步。

---

## 4. 生命周期

静态；无 close；无资源；可并发调用（调用方保证函数线程安全）。`Context` 只用于取消查询。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `RootFinder()` | 无 | 私有；禁止外部实例化 | 外部 `new` 不可用 |

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `bisect` | 二分法 | `Context context, Double(Double) function, Double lower, Double upper, Double tolerance, Int maximumIterations` | `Result<Double, Error>` | 区间/括根/非有限/不收敛/取消 |
| `brent` | Brent 法 | 同上 | 同上 | 同上 |
| `newton` | Newton 法 | `Context context, Double(Double) function, Double(Double) derivative, Double initialPoint, Double tolerance, Int maximumIterations` | 同上 | 导数零/非有限/不收敛/取消 |
| `secant` | 割线法 | `Context context, Double(Double) function, Double firstPoint, Double secondPoint, Double tolerance, Int maximumIterations` | 同上 | 初值相同/斜率零/非有限/不收敛/取消 |
| `find` | 默认入口 | `Context context, Double(Double) function, Double lower, Double upper, Double tolerance, Int maximumIterations` | 同上 | 同 Brent |

### 7.2 语义

- 返回的是根的近似值；不返回残差或迭代次数。
- `bisect`/`brent` 的区间端点函数值乘积为 `0` 时直接返回该端点。
- `brent` 是首选的有括根区间算法；`bisect` 用于需要最坏情况可预测性的场景。
- `newton`/`secant` 不保证全局收敛；调用方应给出合理初值并检查 `Err`。
- 不保证返回区间内“第一个”根；有多个根时结果依赖算法与初值。

---

## 8. 使用的技术

- 二分；
- Brent-Dekker（逆二次插值 + 割线 + 二分兜底）；
- Newton-Raphson；
- 割线法；
- 相对容差与迭代上限；
- 协作取消。

---

## 9. 需要的支撑

- 语言：class、`Int`、`Double`、`Bool`、`Result`；
- 数学：`abs`、`min`、`isNaN`、`isInf`、`isFinite`；
- 执行：`Context.isCancelled`；
- 错误：`BasicError`、`ErrorKind.InvalidArgument`、`ErrorKind.Cancelled`。

---

## 10. 依赖的特性/接口/类

[`Context`](../../core/execution/Context.md)、[`BasicError`](../../core/errors/BasicError.md)、[`ErrorKind`](../../core/errors/ErrorKind.md)。

---

## 11. 所有权与并发

静态；无共享可变状态；可并发调用。输入只借用；返回 `Double`。`Context` 不保存。类不可实例化，无相等语义。

---

## 12. 示例与反例

正确：`RootFinder.brent(context, function, 0.0, 2.0, 1e-12, 200)`；`bisect` 用于函数值异号的区间；`newton` 提供解析导数与合理初值；`secant` 两个初值不同。  
反例：端点同号仍调用 `brent` 并期望找到根；导数为零仍继续 Newton；初值含 Inf；把 `maximumIterations` 设为 0；忽略 `Err` 并使用最后一次迭代值；期望返回所有根。

---

## 13. 测试/场景义务

线性/二次/三次/超越方程；端点恰为零；端点同号；区间内多根；`lower >= upper`；容差 0/负/NaN；迭代上限 1；Newton 导数为零/导数非有限/初值远离根；割线初值相同/斜率零；取消；结果代回函数验证残差。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class RootFinder {
    private RootFinder() {}

    static Result<Double, Error> bisect(Context context,
        Double(Double) function, Double lower, Double upper,
        Double tolerance, Int maximumIterations) {
        if context == null {
            throw "RootFinder.bisect: null context"
        }
        if function == null {
            throw "RootFinder.bisect: null function"
        }
        Result<Unit, Error> validation = _validateBracket(lower, upper,
            tolerance, maximumIterations, "RootFinder.bisect")
        if validation.isErr() {
            return Err(validation.error())
        }
        Result<Double, Error> lowerValue = _evaluate(context, function, lower,
            "RootFinder.bisect")
        if lowerValue.isErr() {
            return Err(lowerValue.error())
        }
        Result<Double, Error> upperValue = _evaluate(context, function, upper,
            "RootFinder.bisect")
        if upperValue.isErr() {
            return Err(upperValue.error())
        }
        if lowerValue.value() == 0.0 {
            return Ok(lower)
        }
        if upperValue.value() == 0.0 {
            return Ok(upper)
        }
        if (lowerValue.value() > 0.0 && upperValue.value() > 0.0)
            || (lowerValue.value() < 0.0 && upperValue.value() < 0.0) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "RootFinder.bisect: interval does not bracket a root"))
        }
        Double left = lower
        Double right = upper
        Double leftObjective = lowerValue.value()
        Int iteration = 0
        while iteration < maximumIterations {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "RootFinder.bisect: cancelled"))
            }
            Double middle = 0.5 * (left + right)
            Result<Double, Error> middleValue = _evaluate(context, function,
                middle, "RootFinder.bisect")
            if middleValue.isErr() {
                return Err(middleValue.error())
            }
            if middleValue.value() == 0.0 {
                return Ok(middle)
            }
            if leftObjective * middleValue.value() < 0.0 {
                right = middle
            } else {
                left = middle
                leftObjective = middleValue.value()
            }
            if abs(right - left) <= tolerance * (1.0 + abs(middle)) {
                return Ok(middle)
            }
            iteration = iteration + 1
        }
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "RootFinder.bisect: did not converge"))
    }

    static Result<Double, Error> brent(Context context,
        Double(Double) function, Double lower, Double upper,
        Double tolerance, Int maximumIterations) {
        if context == null {
            throw "RootFinder.brent: null context"
        }
        if function == null {
            throw "RootFinder.brent: null function"
        }
        Result<Unit, Error> validation = _validateBracket(lower, upper,
            tolerance, maximumIterations, "RootFinder.brent")
        if validation.isErr() {
            return Err(validation.error())
        }
        Result<Double, Error> lowerValue = _evaluate(context, function, lower,
            "RootFinder.brent")
        if lowerValue.isErr() {
            return Err(lowerValue.error())
        }
        Result<Double, Error> upperValue = _evaluate(context, function, upper,
            "RootFinder.brent")
        if upperValue.isErr() {
            return Err(upperValue.error())
        }
        if lowerValue.value() == 0.0 {
            return Ok(lower)
        }
        if upperValue.value() == 0.0 {
            return Ok(upper)
        }
        if (lowerValue.value() > 0.0 && upperValue.value() > 0.0)
            || (lowerValue.value() < 0.0 && upperValue.value() < 0.0) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "RootFinder.brent: interval does not bracket a root"))
        }
        Double first = lower
        Double second = upper
        Double third = upper
        Double firstValue = lowerValue.value()
        Double secondValue = upperValue.value()
        Double thirdValue = secondValue
        Double previousStep = second - first
        Double beforePreviousStep = previousStep
        Int iteration = 0
        while iteration < maximumIterations {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "RootFinder.brent: cancelled"))
            }
            if (secondValue > 0.0 && thirdValue > 0.0)
                || (secondValue < 0.0 && thirdValue < 0.0) {
                third = first
                thirdValue = firstValue
                previousStep = second - first
                beforePreviousStep = previousStep
            }
            if abs(thirdValue) < abs(secondValue) {
                first = second
                second = third
                third = first
                firstValue = secondValue
                secondValue = thirdValue
                thirdValue = firstValue
            }
            Double tolerance1 = tolerance * (1.0 + abs(second))
            Double middle = 0.5 * (third - second)
            if abs(middle) <= tolerance1 || secondValue == 0.0 {
                return Ok(second)
            }
            if abs(beforePreviousStep) >= tolerance1
                && abs(firstValue) > abs(secondValue) {
                Double ratio = secondValue / firstValue
                Double numerator = 0.0
                Double denominator = 0.0
                if first == third {
                    numerator = 2.0 * middle * ratio
                    denominator = 1.0 - ratio
                } else {
                    Double firstRatio = firstValue / thirdValue
                    Double secondRatio = secondValue / thirdValue
                    numerator = ratio * (2.0 * middle * firstRatio
                        * (firstRatio - secondRatio)
                        - (second - first) * (secondRatio - 1.0))
                    denominator = (firstRatio - 1.0) * (secondRatio - 1.0)
                        * (ratio - 1.0)
                }
                if numerator > 0.0 {
                    denominator = 0.0 - denominator
                }
                numerator = abs(numerator)
                Double minimumOne = 3.0 * middle * denominator
                    - abs(tolerance1 * denominator)
                Double minimumTwo = abs(beforePreviousStep * denominator)
                if 2.0 * numerator < min(minimumOne, minimumTwo) {
                    beforePreviousStep = previousStep
                    previousStep = numerator / denominator
                } else {
                    previousStep = middle
                    beforePreviousStep = previousStep
                }
            } else {
                previousStep = middle
                beforePreviousStep = previousStep
            }
            first = second
            firstValue = secondValue
            if abs(previousStep) > tolerance1 {
                second = second + previousStep
            } else {
                if middle > 0.0 {
                    second = second + tolerance1
                } else {
                    second = second - tolerance1
                }
            }
            Result<Double, Error> secondValueResult = _evaluate(context,
                function, second, "RootFinder.brent")
            if secondValueResult.isErr() {
                return Err(secondValueResult.error())
            }
            secondValue = secondValueResult.value()
            iteration = iteration + 1
        }
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "RootFinder.brent: did not converge"))
    }

    static Result<Double, Error> newton(Context context,
        Double(Double) function, Double(Double) derivative,
        Double initialPoint, Double tolerance, Int maximumIterations) {
        if context == null {
            throw "RootFinder.newton: null context"
        }
        if function == null || derivative == null {
            throw "RootFinder.newton: null callback"
        }
        if !isFinite(initialPoint) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "RootFinder.newton: non-finite initial point"))
        }
        Result<Unit, Error> validation = _validateTolerance(tolerance,
            maximumIterations, "RootFinder.newton")
        if validation.isErr() {
            return Err(validation.error())
        }
        Double point = initialPoint
        Result<Double, Error> pointValue = _evaluate(context, function, point,
            "RootFinder.newton")
        if pointValue.isErr() {
            return Err(pointValue.error())
        }
        Double value = pointValue.value()
        Int iteration = 0
        while iteration < maximumIterations {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "RootFinder.newton: cancelled"))
            }
            if value == 0.0 {
                return Ok(point)
            }
            Double derivativeValue = derivative(point)
            if isNaN(derivativeValue) || isInf(derivativeValue) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "RootFinder.newton: non-finite derivative"))
            }
            if derivativeValue == 0.0 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "RootFinder.newton: zero derivative"))
            }
            Double step = value / derivativeValue
            Double nextPoint = point - step
            if !isFinite(nextPoint) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "RootFinder.newton: non-finite iterate"))
            }
            Result<Double, Error> nextValue = _evaluate(context, function,
                nextPoint, "RootFinder.newton")
            if nextValue.isErr() {
                return Err(nextValue.error())
            }
            point = nextPoint
            value = nextValue.value()
            if abs(step) <= tolerance * (1.0 + abs(point)) {
                return Ok(point)
            }
            iteration = iteration + 1
        }
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "RootFinder.newton: did not converge"))
    }

    static Result<Double, Error> secant(Context context,
        Double(Double) function, Double firstPoint, Double secondPoint,
        Double tolerance, Int maximumIterations) {
        if context == null {
            throw "RootFinder.secant: null context"
        }
        if function == null {
            throw "RootFinder.secant: null function"
        }
        if !isFinite(firstPoint) || !isFinite(secondPoint)
            || firstPoint == secondPoint {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "RootFinder.secant: invalid initial points"))
        }
        Result<Unit, Error> validation = _validateTolerance(tolerance,
            maximumIterations, "RootFinder.secant")
        if validation.isErr() {
            return Err(validation.error())
        }
        Double previousPoint = firstPoint
        Double currentPoint = secondPoint
        Result<Double, Error> previousValue = _evaluate(context, function,
            previousPoint, "RootFinder.secant")
        if previousValue.isErr() {
            return Err(previousValue.error())
        }
        Result<Double, Error> currentValue = _evaluate(context, function,
            currentPoint, "RootFinder.secant")
        if currentValue.isErr() {
            return Err(currentValue.error())
        }
        Double previousObjective = previousValue.value()
        Double currentObjective = currentValue.value()
        Int iteration = 0
        while iteration < maximumIterations {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "RootFinder.secant: cancelled"))
            }
            if currentObjective == 0.0 {
                return Ok(currentPoint)
            }
            Double denominator = currentObjective - previousObjective
            if denominator == 0.0 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "RootFinder.secant: zero slope"))
            }
            Double step = currentObjective * (currentPoint - previousPoint)
                / denominator
            Double nextPoint = currentPoint - step
            if !isFinite(nextPoint) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "RootFinder.secant: non-finite iterate"))
            }
            Result<Double, Error> nextValue = _evaluate(context, function,
                nextPoint, "RootFinder.secant")
            if nextValue.isErr() {
                return Err(nextValue.error())
            }
            previousPoint = currentPoint
            previousObjective = currentObjective
            currentPoint = nextPoint
            currentObjective = nextValue.value()
            if abs(step) <= tolerance * (1.0 + abs(currentPoint)) {
                return Ok(currentPoint)
            }
            iteration = iteration + 1
        }
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "RootFinder.secant: did not converge"))
    }

    static Result<Double, Error> find(Context context,
        Double(Double) function, Double lower, Double upper,
        Double tolerance, Int maximumIterations) {
        return RootFinder.brent(context, function, lower, upper, tolerance,
            maximumIterations)
    }

    static Result<Unit, Error> _validateBracket(Double lower, Double upper,
        Double tolerance, Int maximumIterations, String algorithm) {
        if !isFinite(lower) || !isFinite(upper) || lower >= upper {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                algorithm + ": invalid bracket"))
        }
        return _validateTolerance(tolerance, maximumIterations, algorithm)
    }

    static Result<Unit, Error> _validateTolerance(Double tolerance,
        Int maximumIterations, String algorithm) {
        if isNaN(tolerance) || isInf(tolerance) || tolerance <= 0.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                algorithm + ": invalid tolerance"))
        }
        if maximumIterations < 1 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                algorithm + ": invalid iteration limit"))
        }
        return Ok(unit)
    }

    static Result<Double, Error> _evaluate(Context context,
        Double(Double) function, Double point, String algorithm) {
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled,
                algorithm + ": cancelled"))
        }
        Double value = function(point)
        if isNaN(value) || isInf(value) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                algorithm + ": non-finite function value"))
        }
        return Ok(value)
    }
}
```
