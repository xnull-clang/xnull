# `GpuBufferUsage`

| 项 | 值 |
| --- | --- |
| 类型 | `enum GpuBufferUsage` |
| 包 | `xdk.gpu` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

GPU 缓冲区的使用/绑定意图：只读 storage、只写 storage、读写 storage、通用 storage、uniform、indirect 参数。

只说明“这个 buffer 准备怎样被计算管线使用”，不说明：

- CPU 映射方式、缓存策略、内存类型、驻留/驱逐；
- 分配大小、对齐、显存预算；
- 纹理/图像/采样器/交换链；
- 顶点/索引用途（渲染属于 X）。

---

## 2. 设计逻辑

- 封闭枚举；应用不能扩展；只允许追加成员，不允许改义/删除。
- `Read`/`Write`/`ReadWrite` 表示 shader storage 访问模式；`Storage` 表示未限定访问的 storage；`Uniform` 表示 uniform buffer；`Indirect` 表示 indirect dispatch 参数。
- usage 在 buffer 创建时固定；不能把一个 buffer 的 usage 当作可变提示。
- 绑定兼容性由“管线槽声明的 usage”和“实际 buffer 的 usage”共同决定；规则见 §3。
- `Storage` 是通配语义，不是默认值；调用方应优先声明具体访问模式，只有在确实无法分类时才用 `Storage`。
- `Indirect` 在基线只允许创建、CPU 写入/读取；不允许绑定到 `GpuPipeline`，因为基线没有 `dispatchIndirect`。
- `Vertex`/`Index` 不是基线成员；渲染用途留到 X，未来追加，不改变现有成员含义。
- 值语义；可作 `Map`/`Set` 键。

---

## 3. 表示与不变量

| 成员 | 含义 | 可绑定的管线槽 |
| --- | --- | --- |
| `Read` | shader 只读 storage | `Read`、`Storage` |
| `Write` | shader 只写 storage | `Write`、`Storage` |
| `ReadWrite` | shader 读写 storage | `Read`、`Write`、`ReadWrite`、`Storage` |
| `Storage` | 未限定访问的 storage | `Read`、`Write`、`ReadWrite`、`Storage` |
| `Uniform` | uniform buffer | `Uniform` |
| `Indirect` | indirect dispatch 参数 | 不可绑定 |

不变量：

- 成员固定；只允许追加；值语义。
- usage 创建后固定；不能在同一 buffer 上改变。
- `Indirect` 不是普通 shader 绑定；基线管线布局不得包含 `Indirect`。
- `Uniform` 与 storage 互不兼容；不能把 uniform buffer 绑定到 storage 槽，反之亦然。
- `Storage` 是显式通配，不是“未知”或“默认”；不得用 `Storage` 掩盖本可声明的访问模式。
- 绑定兼容是单向判断：管线槽声明 usage，buffer 提供 usage；不能反过来推断。

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
| `gpuBufferUsageName` | 稳定小写名 | `GpuBufferUsage usage` | `String` | 无 | null → `"unknown"` |
| `gpuBufferUsageFromName` | 名称解析 | `String name` | `GpuBufferUsage?` | 无；未知返回 null | trim + 小写；只接受稳定名 |
| `gpuBufferUsageAllowsBinding` | 绑定兼容判断 | `GpuBufferUsage declaredUsage, GpuBufferUsage bufferUsage` | `Bool` | 无；null → false | 见兼容矩阵 |

说明：

- `gpuBufferUsageName` 返回 `"read"`、`"write"`、`"read_write"`、`"storage"`、`"uniform"`、`"indirect"` 之一；`null` 返回 `"unknown"`，用于诊断，不新增枚举成员。
- `gpuBufferUsageFromName` 只做 `trim().toLower()`；不做模糊匹配、不猜测缩写；未知名称返回 `null`。
- `gpuBufferUsageAllowsBinding` 的规则：
  - 任一参数为 null → false；
  - 管线槽 `Uniform` → 仅 buffer `Uniform`；
  - 管线槽 `Indirect` → 永远 false；
  - buffer `Uniform` 或 `Indirect` 绑定到非对应槽 → false；
  - 管线槽 `Storage` → 任意 storage buffer（`Read`/`Write`/`ReadWrite`/`Storage`）；
  - 管线槽 `Read` → `Read`/`ReadWrite`/`Storage`；
  - 管线槽 `Write` → `Write`/`ReadWrite`/`Storage`；
  - 管线槽 `ReadWrite` → `ReadWrite`/`Storage`。
- 该函数只判断兼容性，不检查设备、生命周期、大小、对齐；这些由 `GpuCommandBuffer.bindBuffer` 和原生适配器负责。

---

## 8. 使用的技术

- 简单枚举；
- 稳定名称映射；
- 兼容矩阵；
- 值语义比较。

---

## 9. 需要的支撑

- 语言：enum、String、Bool；
- 运行时：无；
- 接口：`GpuBuffer`、`GpuPipeline`、`GpuCommandBuffer`。

---

## 10. 依赖的特性/接口/类

[`GpuBuffer`](GpuBuffer.md)、[`GpuPipeline`](GpuPipeline.md)、[`GpuCommandBuffer`](GpuCommandBuffer.md)。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。

相等：按枚举值比较；可作 `Map`/`Set` 键。

---

## 12. 示例与反例

正确：

- 创建 `ReadWrite` buffer，绑定到管线声明为 `Read` 的槽（读写包含读，兼容）。
- 创建 `Write` buffer，只绑定到 `Write` 或 `Storage` 槽。
- `Uniform` buffer 只绑定 `Uniform` 槽。
- 确实无法分类的 storage buffer 才用 `Storage`，并接受它能绑定到任意 storage 槽。
- `Indirect` buffer 只用于 CPU 填充；等待 X 的 `dispatchIndirect`。

反例：

- 把 `Read` buffer 绑定到 `Write` 槽。
- 把 `Uniform` buffer 当 storage 使用，或把 storage buffer 绑定 `Uniform` 槽。
- 把 `Storage` 当默认值，所有 buffer 都用它。
- 假设枚举里有 `Vertex`/`Index`，或在基线请求渲染用途。
- 把 `Indirect` 绑定到普通管线槽。
- 创建后试图改变 buffer 的 usage。

---

## 13. 测试/场景义务

- 每个成员稳定名/解析；大小写/空白归一；未知名称返回 null。
- 兼容矩阵：6×6 全覆盖；null 参数返回 false。
- `Storage` 通配：任意 storage buffer 可绑定任意 storage 槽；`Storage` 不能绑定 `Uniform`。
- `Uniform` 精确匹配；`Indirect` 永远不可绑定。
- `Read`/`Write`/`ReadWrite` 的单向兼容：`ReadWrite` 可进 `Read`/`Write`，`Read` 不能进 `Write`。
- 与 `GpuBuffer.usage()`、`GpuPipeline.bufferLayout()`、`GpuCommandBuffer.bindBuffer` 组合。
- 追加成员不改旧值；值语义可作 `Map` 键。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
enum GpuBufferUsage {
    Read,
    Write,
    ReadWrite,
    Storage,
    Uniform,
    Indirect,
}

String gpuBufferUsageName(GpuBufferUsage usage) {
    if usage == null { return "unknown" }
    if usage == GpuBufferUsage.Read { return "read" }
    if usage == GpuBufferUsage.Write { return "write" }
    if usage == GpuBufferUsage.ReadWrite { return "read_write" }
    if usage == GpuBufferUsage.Storage { return "storage" }
    if usage == GpuBufferUsage.Uniform { return "uniform" }
    if usage == GpuBufferUsage.Indirect { return "indirect" }
    return "unknown"
}

GpuBufferUsage? gpuBufferUsageFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "read" { return GpuBufferUsage.Read }
    if normalized == "write" { return GpuBufferUsage.Write }
    if normalized == "read_write" { return GpuBufferUsage.ReadWrite }
    if normalized == "storage" { return GpuBufferUsage.Storage }
    if normalized == "uniform" { return GpuBufferUsage.Uniform }
    if normalized == "indirect" { return GpuBufferUsage.Indirect }
    return null
}

Bool gpuBufferUsageAllowsBinding(GpuBufferUsage declaredUsage,
                                GpuBufferUsage bufferUsage) {
    if declaredUsage == null || bufferUsage == null { return false }
    if declaredUsage == GpuBufferUsage.Uniform {
        return bufferUsage == GpuBufferUsage.Uniform
    }
    if declaredUsage == GpuBufferUsage.Indirect { return false }
    if bufferUsage == GpuBufferUsage.Uniform
        || bufferUsage == GpuBufferUsage.Indirect {
        return false
    }
    if declaredUsage == GpuBufferUsage.Storage { return true }
    if declaredUsage == GpuBufferUsage.Read {
        return bufferUsage == GpuBufferUsage.Read
            || bufferUsage == GpuBufferUsage.ReadWrite
            || bufferUsage == GpuBufferUsage.Storage
    }
    if declaredUsage == GpuBufferUsage.Write {
        return bufferUsage == GpuBufferUsage.Write
            || bufferUsage == GpuBufferUsage.ReadWrite
            || bufferUsage == GpuBufferUsage.Storage
    }
    return bufferUsage == GpuBufferUsage.ReadWrite
        || bufferUsage == GpuBufferUsage.Storage
}
```
