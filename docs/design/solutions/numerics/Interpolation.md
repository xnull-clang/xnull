# `Interpolation`

| 项 | 值 |
| --- | --- |
| 类型 | `class Interpolation` |
| 包 | `xdk.numerics` |
| 稳定性 | `preview` |
| 依赖 | `BasicError`、`ErrorKind` |

---

## 1. 定位

一维分段插值：线性、自然三次样条、夹持三次样条、PCHIP（保形分段三次 Hermite）；在节点区间内求值与求导数。

不做：最近邻、二维/多维插值、B 样条基、平滑样条、外推、参数曲线、最小二乘拟合。

---

## 2. 设计逻辑

- 不可变值对象；构造时校验节点严格递增并复制列表。
- 内部统一为“每段一个局部多项式”：第 `i` 段以 `t = x - xValues[i]` 为自变量，系数升幂存放。
  - 线性段：`[y_i, slope_i]`。
  - 三次段：`[a, b, c, d]`，即 `a + b t + c t^2 + d t^3`。
- 不同工厂只改变“如何算每段系数”，`evaluate`/`derivative` 共用同一套二分定位与 Horner 求值。
- 自然样条用三对角方程求二阶导数，夹持样条用端点斜率方程；PCHIP 用 Fritsch-Carlson 单调斜率。
- `evaluate`/`derivative` 只接受 `[xValues.first, xValues.last]` 内的值；区间外返回 `InvalidArgument`，不静默外推。
- 构造与求值都是单线程、无全局状态；不接 `Context`（O(n) 构造、O(log n) 求值）。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_xValues` | `List<Double>` | 严格递增节点，长度 `>= 2` |
| `_pieceCoefficients` | `List<List<Double>>` | 每段局部多项式系数；长度 = 节点数 - 1 |
| `_pieceDegree` | `Int` | 1（线性）或 3（三次） |

不变量：

- `_xValues` 所有元素有限且严格递增。
- 每段系数长度 = `_pieceDegree + 1`，所有系数有限。
- `_pieceCoefficients.length() == _xValues.length() - 1`。
- 列表深复制；外部无法取得内部列表。
- 值不可变；求值不修改对象。

---

## 4. 生命周期

不可变；无 close；无资源；可跨任务共享。

---

## 5. 构造契约

构造器私有；公共入口如下。`null` 是合同错误（panic）；数据问题返回 `InvalidArgument`。

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Interpolation.linear(List<Double> xValues, List<Double> yValues)` | 等长、`>=2`、x 严格递增、有限 | 分段线性 | `InvalidArgument` |
| `Interpolation.naturalCubicSpline(List<Double> xValues, List<Double> yValues)` | 同上 | 自然边界 | 同上 |
| `Interpolation.clampedCubicSpline(List<Double> xValues, List<Double> yValues, Double leftSlope, Double rightSlope)` | 同上；端点斜率有限 | 夹持边界 | 同上 |
| `Interpolation.pchip(List<Double> xValues, List<Double> yValues)` | 同上 | 保形分段三次 | 同上 |

---

## 6. 字段表

见 §3；字段私有、只读。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `evaluate` | 区间内求值 | `Double value` | `Result<Double, Error>` | 越界/非有限/结果非有限 |
| `derivative` | 区间内导数 | `Double value` | `Result<Double, Error>` | 同上 |
| `knotCount` | 节点数 | 无 | `Int` | 无 |
| `pieceCount` | 段数 | 无 | `Int` | 无 |
| `pieceDegree` | 段次数 | 无 | `Int` | 无 |
| `xValues` | 节点副本 | 无 | `List<Double>` | 无 |
| `equals` | 结构相等 | `Interpolation other` | `Bool` | null → false |
| `toString` | 文本 | 无 | `String` | 无 |

### 7.2 语义

- `evaluate` 在节点处返回对应 `y` 值（浮点误差内）。
- `derivative` 对线性段返回常数斜率；对三次段返回 `b + 2c t + 3d t^2`；节点处取左侧段的导数（首节点取第一段）。
- `equals` 比较节点与每段系数逐项相等；属于精确结构比较，不做容差。
- 不外推；需要外推时调用方自行构造边界段或使用其他模型。

---

## 8. 使用的技术

- 局部多项式表示；
- 二分定位；
- Horner 求值与求导；
- 三对角方程（Thomas 算法）；
- 自然/夹持样条边界条件；
- Fritsch-Carlson 保形斜率；
- 数据校验与深复制。

---

## 9. 需要的支撑

- 语言：class、`Int`、`Double`、`Bool`、`List`、`String`、`Result`；
- 数学：`abs`、`isNaN`、`isInf`、`isFinite`；
- 错误：`BasicError`、`ErrorKind.InvalidArgument`。

---

## 10. 依赖的特性/接口/类

[`BasicError`](../../core/errors/BasicError.md)、[`ErrorKind`](../../core/errors/ErrorKind.md)。

---

## 11. 所有权与并发

不可变；构造深复制节点与系数；`xValues()` 返回副本。可跨任务共享；无锁；无 close。相等是结构相等；可作 `Map` 键（实现方需提供稳定哈希）。

---

## 12. 示例与反例

正确：`Interpolation.linear(xValues, yValues)`；`naturalCubicSpline` 后在节点之间求值；`pchip` 保持单调数据；`derivative` 检查左右导数。  
反例：x 非严格递增；节点含 NaN；在 `[x0, xn-1]` 之外求值；期望 `pchip` 产生过冲；把 `xValues()` 当内部列表修改；用 `equals` 做浮点容差比较。

---

## 13. 测试/场景义务

两节点/三节点/多节点；线性精确通过节点；自然样条在节点处连续、二阶导连续、端点二阶导为 0；夹持样条端点导数等于给定斜率；PCHIP 对单调数据保持单调、不过冲；重复 x；非有限 x/y；越界求值；导数与数值差分一致；`xValues()` 独立性；`equals`。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class Interpolation {
    final List<Double> _xValues
    final List<List<Double>> _pieceCoefficients
    final Int _pieceDegree

    private Interpolation(List<Double> xValues,
        List<List<Double>> pieceCoefficients, Int pieceDegree) {
        if xValues == null || pieceCoefficients == null {
            throw "Interpolation: null data"
        }
        if xValues.length() < 2 {
            throw "Interpolation: at least two knots are required"
        }
        if pieceDegree != 1 && pieceDegree != 3 {
            throw "Interpolation: unsupported degree"
        }
        List<Double> copiedX = xValues.copy()
        Int index = 0
        while index < copiedX.length() {
            if !isFinite(copiedX.get(index)) {
                throw "Interpolation: non-finite knot"
            }
            if index > 0 && copiedX.get(index) <= copiedX.get(index - 1) {
                throw "Interpolation: knots must be strictly increasing"
            }
            index = index + 1
        }
        if pieceCoefficients.length() != copiedX.length() - 1 {
            throw "Interpolation: piece count mismatch"
        }
        List<List<Double>> copiedPieces = []
        index = 0
        while index < pieceCoefficients.length() {
            List<Double> piece = pieceCoefficients.get(index).copy()
            if piece.length() != pieceDegree + 1 {
                throw "Interpolation: piece degree mismatch"
            }
            Int coefficientIndex = 0
            while coefficientIndex < piece.length() {
                if !isFinite(piece.get(coefficientIndex)) {
                    throw "Interpolation: non-finite coefficient"
                }
                coefficientIndex = coefficientIndex + 1
            }
            copiedPieces.push(piece)
            index = index + 1
        }
        _xValues = copiedX
        _pieceCoefficients = copiedPieces
        _pieceDegree = pieceDegree
    }

    static Result<Interpolation, Error> linear(List<Double> xValues,
        List<Double> yValues) {
        Result<Unit, Error> validation = _validateData(xValues, yValues,
            "Interpolation.linear")
        if validation.isErr() {
            return Err(validation.error())
        }
        List<List<Double>> pieces = []
        Int index = 0
        while index < xValues.length() - 1 {
            Double width = xValues.get(index + 1) - xValues.get(index)
            Double slope = (yValues.get(index + 1) - yValues.get(index)) / width
            List<Double> piece = [yValues.get(index), slope]
            pieces.push(piece)
            index = index + 1
        }
        return Ok(new Interpolation(xValues, pieces, 1))
    }

    static Result<Interpolation, Error> naturalCubicSpline(
        List<Double> xValues, List<Double> yValues) {
        Result<Unit, Error> validation = _validateData(xValues, yValues,
            "Interpolation.naturalCubicSpline")
        if validation.isErr() {
            return Err(validation.error())
        }
        Result<List<Double>, Error> secondDerivatives =
            _naturalSecondDerivatives(xValues, yValues)
        if secondDerivatives.isErr() {
            return Err(secondDerivatives.error())
        }
        return _cubicInterpolation(xValues, yValues, secondDerivatives.value(),
            "Interpolation.naturalCubicSpline")
    }

    static Result<Interpolation, Error> clampedCubicSpline(
        List<Double> xValues, List<Double> yValues, Double leftSlope,
        Double rightSlope) {
        Result<Unit, Error> validation = _validateData(xValues, yValues,
            "Interpolation.clampedCubicSpline")
        if validation.isErr() {
            return Err(validation.error())
        }
        if !isFinite(leftSlope) || !isFinite(rightSlope) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Interpolation.clampedCubicSpline: non-finite end slope"))
        }
        Result<List<Double>, Error> secondDerivatives =
            _clampedSecondDerivatives(xValues, yValues, leftSlope, rightSlope)
        if secondDerivatives.isErr() {
            return Err(secondDerivatives.error())
        }
        return _cubicInterpolation(xValues, yValues, secondDerivatives.value(),
            "Interpolation.clampedCubicSpline")
    }

    static Result<Interpolation, Error> pchip(List<Double> xValues,
        List<Double> yValues) {
        Result<Unit, Error> validation = _validateData(xValues, yValues,
            "Interpolation.pchip")
        if validation.isErr() {
            return Err(validation.error())
        }
        Result<List<Double>, Error> slopes = _pchipSlopes(xValues, yValues)
        if slopes.isErr() {
            return Err(slopes.error())
        }
        List<List<Double>> pieces = []
        Int index = 0
        while index < xValues.length() - 1 {
            Double width = xValues.get(index + 1) - xValues.get(index)
            Double delta = (yValues.get(index + 1) - yValues.get(index)) / width
            Double leftDerivative = slopes.value().get(index)
            Double rightDerivative = slopes.value().get(index + 1)
            Double third = (3.0 * delta - 2.0 * leftDerivative
                - rightDerivative) / width
            Double fourth = (leftDerivative + rightDerivative
                - 2.0 * delta) / (width * width)
            List<Double> piece = [yValues.get(index), leftDerivative,
                third, fourth]
            pieces.push(piece)
            index = index + 1
        }
        return Ok(new Interpolation(xValues, pieces, 3))
    }

    Result<Double, Error> evaluate(Double value) {
        if isNaN(value) || isInf(value) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Interpolation.evaluate: non-finite value"))
        }
        if value < _xValues.get(0)
            || value > _xValues.get(_xValues.length() - 1) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Interpolation.evaluate: value outside knot range"))
        }
        Int pieceIndex = _findPiece(value)
        Double local = value - _xValues.get(pieceIndex)
        List<Double> piece = _pieceCoefficients.get(pieceIndex)
        Double result = 0.0
        Int index = piece.length() - 1
        while index >= 0 {
            result = result * local + piece.get(index)
            index = index - 1
        }
        if isNaN(result) || isInf(result) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Interpolation.evaluate: non-finite result"))
        }
        return Ok(result)
    }

    Result<Double, Error> derivative(Double value) {
        if isNaN(value) || isInf(value) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Interpolation.derivative: non-finite value"))
        }
        if value < _xValues.get(0)
            || value > _xValues.get(_xValues.length() - 1) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Interpolation.derivative: value outside knot range"))
        }
        Int pieceIndex = _findPiece(value)
        Double local = value - _xValues.get(pieceIndex)
        List<Double> piece = _pieceCoefficients.get(pieceIndex)
        Double result = 0.0
        Int index = piece.length() - 1
        while index >= 1 {
            result = result * local + piece.get(index) * (index as Double)
            index = index - 1
        }
        if isNaN(result) || isInf(result) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Interpolation.derivative: non-finite result"))
        }
        return Ok(result)
    }

    Int knotCount() {
        return _xValues.length()
    }

    Int pieceCount() {
        return _pieceCoefficients.length()
    }

    Int pieceDegree() {
        return _pieceDegree
    }

    List<Double> xValues() {
        return _xValues.copy()
    }

    Bool equals(Interpolation other) {
        if other == null {
            return false
        }
        if _pieceDegree != other.pieceDegree()
            || _xValues.length() != other.knotCount() {
            return false
        }
        Int index = 0
        while index < _xValues.length() {
            if _xValues.get(index) != other._xValues.get(index) {
                return false
            }
            index = index + 1
        }
        if _pieceCoefficients.length() != other._pieceCoefficients.length() {
            return false
        }
        index = 0
        while index < _pieceCoefficients.length() {
            List<Double> left = _pieceCoefficients.get(index)
            List<Double> right = other._pieceCoefficients.get(index)
            if left.length() != right.length() {
                return false
            }
            Int coefficientIndex = 0
            while coefficientIndex < left.length() {
                if left.get(coefficientIndex) != right.get(coefficientIndex) {
                    return false
                }
                coefficientIndex = coefficientIndex + 1
            }
            index = index + 1
        }
        return true
    }

    String toString() {
        return "Interpolation(knots=" + str(_xValues.length())
            + ", degree=" + str(_pieceDegree) + ")"
    }

    Int _findPiece(Double value) {
        Int low = 0
        Int high = _xValues.length() - 1
        while high - low > 1 {
            Int middle = (low + high) / 2
            if value < _xValues.get(middle) {
                high = middle
            } else {
                low = middle
            }
        }
        return low
    }

    static Result<Unit, Error> _validateData(List<Double> xValues,
        List<Double> yValues, String algorithm) {
        if xValues == null || yValues == null {
            throw "Interpolation: null data"
        }
        if xValues.length() != yValues.length() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                algorithm + ": length mismatch"))
        }
        if xValues.length() < 2 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                algorithm + ": at least two knots are required"))
        }
        Int index = 0
        while index < xValues.length() {
            if !isFinite(xValues.get(index)) || !isFinite(yValues.get(index)) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    algorithm + ": non-finite data"))
            }
            if index > 0 && xValues.get(index) <= xValues.get(index - 1) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    algorithm + ": knots must be strictly increasing"))
            }
            index = index + 1
        }
        return Ok(unit)
    }

    static Result<List<Double>, Error> _naturalSecondDerivatives(
        List<Double> xValues, List<Double> yValues) {
        Int count = xValues.length()
        List<Double> lower = []
        List<Double> diagonal = []
        List<Double> upper = []
        List<Double> rightHandSide = []
        Int index = 0
        while index < count {
            lower.push(0.0)
            diagonal.push(0.0)
            upper.push(0.0)
            rightHandSide.push(0.0)
            index = index + 1
        }
        diagonal.set(0, 1.0)
        diagonal.set(count - 1, 1.0)
        index = 1
        while index < count - 1 {
            Double leftWidth = xValues.get(index) - xValues.get(index - 1)
            Double rightWidth = xValues.get(index + 1) - xValues.get(index)
            Double leftSlope = (yValues.get(index) - yValues.get(index - 1))
                / leftWidth
            Double rightSlope = (yValues.get(index + 1) - yValues.get(index))
                / rightWidth
            lower.set(index, leftWidth)
            diagonal.set(index, 2.0 * (leftWidth + rightWidth))
            upper.set(index, rightWidth)
            rightHandSide.set(index,
                6.0 * (rightSlope - leftSlope))
            index = index + 1
        }
        return _solveTridiagonal(lower, diagonal, upper, rightHandSide,
            "Interpolation.naturalCubicSpline")
    }

    static Result<List<Double>, Error> _clampedSecondDerivatives(
        List<Double> xValues, List<Double> yValues, Double leftSlope,
        Double rightSlope) {
        Int count = xValues.length()
        List<Double> lower = []
        List<Double> diagonal = []
        List<Double> upper = []
        List<Double> rightHandSide = []
        Int index = 0
        while index < count {
            lower.push(0.0)
            diagonal.push(0.0)
            upper.push(0.0)
            rightHandSide.push(0.0)
            index = index + 1
        }
        Double firstWidth = xValues.get(1) - xValues.get(0)
        Double firstSlope = (yValues.get(1) - yValues.get(0)) / firstWidth
        diagonal.set(0, 2.0)
        upper.set(0, 1.0)
        rightHandSide.set(0, 6.0 / firstWidth * (firstSlope - leftSlope))
        index = 1
        while index < count - 1 {
            Double leftWidth = xValues.get(index) - xValues.get(index - 1)
            Double rightWidth = xValues.get(index + 1) - xValues.get(index)
            Double leftDelta = (yValues.get(index) - yValues.get(index - 1))
                / leftWidth
            Double rightDelta = (yValues.get(index + 1) - yValues.get(index))
                / rightWidth
            lower.set(index, leftWidth)
            diagonal.set(index, 2.0 * (leftWidth + rightWidth))
            upper.set(index, rightWidth)
            rightHandSide.set(index, 6.0 * (rightDelta - leftDelta))
            index = index + 1
        }
        Double lastWidth = xValues.get(count - 1) - xValues.get(count - 2)
        Double lastSlope = (yValues.get(count - 1) - yValues.get(count - 2))
            / lastWidth
        lower.set(count - 1, 1.0)
        diagonal.set(count - 1, 2.0)
        rightHandSide.set(count - 1,
            6.0 / lastWidth * (rightSlope - lastSlope))
        return _solveTridiagonal(lower, diagonal, upper, rightHandSide,
            "Interpolation.clampedCubicSpline")
    }

    static Result<List<Double>, Error> _solveTridiagonal(List<Double> lower,
        List<Double> diagonal, List<Double> upper,
        List<Double> rightHandSide, String algorithm) {
        Int count = diagonal.length()
        List<Double> lowerCopy = lower.copy()
        List<Double> diagonalCopy = diagonal.copy()
        List<Double> upperCopy = upper.copy()
        List<Double> rightCopy = rightHandSide.copy()
        Int index = 1
        while index < count {
            if diagonalCopy.get(index - 1) == 0.0 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    algorithm + ": singular tridiagonal system"))
            }
            Double factor = lowerCopy.get(index) / diagonalCopy.get(index - 1)
            diagonalCopy.set(index,
                diagonalCopy.get(index) - factor * upperCopy.get(index - 1))
            rightCopy.set(index,
                rightCopy.get(index) - factor * rightCopy.get(index - 1))
            index = index + 1
        }
        if diagonalCopy.get(count - 1) == 0.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                algorithm + ": singular tridiagonal system"))
        }
        List<Double> result = []
        Int fillIndex = 0
        while fillIndex < count {
            result.push(0.0)
            fillIndex = fillIndex + 1
        }
        result.set(count - 1,
            rightCopy.get(count - 1) / diagonalCopy.get(count - 1))
        index = count - 2
        while index >= 0 {
            result.set(index, (rightCopy.get(index)
                - upperCopy.get(index) * result.get(index + 1))
                / diagonalCopy.get(index))
            index = index - 1
        }
        return Ok(result)
    }

    static Result<Interpolation, Error> _cubicInterpolation(
        List<Double> xValues, List<Double> yValues,
        List<Double> secondDerivatives, String algorithm) {
        List<List<Double>> pieces = []
        Int index = 0
        while index < xValues.length() - 1 {
            Double width = xValues.get(index + 1) - xValues.get(index)
            Double delta = (yValues.get(index + 1) - yValues.get(index)) / width
            Double leftSecond = secondDerivatives.get(index)
            Double rightSecond = secondDerivatives.get(index + 1)
            Double first = yValues.get(index)
            Double second = delta
                - width * (2.0 * leftSecond + rightSecond) / 6.0
            Double third = leftSecond / 2.0
            Double fourth = (rightSecond - leftSecond) / (6.0 * width)
            List<Double> piece = [first, second, third, fourth]
            pieces.push(piece)
            index = index + 1
        }
        return Ok(new Interpolation(xValues, pieces, 3))
    }

    static Result<List<Double>, Error> _pchipSlopes(List<Double> xValues,
        List<Double> yValues) {
        Int count = xValues.length()
        List<Double> widths = []
        List<Double> deltas = []
        Int index = 0
        while index < count - 1 {
            Double width = xValues.get(index + 1) - xValues.get(index)
            widths.push(width)
            deltas.push((yValues.get(index + 1) - yValues.get(index)) / width)
            index = index + 1
        }
        List<Double> slopes = []
        if count == 2 {
            slopes.push(deltas.get(0))
            slopes.push(deltas.get(0))
            return Ok(slopes)
        }
        slopes.push(_endpointSlope(widths.get(0), widths.get(1),
            deltas.get(0), deltas.get(1)))
        index = 1
        while index < count - 1 {
            Double leftDelta = deltas.get(index - 1)
            Double rightDelta = deltas.get(index)
            if leftDelta * rightDelta <= 0.0 {
                slopes.push(0.0)
            } else {
                Double leftWeight = 2.0 * widths.get(index) + widths.get(index - 1)
                Double rightWeight = widths.get(index) + 2.0 * widths.get(index - 1)
                slopes.push((leftWeight + rightWeight)
                    / (leftWeight / leftDelta + rightWeight / rightDelta))
            }
            index = index + 1
        }
        slopes.push(_endpointSlope(widths.get(count - 2),
            widths.get(count - 3), deltas.get(count - 2),
            deltas.get(count - 3)))
        return Ok(slopes)
    }

    static Double _endpointSlope(Double firstWidth, Double secondWidth,
        Double firstDelta, Double secondDelta) {
        Double slope = ((2.0 * firstWidth + secondWidth) * firstDelta
            - firstWidth * secondDelta) / (firstWidth + secondWidth)
        if slope * firstDelta <= 0.0 {
            return 0.0
        }
        if firstDelta * secondDelta < 0.0
            && abs(slope) > 3.0 * abs(firstDelta) {
            return 3.0 * firstDelta
        }
        return slope
    }
}
```
