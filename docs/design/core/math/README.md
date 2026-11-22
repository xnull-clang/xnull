# `xdk.math` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.math` |
| 层 | `xdk.core` / L2 |
| 依赖 | `xdk.errors` |
| 被依赖 | `time`、`stats`、`metrics`、`net` |
| 稳定性 | 基础 `stable`；Decimal/Complex `preview` |
| 文档原则 | 包级说明在本 README；每个类/枚举/标量一个 PascalCase 文件 |

---

## 1. 包定位

`xdk.math` 提供数值计算：

- 浮点常量/分类/取整/幂/三角/插值；
- 整数 checked/saturating/数论/组合；
- `Int128` checked 算术；
- `Decimal` 固定精度十进制（金额/精确计算）；
- `Complex` 复数（X）；
- 统计/直方图/回归/移动平均。

不做：随机数（`xdk.random`）、任意精度、矩阵/张量（）、GPU。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| IEEE 754 | 浮点域错误返回 NaN/Inf，不 panic |
| 整数宽度 | `Int` 32 位、`Long` 64 位；溢出 checked/saturating |
| 合同错误 | 非法 shift/负阶乘/非法 Decimal 参数 panic 或 Result 按方法定 |
| 无隐式提升 | Int/Long/Decimal 显式选择 |
| 无全局状态 | 无常量可变/全局舍入模式 |
| 精度明确 | Decimal 固定 64 位系数；不冒充任意精度 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `RoundingMode` | enum | 舍入模式 | [`RoundingMode.md`](RoundingMode.md) |
| `Int128` | 语言标量 | 128 位整数/checked 函数 | [`Int128.md`](Int128.md) |
| `Decimal` | class | 固定精度十进制 | [`Decimal.md`](Decimal.md) |
| `Complex` | class | 复数（X） | [`Complex.md`](Complex.md) |

---

## 4. 顶层函数

### 4.1 常量/分类

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `PI` | π | 无 | `Double` | 无 |
| `E` | e | 无 | `Double` | 无 |
| `TAU` | 2π | 无 | `Double` | 无 |
| `Inf` | 正无穷 | 无 | `Double` | 无 |
| `NaN` | NaN | 无 | `Double` | 无 |
| `isNaN` | 是否 NaN | `Double value` | `Bool` | 无 |
| `isInf` | 是否无穷 | `Double value` | `Bool` | 无 |
| `isFinite` | 是否有限 | `Double value` | `Bool` | 无 |
| `sign` | 符号 | `Double value` | `Double` | 无 |

### 4.2 取绝对值/比较/取整

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `abs` | 浮点绝对值 | `Double value` | `Double` | 无 |
| `absI` | Int 绝对值 | `Int value` | `Int` | MIN → panic |
| `absL` | Long 绝对值 | `Long value` | `Long` | MIN → panic |
| `min/max` | 浮点最小/最大 | `Double left, Double right` | `Double` | 无 |
| `minI/maxI` | Int 最小/最大 | `Int left, Int right` | `Int` | 无 |
| `minL/maxL` | Long 最小/最大 | `Long left, Long right` | `Long` | 无 |
| `clamp` | 浮点钳制 | `Double value, Double minimum, Double maximum` | `Double` | min>max → panic |
| `clampI/clampL` | 整数钳制 | 同上 | `Int`/`Long` | min>max → panic |
| `floor/ceil/round/trunc` | 浮点取整 | `Double value` | `Double` | 无 |
| `floorToInt/ceilToInt/roundToInt/truncToInt` | 取整转 Int | `Double value` | `Int` | 溢出 → `InvalidArgument`? 见下 |

> `*ToInt` 返回 `Result<Int, Error>`；NaN/溢出 → `InvalidArgument`。表中简写为 `Int` 仅为分组。

### 4.3 幂/指数/对数/三角

| 组 | 函数 |
| --- | --- |
| 模/幂 | `mod(Double,Double)`、`rem(Double,Double)`、`pow(Double,Double)`、`sqrt`、`cbrt`、`hypot(Double,Double)` |
| 指数/对数 | `exp`、`log`、`log2`、`log10` |
| 三角 | `sin`、`cos`、`tan`、`asin`、`acos`、`atan`、`atan2(Double,Double)` |
| 双曲 | `sinh`、`cosh`、`tanh` |
| 角度 | `deg2rad`、`rad2deg` |
| 插值 | `lerp(Double,Double,Double)`、`smoothstep`、`mapRange` |

失败：无；域错误按 IEEE 返回 NaN/Inf。

### 4.4 数论/组合

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `gcd` | 最大公约数 | `Int left, Int right` | `Int` | 无 |
| `lcm` | 最小公倍数 | `Int left, Int right` | `Int` | 溢出 → `InvalidArgument` |
| `isPrime` | 是否素数 | `Int value` | `Bool` | 无 |
| `nextPrime` | 下一个素数 | `Int value` | `Result<Int, Error>` | 溢出 |
| `primeFactors` | 素因子 | `Int value` | `List<Int>` | 负数 → panic |
| `factorial` | 阶乘 | `Int value` | `Result<Int, Error>` | 负数/超 32 位 |
| `binomial` | 二项式系数 | `Int totalCount, Int selectedCount` | `Result<Long, Error>` | 非法/溢出 |
| `permutations` | 排列 | 同上 | `Result<Long, Error>` | 非法/溢出 |
| `combinations` | 组合 | 同上 | `Result<Long, Error>` | 非法/溢出 |

### 4.5 Int/Long checked/saturating

| 组 | 函数 |
| --- | --- |
| 边界 | `maxIntValue`、`minIntValue`、`maxLongValue`、`minLongValue` |
| Int checked | `addIntChecked`、`subIntChecked`、`mulIntChecked`、`divIntChecked`、`modIntChecked`、`negIntChecked`、`absIntChecked` |
| Long checked | `addLongChecked`、`subLongChecked`、`mulLongChecked`、`divLongChecked`、`modLongChecked`、`negLongChecked`、`absLongChecked` |
| Int saturating | `addIntSaturating`、`subIntSaturating`、`mulIntSaturating` |
| Long saturating | `addLongSaturating`、`subLongSaturating`、`mulLongSaturating` |

规则：除零/溢出/下溢/`min / -1`/`neg(min)`/`abs(min)` → `InvalidArgument`；`mod(min,-1)=0`；saturating 钳制到 min/max。

### 4.6 Int128

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `int128Min/Max` | 边界 | 无 | `Int128` | 无 |
| `addI128Checked` | 加 | `Int128 left, Int128 right` | `Result<Int128, Error>` | 溢出 |
| `subI128Checked` | 减 | 同上 | `Result<Int128, Error>` | 溢出 |
| `mulI128Checked` | 乘 | 同上 | `Result<Int128, Error>` | 溢出 |
| `divI128Checked` | 除 | 同上 | `Result<Int128, Error>` | 除零/溢出 |
| `modI128Checked` | 模 | 同上 | `Result<Int128, Error>` | 除零；`min%-1=0` |
| `negI128Checked` | 取负 | `Int128 value` | `Result<Int128, Error>` | MIN |
| `absI128Checked` | 绝对值 | `Int128 value` | `Result<Int128, Error>` | MIN |

### 4.7 统计

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `sum` | 和 | `List<Double> values` | `Double` | 空 → 0 |
| `product` | 积 | 同上 | `Double` | 空 → 1 |
| `mean` | 均值 | 同上 | `Double` | 空 → NaN |
| `median` | 中位数 | 同上 | `Double` | 空 → NaN |
| `mode` | 众数 | 同上 | `Double?` | 空 → null |
| `variance` | 方差 | 同上 | `Double` | 空 → NaN |
| `sampleVariance` | 样本方差 | 同上 | `Double` | <2 → NaN |
| `stddev` | 标准差 | 同上 | `Double` | 空 → NaN |
| `quantile` | 分位 | `List<Double> values, Double q` | `Double` | q 钳制 [0,1] |
| `percentile` | 百分位 | `List<Double> values, Double p` | `Double` | p 钳制 [0,100] |
| `range` | 极差 | `List<Double> values` | `Double` | 空 → NaN |
| `covariance` | 协方差 | `List<Double> left, List<Double> right` | `Double` | 长度不等 → panic |
| `correlation` | 相关 | 同上 | `Double` | 长度不等/零方差 → NaN |
| `linearRegression` | 回归 | 同上 | `Regression`? | 见下 |
| `histogram` | 直方图 | `List<Double> values, List<Double> boundaries` | `List<Int>` | 边界非递增 → panic |
| `movingAverage` | 移动平均 | `List<Double> values, Int window` | `List<Double>` | window≤0 → panic |
| `ema` | 指数移动平均 | `List<Double> values, Double alpha` | `List<Double>` | alpha 0..1 否则 panic |
| `zscore` | 标准分 | `List<Double> values, Double value` | `Double` | 零方差 → NaN |

> `linearRegression` 需要 `Regression` 类型；本批先列为函数契约，类型归 X，避免在 math 里塞未设计类。

---

## 5. 关键函数伪代码

### 5.1 `factorial`

```xnull
Result<Int, Error> factorial(Int value) {
    if value < 0 {
        return Err(new BasicError(ErrorKind.InvalidArgument, "negative factorial"))
    }
    Int result = 1
    Int index = 2
    while index <= value {
        if result > 2147483647 / index {
            return Err(new BasicError(ErrorKind.InvalidArgument, "factorial overflow"))
        }
        result = result * index
        index = index + 1
    }
    return Ok(result)
}
```

### 5.2 `gcd` / `lcm`

```xnull
Int gcd(Int left, Int right) {
    Int a = left
    Int b = right
    if a < 0 { a = 0 - a }
    if b < 0 { b = 0 - b }
    while b != 0 {
        Int temporary = b
        b = a % b
        a = temporary
    }
    return a
}

Result<Int, Error> lcm(Int left, Int right) {
    if left == 0 || right == 0 { return Ok(0) }
    Int divisor = gcd(left, right)
    Long product = (left / divisor) as Long * (right as Long)
    if product > 2147483647 || product < -2147483648 {
        return Err(new BasicError(ErrorKind.InvalidArgument, "lcm overflow"))
    }
    return Ok(product as Int)
}
```

### 5.3 `mean` / `median` / `quantile`

```xnull
Double mean(List<Double> values) {
    if values.length() == 0 { return NaN() }
    Double total = 0.0
    Int index = 0
    while index < values.length() {
        total = total + values.get(index)
        index = index + 1
    }
    return total / values.length()
}

Double median(List<Double> values) {
    if values.length() == 0 { return NaN() }
    List<Double> sorted = sortedBy(values, (Double a, Double b) -> a < b)
    Int middle = sorted.length() / 2
    if sorted.length() % 2 == 1 {
        return sorted.get(middle)
    }
    return (sorted.get(middle - 1) + sorted.get(middle)) / 2.0
}

Double quantile(List<Double> values, Double probability) {
    if values.length() == 0 { return NaN() }
    Double clamped = clamp(probability, 0.0, 1.0)
    List<Double> sorted = sortedBy(values, (Double a, Double b) -> a < b)
    Double position = clamped * (sorted.length() - 1)
    Int lower = floorToInt(position)
    Int upper = ceilToInt(position)
    if lower == upper {
        return sorted.get(lower)
    }
    Double fraction = position - lower
    return lerp(sorted.get(lower), sorted.get(upper), fraction)
}
```

### 5.4 `addIntChecked`

```xnull
Result<Int, Error> addIntChecked(Int left, Int right) {
    Long sum = (left as Long) + (right as Long)
    if sum > 2147483647 || sum < -2147483648 {
        return Err(new BasicError(ErrorKind.InvalidArgument, "int overflow"))
    }
    return Ok(sum as Int)
}
```

---

## 6. 场景

### M1：金额计算

`Decimal.parse`/`add`/`sub`/`mul`/`div`/`setScale`；舍入 `HalfEven`；溢出 `InvalidArgument`；不静默回绕。

### M2：安全整数

`addIntChecked`/`mulLongChecked`；溢出返回 Err；saturating 只用于明确要钳制的场景。

### M3：统计报表

`mean/median/quantile/stddev`；空列表规则；NaN 传播；直方图边界。

### M4：几何/信号

`sin/cos/atan2/sqrt/hypot`；域错误 NaN/Inf；插值 `lerp/smoothstep`。

### M5：Int128 大整数

宽字面量 + `addI128Checked`；溢出/`MIN` 处理；不降级到 Long。

### M6：组合计数

`factorial/binomial/permutations/combinations`；负数/溢出 `InvalidArgument`。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 任意精度 | 不做；Decimal 是固定 64 位系数 |
| BigDecimal 语义 | Decimal 不冒充任意精度；超 18 位需  |
| 随机数 | `xdk.random` |
| 矩阵/张量 |  |
| 复数 | `Complex` 为 X |
| 回归类型 | `Regression` 归 X；本批只列函数契约 |
| 舍入模式 | 全局无默认；Decimal 方法显式传 `RoundingMode` |
| 浮点比较 | 不提供 epsilon 相等；调用方显式 |
| 统计空列表 | sum=0/product=1，mean/median/stddev=NaN |
| `Int128` | 语言标量；不定义 class |

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | 无领域注解 |
| 本包消费 | `@Value`、`@Builder`、`@Copy` |
| 处理器 | 标准 A8 |
| 生成物 | Decimal/Complex 值语义、构造/舍入选项 |
| 状态 | 无领域注解；A8 派生 planned；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `Decimal`/`Complex` | `@Value` | 值语义成员 |
| `RoundingMode` | — | enum |
| `Decimal` 构造选项 | `@Builder` | builder/build 校验 |

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
