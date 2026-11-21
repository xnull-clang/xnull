# `Optimizer`

| 项 | 值 |
| --- | --- |
| 类型 | `class Optimizer` |
| 包 | `xdk.ml` |
| 稳定性 | `preview` |
| 依赖 | `OptimizerKind`、`Double`、`Bool` |

---

## 1. 定位

优化器配置值对象：算法种类与学习率、权重衰减、动量、Adam 矩参数、epsilon。

只描述“训练器应使用哪组优化超参数”，不执行参数更新、不保存动量/二阶矩、不计算梯度、不调度学习率。

不做：`step`、`zeroGrad`、梯度裁剪、学习率 warmup/decay、参数分组、稀疏梯度、混合精度、优化器状态序列化。

---

## 2. 设计逻辑

- 用 `class`：七个字段需要统一范围校验，且未来可扩展；不是枚举，也不是协议。
- 不可变配置：构造后只读；`copy()` 返回新实例；没有 `setLearningRate`。
- `_kind` 决定超参数解释：SGD 使用 momentum；Adam/AdamW 使用 beta1/beta2/epsilon；RmsProp 使用 beta2/epsilon/momentum；AdaGrad 使用 epsilon；`Other` 由实现约定。
- 无关超参数仍必须给合法值；本类不因 kind 把字段设为“未定义”，避免 null/0 双关。
- 更新规则、状态布局、参数遍历由 [`Trainer`](Trainer.md) 的实现与 X 自动微分/优化引擎负责；本类不伪造 `step`。
- 学习率必须有限且 >0；权重衰减/动量/beta 必须在有限区间；epsilon 必须有限且 >0。
- 不包含模型/参数/设备；配置可跨任务共享。
- 不提供全局默认优化器；默认值由调用方显式选择。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_kind` | `OptimizerKind` | final | 非 null |
| `_learningRate` | `Double` | final | 有限且 >0 |
| `_weightDecay` | `Double` | final | 有限且 ≥0 |
| `_momentum` | `Double` | final | 有限且 `[0,1)` |
| `_beta1` | `Double` | final | 有限且 `[0,1)` |
| `_beta2` | `Double` | final | 有限且 `[0,1)` |
| `_epsilon` | `Double` | final | 有限且 >0 |

不变量：kind 非 null；所有数值有限；learningRate >0；weightDecay ≥0；momentum/beta1/beta2 在 `[0,1)`；epsilon >0；构造后不可变。

---

## 4. 生命周期

构造后不可变；无 close；无资源；可跨任务共享；可被多个 `Trainer` 实现读取。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Optimizer(OptimizerKind optimizerKind, Double learningRate, Double weightDecay, Double momentum, Double beta1, Double beta2, Double epsilon)` | 算法、学习率、权重衰减、动量、beta1、beta2、epsilon | kind 非 null；learningRate 有限 >0；weightDecay 有限 ≥0；momentum/beta1/beta2 有限 `[0,1)`；epsilon 有限 >0 | 违约 → panic |

---

## 6. 字段表

见 §3；字段私有。不暴露优化器状态、参数引用、设备或随机源。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `kind` | 优化器种类 | 无 | `OptimizerKind` | 无 | O(1) |
| `learningRate` | 学习率 | 无 | `Double` | 无 | >0 |
| `weightDecay` | 权重衰减 | 无 | `Double` | 无 | ≥0 |
| `momentum` | 动量 | 无 | `Double` | 无 | `[0,1)` |
| `beta1` | 一阶矩衰减 | 无 | `Double` | 无 | `[0,1)` |
| `beta2` | 二阶矩衰减 | 无 | `Double` | 无 | `[0,1)` |
| `epsilon` | 数值稳定项 | 无 | `Double` | 无 | >0 |
| `copy` | 复制 | 无 | `Optimizer` | 无 | 独立值 |
| `describe` | 单行描述 | 无 | `String` | 无 | 不含参数 |

说明：

- `copy()` 与构造器共享语义：新对象；数值为值类型。
- `describe()` 不输出完整超参数（避免日志噪声/敏感调参信息），只输出 kind 与 learningRate。
- 不提供 `step`/`zeroGrad`/`state`：这些需要参数、梯度和自动微分引擎，属于 X。`Trainer` 实现必须以显式梯度调用自己的优化器状态，不得把本类当可执行优化器。
- `OptimizerKind.Other` 合法；Trainer 实现不支持时返回 `Unsupported`。
- 不把 `weightDecay` 自动解释为 L2 正则/解耦衰减：AdamW 由 kind 表达解耦语义，其他 kind 由实现解释。

---

## 8. 使用的技术

- 不可变配置值对象；
- 数值范围/有限性校验；
- 算法种类与超参数分离；
- 与自动微分/优化执行解耦。

---

## 9. 需要的支撑

- 语言：class、final 字段、Double、Bool、String；
- 数学：`isFinite`；
- 接口：[`OptimizerKind`](OptimizerKind.md)、[`Trainer`](Trainer.md)、[`LossKind`](LossKind.md)、[`EpochStats`](EpochStats.md)。

---

## 10. 依赖的特性/接口/类

[`OptimizerKind`](OptimizerKind.md)、[`Trainer`](Trainer.md)、[`LossKind`](LossKind.md)、[`EpochStats`](EpochStats.md)。

不依赖 PyTorch、自动微分引擎、GPU 内核或优化器状态文件。

---

## 11. 所有权与并发

不可变；可共享；无资源；无取消点。  
相等：没有 `equals`；`==` 是引用身份；需要比较时逐字段比较；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：`new Optimizer(OptimizerKind.AdamW, 0.001, 0.01, 0.0, 0.9, 0.999, 0.00000001)`；Trainer 读取配置并维护自己的状态；不支持 `Other` 的实现返回 `Unsupported`。  
反例：期望 `optimizer.step(parameters)` 存在；把 `learningRate == 0` 当“冻结参数”；用 `momentum` 同时表示 Adam beta1；在优化器里保存参数张量并跨训练步复用；用 `copy()` 复制优化器状态（本类无状态）。

---

## 13. 测试/场景义务

kind null panic；learningRate 0/负/NaN/Inf panic；weightDecay 负/NaN/Inf panic；momentum/beta1/beta2 边界 0/<1/1/NaN/Inf；epsilon 0/负/NaN/Inf panic；各 kind 组合；`copy` 独立；`describe` 稳定；配置跨任务共享；不与 Trainer 状态混淆。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class Optimizer {
    final OptimizerKind _kind
    final Double _learningRate
    final Double _weightDecay
    final Double _momentum
    final Double _beta1
    final Double _beta2
    final Double _epsilon

    Optimizer(OptimizerKind optimizerKind, Double learningRate,
              Double weightDecay, Double momentum, Double beta1,
              Double beta2, Double epsilon) {
        if optimizerKind == null {
            throw "Optimizer: null optimizer kind"
        }
        if !isFinite(learningRate) || learningRate <= 0.0 {
            throw "Optimizer: invalid learning rate"
        }
        if !isFinite(weightDecay) || weightDecay < 0.0 {
            throw "Optimizer: invalid weight decay"
        }
        if !isFinite(momentum) || momentum < 0.0 || momentum >= 1.0 {
            throw "Optimizer: invalid momentum"
        }
        if !isFinite(beta1) || beta1 < 0.0 || beta1 >= 1.0 {
            throw "Optimizer: invalid beta1"
        }
        if !isFinite(beta2) || beta2 < 0.0 || beta2 >= 1.0 {
            throw "Optimizer: invalid beta2"
        }
        if !isFinite(epsilon) || epsilon <= 0.0 {
            throw "Optimizer: invalid epsilon"
        }
        _kind = optimizerKind
        _learningRate = learningRate
        _weightDecay = weightDecay
        _momentum = momentum
        _beta1 = beta1
        _beta2 = beta2
        _epsilon = epsilon
    }

    OptimizerKind kind() { return _kind }
    Double learningRate() { return _learningRate }
    Double weightDecay() { return _weightDecay }
    Double momentum() { return _momentum }
    Double beta1() { return _beta1 }
    Double beta2() { return _beta2 }
    Double epsilon() { return _epsilon }

    Optimizer copy() {
        return new Optimizer(_kind, _learningRate, _weightDecay, _momentum,
            _beta1, _beta2, _epsilon)
    }

    String describe() {
        return "optimizer kind=" + optimizerKindName(_kind)
            + " learningRate=" + str(_learningRate)
    }
}
```
