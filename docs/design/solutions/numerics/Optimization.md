# `Optimization`

| 项 | 值 |
| --- | --- |
| 类型 | `class Optimization`（静态算子） |
| 包 | `xdk.numerics` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Pair`、`BasicError`、`ErrorKind` |

---

## 1. 定位

无约束局部优化：一维有界 Brent、一维无界“括入 + Brent”、多变量 Nelder-Mead、多变量 BFGS（需要梯度）。

不做：约束优化、线性规划、全局优化、最小二乘拟合、随机搜索、自动微分、GPU/并行。

---

## 2. 设计逻辑

- 全部静态；无状态；目标函数与梯度由调用方提供。
- 一维有界用 Brent：黄金分割 + 抛物线插值，只需要目标函数值。
- 一维无界先做括入（bracket），再用 Brent 收窄；括入失败返回错误。
- 多变量默认 Nelder-Mead：无导数、实现简单、对噪声目标函数较稳；BFGS 用于目标函数可微且能提供梯度。
- 目标函数/梯度返回 NaN/±Inf 时立即 `InvalidArgument`；不继续迭代。
- 迭代次数用 `Int`，达到上限仍未满足容差返回 `InvalidArgument`。
- 结果是局部最优，不承诺全局最优；调用方应从多个初值重启。
- 所有长操作首参 `Context`；每轮迭代/线搜索检查取消。

---

## 3. 表示与不变量

无实例字段；类不可实例化。

不变量：

- 目标函数/梯度非 null；初值非空且所有分量有限。
- 容差有限且 `> 0`；迭代上限 `>= 1`。
- 一维有界要求 `lower < upper`；无界要求 `initialStep > 0` 且有限。
- 多变量维度 = 初值长度；所有候选点维度必须一致。
- 目标函数值必须是有限 `Double`。
- 不保存目标函数、梯度、历史点。

---

## 4. 生命周期

静态；无 close；无资源；可并发调用（调用方保证目标函数线程安全）。`Context` 只用于取消查询。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Optimization()` | 无 | 私有；禁止外部实例化 | 外部 `new` 不可用 |

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `minimizeBounded` | 一维有界 Brent | `Context context, Double(Double) objective, Double lower, Double upper, Double tolerance, Int maximumIterations` | `Result<Pair<Double, Double>, Error>` | 参数/非有限/不收敛/取消 |
| `minimize1d` | 一维无界 | `Context context, Double(Double) objective, Double initialPoint, Double initialStep, Double tolerance, Int maximumIterations` | 同上 | 括入失败/参数/非有限/取消 |
| `minimizeNelderMead` | 多变量无导数 | `Context context, Double(List<Double>) objective, List<Double> initialPoint, Double tolerance, Int maximumIterations` | `Result<Pair<List<Double>, Double>, Error>` | 参数/非有限/不收敛/取消 |
| `minimizeBfgs` | 多变量 BFGS | `Context context, Double(List<Double>) objective, List<Double>(List<Double>) gradient, List<Double> initialPoint, Double tolerance, Int maximumIterations` | 同上 | 参数/非有限/线搜索失败/取消 |
| `minimize` | 默认多变量入口 | `Context context, Double(List<Double>) objective, List<Double> initialPoint, Double tolerance, Int maximumIterations` | 同上 | 同 Nelder-Mead |

### 7.2 返回布局

- 一维：`Pair.first` 是最优点，`Pair.second` 是目标函数值。
- 多变量：`Pair.first` 是最优点副本，`Pair.second` 是目标函数值。
- `minimize` 等价于 `minimizeNelderMead`，默认算法在 preview 内可能调整；需要固定算法时直接调具体方法。

---

## 8. 使用的技术

- Brent 一维最小化（黄金分割 + 抛物线）；
- 括入（bracket）与步长倍增；
- Nelder-Mead 反射/扩张/收缩/压缩；
- BFGS 逆 Hessian 更新；
- Armijo 回溯线搜索；
- 有限值检查与相对容差；
- 协作取消。

---

## 9. 需要的支撑

- 语言：class、`Int`、`Double`、`Bool`、`List`、`Result`；
- 数学：`abs`、`max`、`sqrt`、`isNaN`、`isInf`、`isFinite`；
- 执行：`Context.isCancelled`；
- 错误：`BasicError`、`ErrorKind.InvalidArgument`、`ErrorKind.Cancelled`；
- 容器：`Pair`、`List.copy`、`List.push`、`List.set`。

---

## 10. 依赖的特性/接口/类

[`Context`](../../core/execution/Context.md)、[`Pair`](../../core/collections/Pair.md)、[`BasicError`](../../core/errors/BasicError.md)、[`ErrorKind`](../../core/errors/ErrorKind.md)。

---

## 11. 所有权与并发

静态；无共享可变状态；可并发调用。输入只借用；返回点/值是新对象。`Context` 不保存。类不可实例化，无相等语义。

---

## 12. 示例与反例

正确：`Optimization.minimizeBounded(context, objective, -5.0, 5.0, 1e-10, 200)`；`minimize1d` 从 `0.0` 与步长 `1.0` 括入；`minimizeNelderMead` 从 `[1.0, 1.0]` 开始；`minimizeBfgs` 提供解析梯度。  
反例：把最大化问题直接传入而不取负；对约束问题期望自动满足边界；目标函数返回 NaN 却期望继续；初值含 Inf；忽略线搜索失败；期望全局最优。

---

## 13. 测试/场景义务

二次函数有界/无界；Rosenbrock 二维；非凸多峰从不同初值；目标函数在初值处非有限；`lower >= upper`；`initialStep <= 0`；容差 0/负/NaN；迭代上限 1；Nelder-Mead 的收缩/压缩分支；BFGS 的线搜索失败/非正曲率；梯度长度不符；取消；结果代回目标函数验证。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class Optimization {
    private Optimization() {}

    static Result<Pair<Double, Double>, Error> minimizeBounded(
        Context context, Double(Double) objective, Double lower, Double upper,
        Double tolerance, Int maximumIterations) {
        if context == null {
            throw "Optimization.minimizeBounded: null context"
        }
        if objective == null {
            throw "Optimization.minimizeBounded: null objective"
        }
        if !isFinite(lower) || !isFinite(upper) || lower >= upper {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Optimization.minimizeBounded: invalid bounds"))
        }
        Result<Unit, Error> validation = _validate(tolerance,
            maximumIterations, "Optimization.minimizeBounded")
        if validation.isErr() {
            return Err(validation.error())
        }
        return _brent(context, objective, lower, upper, tolerance,
            maximumIterations)
    }

    static Result<Pair<Double, Double>, Error> minimize1d(Context context,
        Double(Double) objective, Double initialPoint, Double initialStep,
        Double tolerance, Int maximumIterations) {
        if context == null {
            throw "Optimization.minimize1d: null context"
        }
        if objective == null {
            throw "Optimization.minimize1d: null objective"
        }
        if !isFinite(initialPoint) || !isFinite(initialStep)
            || initialStep <= 0.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Optimization.minimize1d: invalid initial point or step"))
        }
        Result<Unit, Error> validation = _validate(tolerance,
            maximumIterations, "Optimization.minimize1d")
        if validation.isErr() {
            return Err(validation.error())
        }
        Result<Pair<Double, Double>, Error> bracket = _bracket(context,
            objective, initialPoint, initialStep)
        if bracket.isErr() {
            return Err(bracket.error())
        }
        return _brent(context, objective, bracket.value().first,
            bracket.value().second, tolerance, maximumIterations)
    }

    static Result<Pair<List<Double>, Double>, Error> minimizeNelderMead(
        Context context, Double(List<Double>) objective, List<Double> initialPoint,
        Double tolerance, Int maximumIterations) {
        if context == null {
            throw "Optimization.minimizeNelderMead: null context"
        }
        if objective == null {
            throw "Optimization.minimizeNelderMead: null objective"
        }
        if initialPoint == null || initialPoint.length() == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Optimization.minimizeNelderMead: empty initial point"))
        }
        Result<Unit, Error> validation = _validatePoint(initialPoint,
            "Optimization.minimizeNelderMead")
        if validation.isErr() {
            return Err(validation.error())
        }
        validation = _validate(tolerance, maximumIterations,
            "Optimization.minimizeNelderMead")
        if validation.isErr() {
            return Err(validation.error())
        }
        Int dimension = initialPoint.length()
        List<List<Double>> simplex = []
        simplex.push(initialPoint.copy())
        Int coordinate = 0
        while coordinate < dimension {
            List<Double> point = initialPoint.copy()
            Double scale = 0.05 * max(1.0, abs(initialPoint.get(coordinate)))
            if scale == 0.0 {
                scale = 0.00025
            }
            point.set(coordinate, point.get(coordinate) + scale)
            simplex.push(point)
            coordinate = coordinate + 1
        }
        List<Double> values = []
        Int pointIndex = 0
        while pointIndex < simplex.length() {
            Result<Double, Error> value = _evaluateVector(context, objective,
                simplex.get(pointIndex), "Optimization.minimizeNelderMead")
            if value.isErr() {
                return Err(value.error())
            }
            values.push(value.value())
            pointIndex = pointIndex + 1
        }
        Int iteration = 0
        while iteration < maximumIterations {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "Optimization.minimizeNelderMead: cancelled"))
            }
            Int bestIndex = 0
            Int worstIndex = 0
            Int secondWorstIndex = 0
            Int index = 1
            while index < values.length() {
                if values.get(index) < values.get(bestIndex) {
                    bestIndex = index
                }
                if values.get(index) > values.get(worstIndex) {
                    worstIndex = index
                }
                index = index + 1
            }
            if worstIndex == 0 {
                secondWorstIndex = 1
            } else {
                secondWorstIndex = 0
            }
            index = 0
            while index < values.length() {
                if index != worstIndex {
                    if values.get(index) > values.get(secondWorstIndex) {
                        secondWorstIndex = index
                    }
                }
                index = index + 1
            }
            Double spread = 0.0
            List<Double> bestPoint = simplex.get(bestIndex)
            index = 0
            while index < simplex.length() {
                Double distance = _distance(simplex.get(index), bestPoint)
                if distance > spread {
                    spread = distance
                }
                index = index + 1
            }
            if spread <= tolerance * (1.0 + _norm(bestPoint)) {
                return Ok(new Pair<List<Double>, Double>(bestPoint.copy(),
                    values.get(bestIndex)))
            }
            List<Double> centroid = _centroid(simplex, worstIndex)
            List<Double> worstPoint = simplex.get(worstIndex)
            List<Double> reflected = _pointAdd(centroid,
                _pointScale(_pointSubtract(centroid, worstPoint), 1.0))
            Result<Double, Error> reflectedValue = _evaluateVector(context,
                objective, reflected, "Optimization.minimizeNelderMead")
            if reflectedValue.isErr() {
                return Err(reflectedValue.error())
            }
            if reflectedValue.value() < values.get(bestIndex) {
                List<Double> expanded = _pointAdd(centroid,
                    _pointScale(_pointSubtract(reflected, centroid), 2.0))
                Result<Double, Error> expandedValue = _evaluateVector(context,
                    objective, expanded, "Optimization.minimizeNelderMead")
                if expandedValue.isErr() {
                    return Err(expandedValue.error())
                }
                if expandedValue.value() < reflectedValue.value() {
                    simplex.set(worstIndex, expanded)
                    values.set(worstIndex, expandedValue.value())
                } else {
                    simplex.set(worstIndex, reflected)
                    values.set(worstIndex, reflectedValue.value())
                }
            } else if reflectedValue.value() < values.get(secondWorstIndex) {
                simplex.set(worstIndex, reflected)
                values.set(worstIndex, reflectedValue.value())
            } else {
                Bool outside = reflectedValue.value() < values.get(worstIndex)
                List<Double> contracted = centroid
                if outside {
                    contracted = _pointAdd(centroid,
                        _pointScale(_pointSubtract(reflected, centroid), 0.5))
                } else {
                    contracted = _pointAdd(centroid,
                        _pointScale(_pointSubtract(worstPoint, centroid), 0.5))
                }
                Result<Double, Error> contractedValue = _evaluateVector(context,
                    objective, contracted, "Optimization.minimizeNelderMead")
                if contractedValue.isErr() {
                    return Err(contractedValue.error())
                }
                Bool accept = false
                if outside {
                    if contractedValue.value() <= reflectedValue.value() {
                        accept = true
                    }
                } else {
                    if contractedValue.value() < values.get(worstIndex) {
                        accept = true
                    }
                }
                if accept {
                    simplex.set(worstIndex, contracted)
                    values.set(worstIndex, contractedValue.value())
                } else {
                    index = 0
                    while index < simplex.length() {
                        if index != bestIndex {
                            List<Double> shrunk = _pointAdd(bestPoint,
                                _pointScale(_pointSubtract(simplex.get(index),
                                    bestPoint), 0.5))
                            simplex.set(index, shrunk)
                            Result<Double, Error> shrunkValue = _evaluateVector(
                                context, objective, shrunk,
                                "Optimization.minimizeNelderMead")
                            if shrunkValue.isErr() {
                                return Err(shrunkValue.error())
                            }
                            values.set(index, shrunkValue.value())
                        }
                        index = index + 1
                    }
                }
            }
            iteration = iteration + 1
        }
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "Optimization.minimizeNelderMead: did not converge"))
    }

    static Result<Pair<List<Double>, Double>, Error> minimizeBfgs(
        Context context, Double(List<Double>) objective,
        List<Double>(List<Double>) gradient, List<Double> initialPoint,
        Double tolerance, Int maximumIterations) {
        if context == null {
            throw "Optimization.minimizeBfgs: null context"
        }
        if objective == null || gradient == null {
            throw "Optimization.minimizeBfgs: null callback"
        }
        if initialPoint == null || initialPoint.length() == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Optimization.minimizeBfgs: empty initial point"))
        }
        Result<Unit, Error> validation = _validatePoint(initialPoint,
            "Optimization.minimizeBfgs")
        if validation.isErr() {
            return Err(validation.error())
        }
        validation = _validate(tolerance, maximumIterations,
            "Optimization.minimizeBfgs")
        if validation.isErr() {
            return Err(validation.error())
        }
        Int dimension = initialPoint.length()
        List<Double> currentPoint = initialPoint.copy()
        Result<Double, Error> currentValue = _evaluateVector(context, objective,
            currentPoint, "Optimization.minimizeBfgs")
        if currentValue.isErr() {
            return Err(currentValue.error())
        }
        Result<List<Double>, Error> currentGradient = _evaluateGradient(context,
            gradient, currentPoint, dimension, "Optimization.minimizeBfgs")
        if currentGradient.isErr() {
            return Err(currentGradient.error())
        }
        List<List<Double>> inverseHessian = _identityMatrix(dimension)
        Int iteration = 0
        while iteration < maximumIterations {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "Optimization.minimizeBfgs: cancelled"))
            }
            Double gradientNorm = _norm(currentGradient.value())
            if gradientNorm <= tolerance * max(1.0, abs(currentValue.value())) {
                return Ok(new Pair<List<Double>, Double>(currentPoint.copy(),
                    currentValue.value()))
            }
            List<Double> direction = _pointScale(
                _matrixVector(inverseHessian, currentGradient.value()), -1.0)
            Double slope = _dot(currentGradient.value(), direction)
            if slope >= 0.0 {
                inverseHessian = _identityMatrix(dimension)
                direction = _pointScale(currentGradient.value(), -1.0)
                slope = _dot(currentGradient.value(), direction)
            }
            Double step = 1.0
            List<Double> nextPoint = []
            Double nextValue = currentValue.value()
            Bool accepted = false
            Int lineIteration = 0
            while lineIteration < 50 {
                nextPoint = _pointAdd(currentPoint, _pointScale(direction, step))
                Result<Double, Error> candidate = _evaluateVector(context,
                    objective, nextPoint, "Optimization.minimizeBfgs")
                if candidate.isErr() {
                    return Err(candidate.error())
                }
                nextValue = candidate.value()
                if nextValue <= currentValue.value() + 1e-4 * step * slope {
                    accepted = true
                    break
                }
                step = step * 0.5
                lineIteration = lineIteration + 1
            }
            if !accepted {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "Optimization.minimizeBfgs: line search failed"))
            }
            Result<List<Double>, Error> nextGradient = _evaluateGradient(context,
                gradient, nextPoint, dimension, "Optimization.minimizeBfgs")
            if nextGradient.isErr() {
                return Err(nextGradient.error())
            }
            List<Double> displacement = _pointSubtract(nextPoint, currentPoint)
            List<Double> gradientChange = _pointSubtract(nextGradient.value(),
                currentGradient.value())
            Double curvature = _dot(gradientChange, displacement)
            if curvature > 1e-12 {
                List<Double> hDisplacement = _matrixVector(inverseHessian,
                    displacement)
                Double displacementHessian = _dot(displacement, hDisplacement)
                Double coefficient = (1.0 + displacementHessian / curvature)
                    / curvature
                List<List<Double>> outerDisplacement = _outerProduct(
                    displacement, displacement)
                List<List<Double>> crossOne = _outerProduct(hDisplacement,
                    displacement)
                List<List<Double>> crossTwo = _outerProduct(displacement,
                    hDisplacement)
                inverseHessian = _matrixAdd(inverseHessian,
                    _matrixScale(outerDisplacement, coefficient))
                inverseHessian = _matrixAdd(inverseHessian,
                    _matrixScale(crossOne, 0.0 - 1.0 / curvature))
                inverseHessian = _matrixAdd(inverseHessian,
                    _matrixScale(crossTwo, 0.0 - 1.0 / curvature))
            }
            currentPoint = nextPoint
            currentValue = Ok(nextValue)
            currentGradient = nextGradient
            iteration = iteration + 1
        }
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "Optimization.minimizeBfgs: did not converge"))
    }

    static Result<Pair<List<Double>, Double>, Error> minimize(Context context,
        Double(List<Double>) objective, List<Double> initialPoint,
        Double tolerance, Int maximumIterations) {
        return Optimization.minimizeNelderMead(context, objective, initialPoint,
            tolerance, maximumIterations)
    }

    static Result<Pair<Double, Double>, Error> _brent(Context context,
        Double(Double) objective, Double lower, Double upper, Double tolerance,
        Int maximumIterations) {
        Double golden = 0.6180339887498949
        Double left = lower
        Double right = upper
        Double current = left + (1.0 - golden) * (right - left)
        Double previous = current
        Double beforePrevious = current
        Result<Double, Error> currentValue = _evaluate1d(context, objective,
            current, "Optimization._brent")
        if currentValue.isErr() {
            return Err(currentValue.error())
        }
        Double currentObjective = currentValue.value()
        Double previousObjective = currentObjective
        Double beforeObjective = currentObjective
        Double lastStep = 0.0
        Double stepBeforeLast = 0.0
        Int iteration = 0
        while iteration < maximumIterations {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "Optimization._brent: cancelled"))
            }
            Double middle = 0.5 * (left + right)
            Double tolerance1 = tolerance * (1.0 + abs(current))
            Double tolerance2 = 2.0 * tolerance1
            if abs(current - middle) <= tolerance2 - 0.5 * (right - left) {
                return Ok(new Pair<Double, Double>(current, currentObjective))
            }
            Bool usedParabolic = false
            if abs(stepBeforeLast) > tolerance1 {
                Double first = (current - previous)
                    * (currentObjective - beforeObjective)
                Double second = (current - beforePrevious)
                    * (currentObjective - previousObjective)
                Double numerator = (current - beforePrevious) * second
                    - (current - previous) * first
                Double denominator = 2.0 * (second - first)
                if denominator > 0.0 {
                    numerator = 0.0 - numerator
                }
                denominator = abs(denominator)
                if abs(numerator) < abs(0.5 * denominator * stepBeforeLast)
                    && numerator > denominator * (left - current)
                    && numerator < denominator * (right - current) {
                    stepBeforeLast = lastStep
                    lastStep = numerator / denominator
                    Double candidate = current + lastStep
                    if candidate - left < tolerance2
                        || right - candidate < tolerance2 {
                        if current < middle {
                            lastStep = tolerance1
                        } else {
                            lastStep = 0.0 - tolerance1
                        }
                    }
                    usedParabolic = true
                }
            }
            if !usedParabolic {
                if current < middle {
                    stepBeforeLast = right - current
                } else {
                    stepBeforeLast = left - current
                }
                lastStep = golden * stepBeforeLast
            }
            Double candidate = current + lastStep
            Result<Double, Error> candidateValue = _evaluate1d(context,
                objective, candidate, "Optimization._brent")
            if candidateValue.isErr() {
                return Err(candidateValue.error())
            }
            Double candidateObjective = candidateValue.value()
            if candidateObjective <= currentObjective {
                if candidate < current {
                    right = current
                } else {
                    left = current
                }
                beforePrevious = previous
                beforeObjective = previousObjective
                previous = current
                previousObjective = currentObjective
                current = candidate
                currentObjective = candidateObjective
            } else {
                if candidate < current {
                    left = candidate
                } else {
                    right = candidate
                }
                if candidateObjective <= previousObjective || previous == current {
                    beforePrevious = previous
                    beforeObjective = previousObjective
                    previous = candidate
                    previousObjective = candidateObjective
                } else if candidateObjective <= beforeObjective
                    || beforePrevious == current || beforePrevious == previous {
                    beforePrevious = candidate
                    beforeObjective = candidateObjective
                }
            }
            iteration = iteration + 1
        }
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "Optimization._brent: did not converge"))
    }

    static Result<Pair<Double, Double>, Error> _bracket(Context context,
        Double(Double) objective, Double initialPoint, Double initialStep) {
        Double current = initialPoint
        Result<Double, Error> currentValue = _evaluate1d(context, objective,
            current, "Optimization._bracket")
        if currentValue.isErr() {
            return Err(currentValue.error())
        }
        Double currentObjective = currentValue.value()
        Double direction = 1.0
        Double next = current + initialStep
        Result<Double, Error> nextValue = _evaluate1d(context, objective, next,
            "Optimization._bracket")
        if nextValue.isErr() {
            return Err(nextValue.error())
        }
        Double nextObjective = nextValue.value()
        if nextObjective > currentObjective {
            direction = -1.0
            Double temporaryPoint = current
            current = next
            next = temporaryPoint
            Double temporaryObjective = currentObjective
            currentObjective = nextObjective
            nextObjective = temporaryObjective
        }
        Double step = initialStep
        Int iteration = 0
        while iteration < 100 {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "Optimization._bracket: cancelled"))
            }
            Double candidate = next + direction * step
            Result<Double, Error> candidateValue = _evaluate1d(context,
                objective, candidate, "Optimization._bracket")
            if candidateValue.isErr() {
                return Err(candidateValue.error())
            }
            if candidateValue.value() > nextObjective {
                Double lower = current
                Double upper = next
                if lower > upper {
                    lower = next
                    upper = current
                }
                return Ok(new Pair<Double, Double>(lower, upper))
            }
            current = next
            currentObjective = nextObjective
            next = candidate
            nextObjective = candidateValue.value()
            step = step * 1.6180339887498949
            iteration = iteration + 1
        }
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "Optimization._bracket: did not bracket a minimum"))
    }

    static Result<Unit, Error> _validate(Double tolerance,
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

    static Result<Unit, Error> _validatePoint(List<Double> point,
        String algorithm) {
        Int index = 0
        while index < point.length() {
            if !isFinite(point.get(index)) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    algorithm + ": non-finite initial point"))
            }
            index = index + 1
        }
        return Ok(unit)
    }

    static Result<Double, Error> _evaluate1d(Context context,
        Double(Double) objective, Double point, String algorithm) {
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled,
                algorithm + ": cancelled"))
        }
        if isNaN(point) || isInf(point) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                algorithm + ": non-finite point"))
        }
        Double value = objective(point)
        if isNaN(value) || isInf(value) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                algorithm + ": non-finite objective"))
        }
        return Ok(value)
    }

    static Result<Double, Error> _evaluateVector(Context context,
        Double(List<Double>) objective, List<Double> point, String algorithm) {
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled,
                algorithm + ": cancelled"))
        }
        Int pointIndex = 0
        while pointIndex < point.length() {
            if !isFinite(point.get(pointIndex)) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    algorithm + ": non-finite point"))
            }
            pointIndex = pointIndex + 1
        }
        Double value = objective(point.copy())
        if isNaN(value) || isInf(value) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                algorithm + ": non-finite objective"))
        }
        return Ok(value)
    }

    static Result<List<Double>, Error> _evaluateGradient(Context context,
        List<Double>(List<Double>) gradient, List<Double> point,
        Int dimension, String algorithm) {
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled,
                algorithm + ": cancelled"))
        }
        List<Double> result = gradient(point.copy())
        if result == null || result.length() != dimension {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                algorithm + ": gradient dimension mismatch"))
        }
        Int index = 0
        while index < result.length() {
            if !isFinite(result.get(index)) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    algorithm + ": non-finite gradient"))
            }
            index = index + 1
        }
        return Ok(result.copy())
    }

    static List<Double> _centroid(List<List<Double>> simplex, Int excludedIndex) {
        Int dimension = simplex.get(0).length()
        List<Double> result = []
        Int coordinate = 0
        while coordinate < dimension {
            result.push(0.0)
            coordinate = coordinate + 1
        }
        Int count = 0
        Int index = 0
        while index < simplex.length() {
            if index != excludedIndex {
                coordinate = 0
                while coordinate < dimension {
                    result.set(coordinate, result.get(coordinate)
                        + simplex.get(index).get(coordinate))
                    coordinate = coordinate + 1
                }
                count = count + 1
            }
            index = index + 1
        }
        coordinate = 0
        while coordinate < dimension {
            result.set(coordinate, result.get(coordinate) / (count as Double))
            coordinate = coordinate + 1
        }
        return result
    }

    static List<Double> _pointAdd(List<Double> left, List<Double> right) {
        List<Double> result = []
        Int index = 0
        while index < left.length() {
            result.push(left.get(index) + right.get(index))
            index = index + 1
        }
        return result
    }

    static List<Double> _pointSubtract(List<Double> left, List<Double> right) {
        List<Double> result = []
        Int index = 0
        while index < left.length() {
            result.push(left.get(index) - right.get(index))
            index = index + 1
        }
        return result
    }

    static List<Double> _pointScale(List<Double> point, Double factor) {
        List<Double> result = []
        Int index = 0
        while index < point.length() {
            result.push(point.get(index) * factor)
            index = index + 1
        }
        return result
    }

    static Double _dot(List<Double> left, List<Double> right) {
        Double result = 0.0
        Int index = 0
        while index < left.length() {
            result = result + left.get(index) * right.get(index)
            index = index + 1
        }
        return result
    }

    static Double _norm(List<Double> point) {
        return sqrt(_dot(point, point))
    }

    static Double _distance(List<Double> left, List<Double> right) {
        return _norm(_pointSubtract(left, right))
    }

    static List<List<Double>> _identityMatrix(Int dimension) {
        List<List<Double>> result = []
        Int rowIndex = 0
        while rowIndex < dimension {
            List<Double> row = []
            Int columnIndex = 0
            while columnIndex < dimension {
                if rowIndex == columnIndex {
                    row.push(1.0)
                } else {
                    row.push(0.0)
                }
                columnIndex = columnIndex + 1
            }
            result.push(row)
            rowIndex = rowIndex + 1
        }
        return result
    }

    static List<Double> _matrixVector(List<List<Double>> matrix,
        List<Double> vector) {
        List<Double> result = []
        Int rowIndex = 0
        while rowIndex < matrix.length() {
            result.push(_dot(matrix.get(rowIndex), vector))
            rowIndex = rowIndex + 1
        }
        return result
    }

    static List<List<Double>> _outerProduct(List<Double> left,
        List<Double> right) {
        List<List<Double>> result = []
        Int rowIndex = 0
        while rowIndex < left.length() {
            List<Double> row = []
            Int columnIndex = 0
            while columnIndex < right.length() {
                row.push(left.get(rowIndex) * right.get(columnIndex))
                columnIndex = columnIndex + 1
            }
            result.push(row)
            rowIndex = rowIndex + 1
        }
        return result
    }

    static List<List<Double>> _matrixAdd(List<List<Double>> left,
        List<List<Double>> right) {
        List<List<Double>> result = []
        Int rowIndex = 0
        while rowIndex < left.length() {
            List<Double> row = []
            Int columnIndex = 0
            while columnIndex < left.get(rowIndex).length() {
                row.push(left.get(rowIndex).get(columnIndex)
                    + right.get(rowIndex).get(columnIndex))
                columnIndex = columnIndex + 1
            }
            result.push(row)
            rowIndex = rowIndex + 1
        }
        return result
    }

    static List<List<Double>> _matrixScale(List<List<Double>> matrix,
        Double factor) {
        List<List<Double>> result = []
        Int rowIndex = 0
        while rowIndex < matrix.length() {
            List<Double> row = []
            Int columnIndex = 0
            while columnIndex < matrix.get(rowIndex).length() {
                row.push(matrix.get(rowIndex).get(columnIndex) * factor)
                columnIndex = columnIndex + 1
            }
            result.push(row)
            rowIndex = rowIndex + 1
        }
        return result
    }
}
```
