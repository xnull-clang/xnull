# `SignalBuffer`

| 项 | 值 |
| --- | --- |
| 类型 | `class SignalBuffer`（静态算子） |
| 包 | `xdk.numerics` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`SpecialFunctions`、`BasicError`、`ErrorKind` |

---

## 1. 定位

一维信号基础：矩形/Hann/Hamming/Blackman/Kaiser 窗、全卷积、因果 FIR、直接型 IIR。

不做：二维卷积、FFT 卷积、滤波器设计（Butterworth/Chebyshev）、重采样、谱估计、峰值检测、自适应滤波、实时流状态。

---

## 2. 设计逻辑

- 全部静态；无状态；每次调用独立。
- 窗函数返回长度等于输入长度的 `List<Double>`；`periodic = true` 用于 FFT 周期窗，`false` 用于对称窗。
- Kaiser 窗复用 `SpecialFunctions.besselI(0, argument)`，不另写 Bessel 近似。
- `convolve` 是完整卷积，输出长度 `signal.length + kernel.length - 1`；不做 same/valid 变体，调用方自行切片。
- `firFilter` 与 `iirFilter` 输出长度等于输入长度；初始状态为零；不保存滤波器状态。
- IIR 采用直接型 I：`y[n] = (Σ b[k]x[n-k] - Σ_{k>=1} a[k]y[n-k]) / a[0]`。
- 输入/系数/输出出现 NaN/Inf 时立即 `InvalidArgument`；不返回带 NaN 的“结果”。
- 卷积/滤波是长操作，首参 `Context`；窗函数是单遍 O(n)，不接 `Context`。

---

## 3. 表示与不变量

无实例字段；类不可实例化。

不变量：

- 窗长度 `>= 1`；长度 1 时所有窗返回 `[1.0]`。
- `periodic` 为 `true` 时分母为 `length`；为 `false` 时分母为 `length - 1`。
- Kaiser 的 `beta >= 0` 且有限。
- 卷积的 `signal`/`kernel` 非空；所有元素有限。
- FIR 系数非空；IIR 分母非空且 `denominator[0] != 0`。
- 输出列表是新对象；不别名输入。

---

## 4. 生命周期

静态；无 close；无资源；可并发调用。`Context` 只用于取消查询。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `SignalBuffer()` | 无 | 私有；禁止外部实例化 | 外部 `new` 不可用 |

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `rectangularWindow` | 矩形窗 | `Int length` | `Result<List<Double>, Error>` | `length < 1` |
| `hannWindow` | Hann 窗 | `Int length, Bool periodic` | 同上 | 同上 |
| `hammingWindow` | Hamming 窗 | 同上 | 同上 | 同上 |
| `blackmanWindow` | Blackman 窗 | 同上 | 同上 | 同上 |
| `kaiserWindow` | Kaiser 窗 | `Int length, Double beta, Bool periodic` | 同上 | 长度/`beta` 非有限或负 |
| `convolve` | 全卷积 | `Context context, List<Double> signal, List<Double> kernel` | `Result<List<Double>, Error>` | 空/非有限/溢出/取消 |
| `firFilter` | 因果 FIR | `Context context, List<Double> signal, List<Double> coefficients` | 同上 | 空/非有限/取消 |
| `iirFilter` | 直接型 IIR | `Context context, List<Double> signal, List<Double> numerator, List<Double> denominator` | 同上 | 空/首系数零/非有限/取消 |

### 7.2 窗公式

- 矩形：`w[n] = 1`。
- Hann：`0.5 - 0.5 * cos(2πn / denominator)`。
- Hamming：`0.54 - 0.46 * cos(2πn / denominator)`。
- Blackman：`0.42 - 0.5 * cos(2πn / denominator) + 0.08 * cos(4πn / denominator)`。
- Kaiser：`I0(beta * sqrt(1 - (2n/denominator - 1)^2)) / I0(beta)`。

`n` 取 `0..length-1`；`denominator` 按 §3 选择。

### 7.3 滤波语义

- 输入索引为负时视为 `0.0`；输出索引为负时视为 `0.0`。
- IIR 的 `denominator[0]` 是 `a[0]`，不能为 0；不做归一化，调用方负责。
- 滤波器稳定性不由本方法检查；系数导致的发散会以非有限输出返回 `InvalidArgument`。

---

## 8. 使用的技术

- 周期/对称窗公式；
- Kaiser 的零阶修正 Bessel；
- 直接卷积；
- 直接型 I IIR 差分方程；
- 有限值检查；
- 协作取消。

---

## 9. 需要的支撑

- 语言：class、`Int`、`Double`、`Bool`、`List`、`Result`；
- 数学：`abs`、`sqrt`、`cos`、`PI`、`isNaN`、`isInf`、`isFinite`；
- 特殊函数：`SpecialFunctions.besselI`；
- 执行：`Context.isCancelled`；
- 错误：`BasicError`、`ErrorKind.InvalidArgument`、`ErrorKind.Cancelled`。

---

## 10. 依赖的特性/接口/类

[`Context`](../../core/execution/Context.md)、[`SpecialFunctions`](SpecialFunctions.md)、[`BasicError`](../../core/errors/BasicError.md)、[`ErrorKind`](../../core/errors/ErrorKind.md)。

---

## 11. 所有权与并发

静态；无共享可变状态；可并发调用。输入只借用；输出是新列表。`Context` 不保存。类不可实例化，无相等语义。

---

## 12. 示例与反例

正确：`SignalBuffer.hannWindow(1024, true)`；`SignalBuffer.kaiserWindow(256, 8.0, false)`；`SignalBuffer.convolve(context, signal, kernel)`；`SignalBuffer.iirFilter(context, signal, numerator, denominator)`。  
反例：对 `length = 0` 调用窗；把 `periodic = true` 的窗用于对称 FIR 设计而不检查；对空 kernel 卷积；IIR 分母首项为 0；期望 `convolve` 返回与输入等长（它是全卷积）；忽略输出非有限错误。

---

## 13. 测试/场景义务

窗长度 1/2/奇数/偶数；周期/对称的端点和对称性；Kaiser 的 `beta = 0`/大值；卷积的长度/交换律/脉冲核；FIR 的单位脉冲/延迟/零系数；IIR 的一阶低通/分母首项非 1/发散；空列表；NaN/Inf；取消；输出不别名输入。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class SignalBuffer {
    private SignalBuffer() {}

    static Result<List<Double>, Error> rectangularWindow(Int length) {
        if length < 1 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SignalBuffer.rectangularWindow: invalid length"))
        }
        List<Double> result = []
        Int index = 0
        while index < length {
            result.push(1.0)
            index = index + 1
        }
        return Ok(result)
    }

    static Result<List<Double>, Error> hannWindow(Int length,
        Bool periodic) {
        Result<Unit, Error> validation = _validateWindow(length,
            "SignalBuffer.hannWindow")
        if validation.isErr() {
            return Err(validation.error())
        }
        if length == 1 {
            return Ok([1.0])
        }
        Double denominator = _windowDenominator(length, periodic)
        List<Double> result = []
        Int index = 0
        while index < length {
            Double angle = 2.0 * PI() * (index as Double) / denominator
            result.push(0.5 - 0.5 * cos(angle))
            index = index + 1
        }
        return Ok(result)
    }

    static Result<List<Double>, Error> hammingWindow(Int length,
        Bool periodic) {
        Result<Unit, Error> validation = _validateWindow(length,
            "SignalBuffer.hammingWindow")
        if validation.isErr() {
            return Err(validation.error())
        }
        if length == 1 {
            return Ok([1.0])
        }
        Double denominator = _windowDenominator(length, periodic)
        List<Double> result = []
        Int index = 0
        while index < length {
            Double angle = 2.0 * PI() * (index as Double) / denominator
            result.push(0.54 - 0.46 * cos(angle))
            index = index + 1
        }
        return Ok(result)
    }

    static Result<List<Double>, Error> blackmanWindow(Int length,
        Bool periodic) {
        Result<Unit, Error> validation = _validateWindow(length,
            "SignalBuffer.blackmanWindow")
        if validation.isErr() {
            return Err(validation.error())
        }
        if length == 1 {
            return Ok([1.0])
        }
        Double denominator = _windowDenominator(length, periodic)
        List<Double> result = []
        Int index = 0
        while index < length {
            Double angle = 2.0 * PI() * (index as Double) / denominator
            result.push(0.42 - 0.5 * cos(angle) + 0.08 * cos(2.0 * angle))
            index = index + 1
        }
        return Ok(result)
    }

    static Result<List<Double>, Error> kaiserWindow(Int length, Double beta,
        Bool periodic) {
        Result<Unit, Error> validation = _validateWindow(length,
            "SignalBuffer.kaiserWindow")
        if validation.isErr() {
            return Err(validation.error())
        }
        if isNaN(beta) || isInf(beta) || beta < 0.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SignalBuffer.kaiserWindow: invalid beta"))
        }
        if length == 1 {
            return Ok([1.0])
        }
        Double denominator = _windowDenominator(length, periodic)
        Result<Double, Error> normalization = SpecialFunctions.besselI(0, beta)
        if normalization.isErr() {
            return Err(normalization.error())
        }
        if normalization.value() == 0.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SignalBuffer.kaiserWindow: zero normalization"))
        }
        List<Double> result = []
        Int index = 0
        while index < length {
            Double ratio = 2.0 * (index as Double) / denominator - 1.0
            Double argument = beta * sqrt(1.0 - ratio * ratio)
            Result<Double, Error> value = SpecialFunctions.besselI(0, argument)
            if value.isErr() {
                return Err(value.error())
            }
            Double windowValue = value.value() / normalization.value()
            if isNaN(windowValue) || isInf(windowValue) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "SignalBuffer.kaiserWindow: non-finite value"))
            }
            result.push(windowValue)
            index = index + 1
        }
        return Ok(result)
    }

    static Result<List<Double>, Error> convolve(Context context,
        List<Double> signal, List<Double> kernel) {
        if context == null {
            throw "SignalBuffer.convolve: null context"
        }
        if signal == null || kernel == null {
            throw "SignalBuffer.convolve: null input"
        }
        if signal.length() == 0 || kernel.length() == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SignalBuffer.convolve: empty input"))
        }
        Result<Unit, Error> validation = _validateValues(signal,
            "SignalBuffer.convolve")
        if validation.isErr() {
            return Err(validation.error())
        }
        validation = _validateValues(kernel, "SignalBuffer.convolve")
        if validation.isErr() {
            return Err(validation.error())
        }
        Long outputLength = (signal.length() as Long)
            + (kernel.length() as Long) - 1
        if outputLength > 2147483647 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SignalBuffer.convolve: output too large"))
        }
        List<Double> result = []
        Long clearIndex = 0
        while clearIndex < outputLength {
            result.push(0.0)
            clearIndex = clearIndex + 1
        }
        Int signalIndex = 0
        while signalIndex < signal.length() {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "SignalBuffer.convolve: cancelled"))
            }
            Int kernelIndex = 0
            while kernelIndex < kernel.length() {
                Int position = signalIndex + kernelIndex
                Double value = result.get(position)
                    + signal.get(signalIndex) * kernel.get(kernelIndex)
                if isNaN(value) || isInf(value) {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "SignalBuffer.convolve: non-finite output"))
                }
                result.set(position, value)
                kernelIndex = kernelIndex + 1
            }
            signalIndex = signalIndex + 1
        }
        return Ok(result)
    }

    static Result<List<Double>, Error> firFilter(Context context,
        List<Double> signal, List<Double> coefficients) {
        if context == null {
            throw "SignalBuffer.firFilter: null context"
        }
        if signal == null || coefficients == null {
            throw "SignalBuffer.firFilter: null input"
        }
        if signal.length() == 0 || coefficients.length() == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SignalBuffer.firFilter: empty input"))
        }
        Result<Unit, Error> validation = _validateValues(signal,
            "SignalBuffer.firFilter")
        if validation.isErr() {
            return Err(validation.error())
        }
        validation = _validateValues(coefficients, "SignalBuffer.firFilter")
        if validation.isErr() {
            return Err(validation.error())
        }
        List<Double> result = []
        Int index = 0
        while index < signal.length() {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "SignalBuffer.firFilter: cancelled"))
            }
            Double sum = 0.0
            Int coefficientIndex = 0
            while coefficientIndex < coefficients.length() {
                Int sourceIndex = index - coefficientIndex
                if sourceIndex >= 0 {
                    sum = sum + coefficients.get(coefficientIndex)
                        * signal.get(sourceIndex)
                }
                coefficientIndex = coefficientIndex + 1
            }
            if isNaN(sum) || isInf(sum) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "SignalBuffer.firFilter: non-finite output"))
            }
            result.push(sum)
            index = index + 1
        }
        return Ok(result)
    }

    static Result<List<Double>, Error> iirFilter(Context context,
        List<Double> signal, List<Double> numerator,
        List<Double> denominator) {
        if context == null {
            throw "SignalBuffer.iirFilter: null context"
        }
        if signal == null || numerator == null || denominator == null {
            throw "SignalBuffer.iirFilter: null input"
        }
        if signal.length() == 0 || numerator.length() == 0
            || denominator.length() == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SignalBuffer.iirFilter: empty input"))
        }
        Result<Unit, Error> validation = _validateValues(signal,
            "SignalBuffer.iirFilter")
        if validation.isErr() {
            return Err(validation.error())
        }
        validation = _validateValues(numerator, "SignalBuffer.iirFilter")
        if validation.isErr() {
            return Err(validation.error())
        }
        validation = _validateValues(denominator, "SignalBuffer.iirFilter")
        if validation.isErr() {
            return Err(validation.error())
        }
        if denominator.get(0) == 0.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SignalBuffer.iirFilter: zero leading denominator"))
        }
        List<Double> result = []
        Int index = 0
        while index < signal.length() {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "SignalBuffer.iirFilter: cancelled"))
            }
            Double sum = 0.0
            Int forwardIndex = 0
            while forwardIndex < numerator.length() {
                Int sourceIndex = index - forwardIndex
                if sourceIndex >= 0 {
                    sum = sum + numerator.get(forwardIndex)
                        * signal.get(sourceIndex)
                }
                forwardIndex = forwardIndex + 1
            }
            Int feedbackIndex = 1
            while feedbackIndex < denominator.length() {
                Int outputIndex = index - feedbackIndex
                if outputIndex >= 0 {
                    sum = sum - denominator.get(feedbackIndex)
                        * result.get(outputIndex)
                }
                feedbackIndex = feedbackIndex + 1
            }
            Double outputValue = sum / denominator.get(0)
            if isNaN(outputValue) || isInf(outputValue) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "SignalBuffer.iirFilter: non-finite output"))
            }
            result.push(outputValue)
            index = index + 1
        }
        return Ok(result)
    }

    static Result<Unit, Error> _validateWindow(Int length, String algorithm) {
        if length < 1 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                algorithm + ": invalid length"))
        }
        return Ok(unit)
    }

    static Double _windowDenominator(Int length, Bool periodic) {
        if periodic {
            return length as Double
        }
        return (length - 1) as Double
    }

    static Result<Unit, Error> _validateValues(List<Double> values,
        String algorithm) {
        Int index = 0
        while index < values.length() {
            if !isFinite(values.get(index)) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    algorithm + ": non-finite value"))
            }
            index = index + 1
        }
        return Ok(unit)
    }
}
```
