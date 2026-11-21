# `Numerics`

| 项 | 值 |
| --- | --- |
| 类型 | `class Numerics`（静态入口） |
| 包 | `xdk.numerics` |
| 稳定性 | `preview` |
| 依赖 | `BigInt`、`BigFloat`、`Polynomial`、`Integration`、`Optimization`、`OdeSolver`、`Fft`、`Interpolation`、`RootFinder`、`Context`、`Pair`、`RoundingMode` |

---

## 1. 定位

`xdk.numerics` 的默认入口：为常用任务提供固定默认参数的便捷方法，并暴露后端标识与默认容差。

不做：替代各领域类的完整 API；不隐藏算法选择；不重复 `xdk.linalg`/`xdk.tensor` 的矩阵/张量操作；不提供符号计算或 GPU 调度。

---

## 2. 设计逻辑

- 静态门面；无实例状态；所有方法委托到具体类型，不实现第二套算法。
- 只包装“最常用的一条路径”：默认积分、默认一维/多变量优化、默认 ODE、默认 FFT、线性/自然三次插值、Brent 求根、BigInt/BigFloat 解析、Polynomial 构造。
- 需要特定算法、特定容差或更多控制时，直接调用对应类型；`Numerics` 不是唯一入口。
- 默认参数是 preview 契约的一部分，但可能在 preview 内调整；需要稳定行为时显式调用具体方法并传参数。
- 默认入口的失败语义与底层方法完全一致；不吞掉 `Err`，不把不收敛转成 `NaN`。
- 后端标识固定为 `"X"`；不暴露 BLAS/LAPACK/FFTW/GMP 名称。

---

## 3. 表示与不变量

无实例字段；类不可实例化。

不变量：

- 所有方法静态；无缓存、无全局状态。
- 默认容差、默认迭代上限是常量，不随调用改变。
- 返回值是底层方法的新结果；不缓存、不共享可变对象。
- 不保存 `Context`、回调或输入列表。

---

## 4. 生命周期

静态；无 close；无资源；可并发调用。`Context` 只透传给底层方法。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Numerics()` | 无 | 私有；禁止外部实例化 | 外部 `new` 不可用 |

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `backendName` | 后端标识 | 无 | `String` | 无 |
| `defaultTolerance` | 默认容差 | 无 | `Double` | 无 |
| `defaultMaximumIterations` | 默认迭代上限 | 无 | `Int` | 无 |
| `defaultMaximumSteps` | 默认 ODE 步数上限 | 无 | `Int` | 无 |
| `integrate` | 默认积分 | `Context context, Double(Double) integrand, Double lower, Double upper` | `Result<Double, Error>` | 同 `Integration.integrate` |
| `minimize1d` | 默认一维优化 | `Context context, Double(Double) objective, Double lower, Double upper` | `Result<Pair<Double, Double>, Error>` | 同 `Optimization.minimizeBounded` |
| `minimize` | 默认多变量优化 | `Context context, Double(List<Double>) objective, List<Double> initialPoint` | `Result<Pair<List<Double>, Double>, Error>` | 同 `Optimization.minimizeNelderMead` |
| `solveOde` | 默认 ODE | `Context context, List<Double>(Double, List<Double>) derivative, Double initialTime, List<Double> initialState, Double endTime` | `Result<Pair<List<Double>, List<List<Double>>>, Error>` | 同 `OdeSolver.solve` |
| `forwardFft` | 复数正变换 | `Context context, List<Complex> values` | `Result<List<Complex>, Error>` | 同 `Fft.forward` |
| `inverseFft` | 复数逆变换 | `Context context, List<Complex> values` | 同上 | 同 `Fft.inverse` |
| `forwardRealFft` | 实数正变换 | `Context context, List<Double> values` | 同上 | 同 `Fft.forwardReal` |
| `inverseRealFft` | 实数逆变换 | `Context context, List<Complex> spectrum, Int outputLength` | `Result<List<Double>, Error>` | 同 `Fft.inverseReal` |
| `interpolateLinear` | 线性插值 | `List<Double> xValues, List<Double> yValues` | `Result<Interpolation, Error>` | 同 `Interpolation.linear` |
| `interpolateCubic` | 自然三次样条 | 同上 | 同上 | 同 `Interpolation.naturalCubicSpline` |
| `findRoot` | 默认求根 | `Context context, Double(Double) function, Double lower, Double upper` | `Result<Double, Error>` | 同 `RootFinder.brent` |
| `parseBigInt` | 解析 BigInt | `String text, Int maximumDigits` | `Result<BigInt, Error>` | 同 `BigInt.parse` |
| `parseBigFloat` | 解析 BigFloat | `String text, Int precisionBits, RoundingMode mode, Int maximumDigits` | `Result<BigFloat, Error>` | 同 `BigFloat.parse` |
| `polynomial` | 构造多项式 | `List<Double> coefficients` | `Polynomial` | null → panic |

### 7.2 默认参数

| 默认 | 值 |
| --- | --- |
| `defaultTolerance` | `1e-10` |
| `defaultMaximumIterations` | `1000` |
| `defaultMaximumSteps` | `100000` |
| `integrate` 的区间上限 | `defaultMaximumIterations` |
| `minimize` 的迭代上限 | `defaultMaximumIterations` |
| `solveOde` 的容差 | `1e-8` |
| `findRoot` 的容差/迭代 | `1e-12` / `200` |
| `inverseRealFft` 的容差 | `defaultTolerance` |

---

## 8. 使用的技术

- 静态门面；
- 默认参数集中；
- 委托而非复制；
- 后端字符串常量；
- 无状态并发。

---

## 9. 需要的支撑

- 语言：class、`Int`、`Double`、`String`、`List`、`Result`；
- 类型：`Context`、`Pair`、`Complex`、`RoundingMode`；
- 委托：`BigInt`、`BigFloat`、`Polynomial`、`Integration`、`Optimization`、`OdeSolver`、`Fft`、`Interpolation`、`RootFinder`；
- 错误：沿底层返回。

---

## 10. 依赖的特性/接口/类

[`BigInt`](BigInt.md)、[`BigFloat`](BigFloat.md)、[`Polynomial`](Polynomial.md)、[`Integration`](Integration.md)、[`Optimization`](Optimization.md)、[`OdeSolver`](OdeSolver.md)、[`Fft`](Fft.md)、[`Interpolation`](Interpolation.md)、[`RootFinder`](RootFinder.md)、[`Context`](../../core/execution/Context.md)、[`Pair`](../../core/collections/Pair.md)、[`Complex`](../../core/math/Complex.md)、[`RoundingMode`](../../core/math/RoundingMode.md)。

---

## 11. 所有权与并发

静态；无共享可变状态；可并发调用。输入只借用；输出是底层新结果。`Context` 不保存。类不可实例化，无相等语义。

---

## 12. 示例与反例

正确：`Numerics.integrate(context, integrand, 0.0, 1.0)`；`Numerics.minimize` 从 `[1.0, 1.0]` 开始；`Numerics.solveOde` 用默认 Dormand-Prince；`Numerics.forwardFft`。  
反例：把 `Numerics` 当完整 API，期望指定算法；期望默认容差永远不变；忽略 `Err`；用 `Numerics` 包装矩阵求解（应直接用 `xdk.linalg`）；期望后端名可配置。

---

## 13. 测试/场景义务

每个方法委托一致性（与底层同输入同输出/同错误）；默认常量；空/非法输入；取消透传；后端名；并发只读；不缓存/不串扰。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class Numerics {
    private Numerics() {}

    static String backendName() {
        return "X"
    }

    static Double defaultTolerance() {
        return 1e-10
    }

    static Int defaultMaximumIterations() {
        return 1000
    }

    static Int defaultMaximumSteps() {
        return 100000
    }

    static Result<Double, Error> integrate(Context context,
        Double(Double) integrand, Double lower, Double upper) {
        return Integration.integrate(context, integrand, lower, upper,
            Numerics.defaultTolerance(), Numerics.defaultMaximumIterations())
    }

    static Result<Pair<Double, Double>, Error> minimize1d(Context context,
        Double(Double) objective, Double lower, Double upper) {
        return Optimization.minimizeBounded(context, objective, lower, upper,
            Numerics.defaultTolerance(), Numerics.defaultMaximumIterations())
    }

    static Result<Pair<List<Double>, Double>, Error> minimize(Context context,
        Double(List<Double>) objective, List<Double> initialPoint) {
        return Optimization.minimizeNelderMead(context, objective,
            initialPoint, Numerics.defaultTolerance(),
            Numerics.defaultMaximumIterations())
    }

    static Result<Pair<List<Double>, List<List<Double>>>, Error> solveOde(
        Context context, List<Double>(Double, List<Double>) derivative,
        Double initialTime, List<Double> initialState, Double endTime) {
        return OdeSolver.solve(context, derivative, initialTime, initialState,
            endTime, 1e-8, Numerics.defaultMaximumSteps())
    }

    static Result<List<Complex>, Error> forwardFft(Context context,
        List<Complex> values) {
        return Fft.forward(context, values)
    }

    static Result<List<Complex>, Error> inverseFft(Context context,
        List<Complex> values) {
        return Fft.inverse(context, values)
    }

    static Result<List<Complex>, Error> forwardRealFft(Context context,
        List<Double> values) {
        return Fft.forwardReal(context, values)
    }

    static Result<List<Double>, Error> inverseRealFft(Context context,
        List<Complex> spectrum, Int outputLength) {
        return Fft.inverseReal(context, spectrum, outputLength,
            Numerics.defaultTolerance())
    }

    static Result<Interpolation, Error> interpolateLinear(
        List<Double> xValues, List<Double> yValues) {
        return Interpolation.linear(xValues, yValues)
    }

    static Result<Interpolation, Error> interpolateCubic(
        List<Double> xValues, List<Double> yValues) {
        return Interpolation.naturalCubicSpline(xValues, yValues)
    }

    static Result<Double, Error> findRoot(Context context,
        Double(Double) function, Double lower, Double upper) {
        return RootFinder.brent(context, function, lower, upper, 1e-12, 200)
    }

    static Result<BigInt, Error> parseBigInt(String text, Int maximumDigits) {
        return BigInt.parse(text, maximumDigits)
    }

    static Result<BigFloat, Error> parseBigFloat(String text,
        Int precisionBits, RoundingMode mode, Int maximumDigits) {
        return BigFloat.parse(text, precisionBits, mode, maximumDigits)
    }

    static Polynomial polynomial(List<Double> coefficients) {
        return Polynomial.of(coefficients)
    }
}
```
