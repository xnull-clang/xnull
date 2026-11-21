# `Transform`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol Transform` |
| 包 | `xdk.ml` |
| 稳定性 | `preview` |
| 依赖 | `Batch`、`Context`、`Error` |

---

## 1. 定位

批次/样本变换合同：接收 `Batch`，返回新的 `Batch`，可附带稳定描述。

只定义“输入批次 → 输出批次”的纯管道步骤；不做数据集索引、洗牌、拼批、并行预取、缓存、设备放置或模型推理。

不做：Tokenizer、图像解码/裁剪、音频重采样、数据增强库、随机数全局状态、自动求导。

---

## 2. 设计逻辑

- 非泛型协议：变换统一在 `Batch` 上表达，避免为每种样本类型引入泛型。
- 返回新 `Batch`，不原地修改；`Batch`/`Tensor` 不可变。
- `apply` 是阻塞点，首参 `Context`；取消返回 `Cancelled`，不返回半个批次。
- DataLoader 按“单样本批次”（`sampleCount == 1`）调用变换；独立使用时可以处理任意 `sampleCount`。
- 变换可以改变张量形状/ dtype（例如归一化、转置），但不能改变样本数；DataLoader 会在调用后校验 `sampleCount == 1`。
- 有状态变换（随机增强、running statistics）由实现自行同步；协议不承诺线程安全。
- 变换不拥有数据集/会话；无 close。持有文件/设备等资源的实现应在自己的公开 API 提供关闭，DataLoader 不会关闭变换。
- 不提供 `fit`/`inverse`/`compose`；组合由 DataLoader 的 `transforms` 列表顺序表达。

---

## 3. 表示与不变量

协议无字段。实现保证：

- `apply` 不修改传入 `Batch`；
- 成功返回的 `Batch` 非 null，张量满足 `Batch` 的批维合同；
- 不改变样本数（输入 `sampleCount` 与输出 `sampleCount` 相同）；
- 取消时不返回部分结果；
- `describe` 稳定、可读，不泄露样本内容；
- 无 close 语义；实现若持有资源，生命周期由实现另行声明。

---

## 4. 生命周期

协议无构造；实现创建后可用；实现可以长期复用。协议无 `close`；需要释放资源的实现必须在自己类型上提供 `close`，并由调用方负责，不由 `DataLoader` 隐式关闭。

---

## 5. 构造契约

协议无构造。实现类提供构造器；构造失败由实现决定，协议不规定。

实现应在构造时固定配置（例如归一化均值/方差）；需要变更时创建新变换。

---

## 6. 字段表

无协议字段。实现可持有配置、随机源、缓存或查找表，但不得通过协议暴露。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `apply` | 变换一个批次 | `Context context, Batch batch` | `Result<Batch, Error>` | `InvalidArgument`/`Cancelled`/实现错误 |
| `describe` | 单行描述 | 无 | `String` | 无 |

说明：

- `apply`：`context == null` 或 `batch == null` → panic；取消 → `Cancelled`；输出 `sampleCount` 与输入不同 → `InvalidArgument`。
- `apply` 可以改变输入/目标的数量和形状，但不得改变样本数；例如可以丢弃目标，不能丢弃样本。
- `apply` 不做设备传输；需要设备放置时由运行时适配器或上层处理。
- `describe` 用于日志/诊断；不输出张量值、文件路径或敏感配置。
- 变换不应捕获并隐藏 `Cancelled`；必须原样传播或返回新的取消错误。
- 随机变换必须由调用方注入随机源，不使用全局 RNG。

---

## 8. 使用的技术

- 非泛型协议；
- 不可变批次转换；
- `Context` 取消；
- 样本数保持；
- 顺序组合；
- 无全局随机源。

---

## 9. 需要的支撑

- 语言：protocol、class、String、Bool、Result、Unit、void；
- 运行时：由实现决定（CPU 计算、随机源、文件）；
- 接口：[`Batch`](Batch.md)、[`DataLoader`](DataLoader.md)、[`Dataset`](Dataset.md)、`Context`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

[`Batch`](Batch.md)、[`DataLoader`](DataLoader.md)、[`Dataset`](Dataset.md)、[`Tensor`](../../platform/tensor/Tensor.md)、`Context`、`Error`。

不依赖具体数据格式、模型运行时或图像/文本处理库。

---

## 11. 所有权与并发

调用方拥有变换；`DataLoader` 只借用。`apply` 返回新批次；不保留对输入批次的写引用。

协议不承诺线程安全；`DataLoader` 顺序调用。多任务共享同一变换时，实现必须自行同步（尤其随机增强）。

无 `equals`/`copy`；变换是行为对象，不是值对象。

---

## 12. 示例与反例

正确：归一化变换读取配置，逐元素计算并返回新 `Batch`；随机裁剪变换持有注入的随机源；`describe()` 返回 `"normalize(mean=0.5,std=0.5)"`。  
反例：`apply` 原地修改输入张量；输出 `sampleCount` 与输入不同；取消时返回部分批次；在变换内创建全局 RNG；`apply` 关闭数据集；把 tokenizer/图像解码塞进基线变换；`describe` 输出样本内容。

---

## 13. 测试/场景义务

单样本/多样本；输入不变；输出样本数保持；目标可空/非空；取消；null context/batch；返回 null 批次；`describe` 稳定；顺序组合；随机源显式；资源型实现自行 close；DataLoader 校验 `sampleCount == 1`。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
protocol Transform {
    Result<Batch, Error> apply(Context context, Batch batch);
    String describe();
}
```
