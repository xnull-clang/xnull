# `Dataset`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol Dataset` |
| 包 | `xdk.ml` |
| 稳定性 | `preview` |
| 依赖 | `Batch`、`Context`、`Error` |

---

## 1. 定位

随机访问的数据集合同：样本总数、按 Long 下标读取单样本 `Batch`、打开状态与关闭。

只定义“如何按索引取一个样本”，不做批次拼接、洗牌、变换、并行加载、缓存、下载或格式解码。批次与流水线由 [`DataLoader`](DataLoader.md) 负责；样本内容由实现解释。

不做：迭代器、epoch、batch、shuffle、transform、多进程/多线程预取、内存映射、远程数据集、全局注册表。

---

## 2. 设计逻辑

- 非泛型协议：样本统一用 [`Batch`](Batch.md) 表达；`Batch.sampleCount()` 必须为 1，张量第 0 维为 1，表示“单样本也带批维”。
- 下标用 `Long`：数据集样本数可以超过 `Int`；具体实现对超大索引可以返回 `Unsupported`/`InvalidArgument`。
- `size` 是稳定快照：数据集打开期间不变化；需要动态数据集时创建新实例。
- `get` 是唯一阻塞点，首参 `Context`；取消返回 `Cancelled`，不产生半个样本。
- 资源生命周期显式：`close` 幂等，关闭后 `get` 返回 `Unavailable`；`size`/`describe` 仍可读。
- 协议不要求线程安全：`DataLoader` 顺序调用；多任务共享时实现必须自行同步。
- 不拥有 `DataLoader`；`DataLoader` 也不关闭借用的数据集。
- 没有全局数据集注册表或默认数据集。

---

## 3. 表示与不变量

协议无字段。实现保证：

- `size()` 在打开期间稳定且 ≥0；
- `get` 只返回 `sampleCount == 1` 的 `Batch`；
- 返回的 `Batch` 中每个张量第 0 维为 1；
- `get` 不修改数据集内部可观察状态（缓存除外，缓存不作为语义）；
- `close` 幂等；关闭后不可重新打开；
- `isOpen` 与生命周期一致：构造后 true，`close` 后 false；
- `size`/`describe` 在关闭后仍可读。

---

## 4. 生命周期

实现创建后为 open；可 `get`；`close` 后为 closed；`close` 幂等；关闭后不可重新打开。

资源型实现（文件、内存映射、网络游标）必须在 `close` 释放。调用方拥有数据集并负责关闭；`DataLoader` 只借用。

---

## 5. 构造契约

协议无构造。实现类提供构造器，并在构造完成后处于 open；构造失败由实现决定，协议不规定。

实现必须在构造时固定 `size`；若数据源在打开期间变化，应返回 `DataCorrupted` 或要求调用方重建数据集。

---

## 6. 字段表

无协议字段。实现可持有文件句柄、索引、缓存或连接，但不得通过协议暴露。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `size` | 样本总数 | 无 | `Long` | 无 |
| `get` | 读取单样本 | `Context context, Long sampleIndex` | `Result<Batch, Error>` | `InvalidArgument`/`Unavailable`/`Cancelled`/实现错误 |
| `isOpen` | 是否可读 | 无 | `Bool` | 无 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `describe` | 单行描述 | 无 | `String` | 无 |

说明：

- `get`：`context == null` → panic；`sampleIndex < 0` 或 `>= size()` → `InvalidArgument`；关闭 → `Unavailable`；取消 → `Cancelled`。
- `get` 返回的 `Batch` 是独立快照；实现不得在返回后继续修改其中的张量（`Tensor` 不可变）。
- `get` 不负责批处理；调用方传入的是样本下标，不是批次下标。
- `size` 不阻塞、不分配；可在关闭后调用。
- `close` 第一次调用释放资源；后续调用返回 `Ok(unit)`；即使之前的 `get` 失败也必须释放。
- `describe` 不输出样本内容或敏感路径；关闭后仍可读。

---

## 8. 使用的技术

- 非泛型协议；
- 随机访问索引；
- `Long` 样本总数；
- `Context` 取消；
- 幂等关闭；
- 单样本带批维约定；
- 与 DataLoader 的借用关系。

---

## 9. 需要的支撑

- 语言：protocol、class、Long、Bool、Result、Unit、void；
- 运行时：由实现决定（内存/文件/网络）；
- 接口：[`Batch`](Batch.md)、[`DataLoader`](DataLoader.md)、[`Transform`](Transform.md)、`Context`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

[`Batch`](Batch.md)、[`DataLoader`](DataLoader.md)、[`Transform`](Transform.md)、[`Tensor`](../../platform/tensor/Tensor.md)、`Context`、`Error`。

不依赖 `xdk.fs`、`xdk.net`、`xdk.io`；实现自行选择数据源。

---

## 11. 所有权与并发

实现拥有底层资源；调用方持有数据集引用并负责 `close`；`DataLoader` 只借用，不关闭。

协议不承诺线程安全；`DataLoader` 顺序调用 `get`。被多个任务直接共享时，实现必须自行同步；`close` 不得与 `get` 并发。

无 `equals`/`copy`；数据集是资源/服务，不是值对象。

---

## 12. 示例与反例

正确：内存数据集 `size() == 1000`，`get(context, 42)` 返回 `sampleCount == 1` 的张量批；文件数据集在 `close` 释放句柄；`DataLoader` 借用数据集并在 epoch 间复用。  
反例：`get` 返回 `sampleCount > 1`；把 `size` 当批次数量；关闭后继续 `get`；`get` 修改内部样本并影响下一次读取；在 `get` 中做 shuffle；全局单例数据集；`DataLoader` 关闭数据集。

---

## 13. 测试/场景义务

`size` 0/1/大值；`get` 首/中/尾/越界/负值；null context；关闭后 `get`；重复 `close`；`isOpen`；`size`/`describe` 关闭后可读；单样本 `sampleCount == 1`；取消；并发声明；资源释放；`DataLoader` 借用不关闭。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
protocol Dataset {
    Long size();
    Result<Batch, Error> get(Context context, Long sampleIndex);
    Bool isOpen();
    Result<Unit, Error> close();
    String describe();
}
```
