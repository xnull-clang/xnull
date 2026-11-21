# `xdk.tensor` CPU 张量

| 项 | 值 |
| --- | --- |
| 包 | `xdk.tensor` |
| 层 |  |
| 依赖 | `xdk.core`（`bytes`、`math`、`errors`） |
| 被依赖 | `xdk.linalg`、应用 |
| 稳定性 | `preview` |

> 本轮只冻结 CPU 稠密张量；GPU、自动微分、训练不在范围内。包级计划见 [`../../NON-UI-COMPLETION.md`](../../NON-UI-COMPLETION.md)。

---

## 1. 定位

CPU 上的 N 维稠密数值张量：dtype、shape、连续字节存储、逐元素读取与复制式更新、形状变换、矩阵乘。

不做：自动微分、计算图、GPU/加速器、训练、量化、稀疏张量、广播、任意 dtype 提升、字符串/复数元素。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| dtype 显式 | 每个张量携带 `TensorDType`；运算不隐式提升 |
| 形状即合同 | 形状不匹配是调用方违约（panic）；错误消息带运算名与失败类别 |
| 数据不可变 | 构造后字节不再变化；`withValue` 返回新张量，不提供原地 `set` |
| 无裸指针 | 数据封装在 `Bytes`；不暴露地址、容量、分配器 |
| 行主序 | 逻辑索引到连续存储固定为 row-major；`TensorView` 可带步长 |
| 字节序固定 | 小端、定宽、Bool 单字节 0/1；跨进程交换需上层协议 |
| 窄接口 | 元素访问、形状变换、`TensorOps` 静态算子；不把算法塞进 `Tensor` |
| 可预测失败 | 形状/索引/类型违约 panic；`xdk.linalg` 的数值失败用 `Result` |

---

## 3. 类型索引

| 类型 | 种类 | 文件 |
| --- | --- | --- |
| `TensorDType` | enum | [`TensorDType.md`](TensorDType.md) |
| `TensorShape` | class | [`TensorShape.md`](TensorShape.md) |
| `Tensor` | class | [`Tensor.md`](Tensor.md) |
| `TensorView` | class | [`TensorView.md`](TensorView.md) |
| `TensorOps` | class（静态算子） | [`TensorOps.md`](TensorOps.md) |

---

## 4. 跨类型规则

- `TensorDType` 决定元素宽度与数值域；`TensorShape` 只描述维度，不携带 dtype。
- `Tensor` 必须同时有 dtype、shape、字节数据；三者构造时校验，之后不可变。
- 逐元素与矩阵乘要求两个输入 dtype 相同、形状满足运算规则；不做隐式转换。
- 形状不匹配、索引越界、向整数 dtype 写入非整数/越界值均为合同错误（panic）。
- `TensorView` 只读、借用 `Tensor`、不复制；`toTensor()` 才产生独立副本。
- `TensorView` 的 offset/stride 以元素为单位，不是字节；步长非负，本轮不支持负步长。
- 元素计数用 `Long`，维度用 `Int`；底层 `Bytes` 长度仍是 `Int`，单张量字节数受运行时上限约束。
- `xdk.linalg` 通过 [`Linalg.matrixFromTensor`](../linalg/Linalg.md) 读取二维张量；张量包不反向依赖线性代数包。

---

## 5. 场景

- 特征预处理：把 `List<Double>` 批量装入 `Float32`/`Float64` 张量，做逐元素缩放前的加法/乘法。
- 小模型推理：二维权重与输入做 `matmul`；不涉及梯度与训练。
- 数值实验：用 `reshape`/`transpose`/`TensorView` 观察同一份数据的多种布局。
- 线性代数桥接：把二维张量交给 `xdk.linalg` 求解，结果再转回张量。

---

## 6. 缺口

- 自动微分/计算图/训练：X，需独立包。
- GPU/加速器：`xdk.gpu` 与 `xdk.os.gpu`，本包不绑定。
- 复数、量化、混合精度、任意 dtype 提升：X。
- 广播、切片、负步长、稀疏张量：X。
- 超过 `Int` 字节上限的大张量、内存映射张量：X。
- 序列化格式、跨进程共享、并行 kernel、BLAS 后端：X。
