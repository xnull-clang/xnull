# xdk.math —— T0 数学 v1.0

| 项 | 值 |
| --- | --- |
| 包 | `xdk.math` |
| 层级 | T0 |
| 稳定性 | `preview` |
| 依赖 | `xdk.errors` |
| 被依赖 | time、stats（T1）、metrics（T1） |
| 对应源码 | `src/xdk/core/math/Math.x` |
| 当前状态 | Partial（T0-K 通过；Int128 已落地；统计边界为 T0-X） |

## 1. 能力

| 能力 | 说明 | 承载 |
| --- | --- | --- |
| CAP-1 常量 | PI/E/TAU/Inf/NaN | 顶层函数 |
| CAP-2 取整/比较 | abs/min/max/clamp/floor/ceil/round/trunc | 顶层函数 |
| CAP-3 幂/指数/对数 | pow/sqrt/cbrt/exp/log/log2/log10 | 顶层函数 |
| CAP-4 三角 | sin..atan2、双曲函数、角度换算 | 顶层函数 |
| CAP-5 插值 | lerp/mapRange | 顶层函数 |
| CAP-6 整数数论 | gcd/lcm/isPrime/factorial | 顶层函数 |
| CAP-7 统计 | sum/mean/median/variance/stddev/quantile | 顶层函数 |
| CAP-8 Int128 | checked 128 位算术 | `Int128` 标量 + 顶层 checked 函数 |

**非目标**：随机数（T1 `xdk.random`）、任意精度、矩阵/张量、统计推断。

## 2. 契约

```text
Double abs(Double value)
Int absI(Int value)
Int minI(Int left, Int right)
Int maxI(Int left, Int right)
Int clampI(Int value, Int minimum, Int maximum)
Double pow(Double base, Double exponent)
Double sqrt(Double value)
Double log(Double value)
Double sin(Double radians)
Int gcd(Int left, Int right)
Int factorial(Int value)
Double mean(List<Double> values)
Double quantile(List<Double> values, Double quantile)
Bool isNaN(Double value)

Int128 int128Min()
Int128 int128Max()
Result<Int128, Error> addI128Checked(Int128 left, Int128 right)
Result<Int128, Error> subI128Checked(Int128 left, Int128 right)
Result<Int128, Error> mulI128Checked(Int128 left, Int128 right)
Result<Int128, Error> divI128Checked(Int128 left, Int128 right)
Result<Int128, Error> modI128Checked(Int128 left, Int128 right)
Result<Int128, Error> negI128Checked(Int128 value)
Result<Int128, Error> absI128Checked(Int128 value)
```

- 浮点遵循 IEEE 754；域错误返回 NaN/Inf，不 panic。
- `sqrt(-1)`、`log(-1)` 返回 NaN；`pow` 按 IEEE 结果。
- `mod` 的结果符号必须固定并测试；T0 选择与除数同号。
- `factorial(value)` 对负数/过大值返回 `InvalidArgument` 或合同错误；
  T0 固定为 `InvalidArgument`（当前源码需对齐）。
- 统计空列表：`mean/median` 返回 NaN；`sum` 返回 0；文档化。
- `quantile` 的 q 钳制到 `[0,1]`。
- `Int` 运算溢出按 32 位回绕；需要 64 位用 `Long`；需要 128 位用 `Int128`。
- `Int128` 是编译器的有符号 128 位标量：支持宽字面量、四则/比较、
  `print`/`str`、函数参数与返回值，以及 `Result<Int128,Error>`。
- `add/sub/mul/div/modI128Checked` 在溢出、下溢、除零时返回
  `InvalidArgument`；`modI128Checked(min, -1) == Ok(0)`，
  `divI128Checked(min, -1)`、`negI128Checked(min)`、`absI128Checked(min)` 返回错误。
- `Int128` 的 `/`/`%` 与 C 一致：商向零截断，余数符号跟随被除数；
  这与 `mod(Double,Double)` 的除数同号规则不同，测试必须区分。

## 3. 测试义务

- 常量/取整边界；
- NaN/Inf/域错误；
- 整数溢出/负数数论；
- Int128 宽字面量、四则、比较、打印与 checked 边界；
- 空/单元素统计；
- base/full 输出一致。

场景：`xdk_math.x`。

## 4. 后续（T0-X/T1）

- 其他整数的 checked/saturating 版本；
- 统计边界/分位数算法固定；
- 随机数移至 T1 `xdk.random`。
