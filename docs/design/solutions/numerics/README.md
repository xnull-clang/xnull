# `xdk.numerics` 数值计算包

| 项 | 值 |
| --- | --- |
| 包 | `xdk.numerics` |
| 层 | L8 solutions |
| 依赖 | `xdk.core`（`math`、`collections`、`errors`、`execution`）、`xdk.linalg`、`xdk.tensor` |
| 被依赖 | 科学计算工具、数据分析、工程仿真、信号处理应用 |
| 稳定性 | `preview`；不进入 1.0 公共承诺 |
| 后端 | X；公共 API 不出现 BLAS/LAPACK/FFTW/GMP/MPFR |
| 状态 | 12/12 类型：Polynomial/RootFinder/Interpolation/Numerics/BigInt/Integration/Optimization/OdeSolver/Fft/SignalBuffer/SpecialFunctions/BigFloat |

---

## 0.5 实现状态（M26.5）

已实现 12/12 类型：`Polynomial`、`RootFinder`、`Interpolation`、`Numerics`、`BigInt`、
`Integration`、`Optimization`、`OdeSolver`、`Fft`、`SignalBuffer`、`SpecialFunctions`、
`BigFloat`（算术/开方/舍入/转换/exp/log/pow）。

- `BigInt`：符号-绝对值，基数 65536 小端 limbs；parse/toString、Long.MIN、fromDoubleExact；
  加/减/乘/除/余/mod/pow/modPow/modInverse/gcd/lcm/shift/testBit/sqrt/compare；
  除法向零截断、余数同号，`mod` 非负；除法用二进制长除法（等价多 limb 长除）。
- 偏差：`divideAndRemainder` 返回 `BigIntPair`（`quotient()`/`remainderValue()`），
  不是 `Pair<BigInt,BigInt>`；编译器泛型 Pair 与既有 `Pair<Polynomial,Polynomial>`
  在同一编译单元冲突，待编译器修复后恢复泛型 Pair。
- `Integration`：自适应 Simpson、Gauss-Legendre（1..64 阶，Newton 生成节点/权重）、
  tanh-sinh、无穷区间变换；非有限/不收敛/取消显式错误。
- `Optimization`：一维有界 Brent、无界括入+Brent、Nelder-Mead、BFGS（Armijo 回溯）、
  `minimize` 默认入口。
- `OdeSolver`：固定步长 RK4、Dormand-Prince 5(4) 自适应、隐式 Euler + Newton
  （`Linalg.solve`），`solve` 默认自适应入口。
- `Context` 取消检查贯穿迭代；失败不返回伪值。
- `Fft`：2 的幂用迭代 radix-2，其他长度用直接 DFT 回退；`forwardReal` 返回 `n/2+1`；
  `inverseReal` 校验共轭对称并检查虚部容差。
- `SignalBuffer`：rectangular/hann/hamming/blackman/kaiser 窗（periodic/symmetric），
  全卷积、因果 FIR、直接型 I IIR；输入/系数非有限即失败。
- `xdk.math.Complex` 同步补齐（of/fromPolar/四则/共轭/模/辐角/极坐标）。
- `SpecialFunctions`：Lanczos Gamma/logGamma/digamma、Beta/正则不完全 Gamma/Beta、
  erf/erfc/inverseErf、J/Y/I/K Bessel（整数阶）、Airy、Riemann Zeta（Euler-Maclaurin）、
  Lambert W（Halley）、完全椭圆积分（AGM）。
- 偏差：`besselY` 对 `order > 0` 由 Y0/Y1 递推，`x` 很小时仅有 Y0/Y1 高精度；
  `besselJ/I` 在 `|x| > 30` 用渐近式。
- `BigFloat`：符号-绝对值 + `BigInt` 有效数字 + 二进制指数，显式精度与
  `RoundingMode`；parse/fromDouble/fromLong/fromBigInt、加减乘除、round、sqrt、
  toBigInt/toDecimalString/toDouble/compare/equals/isInteger。
  `exp/log/pow`：范围约减 + Taylor/atanh 级数 + 整数幂平方-乘；工作精度 p+16。
- `xdk.math.RoundingMode` 同步补齐（Up/Down/Ceiling/Floor/HalfUp/HalfDown/HalfEven/Unnecessary）。
- 偏差：`BigFloat` 除法/开方使用 guard 位后统一舍入；`toDecimalString` 限制小数位 ≤1000。

---

## 1. 定位

`xdk.numerics` 补齐 `xdk.math` 与 `xdk.linalg` 之上的数值算法面：

- 任意精度整数与任意精度浮点，舍入模式显式；
- 单变量多项式与复根；
- 特殊函数、数值积分、一维/多变量优化、常微分方程、FFT、信号窗/滤波、插值、求根；
- 统一静态入口 `Numerics`，为常用任务提供默认算法。

不做：

- 符号代数、表达式树、自动微分、计算图；
- 稀疏矩阵、GPU/NPU、分布式、多机并行；
- BLAS/LAPACK/FFTW/GMP/MPFR/Arb 的公共绑定；
- 多维 FFT、二维/多维插值、约束优化、线性规划；
- 任意精度复数、区间/球算术、有理数类型；
- 与 `xdk.linalg`/`xdk.tensor` 重复的 `Matrix`/`Tensor`/`Vector` 类型。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 不重复下层类型 | 矩阵、向量、张量、复数、Decimal、舍入枚举全部复用 /；本包只加算法类型 |
| 纯 XNull | 算法以 XNull 语义描述；X 可替换内核，公共 API 不变 |
| 精度显式 | `BigFloat` 每个值携带精度；每次运算显式给目标精度与 `RoundingMode` |
| 无隐式转换 | 不从 `Double` 隐式转 `BigInt`/`BigFloat`；转换必须走命名工厂并显式舍入 |
| 失败不静默 | 定义域/参数错误 `InvalidArgument`；迭代不收敛用 `Result` 错误；不返回“看起来合理”的错值 |
| 取消可传播 | 迭代、步进、变换等长操作首参 `Context`；取消 `Cancelled`，超时 `Timeout` |
| 值不可变 | 数值对象构造后不变；列表参数复制；访问器返回副本 |
| 无全局状态 | 无全局舍入模式、无计划缓存、无 wisdom、无隐藏后端单例 |
| 可预测输出 | 根/极值/变换顺序有明确约定；不依赖哈希或遍历顺序 |
| 尺寸受控 | 列表长度 `Int`；位长/字节规模 `Long`；分配前检查上限 |
| 双精度边界 | `Double` 算法遵循 IEEE 754；域错误显式返回错误，不用 NaN 冒充成功 |

---

## 3. 类型索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `BigInt` | class | 任意精度有符号整数、位运算、模幂、整数开方 | [`BigInt.md`](BigInt.md) |
| `BigFloat` | class | 任意精度二进制浮点、显式精度与舍入、开方/指数/对数/幂 | [`BigFloat.md`](BigFloat.md) |
| `Polynomial` | class | 单变量实系数多项式、求值、微积分、除法、复根 | [`Polynomial.md`](Polynomial.md) |
| `SpecialFunctions` | class（静态算子） | Gamma/Beta/误差/Bessel/Airy/Zeta/Lambert W/椭圆积分 | [`SpecialFunctions.md`](SpecialFunctions.md) |
| `Integration` | class（静态算子） | 自适应、Gauss-Legendre、tanh-sinh、无穷区间积分 | [`Integration.md`](Integration.md) |
| `Optimization` | class（静态算子） | 一维 Brent、多变量 Nelder-Mead/BFGS | [`Optimization.md`](Optimization.md) |
| `OdeSolver` | class（静态算子） | RK4、Dormand-Prince 5(4)、隐式 Euler | [`OdeSolver.md`](OdeSolver.md) |
| `Fft` | class（静态算子） | 一维复数/实数 FFT、逆变换、任意长度 | [`Fft.md`](Fft.md) |
| `SignalBuffer` | class（静态算子） | 窗函数、卷积、FIR/IIR 滤波 | [`SignalBuffer.md`](SignalBuffer.md) |
| `Interpolation` | class | 线性、自然/夹持三次样条、PCHIP | [`Interpolation.md`](Interpolation.md) |
| `RootFinder` | class（静态算子） | 二分、Brent、Newton、割线 | [`RootFinder.md`](RootFinder.md) |
| `Numerics` | class（静态入口） | 默认算法门面、后端标识、默认容差 | [`Numerics.md`](Numerics.md) |

> 类型索引是唯一入口；包 README 不重复方法表。每个类型文件固定 14 段；类型文件 12 个，加本 README 共 13 个文档。

---

## 4. 跨类型规则

### 4.1 依赖与复用

- 复数统一用 [`Complex`](../../core/math/Complex.md)；FFT、特殊函数、多项式复根不得另造复数类型。
- 舍入统一用 [`RoundingMode`](../../core/math/RoundingMode.md)；`BigFloat` 不定义第二套舍入枚举。
- 双值返回统一用 [`Pair`](../../core/collections/Pair.md)；不新增 `ResultPair`/`Point` 包装。
- 错误统一用 [`BasicError`](../../core/errors/BasicError.md) 与 [`ErrorKind`](../../core/errors/ErrorKind.md)。
- 取消统一用 [`Context`](../../core/execution/Context.md)；本包不定义第二套取消令牌。
- 矩阵/向量用 [`xdk.linalg`](../../platform/linalg/README.md) 的 [`Matrix`](../../platform/linalg/Matrix.md)/[`Vector`](../../platform/linalg/Vector.md)；本包不重新定义线性代数类型。
- 张量布局与 dtype 由 [`xdk.tensor`](../../platform/tensor/README.md) 提供；本包不定义 `Tensor`，也不做 GPU/自动微分。
- 拟合、最小二乘等需要分解时调用 `xdk.linalg`；本包不实现第二套 LU/QR/SVD。

### 4.2 失败通道

| 场景 | 通道 |
| --- | --- |
| 定义域错误、非法参数、空列表、长度不符、非有限输入 | `Result` 的 `InvalidArgument` |
| 迭代/步进不收敛、达到上限仍不满足容差 | `Result` 的 `InvalidArgument`，消息含算法名与原因 |
| 调用方违反结构前置条件（如私有构造、越界索引） | 合同错误（panic） |
| 取消/超时 | `Cancelled` / `Timeout` |
| 文档明确允许的 IEEE 溢出 | 返回 `Inf` 或 `0.0`，逐方法写明 |

禁止：

- 用 `NaN` 表示“没算出来”却不写文档；
- 收敛失败仍返回最后一轮迭代值；
- 用 `null` 同时表示“无结果”和“合法零值”；
- 在 `Err` 中只写字符串而不带 `ErrorKind`。

### 4.3 精度与舍入

- `BigInt` 精确；除法向零截断，余数与被除数同号。
- `BigFloat` 值携带 `precisionBits`；每次算术/初等函数显式传目标精度与 `RoundingMode`。
- `BigFloat` 不支持 NaN/±Inf；溢出指数范围、除零、负数开方等一律 `InvalidArgument`。
- `Double` 算法不做隐式 epsilon 比较；容差由调用方显式传入，且必须 `> 0` 且有限。
- 根、极值、积分结果是数值近似；不承诺最后一位正确，只承诺满足给定容差或返回错误。

### 4.4 尺寸与取消

- 列表长度、窗口长度、FFT 长度、迭代次数用 `Int`；位长、字节规模、元素总数用 `Long`。
- 任何可能长时间运行的操作首参 `Context`；每轮迭代/每个步长/每个 FFT 阶段检查取消。
- 分配前用 `Long` 估算元素数并检查 `Int` 上限；超限 `InvalidArgument`，不做回绕。
- 取消后不返回部分结果；调用方要么拿到完整结果，要么拿到 `Cancelled`。

### 4.5 所有权与并发

- `BigInt`、`BigFloat`、`Polynomial`、`Interpolation` 不可变，可跨任务共享。
- 静态算子类无实例状态，可并发调用；不缓存计划、不写全局表。
- 输入列表只借用；构造时复制；访问器返回副本。
- 回调（被积函数、目标函数、导数、ODE 右端）由调用方保证线程安全；本包在调用线程同步调用。

---

## 5. 行业对齐

### 5.1 采用的表面

| 参考 | 采用 | 不采用 |
| --- | --- | --- |
| BLAS/LAPACK | 稠密分解与求解继续由 `xdk.linalg` 提供；本包只消费 `Matrix`/`Vector` | 公共 `dgemm`/`dgesv` 绑定、列主序、工作区查询 |
| Eigen | 稠密数值算法分层、分解工厂、明确失败的思想 | 表达式模板、固定尺寸矩阵、稀疏模块、几何模块 |
| NumPy/SciPy | 多项式、特殊函数、积分、优化、插值、信号、FFT 的领域划分 | ndarray 广播、轴参数、多维 FFT、稀疏、全局随机 |
| Boost.Math | 特殊函数、求根、求积、插值的算法集合 | 模板策略、编译期分发、任意 Real 概念 |
| GSL | QUADPACK 风格自适应积分、ODE 步进、FFT、插值 | 全局错误处理器、`gsl_sf_result` 双通道、工作区对象 |
| FFTW | 一维复数/实数变换、显式归一化、任意长度 | plan/wisdom、原地变换、多线程计划、FFI 句柄 |
| GMP/MPFR/Arb | 任意精度整数/浮点、显式舍入、每值精度 | 有理数、球算术、任意精度复数、底层 limb API |

### 5.2 取舍说明

- **积分**：采用自适应 Gauss-Kronrod 作为默认、tanh-sinh 处理端点奇异、Gauss-Legendre 固定阶；不暴露 QUADPACK 的工作区与错误码表。
- **优化**：只做无约束局部优化；一维 Brent、多变量 Nelder-Mead 与 BFGS；约束、全局优化、最小二乘拟合不在本包。
- **ODE**：固定步长 RK4、自适应 Dormand-Prince 5(4)、带雅可比的隐式 Euler；不做事件检测、稠密输出、刚性 BDF。
- **FFT**：一维、任意长度、复数与实数；归一化规则固定为“正变换不除 N、逆变换除 N”；不做 plan 缓存与多维。
- **任意精度**：`BigInt` 对齐 GMP `mpz` 的常用子集；`BigFloat` 对齐 MPFR 的“每值精度 + 每次舍入”，但不做特殊值与子正规数；不引入 Arb 的球半径。
- **特殊函数**：只做 `Double` 版本；高精度特殊函数由 `BigFloat` 的初等函数组合，不承诺任意精度 Gamma/Zeta。

### 5.3 参考来源

- BLAS：<https://netlib.org/blas/>
- LAPACK 用户指南（驱动/计算/辅助例程分层）：<https://netlib.org/lapack/lug/node22.html>
- Eigen 稠密分解目录：<https://libeigen.gitlab.io/eigen/docs-master/group__TopicLinearAlgebraDecompositions.html>
- NumPy 多项式包：<https://numpy.org/doc/stable/reference/routines.polynomials-package.html>
- SciPy 优化与求根：<https://docs.scipy.org/doc/scipy/reference/optimize.html>
- SciPy 插值：<https://docs.scipy.org/doc/scipy/reference/interpolate.html>
- SciPy 信号：<https://docs.scipy.org/doc/scipy/reference/signal.html>
- SciPy FFT：<https://docs.scipy.org/doc/scipy/reference/fft.html>
- Boost.Math 特殊函数：<https://www.boost.org/doc/libs/latest/libs/math/doc/html/special.html>
- Boost.Math 求根：<https://www.boost.org/doc/libs/latest/libs/math/doc/html/root_finding.html>
- Boost.Math 求积：<https://www.boost.org/doc/libs/latest/libs/math/doc/html/quadrature.html>
- Boost.Math 插值：<https://www.boost.org/doc/libs/latest/libs/math/doc/html/interpolation.html>
- GSL 例程总表：<https://www.gnu.org/software/gsl/doc/html/>
- FFTW 复数 DFT：<https://fftw.org/fftw3_doc/Complex-DFTs.html>
- FFTW 实数 DFT：<https://fftw.org/fftw3_doc/One_002dDimensional-DFTs-of-Real-Data.html>
- GMP 整数函数：<https://gmplib.org/manual/Integer-Functions>
- MPFR 舍入语义：<https://mpfr.org/mpfr-current/mpfr.html>
- Arb 球算术概览：<https://arblib.org/overview.html>

---

## 6. 场景

### M1：高精度累加

`BigFloat.parse("0.1", 256, HalfEven, 64)` 累加一百万次；每次 `add` 指定 256 位与 `HalfEven`；结果用 `toDecimalString` 输出；不把 `Double` 隐式塞进 `BigFloat`。

### M2：多项式求根

`Polynomial.of([-6.0, 11.0, -6.0, 1.0])` 构造三次多项式；`roots(context, 1e-12, 1000)` 返回三个复根；按实部/虚部排序；不收敛时显式处理 `Err`。

### M3：端点奇异积分

`Integration.integrateTanhSinh(context, integrand, 0.0, 1.0, 1e-12, 8)` 处理 `1/sqrt(x)` 型端点奇异；与解析值对比；不把 `NaN` 当成功。

### M4：ODE 轨迹

`solveDormandPrince` 从 `[1.0, 0.0]` 积分谐振子；返回时间列表与状态列表；每步检查 `Context`；误差超限时缩小步长，低于最小步长返回 `Err`。

### M5：频谱分析

`SignalBuffer.hannWindow(1024, true)` 后逐点乘输入；`Fft.forwardReal` 得 513 个非冗余频点；`Fft.inverseReal` 还原时检查 DC/Nyquist 虚部容差。

### M6：一维求根

`RootFinder.brent(context, function, 0.0, 2.0, 1e-12, 200)`；端点同号时立即 `InvalidArgument`；函数返回非有限值时立即失败，不继续迭代。

### M7：插值

`Interpolation.naturalCubicSpline(xValues, yValues)`；`evaluate` 只接受节点区间内的值；区间外返回 `InvalidArgument`，不静默外推。

---

## 7. 缺口

| 项 | 决策 |
| --- | --- |
| 符号代数/自动微分 | 不做；需独立包与表达式模型 |
| 稀疏矩阵/迭代线性求解 | 不做；`xdk.linalg` 只覆盖稠密 |
| GPU/NPU/分布式 | 不做；X 后端不暴露设备 |
| BLAS/LAPACK/FFTW 绑定 | 不做；实现可替换，公共 API 无 FFI 句柄 |
| 多维 FFT/多维插值 | X；当前只做一维 |
| 约束优化/线性规划/全局优化 | X；当前只做无约束局部优化 |
| 刚性 ODE/BDF/事件检测 | X；当前隐式 Euler 只覆盖小刚度 |
| 任意精度特殊函数 | X；`BigFloat` 只保证初等函数 |
| 任意精度复数/有理数/球算术 | X；不与 Arb 竞争 |
| 自适应舍入/误差证明 | 不做；`BigFloat` 是定点精度浮点，不附带区间 |
| 并行 FFT/多线程积分 | X；当前单线程、纯 XNull |

---

## 8. 安全

- **不可信长度**：解析、FFT、插值、滤波在分配前检查长度/位数；超限 `InvalidArgument`；不做 `Int` 回绕。
- **不可信数值**：所有入口拒绝 NaN/±Inf（除 `Double` 算法明确文档化的 IEEE 传播）；回调返回非有限值立即失败。
- **迭代上限**：积分、优化、ODE、求根、多项式求根都要求显式 `maximumIterations`/`maximumDepth`/`maximumLevel`；达到上限返回错误。
- **取消**：长操作每轮检查 `Context`；取消后不写共享缓冲、不返回半成品。
- **无原生内存**：公共 API 不含裸指针、fd、FFI 句柄、BLAS 工作区；不存在 native 缓冲区越界面。
- **确定性**：不使用随机数；算法路径由输入与显式参数决定；不依赖哈希遍历顺序。
- **拒绝服务**：`BigInt` 解析、`BigFloat` 精度、FFT 长度、插值节点数都有上限；调用方仍应对公网输入做配额。
- **无隐式求值**：不做符号展开、不做用户文本求值；多项式与回调都是显式数据/函数。

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | 无领域注解 |
| 本包消费 | `@Value`、`@Builder`、`@Copy` |
| 处理器 | 标准 A8 |
| 生成物 | 大数/多项式/信号值语义 |
| 状态 | 无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `BigInt`/`BigFloat`/`Polynomial`/`SignalBuffer` | `@Value`/`@Builder` | 值语义/构造 |

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
