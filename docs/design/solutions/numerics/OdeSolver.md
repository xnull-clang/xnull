# `OdeSolver`

| 项 | 值 |
| --- | --- |
| 类型 | `class OdeSolver`（静态算子） |
| 包 | `xdk.numerics` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Pair`、`Matrix`、`Vector`、`Linalg`、`BasicError`、`ErrorKind` |

---

## 1. 定位

一阶常微分方程初值问题：固定步长 RK4、自适应 Dormand-Prince 5(4)、带雅可比的隐式 Euler。

不做：事件检测、稠密输出、刚性 BDF/Radau、边值问题、微分代数方程、随机微分方程、自动微分、并行。

---

## 2. 设计逻辑

- 全部静态；右端函数 `derivative(time, state)` 与雅可比 `jacobian(time, state)` 由调用方提供。
- 只做前向积分：`endTime > initialTime`；反向积分是 X 缺口。
- 固定步长方法用最后一个短步精确落在 `endTime`；输出包含初始点。
- 自适应方法用 Dormand-Prince 5(4) 的 5 阶解推进、4 阶解估错；误差按 `tolerance * (1 + |y|)` 归一。
- 隐式 Euler 用 Newton 迭代解 `y_{n+1} = y_n + h f(t+h, y_{n+1})`；系统矩阵 `I - h J` 交给 `xdk.linalg` 求解。
- 右端/雅可比返回非有限值或维度不符时立即 `InvalidArgument`。
- 输出布局：`Pair.first` 是时间列表，`Pair.second` 是状态列表；两者长度相等，每个状态长度 = 初值长度。
- 所有长操作首参 `Context`；每步/每个 Newton 迭代检查取消。

---

## 3. 表示与不变量

无实例字段；类不可实例化。

不变量：

- `initialState` 非空，所有分量有限。
- `initialTime`/`endTime` 有限；`endTime >= initialTime`；相等时只返回初始行。
- `stepSize`/`initialStep`/`maximumStep`/`tolerance` 有限且 `> 0`。
- `maximumSteps`/`maximumIterations` `>= 1`。
- 右端返回的列表长度必须等于状态维度；每个分量有限。
- 雅可比必须是 `dimension × dimension` 的有限 `Matrix`。
- 不保存回调、状态历史或矩阵分解。

---

## 4. 生命周期

静态；无 close；无资源；可并发调用（调用方保证回调线程安全）。`Context` 只用于取消查询。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `OdeSolver()` | 无 | 私有；禁止外部实例化 | 外部 `new` 不可用 |

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `solveRk4` | 固定步长 RK4 | `Context context, List<Double>(Double, List<Double>) derivative, Double initialTime, List<Double> initialState, Double endTime, Double stepSize, Int maximumSteps` | `Result<Pair<List<Double>, List<List<Double>>>, Error>` | 参数/回调维度/非有限/步数上限/取消 |
| `solveDormandPrince` | 自适应 RK45 | `Context context, List<Double>(Double, List<Double>) derivative, Double initialTime, List<Double> initialState, Double endTime, Double tolerance, Double initialStep, Double maximumStep, Int maximumSteps` | 同上 | 参数/误差估计非有限/步长下溢/取消 |
| `solveImplicitEuler` | 隐式 Euler + Newton | `Context context, List<Double>(Double, List<Double>) derivative, Matrix(Double, List<Double>) jacobian, Double initialTime, List<Double> initialState, Double endTime, Double stepSize, Double tolerance, Int maximumIterations, Int maximumSteps` | 同上 | 参数/雅可比/奇异系统/不收敛/取消 |
| `solve` | 默认自适应入口 | `Context context, List<Double>(Double, List<Double>) derivative, Double initialTime, List<Double> initialState, Double endTime, Double tolerance, Int maximumSteps` | 同上 | 同 Dormand-Prince |

### 7.2 语义

- 输出时间严格递增；`times.get(0) == initialTime`，最后一个时间等于 `endTime`。
- 固定步长：最后一步使用 `min(stepSize, endTime - time)`；不允许跳过终点。
- 自适应：`initialStep` 会被 `maximumStep` 截断；接受步后按误差调整，拒绝步按误差缩小。
- 误差归一：`abs(error_i) <= tolerance * (1 + abs(y5_i))` 对所有分量成立才接受。
- 步长小于 `1e-12 * (1 + abs(time))` 仍不能接受：`InvalidArgument`。
- 隐式 Euler 的 Newton 收敛条件：`delta.norm() <= tolerance * (1 + next.norm())`。
- `solve` 的默认步长：`initialStep = (endTime - initialTime) / 100`，`maximumStep = (endTime - initialTime) / 10`。

---

## 8. 使用的技术

- 经典四阶 Runge-Kutta；
- Dormand-Prince 5(4) 嵌入对与误差控制；
- 步长接受/拒绝与安全因子；
- 隐式 Euler + Newton；
- 雅可比矩阵与 `Linalg.solve`；
- 维度/有限值检查；
- 协作取消。

---

## 9. 需要的支撑

- 语言：class、`Int`、`Double`、`Bool`、`List`、`Result`；
- 数学：`abs`、`max`、`sqrt`、`pow`、`isNaN`、`isInf`、`isFinite`；
- 线性代数：`Matrix`、`Vector`、`Linalg.solve`；
- 执行：`Context.isCancelled`；
- 错误：`BasicError`、`ErrorKind.InvalidArgument`、`ErrorKind.Cancelled`；
- 容器：`Pair`、`List.copy`、`List.push`。

---

## 10. 依赖的特性/接口/类

[`Context`](../../core/execution/Context.md)、[`Pair`](../../core/collections/Pair.md)、[`Matrix`](../../platform/linalg/Matrix.md)、[`Vector`](../../platform/linalg/Vector.md)、[`Linalg`](../../platform/linalg/Linalg.md)、[`BasicError`](../../core/errors/BasicError.md)、[`ErrorKind`](../../core/errors/ErrorKind.md)。

---

## 11. 所有权与并发

静态；无共享可变状态；可并发调用。输入状态只借用；输出时间/状态列表是新的副本。`Context` 不保存。类不可实例化，无相等语义。

---

## 12. 示例与反例

正确：`solveRk4(context, derivative, 0.0, [1.0, 0.0], 10.0, 0.01, 100000)` 积分谐振子；`solveDormandPrince` 给 `1e-8` 容差；`solveImplicitEuler` 提供解析雅可比。  
反例：反向积分；右端返回长度不符的列表；雅可比不是方阵；忽略 `Linalg.solve` 的奇异错误；用固定步长 RK4 解刚性方程并期望稳定；把输出状态列表当内部缓存修改。

---

## 13. 测试/场景义务

指数衰减/谐振子/Logistic 方程；RK4 的步长收敛阶；Dormand-Prince 的接受/拒绝/步长上限/下溢；隐式 Euler 的 Newton 收敛/奇异雅可比/迭代上限；初值含 NaN/Inf；`endTime == initialTime`；`endTime < initialTime`；步长 0/负；`maximumSteps` 1；右端维度不符；雅可比维度不符；取消；输出首尾时间与状态一致性。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class OdeSolver {
    private OdeSolver() {}

    static Result<Pair<List<Double>, List<List<Double>>>, Error> solveRk4(
        Context context, List<Double>(Double, List<Double>) derivative,
        Double initialTime, List<Double> initialState, Double endTime,
        Double stepSize, Int maximumSteps) {
        if context == null {
            throw "OdeSolver.solveRk4: null context"
        }
        if derivative == null {
            throw "OdeSolver.solveRk4: null derivative"
        }
        Result<Unit, Error> validation = _validateProblem(initialTime,
            initialState, endTime, maximumSteps, "OdeSolver.solveRk4")
        if validation.isErr() {
            return Err(validation.error())
        }
        validation = _validateStep(stepSize, "OdeSolver.solveRk4")
        if validation.isErr() {
            return Err(validation.error())
        }
        Int dimension = initialState.length()
        Double time = initialTime
        List<Double> state = initialState.copy()
        List<Double> times = [time]
        List<List<Double>> states = [state.copy()]
        Int stepCount = 0
        while time < endTime {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "OdeSolver.solveRk4: cancelled"))
            }
            if stepCount >= maximumSteps {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "OdeSolver.solveRk4: step limit exceeded"))
            }
            Double step = stepSize
            if time + step > endTime {
                step = endTime - time
            }
            Result<List<Double>, Error> first = _evaluateDerivative(context,
                derivative, time, state, dimension, "OdeSolver.solveRk4")
            if first.isErr() {
                return Err(first.error())
            }
            Result<List<Double>, Error> second = _evaluateDerivative(context,
                derivative, time + step / 2.0,
                _addScaled(state, first.value(), step / 2.0), dimension,
                "OdeSolver.solveRk4")
            if second.isErr() {
                return Err(second.error())
            }
            Result<List<Double>, Error> third = _evaluateDerivative(context,
                derivative, time + step / 2.0,
                _addScaled(state, second.value(), step / 2.0), dimension,
                "OdeSolver.solveRk4")
            if third.isErr() {
                return Err(third.error())
            }
            Result<List<Double>, Error> fourth = _evaluateDerivative(context,
                derivative, time + step,
                _addScaled(state, third.value(), step), dimension,
                "OdeSolver.solveRk4")
            if fourth.isErr() {
                return Err(fourth.error())
            }
            List<Double> increment = []
            Int index = 0
            while index < dimension {
                increment.push((first.value().get(index)
                    + 2.0 * second.value().get(index)
                    + 2.0 * third.value().get(index)
                    + fourth.value().get(index)) / 6.0)
                index = index + 1
            }
            state = _addScaled(state, increment, step)
            if !_isFiniteList(state) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "OdeSolver.solveRk4: non-finite state"))
            }
            time = time + step
            times.push(time)
            states.push(state.copy())
            stepCount = stepCount + 1
        }
        return Ok(new Pair<List<Double>, List<List<Double>>>(times, states))
    }

    static Result<Pair<List<Double>, List<List<Double>>>, Error>
        solveDormandPrince(Context context,
        List<Double>(Double, List<Double>) derivative, Double initialTime,
        List<Double> initialState, Double endTime, Double tolerance,
        Double initialStep, Double maximumStep, Int maximumSteps) {
        if context == null {
            throw "OdeSolver.solveDormandPrince: null context"
        }
        if derivative == null {
            throw "OdeSolver.solveDormandPrince: null derivative"
        }
        Result<Unit, Error> validation = _validateProblem(initialTime,
            initialState, endTime, maximumSteps, "OdeSolver.solveDormandPrince")
        if validation.isErr() {
            return Err(validation.error())
        }
        validation = _validateStep(initialStep, "OdeSolver.solveDormandPrince")
        if validation.isErr() {
            return Err(validation.error())
        }
        if !isFinite(maximumStep) || maximumStep <= 0.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "OdeSolver.solveDormandPrince: invalid maximum step"))
        }
        if isNaN(tolerance) || isInf(tolerance) || tolerance <= 0.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "OdeSolver.solveDormandPrince: invalid tolerance"))
        }
        Int dimension = initialState.length()
        Double time = initialTime
        List<Double> state = initialState.copy()
        List<Double> times = [time]
        List<List<Double>> states = [state.copy()]
        Double step = initialStep
        if step > maximumStep {
            step = maximumStep
        }
        Int stepCount = 0
        while time < endTime {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "OdeSolver.solveDormandPrince: cancelled"))
            }
            if stepCount >= maximumSteps {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "OdeSolver.solveDormandPrince: step limit exceeded"))
            }
            Double remaining = endTime - time
            if step > remaining {
                step = remaining
            }
            Result<Pair<List<Double>, List<Double>>, Error> attempt =
                _dormandPrinceStep(context, derivative, time, state, step,
                    dimension)
            if attempt.isErr() {
                return Err(attempt.error())
            }
            Double errorNorm = _errorNorm(attempt.value().second,
                attempt.value().first, tolerance)
            if isNaN(errorNorm) || isInf(errorNorm) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "OdeSolver.solveDormandPrince: invalid error estimate"))
            }
            if errorNorm <= 1.0 {
                time = time + step
                state = attempt.value().first
                if !_isFiniteList(state) {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "OdeSolver.solveDormandPrince: non-finite state"))
                }
                times.push(time)
                states.push(state.copy())
                stepCount = stepCount + 1
                Double factor = 5.0
                if errorNorm > 0.0 {
                    factor = 0.9 * pow(errorNorm, 0.0 - 0.2)
                }
                if factor < 0.2 {
                    factor = 0.2
                }
                if factor > 5.0 {
                    factor = 5.0
                }
                step = step * factor
                if step > maximumStep {
                    step = maximumStep
                }
            } else {
                Double factor = 0.9 * pow(errorNorm, 0.0 - 0.25)
                if factor < 0.1 {
                    factor = 0.1
                }
                if factor > 0.5 {
                    factor = 0.5
                }
                step = step * factor
                if step < 1e-12 * (1.0 + abs(time)) {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "OdeSolver.solveDormandPrince: step size underflow"))
                }
            }
        }
        return Ok(new Pair<List<Double>, List<List<Double>>>(times, states))
    }

    static Result<Pair<List<Double>, List<List<Double>>>, Error>
        solveImplicitEuler(Context context,
        List<Double>(Double, List<Double>) derivative,
        Matrix(Double, List<Double>) jacobian, Double initialTime,
        List<Double> initialState, Double endTime, Double stepSize,
        Double tolerance, Int maximumIterations, Int maximumSteps) {
        if context == null {
            throw "OdeSolver.solveImplicitEuler: null context"
        }
        if derivative == null || jacobian == null {
            throw "OdeSolver.solveImplicitEuler: null callback"
        }
        Result<Unit, Error> validation = _validateProblem(initialTime,
            initialState, endTime, maximumSteps, "OdeSolver.solveImplicitEuler")
        if validation.isErr() {
            return Err(validation.error())
        }
        validation = _validateStep(stepSize, "OdeSolver.solveImplicitEuler")
        if validation.isErr() {
            return Err(validation.error())
        }
        if isNaN(tolerance) || isInf(tolerance) || tolerance <= 0.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "OdeSolver.solveImplicitEuler: invalid tolerance"))
        }
        if maximumIterations < 1 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "OdeSolver.solveImplicitEuler: invalid iteration limit"))
        }
        Int dimension = initialState.length()
        Double time = initialTime
        Vector current = new Vector(initialState)
        List<Double> times = [time]
        List<List<Double>> states = [current.toList()]
        Int stepCount = 0
        while time < endTime {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "OdeSolver.solveImplicitEuler: cancelled"))
            }
            if stepCount >= maximumSteps {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "OdeSolver.solveImplicitEuler: step limit exceeded"))
            }
            Double step = stepSize
            if time + step > endTime {
                step = endTime - time
            }
            Double nextTime = time + step
            Vector next = current.copy()
            Bool converged = false
            Int iteration = 0
            while iteration < maximumIterations {
                Result<List<Double>, Error> derivativeValue =
                    _evaluateDerivative(context, derivative, nextTime,
                        next.toList(), dimension, "OdeSolver.solveImplicitEuler")
                if derivativeValue.isErr() {
                    return Err(derivativeValue.error())
                }
                List<Double> residual = []
                Int index = 0
                while index < dimension {
                    residual.push(next.get(index) - current.get(index)
                        - step * derivativeValue.value().get(index))
                    index = index + 1
                }
                Matrix jacobianValue = jacobian(nextTime, next.toList())
                if jacobianValue == null
                    || jacobianValue.rowCount() != dimension
                    || jacobianValue.columnCount() != dimension {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "OdeSolver.solveImplicitEuler: invalid jacobian"))
                }
                List<Double> systemValues = []
                Int rowIndex = 0
                while rowIndex < dimension {
                    Int columnIndex = 0
                    while columnIndex < dimension {
                        Double identity = 0.0
                        if rowIndex == columnIndex {
                            identity = 1.0
                        }
                        systemValues.push(identity
                            - step * jacobianValue.get(rowIndex, columnIndex))
                        columnIndex = columnIndex + 1
                    }
                    rowIndex = rowIndex + 1
                }
                Result<Vector, Error> delta = Linalg.solve(
                    new Matrix(dimension, dimension, systemValues),
                    new Vector(residual))
                if delta.isErr() {
                    return Err(delta.error())
                }
                next = next.add(delta.value())
                if delta.value().norm()
                    <= tolerance * (1.0 + next.norm()) {
                    converged = true
                    break
                }
                iteration = iteration + 1
            }
            if !converged {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "OdeSolver.solveImplicitEuler: Newton did not converge"))
            }
            time = nextTime
            current = next
            if !_isFiniteList(current.toList()) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "OdeSolver.solveImplicitEuler: non-finite state"))
            }
            times.push(time)
            states.push(current.toList())
            stepCount = stepCount + 1
        }
        return Ok(new Pair<List<Double>, List<List<Double>>>(times, states))
    }

    static Result<Pair<List<Double>, List<List<Double>>>, Error> solve(
        Context context, List<Double>(Double, List<Double>) derivative,
        Double initialTime, List<Double> initialState, Double endTime,
        Double tolerance, Int maximumSteps) {
        if context == null {
            throw "OdeSolver.solve: null context"
        }
        if derivative == null {
            throw "OdeSolver.solve: null derivative"
        }
        Result<Unit, Error> validation = _validateProblem(initialTime,
            initialState, endTime, maximumSteps, "OdeSolver.solve")
        if validation.isErr() {
            return Err(validation.error())
        }
        if isNaN(tolerance) || isInf(tolerance) || tolerance <= 0.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "OdeSolver.solve: invalid tolerance"))
        }
        if endTime < initialTime {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "OdeSolver.solve: end time is before initial time"))
        }
        if endTime == initialTime {
            List<Double> times = [initialTime]
            List<List<Double>> states = [initialState.copy()]
            return Ok(new Pair<List<Double>, List<List<Double>>>(times, states))
        }
        Double interval = endTime - initialTime
        Double initialStep = interval / 100.0
        Double maximumStep = interval / 10.0
        return OdeSolver.solveDormandPrince(context, derivative, initialTime,
            initialState, endTime, tolerance, initialStep, maximumStep,
            maximumSteps)
    }

    static Result<Unit, Error> _validateProblem(Double initialTime,
        List<Double> initialState, Double endTime, Int maximumSteps,
        String algorithm) {
        if initialState == null || initialState.length() == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                algorithm + ": empty initial state"))
        }
        if !isFinite(initialTime) || !isFinite(endTime) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                algorithm + ": non-finite time"))
        }
        if endTime < initialTime {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                algorithm + ": end time is before initial time"))
        }
        if maximumSteps < 1 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                algorithm + ": invalid step limit"))
        }
        Int index = 0
        while index < initialState.length() {
            if !isFinite(initialState.get(index)) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    algorithm + ": non-finite initial state"))
            }
            index = index + 1
        }
        return Ok(unit)
    }

    static Result<Unit, Error> _validateStep(Double stepSize,
        String algorithm) {
        if !isFinite(stepSize) || stepSize <= 0.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                algorithm + ": invalid step size"))
        }
        return Ok(unit)
    }

    static Result<List<Double>, Error> _evaluateDerivative(Context context,
        List<Double>(Double, List<Double>) derivative, Double time,
        List<Double> state, Int dimension, String algorithm) {
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled,
                algorithm + ": cancelled"))
        }
        Int stateIndex = 0
        while stateIndex < state.length() {
            if !isFinite(state.get(stateIndex)) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    algorithm + ": non-finite state"))
            }
            stateIndex = stateIndex + 1
        }
        List<Double> result = derivative(time, state.copy())
        if result == null || result.length() != dimension {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                algorithm + ": derivative dimension mismatch"))
        }
        Int index = 0
        while index < result.length() {
            if !isFinite(result.get(index)) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    algorithm + ": non-finite derivative"))
            }
            index = index + 1
        }
        return Ok(result.copy())
    }

    static List<Double> _addScaled(List<Double> base, List<Double> increment,
        Double factor) {
        List<Double> result = []
        Int index = 0
        while index < base.length() {
            result.push(base.get(index) + increment.get(index) * factor)
            index = index + 1
        }
        return result
    }

    static List<Double> _subtract(List<Double> left, List<Double> right) {
        List<Double> result = []
        Int index = 0
        while index < left.length() {
            result.push(left.get(index) - right.get(index))
            index = index + 1
        }
        return result
    }

    static Result<Pair<List<Double>, List<Double>>, Error>
        _dormandPrinceStep(Context context,
        List<Double>(Double, List<Double>) derivative, Double time,
        List<Double> state, Double step, Int dimension) {
        Result<List<Double>, Error> first = _evaluateDerivative(context,
            derivative, time, state, dimension, "OdeSolver._dormandPrinceStep")
        if first.isErr() {
            return Err(first.error())
        }
        List<Double> secondState = _addScaled(state, first.value(), step / 5.0)
        Result<List<Double>, Error> second = _evaluateDerivative(context,
            derivative, time + step / 5.0, secondState, dimension,
            "OdeSolver._dormandPrinceStep")
        if second.isErr() {
            return Err(second.error())
        }
        List<Double> thirdState = _addScaled(state, first.value(), 3.0 * step / 40.0)
        thirdState = _addScaled(thirdState, second.value(), 9.0 * step / 40.0)
        Result<List<Double>, Error> third = _evaluateDerivative(context,
            derivative, time + 3.0 * step / 10.0, thirdState, dimension,
            "OdeSolver._dormandPrinceStep")
        if third.isErr() {
            return Err(third.error())
        }
        List<Double> fourthState = _addScaled(state, first.value(), 44.0 * step / 45.0)
        fourthState = _addScaled(fourthState, second.value(), -56.0 * step / 15.0)
        fourthState = _addScaled(fourthState, third.value(), 32.0 * step / 9.0)
        Result<List<Double>, Error> fourth = _evaluateDerivative(context,
            derivative, time + 4.0 * step / 5.0, fourthState, dimension,
            "OdeSolver._dormandPrinceStep")
        if fourth.isErr() {
            return Err(fourth.error())
        }
        List<Double> fifthState = _addScaled(state, first.value(), 19372.0 * step / 6561.0)
        fifthState = _addScaled(fifthState, second.value(), -25360.0 * step / 2187.0)
        fifthState = _addScaled(fifthState, third.value(), 64448.0 * step / 6561.0)
        fifthState = _addScaled(fifthState, fourth.value(), -212.0 * step / 729.0)
        Result<List<Double>, Error> fifth = _evaluateDerivative(context,
            derivative, time + 8.0 * step / 9.0, fifthState, dimension,
            "OdeSolver._dormandPrinceStep")
        if fifth.isErr() {
            return Err(fifth.error())
        }
        List<Double> sixthState = _addScaled(state, first.value(), 9017.0 * step / 3168.0)
        sixthState = _addScaled(sixthState, second.value(), -355.0 * step / 33.0)
        sixthState = _addScaled(sixthState, third.value(), 46732.0 * step / 5247.0)
        sixthState = _addScaled(sixthState, fourth.value(), 49.0 * step / 176.0)
        sixthState = _addScaled(sixthState, fifth.value(), -5103.0 * step / 18656.0)
        Result<List<Double>, Error> sixth = _evaluateDerivative(context,
            derivative, time + step, sixthState, dimension,
            "OdeSolver._dormandPrinceStep")
        if sixth.isErr() {
            return Err(sixth.error())
        }
        List<Double> fifthOrder = _addScaled(state, first.value(), 35.0 * step / 384.0)
        fifthOrder = _addScaled(fifthOrder, third.value(), 500.0 * step / 1113.0)
        fifthOrder = _addScaled(fifthOrder, fourth.value(), 125.0 * step / 192.0)
        fifthOrder = _addScaled(fifthOrder, fifth.value(), -2187.0 * step / 6784.0)
        fifthOrder = _addScaled(fifthOrder, sixth.value(), 11.0 * step / 84.0)
        Result<List<Double>, Error> seventh = _evaluateDerivative(context,
            derivative, time + step, fifthOrder, dimension,
            "OdeSolver._dormandPrinceStep")
        if seventh.isErr() {
            return Err(seventh.error())
        }
        List<Double> fourthOrder = _addScaled(state, first.value(), 5179.0 * step / 57600.0)
        fourthOrder = _addScaled(fourthOrder, third.value(), 7571.0 * step / 16695.0)
        fourthOrder = _addScaled(fourthOrder, fourth.value(), 393.0 * step / 640.0)
        fourthOrder = _addScaled(fourthOrder, fifth.value(), -92097.0 * step / 339200.0)
        fourthOrder = _addScaled(fourthOrder, sixth.value(), 187.0 * step / 2100.0)
        fourthOrder = _addScaled(fourthOrder, seventh.value(), step / 40.0)
        List<Double> error = _subtract(fifthOrder, fourthOrder)
        return Ok(new Pair<List<Double>, List<Double>>(fifthOrder, error))
    }

    static Bool _isFiniteList(List<Double> values) {
        Int index = 0
        while index < values.length() {
            if !isFinite(values.get(index)) {
                return false
            }
            index = index + 1
        }
        return true
    }

    static Double _errorNorm(List<Double> error, List<Double> solution,
        Double tolerance) {
        Double maximum = 0.0
        Int index = 0
        while index < error.length() {
            Double scale = tolerance * (1.0 + abs(solution.get(index)))
            Double ratio = abs(error.get(index)) / scale
            if ratio > maximum {
                maximum = ratio
            }
            index = index + 1
        }
        return maximum
    }
}
```
