# `Complex`

| 项 | 值 |
| --- | --- |
| 类型 | `class Complex` |
| 包 | `xdk.math` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

双精度复数：实部/虚部、四则、共轭、模/辐角、极坐标。

不做：任意精度、矩阵/张量、FFT。

---

## 2. 设计逻辑

- 不可变值对象；`_real`/`_imag` 是 `Double`。
- 加/减/乘返回新实例；除零返回 `InvalidArgument`。
- `abs` 是模，`arg` 是辐角；`norm` 是模平方。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_real` | `Double` | 实部 |
| `_imag` | `Double` | 虚部 |

不变量：字段不可变；允许 NaN/Inf（IEEE）。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Complex.of(Double real, Double imag)` | real/imag | 任意 Double | 无 |
| `Complex.fromPolar(Double modulus, Double angle)` | modulus/angle | 任意 | 无 |
| `Complex.zero()` | 无 | 0+0i | 无 |
| `Complex.i()` | 无 | 0+1i | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `real` | 实部 | 无 | `Double` | 无 |
| `imag` | 虚部 | 无 | `Double` | 无 |
| `add` | 加 | `Complex other` | `Complex` | null → panic |
| `sub` | 减 | `Complex other` | `Complex` | null → panic |
| `mul` | 乘 | `Complex other` | `Complex` | null → panic |
| `div` | 除 | `Complex other` | `Result<Complex, Error>` | null/除零 → `InvalidArgument` |
| `scale` | 数乘 | `Double factor` | `Complex` | 无 |
| `conjugate` | 共轭 | 无 | `Complex` | 无 |
| `abs` | 模 | 无 | `Double` | 无 |
| `arg` | 辐角 | 无 | `Double` | 无 |
| `norm` | 模平方 | 无 | `Double` | 无 |
| `equals` | 值相等 | `Complex other` | `Bool` | 无 |
| `toString` | 文本 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 复数四则；
- 共轭/模/辐角；
- 极坐标；
- IEEE 浮点。

---

## 9. 需要的支撑

- 语言：class、Double、Bool、String、Result；
- 运行时：浮点运算；
- 接口：`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`BasicError`、`ErrorKind`、`Result`。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`Complex.of(1,2).mul(Complex.i())` → `-2+1i`。  
反例：除零期望 NaN 静默；用 `==` 做数学相等（浮点）；把 Complex 当容器。

---

## 13. 测试/场景义务

加/减/乘/除；共轭；模/辐角；极坐标；除零；NaN/Inf；toString。

---

## 14. XNull 伪代码

```xnull
class Complex {
    final Double _real
    final Double _imag

    Complex(Double real, Double imag) {
        _real = real
        _imag = imag
    }

    static Complex of(Double real, Double imag) {
        return new Complex(real, imag)
    }

    static Complex fromPolar(Double modulus, Double angle) {
        return new Complex(modulus * cos(angle), modulus * sin(angle))
    }

    static Complex zero() {
        return new Complex(0.0, 0.0)
    }

    static Complex i() {
        return new Complex(0.0, 1.0)
    }

    Double real() { return _real }
    Double imag() { return _imag }

    Complex add(Complex other) {
        if other == null { throw "Complex.add: null" }
        return new Complex(_real + other._real, _imag + other._imag)
    }

    Complex sub(Complex other) {
        if other == null { throw "Complex.sub: null" }
        return new Complex(_real - other._real, _imag - other._imag)
    }

    Complex mul(Complex other) {
        if other == null { throw "Complex.mul: null" }
        Double real = _real * other._real - _imag * other._imag
        Double imag = _real * other._imag + _imag * other._real
        return new Complex(real, imag)
    }

    Result<Complex, Error> div(Complex other) {
        if other == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "null complex"))
        }
        Double denominator = other._real * other._real + other._imag * other._imag
        if denominator == 0.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "complex division by zero"))
        }
        Double real = (_real * other._real + _imag * other._imag) / denominator
        Double imag = (_imag * other._real - _real * other._imag) / denominator
        return Ok(new Complex(real, imag))
    }

    Complex scale(Double factor) {
        return new Complex(_real * factor, _imag * factor)
    }

    Complex conjugate() {
        return new Complex(_real, 0.0 - _imag)
    }

    Double abs() {
        return sqrt(_real * _real + _imag * _imag)
    }

    Double arg() {
        return atan2(_imag, _real)
    }

    Double norm() {
        return _real * _real + _imag * _imag
    }

    Bool equals(Complex other) {
        if other == null { return false }
        return _real == other._real && _imag == other._imag
    }

    String toString() {
        if _imag < 0.0 {
            return str(_real) + str(_imag) + "i"
        }
        return str(_real) + "+" + str(_imag) + "i"
    }
}
```
