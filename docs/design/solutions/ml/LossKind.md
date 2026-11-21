# `LossKind`

| 项 | 值 |
| --- | --- |
| 类型 | `enum LossKind` |
| 包 | `xdk.ml` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

损失函数家族：均方误差、平均绝对误差、交叉熵、二元交叉熵、负对数似然、适配器自定义。

只说明“标量损失如何从预测/目标计算”，不定义反向传播、梯度、正则项、类别权重、掩码或数值优化器。

不做：自动求导、focal loss、dice loss、CTC、对比损失、标签平滑、样本权重、分布式归约。

---

## 2. 设计逻辑

- 损失必须显式：`Trainer.lossKind()` 或 `Ml.computeLoss` 的参数决定语义；不从输出形状猜。
- `Ml.computeLoss` 只计算前向标量损失，不产生梯度；反向传播由 X 自动微分引擎完成。
- 回归损失要求预测与目标同形、同浮点 dtype；分类损失对目标 dtype/形状有明确约定。
- 平均方式固定为“对样本/元素取算术平均”；不提供 `reduction` 参数，避免隐藏的求和/加权语义。
- `Other` 允许自定义损失；`Ml.computeLoss` 对 `Other` 返回 `Unsupported`，实现方必须自行计算。
- 成员只允许追加；序号固定；名称是日志/配置合同。
- 不把损失与指标混淆：准确率/稀疏度/R² 等由应用计算。

---

## 3. 表示与不变量

| 成员 | 序号 | 稳定名 | 预测 | 目标 | 归约 |
| --- | ---: | --- | --- | --- | --- |
| `MeanSquaredError` | 0 | `"mean-squared-error"` | 浮点，任意形状 | 同形同 dtype 浮点 | 元素平均 |
| `MeanAbsoluteError` | 1 | `"mean-absolute-error"` | 浮点，任意形状 | 同形同 dtype 浮点 | 元素平均 |
| `CrossEntropy` | 2 | `"cross-entropy"` | `[batch, classes]` 浮点 logits | `[batch]` Int32/Int64 类别下标 | 样本平均 |
| `BinaryCrossEntropy` | 3 | `"binary-cross-entropy"` | 浮点概率 `[0,1]`，任意形状 | 同形浮点 0/1 | 元素平均 |
| `NegativeLogLikelihood` | 4 | `"negative-log-likelihood"` | `[batch, classes]` 浮点对数概率 | `[batch]` Int32/Int64 类别下标 | 样本平均 |
| `Other` | 5 | `"other"` | 适配器定义 | 适配器定义 | 适配器定义 |

不变量：成员固定；序号 0..5 固定；稳定名唯一；`Other` 合法；损失不隐含优化器、模型格式或指标。

---

## 4. 生命周期

值类型；无构造器、无 close；可自由复制、共享、作为 `Map`/`Set` 键。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| 枚举成员 | 无 | 六个成员之一 | 不存在非法成员 |
| `lossKindFromName` | `String name` | 任意文本 | null/未知/空白 → `null` |

枚举成员直接使用；不允许 `new LossKind()`，不允许应用扩展成员。

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

`LossKind` 没有实例方法。相关顶层函数：

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `lossKindName` | 稳定小写名 | `LossKind lossKind` | `String` | null → panic | 用于日志/配置 |
| `lossKindFromName` | 名称解析 | `String name` | `LossKind?` | 无 | 去空白、忽略大小写；未知 → `null` |
| `lossKindIsRegression` | 是否回归损失 | `LossKind lossKind` | `Bool` | null → panic | MSE/MAE 为真 |

说明：

- 名称是交换合同；不得把 `"mse"`、`"ce"` 解析为成员。
- `lossKindIsRegression` 只帮助选路，不表示预测/目标形状自动兼容。
- `Other` 合法，但 `Ml.computeLoss` 不实现其语义，返回 `Unsupported`。

---

## 8. 使用的技术

- 简单枚举 + 固定序号；
- 名称双向映射；
- 回归/分类语义表；
- 与自动微分/优化器解耦。

---

## 9. 需要的支撑

- 语言：enum、String、Bool；
- 运行时：字符串去空白、小写；
- 接口：[`Ml`](Ml.md)、[`Trainer`](Trainer.md)、[`Optimizer`](Optimizer.md)、`Tensor`。

---

## 10. 依赖的特性/接口/类

[`Ml`](Ml.md)、[`Trainer`](Trainer.md)、[`Optimizer`](Optimizer.md)、[`Tensor`](../../platform/tensor/Tensor.md)。

不依赖 PyTorch、TensorFlow、自动微分引擎或损失函数库。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。  
相等：按枚举值比较；可作 `Map`/`Set` 键。

---

## 12. 示例与反例

正确：`Ml.computeLoss(context, LossKind.CrossEntropy, logits, classTargets)`；回归用 `MeanSquaredError` 且预测/目标同形；`Other` 交给自定义 Trainer 实现。  
反例：把 `"mse"` 当合法名称；用 `MeanSquaredError` 处理类别下标目标；把 `NegativeLogLikelihood` 当 logits 交叉熵（它要求对数概率）；期望 `Ml.computeLoss` 返回梯度；把损失枚举当优化器。

---

## 13. 测试/场景义务

六个成员的名称/序号；`lossKindFromName` 的大小写、空白、未知、空串；`lossKindIsRegression` 对 MSE/MAE 为真、其余为 false；`Other` 不 panic；与 `Optimizer`/`Trainer` 组合；枚举值可作 `Map` 键；不出现第七个成员。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
enum LossKind {
    MeanSquaredError = 0,
    MeanAbsoluteError = 1,
    CrossEntropy = 2,
    BinaryCrossEntropy = 3,
    NegativeLogLikelihood = 4,
    Other = 5,
}

String lossKindName(LossKind lossKind) {
    if lossKind == null { throw "lossKindName: null loss kind" }
    if lossKind == LossKind.MeanSquaredError { return "mean-squared-error" }
    if lossKind == LossKind.MeanAbsoluteError { return "mean-absolute-error" }
    if lossKind == LossKind.CrossEntropy { return "cross-entropy" }
    if lossKind == LossKind.BinaryCrossEntropy {
        return "binary-cross-entropy"
    }
    if lossKind == LossKind.NegativeLogLikelihood {
        return "negative-log-likelihood"
    }
    return "other"
}

LossKind? lossKindFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "mean-squared-error" {
        return LossKind.MeanSquaredError
    }
    if normalized == "mean-absolute-error" {
        return LossKind.MeanAbsoluteError
    }
    if normalized == "cross-entropy" { return LossKind.CrossEntropy }
    if normalized == "binary-cross-entropy" {
        return LossKind.BinaryCrossEntropy
    }
    if normalized == "negative-log-likelihood" {
        return LossKind.NegativeLogLikelihood
    }
    if normalized == "other" { return LossKind.Other }
    return null
}

Bool lossKindIsRegression(LossKind lossKind) {
    if lossKind == null {
        throw "lossKindIsRegression: null loss kind"
    }
    return lossKind == LossKind.MeanSquaredError
        || lossKind == LossKind.MeanAbsoluteError
}
```
