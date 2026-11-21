# `Fft`

| 项 | 值 |
| --- | --- |
| 类型 | `class Fft`（静态算子） |
| 包 | `xdk.numerics` |
| 稳定性 | `preview` |
| 依赖 | `Complex`、`Context`、`BasicError`、`ErrorKind` |

---

## 1. 定位

一维离散 Fourier 变换：复数正/逆变换、实数正变换、实数逆变换；支持任意正整数长度。

不做：多维 FFT、DCT/DST、短时傅里叶、plan/wisdom、原地变换、多线程、GPU、实数半复数打包格式。

---

## 2. 设计逻辑

- 正变换不除 `N`，逆变换除 `N`；`ifft(fft(x)) == x`。
- 长度是 2 的幂时用迭代 radix-2 Cooley-Tukey；否则用 Bluestein（chirp-z）把任意长度卷积成 2 的幂。
- 实数正变换返回 `N/2 + 1` 个非冗余频点（DC 到 Nyquist）；实数逆变换接收同样布局。
- 复数统一用 `Complex`；不定义第二套复数或“半复数”数组。
- 输入列表只借用；输出是新列表；不提供原地变换。
- 空输入 `InvalidArgument`；长度上限 `16777216`，防止单次变换占用不可控内存。
- 所有长操作首参 `Context`；每级 butterfly / Bluestein 卷积检查取消。
- 归一化、符号约定固定；不暴露 FFTW 的 plan、wisdom、对齐或原地语义。

---

## 3. 表示与不变量

无实例字段；类不可实例化。

不变量：

- 输入长度 `n >= 1` 且 `n <= 16777216`。
- 正变换输出长度 = 输入长度。
- `forwardReal` 输出长度 = `n / 2 + 1`（整数除法）。
- `inverseReal` 的 `outputLength >= 1`，`spectrum.length() == outputLength / 2 + 1`。
- 逆变换结果与输入长度一致；不返回半成品。
- 不缓存旋转因子、不保存 plan、不写全局表。

---

## 4. 生命周期

静态；无 close；无资源；可并发调用。`Context` 只用于取消查询。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Fft()` | 无 | 私有；禁止外部实例化 | 外部 `new` 不可用 |

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `forward` | 复数正变换 | `Context context, List<Complex> values` | `Result<List<Complex>, Error>` | 空/超长/非有限/取消 |
| `inverse` | 复数逆变换 | `Context context, List<Complex> values` | 同上 | 同上 |
| `forwardReal` | 实数正变换 | `Context context, List<Double> values` | `Result<List<Complex>, Error>` | 空/超长/非有限/取消 |
| `inverseReal` | 实数逆变换 | `Context context, List<Complex> spectrum, Int outputLength, Double tolerance` | `Result<List<Double>, Error>` | 长度/共轭对称/非有限/取消 |

### 7.2 语义

- `forward`：`X[k] = Σ x[n] * exp(-2πi*k*n/N)`。
- `inverse`：`x[n] = (1/N) * Σ X[k] * exp(2πi*k*n/N)`。
- `forwardReal`：先按复数正变换，再截取 `0..N/2`。
- `inverseReal`：检查 DC 与 Nyquist 的虚部；用共轭对称补全负频率；逆变换后检查所有虚部残差。
- 虚部容差判定：`abs(imag) <= tolerance * (1 + abs(real))`。
- `tolerance` 必须有限且 `> 0`。
- 长度上限 16777216；超限 `InvalidArgument`。

---

## 8. 使用的技术

- radix-2 迭代 Cooley-Tukey；
- 位反转置换；
- 旋转因子递推；
- Bluestein chirp-z；
- 共轭对称补全；
- 归一化与虚部残差检查；
- 协作取消。

---

## 9. 需要的支撑

- 语言：class、`Int`、`Long`、`Double`、`Bool`、`List`、`Result`；
- 数学：`abs`、`cos`、`sin`、`sqrt`、`PI`、`isNaN`、`isInf`、`isFinite`；
- 复数：`Complex.of`、`fromPolar`、`add`、`sub`、`mul`、`conjugate`、`scale`、`real`、`imag`、`abs`；
- 执行：`Context.isCancelled`；
- 错误：`BasicError`、`ErrorKind.InvalidArgument`、`ErrorKind.Cancelled`。

---

## 10. 依赖的特性/接口/类

[`Complex`](../../core/math/Complex.md)、[`Context`](../../core/execution/Context.md)、[`BasicError`](../../core/errors/BasicError.md)、[`ErrorKind`](../../core/errors/ErrorKind.md)。

---

## 11. 所有权与并发

静态；无共享可变状态；可并发调用。输入只借用；输出是新列表。`Context` 不保存。类不可实例化，无相等语义。

---

## 12. 示例与反例

正确：`Fft.forward(context, values)`；`Fft.inverse(context, spectrum)`；`Fft.forwardReal(context, samples)` 得到 `N/2+1` 个频点；`inverseReal` 检查 DC/Nyquist 虚部。  
反例：期望正变换自动除 `N`；把 `forwardReal` 的输出当作完整共轭对称谱；对空列表调用；期望多维；修改输入列表并期望输出别名；忽略长度超限。

---

## 13. 测试/场景义务

长度 1/2/3/4/5/16/17/1024/非 2 的幂；脉冲/常数/单频正弦；`forward` 后 `inverse` 还原；Parseval 能量（按归一化约定）；`forwardReal` 的 DC/Nyquist 为实数；`inverseReal` 的共轭补全；DC/Nyquist 虚部超容差；输入含 NaN/Inf；空列表；超长；取消。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class Fft {
    private Fft() {}

    static Result<List<Complex>, Error> forward(Context context,
        List<Complex> values) {
        if context == null {
            throw "Fft.forward: null context"
        }
        if values == null {
            throw "Fft.forward: null values"
        }
        if values.length() == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Fft.forward: empty input"))
        }
        if values.length() > 16777216 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Fft.forward: input too large"))
        }
        Int index = 0
        while index < values.length() {
            Complex value = values.get(index)
            if value == null || isNaN(value.real()) || isInf(value.real())
                || isNaN(value.imag()) || isInf(value.imag()) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "Fft.forward: non-finite value"))
            }
            index = index + 1
        }
        if values.length() == 1 {
            return Ok([values.get(0)])
        }
        Result<List<Complex>, Error> result = _forwardDispatch(context, values)
        if result.isErr() {
            return Err(result.error())
        }
        if !_isFiniteComplexList(result.value()) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Fft.forward: non-finite result"))
        }
        return result
    }

    static Result<List<Complex>, Error> inverse(Context context,
        List<Complex> values) {
        if context == null {
            throw "Fft.inverse: null context"
        }
        if values == null {
            throw "Fft.inverse: null values"
        }
        if values.length() == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Fft.inverse: empty input"))
        }
        if values.length() > 16777216 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Fft.inverse: input too large"))
        }
        Int validationIndex = 0
        while validationIndex < values.length() {
            Complex value = values.get(validationIndex)
            if value == null || isNaN(value.real()) || isInf(value.real())
                || isNaN(value.imag()) || isInf(value.imag()) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "Fft.inverse: non-finite value"))
            }
            validationIndex = validationIndex + 1
        }
        List<Complex> conjugated = _conjugateList(values)
        Result<List<Complex>, Error> transformed = forward(context, conjugated)
        if transformed.isErr() {
            return Err(transformed.error())
        }
        if !_isFiniteComplexList(transformed.value()) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Fft.inverse: non-finite transform"))
        }
        List<Complex> result = []
        Double scale = 1.0 / (values.length() as Double)
        Int index = 0
        while index < transformed.value().length() {
            result.push(transformed.value().get(index).conjugate().scale(scale))
            index = index + 1
        }
        if !_isFiniteComplexList(result) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Fft.inverse: non-finite result"))
        }
        return Ok(result)
    }

    static Result<List<Complex>, Error> forwardReal(Context context,
        List<Double> values) {
        if context == null {
            throw "Fft.forwardReal: null context"
        }
        if values == null {
            throw "Fft.forwardReal: null values"
        }
        if values.length() == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Fft.forwardReal: empty input"))
        }
        if values.length() > 16777216 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Fft.forwardReal: input too large"))
        }
        List<Complex> complexValues = []
        Int index = 0
        while index < values.length() {
            if !isFinite(values.get(index)) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "Fft.forwardReal: non-finite value"))
            }
            complexValues.push(Complex.of(values.get(index), 0.0))
            index = index + 1
        }
        Result<List<Complex>, Error> transformed = forward(context,
            complexValues)
        if transformed.isErr() {
            return Err(transformed.error())
        }
        List<Complex> result = []
        index = 0
        while index <= values.length() / 2 {
            result.push(transformed.value().get(index))
            index = index + 1
        }
        return Ok(result)
    }

    static Result<List<Double>, Error> inverseReal(Context context,
        List<Complex> spectrum, Int outputLength, Double tolerance) {
        if context == null {
            throw "Fft.inverseReal: null context"
        }
        if spectrum == null {
            throw "Fft.inverseReal: null spectrum"
        }
        if outputLength < 1 || outputLength > 16777216 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Fft.inverseReal: invalid output length"))
        }
        if isNaN(tolerance) || isInf(tolerance) || tolerance <= 0.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Fft.inverseReal: invalid tolerance"))
        }
        if spectrum.length() != outputLength / 2 + 1 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Fft.inverseReal: spectrum length mismatch"))
        }
        Int index = 0
        while index < spectrum.length() {
            Complex value = spectrum.get(index)
            if value == null || isNaN(value.real()) || isInf(value.real())
                || isNaN(value.imag()) || isInf(value.imag()) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "Fft.inverseReal: non-finite value"))
            }
            index = index + 1
        }
        if abs(spectrum.get(0).imag())
            > tolerance * (1.0 + abs(spectrum.get(0).real())) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Fft.inverseReal: DC is not real"))
        }
        if outputLength % 2 == 0 {
            Complex nyquist = spectrum.get(outputLength / 2)
            if abs(nyquist.imag())
                > tolerance * (1.0 + abs(nyquist.real())) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "Fft.inverseReal: Nyquist is not real"))
            }
        }
        List<Complex> full = []
        index = 0
        while index < outputLength {
            full.push(Complex.zero())
            index = index + 1
        }
        full.set(0, Complex.of(spectrum.get(0).real(), 0.0))
        index = 1
        while index < spectrum.length() {
            full.set(index, spectrum.get(index))
            index = index + 1
        }
        index = 1
        while index < spectrum.length() {
            Int mirror = outputLength - index
            if mirror < outputLength && mirror >= 0 {
                full.set(mirror, spectrum.get(index).conjugate())
            }
            index = index + 1
        }
        if outputLength % 2 == 0 {
            full.set(outputLength / 2, Complex.of(spectrum.get(outputLength / 2).real(), 0.0))
        }
        Result<List<Complex>, Error> transformed = inverse(context, full)
        if transformed.isErr() {
            return Err(transformed.error())
        }
        List<Double> result = []
        index = 0
        while index < transformed.value().length() {
            Complex value = transformed.value().get(index)
            if abs(value.imag()) > tolerance * (1.0 + abs(value.real())) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "Fft.inverseReal: non-real result"))
            }
            result.push(value.real())
            index = index + 1
        }
        return Ok(result)
    }

    static Result<List<Complex>, Error> _forwardDispatch(Context context,
        List<Complex> values) {
        if _isPowerOfTwo(values.length()) {
            return _transformRadix2(context, values, false)
        }
        return _bluestein(context, values)
    }

    static Result<List<Complex>, Error> _transformRadix2(Context context,
        List<Complex> values, Bool inverse) {
        Int count = values.length()
        List<Complex> result = values.copy()
        Int reversed = 0
        Int index = 0
        while index < count {
            if reversed > index {
                Complex temporary = result.get(index)
                result.set(index, result.get(reversed))
                result.set(reversed, temporary)
            }
            Int mask = count / 2
            while mask > 0 && (reversed / mask) % 2 != 0 {
                reversed = reversed - mask
                mask = mask / 2
            }
            reversed = reversed + mask
            index = index + 1
        }
        Int length = 2
        while length <= count {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "Fft: cancelled"))
            }
            Double angle = 0.0 - 2.0 * PI() / (length as Double)
            if inverse {
                angle = 0.0 - angle
            }
            Complex rotation = Complex.fromPolar(1.0, angle)
            Int start = 0
            while start < count {
                Complex factor = Complex.of(1.0, 0.0)
                Int offset = 0
                while offset < length / 2 {
                    Complex evenValue = result.get(start + offset)
                    Complex oddValue = result.get(start + offset + length / 2)
                        .mul(factor)
                    result.set(start + offset, evenValue.add(oddValue))
                    result.set(start + offset + length / 2,
                        evenValue.sub(oddValue))
                    factor = factor.mul(rotation)
                    offset = offset + 1
                }
                start = start + length
            }
            length = length * 2
        }
        return Ok(result)
    }

    static Result<List<Complex>, Error> _bluestein(Context context,
        List<Complex> values) {
        Int count = values.length()
        Long convolutionLong = 2L * (count as Long) - 1L
        Result<Int, Error> sizeResult = _nextPowerOfTwo(convolutionLong)
        if sizeResult.isErr() {
            return Err(sizeResult.error())
        }
        Int size = sizeResult.value()
        List<Complex> first = []
        List<Complex> second = []
        Int index = 0
        while index < size {
            first.push(Complex.zero())
            second.push(Complex.zero())
            index = index + 1
        }
        Long modulus = 2L * (count as Long)
        index = 0
        while index < count {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "Fft: cancelled"))
            }
            Long square = (index as Long) * (index as Long)
            Long reduced = square % modulus
            Double angle = 0.0 - PI() * (reduced as Double) / (count as Double)
            Complex chirp = Complex.fromPolar(1.0, angle)
            first.set(index, values.get(index).mul(chirp))
            second.set(index, chirp.conjugate())
            if index > 0 {
                second.set(size - index, chirp.conjugate())
            }
            index = index + 1
        }
        Result<List<Complex>, Error> firstTransform =
            _transformRadix2(context, first, false)
        if firstTransform.isErr() {
            return Err(firstTransform.error())
        }
        Result<List<Complex>, Error> secondTransform =
            _transformRadix2(context, second, false)
        if secondTransform.isErr() {
            return Err(secondTransform.error())
        }
        List<Complex> product = []
        index = 0
        while index < size {
            product.push(firstTransform.value().get(index)
                .mul(secondTransform.value().get(index)))
            index = index + 1
        }
        Result<List<Complex>, Error> convolution =
            _transformRadix2(context, product, true)
        if convolution.isErr() {
            return Err(convolution.error())
        }
        List<Complex> result = []
        Double scale = 1.0 / (size as Double)
        index = 0
        while index < count {
            Long square = (index as Long) * (index as Long)
            Long reduced = square % modulus
            Double angle = 0.0 - PI() * (reduced as Double) / (count as Double)
            Complex chirp = Complex.fromPolar(1.0, angle)
            result.push(convolution.value().get(index).scale(scale).mul(chirp))
            index = index + 1
        }
        return Ok(result)
    }

    static Result<Int, Error> _nextPowerOfTwo(Long length) {
        if length < 1 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Fft: invalid transform length"))
        }
        Long result = 1
        while result < length {
            result = result * 2
            if result > 16777216 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "Fft: transform length too large"))
            }
        }
        return Ok(result as Int)
    }

    static Bool _isFiniteComplexList(List<Complex> values) {
        Int index = 0
        while index < values.length() {
            Complex value = values.get(index)
            if value == null || !isFinite(value.real()) || !isFinite(value.imag()) {
                return false
            }
            index = index + 1
        }
        return true
    }

    static Bool _isPowerOfTwo(Int value) {
        if value < 1 {
            return false
        }
        Int remaining = value
        while remaining > 1 && remaining % 2 == 0 {
            remaining = remaining / 2
        }
        return remaining == 1
    }

    static List<Complex> _conjugateList(List<Complex> values) {
        List<Complex> result = []
        Int index = 0
        while index < values.length() {
            result.push(values.get(index).conjugate())
            index = index + 1
        }
        return result
    }
}
```
