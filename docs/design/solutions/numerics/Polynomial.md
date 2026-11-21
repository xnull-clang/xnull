# `Polynomial`

| 项 | 值 |
| --- | --- |
| 类型 | `class Polynomial` |
| 包 | `xdk.numerics` |
| 稳定性 | `preview` |
| 依赖 | `Complex`、`Matrix`、`Vector`、`QrDecomposition`、`Context`、`Pair` |

---

## 1. 定位

单变量实系数多项式：升幂系数、Horner 求值、复值求值、导数、积分、加减乘、长除法、最小二乘拟合、复根与实根。

不做：符号表达式、因式分解、区间算术、Chebyshev/Legendre 等基变换、多变量多项式、任意精度系数。

---

## 2. 设计逻辑

- 不可变值对象；`_coefficients` 升幂存放，构造时复制并裁掉高次零系数。
- 零多项式用空列表表示，`degree()` 返回 `-1`；常数多项式 `degree()` 为 `0`。
- 系数允许 IEEE NaN/±Inf；求值按 IEEE 传播；`roots`/`fit` 要求系数/数据有限，否则 `InvalidArgument`。
- 乘法/除法可能扩大次数；结果长度用 `Long` 估算，超过 `Int` 上限返回 `InvalidArgument`。
- 复根统一用 `Complex`；二次方程用稳定公式，三次及以上用 Durand-Kerner 同时迭代。
- 拟合复用 `xdk.linalg` 的 QR 最小二乘，不在本类重写分解。
- `roots`/`realRoots` 是长操作，首参 `Context`；求值/微积分是 O(n) 纯计算，不接 `Context`。
- `fit` 的复杂度由设计矩阵规模决定，底层 `QrDecomposition` 无取消点；超大拟合应由调用方分块或改用专门工具。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_coefficients` | `List<Double>` | 升幂系数；末尾不是 0.0（NaN 不算 0.0） |

不变量：

- 零多项式：`_coefficients` 为空；`degree() == -1`。
- 非零：最高次系数非 `0.0`；长度 = `degree + 1`。
- 列表不可变；`coefficients()` 返回副本。
- 系数索引从 0 开始；负索引是合同错误。

---

## 4. 生命周期

不可变；无 close；无资源；可跨任务共享。

---

## 5. 构造契约

构造器私有；公共入口如下。`null` 是合同错误（panic）。

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Polynomial.of(List<Double> coefficients)` | 升幂系数 | 非 null；空列表 = 零多项式 | null → panic |
| `Polynomial.zero()` | 无 | 零多项式 | 无 |
| `Polynomial.constant(Double value)` | `value` | 任意 Double | 无 |
| `Polynomial.monomial(Int degree, Double coefficient)` | `degree >= 0` | 任意 Double 系数 | 负次数 → panic |
| `Polynomial.fit(List<Double> xValues, List<Double> yValues, Int degree)` | 等长、有限、点数 ≥ degree+1 | 最小二乘 | `InvalidArgument`；null → panic |

---

## 6. 字段表

见 §3；字段私有、只读。

---

## 7. 方法总表 / 详表

### 7.1 方法总表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `coefficients` | 系数副本 | 无 | `List<Double>` | 无 |
| `coefficient` | 单系数 | `Int index` | `Double` | 负索引 → panic；超界返回 0.0 |
| `degree` | 次数 | 无 | `Int` | 无 |
| `coefficientCount` | 系数个数 | 无 | `Int` | 无 |
| `isZero` | 是否零多项式 | 无 | `Bool` | 无 |
| `evaluate` | 实值求值 | `Double value` | `Double` | 无 |
| `evaluateComplex` | 复值求值 | `Complex value` | `Complex` | null → panic |
| `derivative` | 导数 | 无 | `Polynomial` | 无 |
| `integral` | 不定积分 | `Double constantTerm` | `Polynomial` | 无 |
| `add` | 加 | `Polynomial other` | `Polynomial` | null → panic |
| `subtract` | 减 | `Polynomial other` | `Polynomial` | null → panic |
| `multiply` | 乘 | `Polynomial other` | `Result<Polynomial, Error>` | 结果过长 → `InvalidArgument` |
| `scale` | 数乘 | `Double factor` | `Polynomial` | 无 |
| `divide` | 长除法 | `Polynomial divisor` | `Result<Pair<Polynomial, Polynomial>, Error>` | 除零多项式/过长 |
| `fit` | 最小二乘拟合 | `List<Double> xValues, List<Double> yValues, Int degree` | `Result<Polynomial, Error>` | 长度/有限性/秩亏 |
| `roots` | 全部复根 | `Context context, Double tolerance, Int maximumIterations` | `Result<List<Complex>, Error>` | 零多项式/非有限/不收敛/取消 |
| `realRoots` | 实根 | 同上 | `Result<List<Double>, Error>` | 同上 |
| `equals` | 系数相等 | `Polynomial other` | `Bool` | null → false |
| `toString` | 文本 | 无 | `String` | 无 |

### 7.2 语义

- 零多项式 `roots` 失败：根集合无限，不能返回有限列表。
- `roots` 返回按 `real` 升序、再按 `imag` 升序排序的列表；重根会重复出现。
- `realRoots` 的判定阈值是 `tolerance * max(1.0, abs(real))`；虚部绝对值不超过阈值才计入。
- `fit` 使用 QR 最小二乘；秩亏返回 `InvalidArgument`，不返回最小范数解。
- `divide` 返回 `(quotient, remainder)`；满足 `被除多项式 = divisor * quotient + remainder`，`remainder.degree < divisor.degree`。

---

## 8. 使用的技术

- 升幂系数 + 末尾裁剪；
- Horner 求值；
- 多项式长除法；
- 稳定二次公式；
- Durand-Kerner 同时迭代；
- QR 最小二乘（复用 `xdk.linalg`）；
- 复数运算（复用 `Complex`）；
- 排序与容差判定。

---

## 9. 需要的支撑

- 语言：class、`Int`、`Long`、`Double`、`Bool`、`List`、`String`、`Result`；
- 数学：`abs`、`sqrt`、`sign`、`PI`、`isNaN`、`isInf`、`pow`；
- 线性代数：`Matrix`、`Vector`、`QrDecomposition`；
- 执行：`Context.isCancelled`；
- 错误：`BasicError`、`ErrorKind.InvalidArgument`、`ErrorKind.Cancelled`；
- 容器：`Pair`、`List.copy`、`List.push`、`List.remove`、`List.set`、`sortedBy`。

---

## 10. 依赖的特性/接口/类

[`Complex`](../../core/math/Complex.md)、[`Context`](../../core/execution/Context.md)、[`Pair`](../../core/collections/Pair.md)、[`Matrix`](../../platform/linalg/Matrix.md)、[`Vector`](../../platform/linalg/Vector.md)、[`QrDecomposition`](../../platform/linalg/QrDecomposition.md)、[`BasicError`](../../core/errors/BasicError.md)、[`ErrorKind`](../../core/errors/ErrorKind.md)。

---

## 11. 所有权与并发

不可变；构造复制系数列表；`coefficients()` 返回副本。可跨任务共享；无锁；无 close。`roots`/`realRoots` 使用传入的 `Context`，不保存。相等是系数逐项相等；可作 `Map` 键（实现方需提供稳定哈希）。

---

## 12. 示例与反例

正确：`Polynomial.of([-6.0, 11.0, -6.0, 1.0])`；`evaluate(2.0)`；`derivative()`；`multiply(other)` 处理 `Err`；`roots(context, 1e-12, 1000)`；`fit(xValues, yValues, 3)` 处理秩亏。  
反例：期望 `coefficients()` 返回内部列表；对零多项式求根并期望空列表；忽略 `multiply` 的长度错误；用 `==` 比较浮点系数；把重根只返回一次；在 `fit` 中传非有限数据。

---

## 13. 测试/场景义务

零/常数/一次/二次/高次；末尾零裁剪；`coefficient` 超界；`evaluate` 的 Horner 与直接展开一致；`evaluateComplex`；导数/积分再求导；加减乘的结合与交换；长除法恒等式；除零；结果过长；二次方程三个判别式分支与稳定公式；三次以上重根/近重根/共轭复根；`roots` 排序；`realRoots` 容差；`fit` 精确拟合/过定/秩亏/非有限；`toString`；`equals` 的 NaN/长度；取消。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class Polynomial {
    final List<Double> _coefficients

    private Polynomial(List<Double> coefficients) {
        if coefficients == null {
            throw "Polynomial: null coefficients"
        }
        List<Double> copied = coefficients.copy()
        while copied.length() > 0 {
            if copied.get(copied.length() - 1) != 0.0 {
                break
            }
            copied.remove(copied.length() - 1)
        }
        _coefficients = copied
    }

    static Polynomial of(List<Double> coefficients) {
        return new Polynomial(coefficients)
    }

    static Polynomial zero() {
        return new Polynomial([])
    }

    static Polynomial constant(Double value) {
        if value == 0.0 {
            return Polynomial.zero()
        }
        return new Polynomial([value])
    }

    static Polynomial monomial(Int degree, Double coefficient) {
        if degree < 0 {
            throw "Polynomial.monomial: negative degree"
        }
        if coefficient == 0.0 {
            return Polynomial.zero()
        }
        List<Double> values = []
        Int index = 0
        while index < degree {
            values.push(0.0)
            index = index + 1
        }
        values.push(coefficient)
        return new Polynomial(values)
    }

    static Result<Polynomial, Error> fit(List<Double> xValues,
        List<Double> yValues, Int degree) {
        if xValues == null || yValues == null {
            throw "Polynomial.fit: null data"
        }
        if degree < 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Polynomial.fit: negative degree"))
        }
        if xValues.length() != yValues.length() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Polynomial.fit: length mismatch"))
        }
        Long required = (degree as Long) + 1
        if (xValues.length() as Long) < required {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Polynomial.fit: not enough points"))
        }
        Long elementCount = (xValues.length() as Long) * required
        if elementCount > 2147483647 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Polynomial.fit: design matrix too large"))
        }
        Int rowIndex = 0
        while rowIndex < xValues.length() {
            if !isFinite(xValues.get(rowIndex)) || !isFinite(yValues.get(rowIndex)) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "Polynomial.fit: non-finite data"))
            }
            rowIndex = rowIndex + 1
        }
        List<Double> values = []
        rowIndex = 0
        while rowIndex < xValues.length() {
            Double xValue = xValues.get(rowIndex)
            Double powerValue = 1.0
            Int columnIndex = 0
            while columnIndex <= degree {
                values.push(powerValue)
                powerValue = powerValue * xValue
                columnIndex = columnIndex + 1
            }
            rowIndex = rowIndex + 1
        }
        Matrix matrix = new Matrix(xValues.length(), degree + 1, values)
        Result<QrDecomposition, Error> factorResult =
            QrDecomposition.factor(matrix)
        if factorResult.isErr() {
            return Err(factorResult.error())
        }
        Result<Vector, Error> solution = factorResult.value()
            .solveLeastSquares(new Vector(yValues.copy()))
        if solution.isErr() {
            return Err(solution.error())
        }
        return Ok(Polynomial.of(solution.value().toList()))
    }

    List<Double> coefficients() {
        return _coefficients.copy()
    }

    Double coefficient(Int index) {
        if index < 0 {
            throw "Polynomial.coefficient: negative index"
        }
        if index >= _coefficients.length() {
            return 0.0
        }
        return _coefficients.get(index)
    }

    Int degree() {
        return _coefficients.length() - 1
    }

    Int coefficientCount() {
        return _coefficients.length()
    }

    Bool isZero() {
        return _coefficients.length() == 0
    }

    Double evaluate(Double value) {
        Double result = 0.0
        Int index = _coefficients.length() - 1
        while index >= 0 {
            result = result * value + _coefficients.get(index)
            index = index - 1
        }
        return result
    }

    Complex evaluateComplex(Complex value) {
        if value == null {
            throw "Polynomial.evaluateComplex: null value"
        }
        Complex result = Complex.zero()
        Int index = _coefficients.length() - 1
        while index >= 0 {
            result = result.mul(value).add(
                Complex.of(_coefficients.get(index), 0.0))
            index = index - 1
        }
        return result
    }

    Polynomial derivative() {
        if _coefficients.length() <= 1 {
            return Polynomial.zero()
        }
        List<Double> values = []
        Int index = 1
        while index < _coefficients.length() {
            values.push(_coefficients.get(index) * (index as Double))
            index = index + 1
        }
        return new Polynomial(values)
    }

    Polynomial integral(Double constantTerm) {
        List<Double> values = []
        values.push(constantTerm)
        Int index = 0
        while index < _coefficients.length() {
            values.push(_coefficients.get(index) / ((index + 1) as Double))
            index = index + 1
        }
        return new Polynomial(values)
    }

    Polynomial add(Polynomial other) {
        if other == null {
            throw "Polynomial.add: null other"
        }
        Int count = self.coefficientCount()
        if other.coefficientCount() > count {
            count = other.coefficientCount()
        }
        List<Double> values = []
        Int index = 0
        while index < count {
            values.push(self.coefficient(index) + other.coefficient(index))
            index = index + 1
        }
        return new Polynomial(values)
    }

    Polynomial subtract(Polynomial other) {
        if other == null {
            throw "Polynomial.subtract: null other"
        }
        Int count = self.coefficientCount()
        if other.coefficientCount() > count {
            count = other.coefficientCount()
        }
        List<Double> values = []
        Int index = 0
        while index < count {
            values.push(self.coefficient(index) - other.coefficient(index))
            index = index + 1
        }
        return new Polynomial(values)
    }

    Polynomial scale(Double factor) {
        List<Double> values = []
        Int index = 0
        while index < _coefficients.length() {
            values.push(_coefficients.get(index) * factor)
            index = index + 1
        }
        return new Polynomial(values)
    }

    Result<Polynomial, Error> multiply(Polynomial other) {
        if other == null {
            throw "Polynomial.multiply: null other"
        }
        if isZero() || other.isZero() {
            return Ok(Polynomial.zero())
        }
        Long resultCount = (self.coefficientCount() as Long)
            + (other.coefficientCount() as Long) - 1
        if resultCount > 2147483647 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Polynomial.multiply: result too large"))
        }
        List<Double> values = []
        Long index = 0
        while index < resultCount {
            values.push(0.0)
            index = index + 1
        }
        Int leftIndex = 0
        while leftIndex < _coefficients.length() {
            Int rightIndex = 0
            while rightIndex < other.coefficientCount() {
                Int position = leftIndex + rightIndex
                values.set(position, values.get(position)
                    + _coefficients.get(leftIndex)
                    * other.coefficient(rightIndex))
                rightIndex = rightIndex + 1
            }
            leftIndex = leftIndex + 1
        }
        return Ok(new Polynomial(values))
    }

    Result<Pair<Polynomial, Polynomial>, Error> divide(Polynomial divisor) {
        if divisor == null {
            throw "Polynomial.divide: null divisor"
        }
        if divisor.isZero() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Polynomial.divide: zero divisor"))
        }
        if self.degree() < divisor.degree() {
            return Ok(new Pair<Polynomial, Polynomial>(
                Polynomial.zero(), self))
        }
        Int quotientCount = self.degree() - divisor.degree() + 1
        List<Double> quotientValues = []
        Int clearIndex = 0
        while clearIndex < quotientCount {
            quotientValues.push(0.0)
            clearIndex = clearIndex + 1
        }
        List<Double> remainderValues = _coefficients.copy()
        Double divisorLeading = divisor.coefficient(divisor.degree())
        Int position = quotientCount - 1
        while position >= 0 {
            Double factor = remainderValues.get(position + divisor.degree())
                / divisorLeading
            quotientValues.set(position, factor)
            Int index = 0
            while index <= divisor.degree() {
                Int target = position + index
                remainderValues.set(target, remainderValues.get(target)
                    - factor * divisor.coefficient(index))
                index = index + 1
            }
            position = position - 1
        }
        Polynomial quotient = new Polynomial(quotientValues)
        Polynomial remainder = new Polynomial(remainderValues)
        return Ok(new Pair<Polynomial, Polynomial>(quotient, remainder))
    }

    Result<List<Complex>, Error> roots(Context context, Double tolerance,
        Int maximumIterations) {
        if context == null {
            throw "Polynomial.roots: null context"
        }
        if isZero() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Polynomial.roots: zero polynomial"))
        }
        if isNaN(tolerance) || isInf(tolerance) || tolerance <= 0.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Polynomial.roots: invalid tolerance"))
        }
        if maximumIterations < 1 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Polynomial.roots: invalid iteration limit"))
        }
        Int index = 0
        while index < _coefficients.length() {
            if !isFinite(_coefficients.get(index)) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "Polynomial.roots: non-finite coefficient"))
            }
            index = index + 1
        }
        if self.degree() == 0 {
            return Ok([])
        }
        if self.degree() == 1 {
            Double root = 0.0 - self.coefficient(0) / self.coefficient(1)
            if !isFinite(root) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "Polynomial.roots: non-finite root"))
            }
            List<Complex> result = []
            result.push(Complex.of(root, 0.0))
            return Ok(result)
        }
        if self.degree() == 2 {
            List<Complex> quadraticRoots = Polynomial._quadraticRoots(
                self.coefficient(2), self.coefficient(1),
                self.coefficient(0))
            if !Polynomial._areFiniteRoots(quadraticRoots) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "Polynomial.roots: non-finite root"))
            }
            return Ok(quadraticRoots)
        }
        return _durandKerner(context, tolerance, maximumIterations)
    }

    Result<List<Double>, Error> realRoots(Context context, Double tolerance,
        Int maximumIterations) {
        Result<List<Complex>, Error> allRoots = self.roots(context, tolerance,
            maximumIterations)
        if allRoots.isErr() {
            return Err(allRoots.error())
        }
        List<Double> realValues = []
        Int index = 0
        while index < allRoots.value().length() {
            Complex root = allRoots.value().get(index)
            Double scale = 1.0
            if abs(root.real()) > 1.0 {
                scale = abs(root.real())
            }
            if abs(root.imag()) <= tolerance * scale {
                realValues.push(root.real())
            }
            index = index + 1
        }
        return Ok(sortedBy(realValues,
            (Double left, Double right) -> left < right))
    }

    Bool equals(Polynomial other) {
        if other == null {
            return false
        }
        if _coefficients.length() != other.coefficientCount() {
            return false
        }
        Int index = 0
        while index < _coefficients.length() {
            if _coefficients.get(index) != other.coefficient(index) {
                return false
            }
            index = index + 1
        }
        return true
    }

    String toString() {
        if isZero() {
            return "0"
        }
        String result = ""
        Int index = self.degree()
        while index >= 0 {
            Double coefficientValue = _coefficients.get(index)
            if coefficientValue != 0.0 {
                if coefficientValue < 0.0 {
                    if result == "" {
                        result = "-"
                    } else {
                        result = result + " - "
                    }
                } else if result != "" {
                    result = result + " + "
                }
                Double magnitude = abs(coefficientValue)
                if index == 0 || magnitude != 1.0 {
                    result = result + str(magnitude)
                }
                if index > 0 {
                    result = result + "x"
                    if index > 1 {
                        result = result + "^" + str(index)
                    }
                }
            }
            index = index - 1
        }
        return result
    }

    Result<List<Complex>, Error> _durandKerner(Context context,
        Double tolerance, Int maximumIterations) {
        Int count = self.degree()
        Double leading = self.coefficient(count)
        Double radius = 1.0
        Int coefficientIndex = 0
        while coefficientIndex < count {
            Double ratio = abs(self.coefficient(coefficientIndex) / leading)
            if ratio > radius - 1.0 {
                radius = 1.0 + ratio
            }
            coefficientIndex = coefficientIndex + 1
        }
        if !isFinite(radius) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Polynomial.roots: invalid root radius"))
        }
        List<Complex> current = []
        Int rootIndex = 0
        while rootIndex < count {
            Double angle = 2.0 * PI() * (rootIndex as Double) / (count as Double)
            current.push(Complex.fromPolar(radius, angle))
            rootIndex = rootIndex + 1
        }
        Int iteration = 0
        while iteration < maximumIterations {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "Polynomial.roots: cancelled"))
            }
            List<Complex> next = []
            Double maximumRelativeChange = 0.0
            rootIndex = 0
            while rootIndex < count {
                Complex value = current.get(rootIndex)
                Complex denominator = Complex.of(leading, 0.0)
                Int otherIndex = 0
                while otherIndex < count {
                    if otherIndex != rootIndex {
                        denominator = denominator.mul(
                            value.sub(current.get(otherIndex)))
                    }
                    otherIndex = otherIndex + 1
                }
                Result<Complex, Error> division =
                    self.evaluateComplex(value).div(denominator)
                if division.isErr() {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "Polynomial.roots: singular iteration"))
                }
                Complex delta = division.value()
                next.push(value.sub(delta))
                Double scale = 1.0
                if value.abs() > 1.0 {
                    scale = value.abs()
                }
                Double relativeChange = delta.abs() / scale
                if relativeChange > maximumRelativeChange {
                    maximumRelativeChange = relativeChange
                }
                rootIndex = rootIndex + 1
            }
            current = next
            if maximumRelativeChange <= tolerance {
                if !Polynomial._areFiniteRoots(current) {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "Polynomial.roots: non-finite root"))
                }
                return Ok(Polynomial._sortRoots(current))
            }
            iteration = iteration + 1
        }
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "Polynomial.roots: did not converge"))
    }

    static List<Complex> _quadraticRoots(Double quadratic, Double linear,
        Double constant) {
        Double discriminant = linear * linear
            - 4.0 * quadratic * constant
        if discriminant < 0.0 {
            Double real = (0.0 - linear) / (2.0 * quadratic)
            Double imaginary = sqrt(0.0 - discriminant)
                / (2.0 * abs(quadratic))
            List<Complex> result = []
            result.push(Complex.of(real, imaginary))
            result.push(Complex.of(real, 0.0 - imaginary))
            return Polynomial._sortRoots(result)
        }
        if discriminant == 0.0 {
            Double root = (0.0 - linear) / (2.0 * quadratic)
            List<Complex> result = []
            result.push(Complex.of(root, 0.0))
            result.push(Complex.of(root, 0.0))
            return result
        }
        Double squareRoot = sqrt(discriminant)
        Double signValue = sign(linear)
        if signValue == 0.0 {
            signValue = 1.0
        }
        Double stableRoot = -0.5 * (linear + signValue * squareRoot)
        List<Complex> result = []
        result.push(Complex.of(stableRoot / quadratic, 0.0))
        result.push(Complex.of(constant / stableRoot, 0.0))
        return Polynomial._sortRoots(result)
    }

    static Bool _areFiniteRoots(List<Complex> roots) {
        Int index = 0
        while index < roots.length() {
            if !isFinite(roots.get(index).real())
                || !isFinite(roots.get(index).imag()) {
                return false
            }
            index = index + 1
        }
        return true
    }

    static List<Complex> _sortRoots(List<Complex> roots) {
        return sortedBy(roots,
            (Complex left, Complex right) -> left.real() < right.real()
                || (left.real() == right.real()
                    && left.imag() < right.imag()))
    }
}
```
