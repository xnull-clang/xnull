# `Regression`

| 项 | 值 |
| --- | --- |
| 类型 | `class Regression` |
| 包 | `xdk.stats` |
| 稳定性 | `preview` |
| 依赖 | `xdk.math` |

---

## 1. 定位

一元最小二乘线性回归：斜率、截距、预测、R²、残差。

不做：多元回归、正则化、非线性拟合、缺失值处理、持久化。

---

## 2. 设计逻辑

- 构造时校验 xValues/yValues 等长、至少 2 个、无 NaN；x 方差必须 >0。
- 计算 xMean/yMean，再算 Sxx/Sxy/Syy；斜率 = Sxy/Sxx，截距 = yMean - slope*xMean。
- R² = 1 - SSres/SStot；SStot=0 时，完美拟合为 1，否则 0。
- 残差按输入顺序保存；构造后不可变。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_slope` | `Double` | 斜率 |
| `_intercept` | `Double` | 截距 |
| `_r2` | `Double` | 决定系数 |
| `_residuals` | `List<Double>` | 残差 |
| `_count` | `Int` | 样本数 |

不变量：count ≥2；slope/intercept/r2 有限；residuals.length = count；x 方差 >0。

---

## 4. 生命周期

不可变；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Regression(List<Double> xValues, List<Double> yValues)` | xValues/yValues | 等长；≥2；无 NaN；x 方差>0 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `slope` | 斜率 | 无 | `Double` | 无 |
| `intercept` | 截距 | 无 | `Double` | 无 |
| `predict` | 预测 | `Double x` | `Double` | 无 |
| `r2` | 决定系数 | 无 | `Double` | 无 |
| `residuals` | 残差副本 | 无 | `List<Double>` | 无 |
| `count` | 样本数 | 无 | `Int` | 无 |

说明：

- `predict(x) = slope * x + intercept`。
- `r2` 越接近 1 拟合越好；负值表示差于均值基线。
- `residuals` 返回副本，不暴露内部列表。

---

## 8. 使用的技术

- 最小二乘；
- 中心化求和；
- R²/残差；
- 输入校验。

---

## 9. 需要的支撑

- 语言：class、List、Double、Int、Bool；
- 运行时：`mean`、`isNaN`；
- 接口：`xdk.math.mean`。

---

## 10. 依赖的特性/接口/类

`xdk.math.mean`、`xdk.math.isNaN`。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`new Regression([1.0,2.0,3.0], [2.0,4.0,6.0])`；slope=2，intercept=0。  
反例：xValues/yValues 长度不等；所有 x 值相同；含 NaN；把 R² 当因果关系。

---

## 13. 测试/场景义务

完美拟合；负斜率；水平线；噪声；R² 边界；残差和≈0；长度不等；x 方差 0；NaN；predict。

---

## 14. XNull 伪代码

```xnull
class Regression {
    final Double _slope
    final Double _intercept
    final Double _r2
    final List<Double> _residuals
    final Int _count

    Regression(List<Double> xValues, List<Double> yValues) {
        if xValues == null || yValues == null { throw "Regression: null input" }
        if xValues.length() != yValues.length() { throw "Regression: length mismatch" }
        if xValues.length() < 2 { throw "Regression: need at least two samples" }
        Int index = 0
        while index < xValues.length() {
            if isNaN(xValues.get(index)) || isNaN(yValues.get(index)) {
                throw "Regression: NaN sample"
            }
            index = index + 1
        }
        Double xMean = mean(xValues)
        Double yMean = mean(yValues)
        Double sxx = 0.0
        Double sxy = 0.0
        Double syy = 0.0
        index = 0
        while index < xValues.length() {
            Double dx = xValues.get(index) - xMean
            Double dy = yValues.get(index) - yMean
            sxx = sxx + dx * dx
            sxy = sxy + dx * dy
            syy = syy + dy * dy
            index = index + 1
        }
        if sxx == 0.0 { throw "Regression: zero x variance" }
        _slope = sxy / sxx
        _intercept = yMean - _slope * xMean
        List<Double> residuals = []
        Double ssRes = 0.0
        index = 0
        while index < xValues.length() {
            Double residual = yValues.get(index) - (_slope * xValues.get(index) + _intercept)
            residuals.push(residual)
            ssRes = ssRes + residual * residual
            index = index + 1
        }
        if syy == 0.0 {
            if ssRes == 0.0 { _r2 = 1.0 } else { _r2 = 0.0 }
        } else {
            _r2 = 1.0 - ssRes / syy
        }
        _residuals = residuals
        _count = xValues.length()
    }

    Double slope() { return _slope }
    Double intercept() { return _intercept }
    Double predict(Double xValue) { return _slope * xValue + _intercept }
    Double r2() { return _r2 }
    List<Double> residuals() { return _residuals.copy() }
    Int count() { return _count }
}
```
