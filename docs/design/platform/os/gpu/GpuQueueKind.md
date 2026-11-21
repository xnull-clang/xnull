# `GpuQueueKind`

| 项 | 值 |
| --- | --- |
| 类型 | `enum GpuQueueKind` |
| 包 | `xdk.os.gpu` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

GPU 队列用途：图形、计算、传输。

不做：命令提交、同步/栅栏、优先级/抢占、队列数量策略、内存分配。kind 只说明创建队列时请求的用途，不承载命令语义。

---

## 2. 设计逻辑

- `Graphics` 请求图形/通用队列；`Compute` 请求计算队列；`Transfer` 请求拷贝/上传/下载队列。
- kind 是创建请求：创建成功后队列按该 kind 固定标记；不支持的 kind 必须返回 `Unsupported`，不允许静默降级。
- `GpuBackend.ComputeOnly` 不承诺 `Graphics`；请求必须返回 `Unsupported`。
- 后端对 `OpenGL`/`WebGpu` 的 compute/transfer 支持可能因版本/扩展而异；由 `createQueue` 显式失败。
- 不表达优先级、抢占、队列族索引、命令类型；这些是 X。
- 值语义；成员只允许追加。

---

## 3. 表示与不变量

| 成员 | 含义 | 备注 |
| --- | --- | --- |
| `Graphics` | 图形/通用队列 | 不用于 `ComputeOnly` 后端 |
| `Compute` | 计算队列 | 不承诺图形能力 |
| `Transfer` | 拷贝/上传/下载队列 | 不承诺图形/计算能力 |

不变量：成员固定；只允许追加；值语义；kind 创建后不可变；不支持的 kind 返回 `Unsupported`，不静默替换。

---

## 4. 生命周期

值类型；无构造器、无 close；可共享。

---

## 5. 构造契约

枚举项直接使用，无构造器。名称解析失败返回 null，不抛错。

---

## 6. 字段表

无实例字段。

---

## 7. 方法面

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `gpuQueueKindName` | 稳定小写名 | `GpuQueueKind kind` | `String` | 无 |
| `gpuQueueKindFromName` | 名称解析 | `String name` | `GpuQueueKind?` | 无；未知返回 null |

说明：

- 名称用于日志/诊断/配置；不是后端队列族名称。
- 解析只接受稳定名，不做模糊匹配；未知名称返回 null。

---

## 8. 使用的技术

- 简单枚举；
- 名称映射；
- 值语义比较。

---

## 9. 需要的支撑

- 语言：enum、String；
- 运行时：无；
- 接口：`GpuQueue`、`GpuDevice`、`GpuBackend`。

---

## 10. 依赖的特性/接口/类

`GpuQueue`、`GpuDevice`、`GpuBackend`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。
相等：按枚举值比较；可作 `Map`/`Set` 键。

---

## 12. 示例与反例

正确：无头计算创建 `GpuQueueKind.Compute`；拷贝创建 `GpuQueueKind.Transfer`；`ComputeOnly` 后端不请求 `Graphics`。  
反例：把 `Graphics` 请求静默降级为 `Compute`；用 kind 推断优先级；假设所有后端支持所有 kind；把 kind 名称当后端队列族索引。

---

## 13. 测试/场景义务

每个成员名称/解析；大小写/空白归一；未知名称返回 null；`ComputeOnly` + `Graphics` 返回 `Unsupported`；
`OpenGL`/`WebGpu` 的 compute/transfer 能力差异；同 kind 多次创建由实现决定；与 `GpuQueue`/`GpuDevice` 组合。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
enum GpuQueueKind {
    Graphics,
    Compute,
    Transfer,
}

String gpuQueueKindName(GpuQueueKind kind) {
    if kind == GpuQueueKind.Graphics { return "graphics" }
    if kind == GpuQueueKind.Compute { return "compute" }
    return "transfer"
}

GpuQueueKind? gpuQueueKindFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "graphics" { return GpuQueueKind.Graphics }
    if normalized == "compute" { return GpuQueueKind.Compute }
    if normalized == "transfer" { return GpuQueueKind.Transfer }
    return null
}
```
