# `GpuProgramKind`

| 项 | 值 |
| --- | --- |
| 类型 | `enum GpuProgramKind` |
| 包 | `xdk.gpu` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

GPU 程序阶段：计算、顶点、片段。

基线只支持 `Compute`；`Vertex`/`Fragment` 是 X 渲染阶段，`GpuCompute.createProgram` 对它们返回 `Unsupported`。本枚举只说明程序属于哪个阶段，不说明：

- 着色器语言、源码/字节码格式、编译器版本；
- 入口点、工作组大小、特化常量、反射信息；
- 后端能力或驱动特性；
- 管线状态、渲染目标、纹理/采样器。

---

## 2. 设计逻辑

- 封闭枚举；应用不能扩展；只允许追加成员。
- `Compute` 是基线唯一受支持的阶段；用于计算管线与 dispatch。
- `Vertex`/`Fragment` 保留成员以便未来渲染扩展与诊断，但基线工厂拒绝创建；它们不代表“部分支持”。
- kind 在 program 创建时固定；不能把同一个 program 当不同阶段使用。
- kind 与后端 `GpuBackend` 正交：后端说明 API 家族，kind 说明程序阶段；二者都不承诺具体能力。
- `gpuProgramKindIsSupported` 只表达基线支持，不探测运行时后端；后端仍可通过 `Unsupported` 拒绝。
- 值语义；可作 `Map`/`Set` 键。

---

## 3. 表示与不变量

| 成员 | 含义 | 基线支持 | 备注 |
| --- | --- | --- | --- |
| `Compute` | 计算内核 | 是 | 计算管线与 dispatch 的唯一阶段 |
| `Vertex` | 顶点阶段 | 否 | X 渲染；`createProgram` 返回 `Unsupported` |
| `Fragment` | 片段阶段 | 否 | X 渲染；`createProgram` 返回 `Unsupported` |

不变量：

- 成员固定；只允许追加；值语义。
- 基线只有 `Compute` 可被 `GpuCompute.createProgram` 成功创建。
- `Vertex`/`Fragment` 不是“待实现的部分成功”；任何公开创建路径都必须显式返回 `Unsupported`。
- kind 创建后固定；不存在切换阶段的 API。
- `GpuProgram` 可以保存非 Compute kind 仅用于宿主/测试/未来兼容；这不构成基线支持。

---

## 4. 生命周期

值类型；无构造器、无 close；可共享；不持有资源。

---

## 5. 构造契约

枚举项直接使用，无构造器。名称解析失败返回 `null`，不抛错。

---

## 6. 字段表

无实例字段；成员见 §3。

---

## 7. 方法总表 / 详表

| 函数 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `gpuProgramKindName` | 稳定小写名 | `GpuProgramKind programKind` | `String` | 无 | null → `"unknown"` |
| `gpuProgramKindFromName` | 名称解析 | `String name` | `GpuProgramKind?` | 无；未知返回 null | trim + 小写 |
| `gpuProgramKindIsSupported` | 基线支持判断 | `GpuProgramKind programKind` | `Bool` | 无；null → false | 仅 `Compute` 为 true |

说明：

- `gpuProgramKindName` 返回 `"compute"`、`"vertex"`、`"fragment"` 之一；null 返回 `"unknown"`，用于诊断。
- `gpuProgramKindFromName` 只接受稳定名，不做模糊匹配；未知名称返回 `null`。
- `gpuProgramKindIsSupported` 是基线策略，不是后端探测；返回 true 后仍可能因后端/代码格式返回 `Unsupported`。

---

## 8. 使用的技术

- 简单枚举；
- 稳定名称映射；
- 基线支持谓词；
- 值语义比较。

---

## 9. 需要的支撑

- 语言：enum、String、Bool；
- 运行时：无；
- 接口：`GpuProgram`、`GpuCompute`、`GpuPipeline`。

---

## 10. 依赖的特性/接口/类

[`GpuProgram`](GpuProgram.md)、[`GpuCompute`](GpuCompute.md)、[`GpuPipeline`](GpuPipeline.md)。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。

相等：按枚举值比较；可作 `Map`/`Set` 键。

---

## 12. 示例与反例

正确：

- 计算程序使用 `GpuProgramKind.Compute`。
- 调用 `gpuProgramKindIsSupported` 做早期分支；false 时不调用 `createProgram`，直接按 X 处理。
- 诊断日志记录稳定名 `compute`/`vertex`/`fragment`。
- 未来渲染扩展追加新成员时，不改现有成员含义。

反例：

- 用 `Vertex`/`Fragment` 创建计算管线，或期望 `createProgram` 成功。
- 把 `gpuProgramKindIsSupported` 当后端能力探测；它只表达基线策略。
- 把 kind 与 `GpuQueueKind` 混为一谈；队列用途与程序阶段正交。
- 认为 `GpuProgram` 保存了源码/入口点/工作组大小。
- 试图在创建后改变 program 的阶段。

---

## 13. 测试/场景义务

- 每个成员稳定名/解析；大小写/空白归一；未知名称返回 null。
- `gpuProgramKindIsSupported`：`Compute` true；`Vertex`/`Fragment` false；null false。
- `GpuCompute.createProgram`：`Compute` 成功路径；`Vertex`/`Fragment` 返回 `Unsupported`；不产生半初始化 program。
- 与 `GpuProgram.programKind()`、`GpuPipeline` 创建、`GpuCommandBuffer.dispatch` 组合。
- 未来追加成员不改旧值；值语义可作 `Map` 键。
- 后端 `Unsupported` 与基线 `Unsupported` 不混淆：kind 支持不代表特定后端/代码格式支持。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
enum GpuProgramKind {
    Compute,
    Vertex,
    Fragment,
}

String gpuProgramKindName(GpuProgramKind programKind) {
    if programKind == null { return "unknown" }
    if programKind == GpuProgramKind.Compute { return "compute" }
    if programKind == GpuProgramKind.Vertex { return "vertex" }
    if programKind == GpuProgramKind.Fragment { return "fragment" }
    return "unknown"
}

GpuProgramKind? gpuProgramKindFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "compute" { return GpuProgramKind.Compute }
    if normalized == "vertex" { return GpuProgramKind.Vertex }
    if normalized == "fragment" { return GpuProgramKind.Fragment }
    return null
}

Bool gpuProgramKindIsSupported(GpuProgramKind programKind) {
    if programKind == null { return false }
    return programKind == GpuProgramKind.Compute
}
```
