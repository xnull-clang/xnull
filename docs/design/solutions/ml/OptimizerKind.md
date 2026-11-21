# `OptimizerKind`

| 项 | 值 |
| --- | --- |
| 类型 | `enum OptimizerKind` |
| 包 | `xdk.ml` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

优化器算法家族：SGD、Adam、AdamW、RMSprop、AdaGrad、适配器自定义。

只说明“用哪类更新规则”，不执行梯度计算、参数更新或状态分配。具体更新由 [`Trainer`](Trainer.md) 的实现与 X 自动微分/优化引擎完成。

不做：反向传播、数值梯度、学习率调度、梯度裁剪、混合精度、分布式 all-reduce、优化器状态持久化。

---

## 2. 设计逻辑

- 算法必须显式：`Optimizer.kind()` 决定超参数解释；不从超参数字段猜测算法。
- 名称对齐 PyTorch 常用优化器，便于跨生态映射；不复制其类层次。
- `Other` 允许自定义优化器；基线不定义其更新规则，Trainer 实现遇到不支持时可返回 `Unsupported`。
- 枚举与 `LossKind`、`MlTask`、`ModelFormat` 正交；优化器不等于损失函数或模型格式。
- 成员只允许追加；序号固定；名称是日志/配置合同。
- 学习率调度不在枚举内；调度是 Trainer/X 的职责。

---

## 3. 表示与不变量

| 成员 | 序号 | 稳定名 | 更新家族 | 主要超参数 |
| --- | ---: | --- | --- | --- |
| `Sgd` | 0 | `"sgd"` | 随机梯度下降 | learningRate、momentum、weightDecay |
| `Adam` | 1 | `"adam"` | 一阶/二阶矩 | learningRate、beta1、beta2、epsilon、weightDecay |
| `AdamW` | 2 | `"adamw"` | 解耦权重衰减 | learningRate、beta1、beta2、epsilon、weightDecay |
| `RmsProp` | 3 | `"rmsprop"` | 均方根传播 | learningRate、beta2、epsilon、momentum、weightDecay |
| `AdaGrad` | 4 | `"adagrad"` | 累积平方梯度 | learningRate、epsilon、weightDecay |
| `Other` | 5 | `"other"` | 适配器定义 | 由实现约定 |

不变量：成员固定；序号 0..5 固定；稳定名唯一；`Other` 合法；不隐含损失函数、模型结构、梯度来源或设备。

---

## 4. 生命周期

值类型；无构造器、无 close；可自由复制、共享、作为 `Map`/`Set` 键。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| 枚举成员 | 无 | 六个成员之一 | 不存在非法成员 |
| `optimizerKindFromName` | `String name` | 任意文本 | null/未知/空白 → `null` |

枚举成员直接使用；不允许 `new OptimizerKind()`，不允许应用扩展成员。

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

`OptimizerKind` 没有实例方法。相关顶层函数：

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `optimizerKindName` | 稳定小写名 | `OptimizerKind optimizerKind` | `String` | null → panic | 用于日志/配置 |
| `optimizerKindFromName` | 名称解析 | `String name` | `OptimizerKind?` | 无 | 去空白、忽略大小写；未知 → `null` |
| `optimizerKindUsesSecondMoment` | 是否使用二阶矩 | `OptimizerKind optimizerKind` | `Bool` | null → panic | Adam/AdamW/RmsProp/AdaGrad 为真 |

说明：

- 名称是交换合同；不得把 `"sgd_momentum"`、`"adam_w"` 解析为成员。
- `optimizerKindUsesSecondMoment` 只帮助状态布局/诊断，不表示优化器可实现。
- `Other` 对谓词返回 false；实现自行决定状态。

---

## 8. 使用的技术

- 简单枚举 + 固定序号；
- 名称双向映射；
- 优化器家族谓词；
- 与训练执行解耦。

---

## 9. 需要的支撑

- 语言：enum、String、Bool；
- 运行时：字符串去空白、小写；
- 接口：[`Optimizer`](Optimizer.md)、[`Trainer`](Trainer.md)、[`LossKind`](LossKind.md)。

---

## 10. 依赖的特性/接口/类

[`Optimizer`](Optimizer.md)、[`Trainer`](Trainer.md)、[`LossKind`](LossKind.md)。

不依赖 PyTorch、自动微分引擎、GPU 内核或优化器状态序列化格式。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。  
相等：按枚举值比较；可作 `Map`/`Set` 键。

---

## 12. 示例与反例

正确：`OptimizerKind.AdamW` 表示解耦权重衰减；`OptimizerKind.Other` 表示自定义更新并由 Trainer 实现解释；用 `optimizerKindUsesSecondMoment` 决定状态布局。  
反例：把 `Sgd` 当带动量的 Adam；用 `Other` 掩盖拼错的 `"adam"`；从 `OptimizerKind` 推断损失函数；假设所有优化器都支持稀疏梯度；把优化器枚举当学习率调度器。

---

## 13. 测试/场景义务

六个成员的名称/序号；`optimizerKindFromName` 的大小写、空白、未知、空串；二阶矩谓词覆盖 0..4 且 `Other` 为 false；与 `Optimizer` 超参数组合；与 `LossKind` 组合；枚举值可作 `Map` 键；不出现第七个成员。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
enum OptimizerKind {
    Sgd = 0,
    Adam = 1,
    AdamW = 2,
    RmsProp = 3,
    AdaGrad = 4,
    Other = 5,
}

String optimizerKindName(OptimizerKind optimizerKind) {
    if optimizerKind == null {
        throw "optimizerKindName: null optimizer kind"
    }
    if optimizerKind == OptimizerKind.Sgd { return "sgd" }
    if optimizerKind == OptimizerKind.Adam { return "adam" }
    if optimizerKind == OptimizerKind.AdamW { return "adamw" }
    if optimizerKind == OptimizerKind.RmsProp { return "rmsprop" }
    if optimizerKind == OptimizerKind.AdaGrad { return "adagrad" }
    return "other"
}

OptimizerKind? optimizerKindFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "sgd" { return OptimizerKind.Sgd }
    if normalized == "adam" { return OptimizerKind.Adam }
    if normalized == "adamw" { return OptimizerKind.AdamW }
    if normalized == "rmsprop" { return OptimizerKind.RmsProp }
    if normalized == "adagrad" { return OptimizerKind.AdaGrad }
    if normalized == "other" { return OptimizerKind.Other }
    return null
}

Bool optimizerKindUsesSecondMoment(OptimizerKind optimizerKind) {
    if optimizerKind == null {
        throw "optimizerKindUsesSecondMoment: null optimizer kind"
    }
    return optimizerKind == OptimizerKind.Adam
        || optimizerKind == OptimizerKind.AdamW
        || optimizerKind == OptimizerKind.RmsProp
        || optimizerKind == OptimizerKind.AdaGrad
}
```
