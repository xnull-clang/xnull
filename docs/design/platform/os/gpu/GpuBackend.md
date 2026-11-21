# `GpuBackend`

| 项 | 值 |
| --- | --- |
| 类型 | `enum GpuBackend` |
| 包 | `xdk.os.gpu` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

GPU 后端家族：Vulkan、Metal、Direct3D 12、OpenGL、WebGPU、仅计算、未知。

不做：驱动/厂商识别、版本/特性级别、设备选择、命令编码、着色器/管线。后端只说明适配器/设备走哪类 API 家族，不承诺具体能力。

---

## 2. 设计逻辑

- 封闭枚举：只列 XDK 基线能命名的后端家族；应用不能扩展。
- `Unknown` 是合法值：平台未识别/枚举失败时返回，不 panic、不猜测。
- `ComputeOnly` 表示“仅计算、没有公开图形队列”的实现；不是某个具体 API。
- 命名稳定：`Direct3D12`/`WebGpu` 是公开拼写；显示名可另做映射。
- 后端不等于驱动、厂商、型号或特性级别；这些由 `GpuAdapter` 字段承载。
- 后端与 `GpuQueueKind` 正交：后端说明 API 家族，队列 kind 说明请求用途。
- 值语义；成员只允许追加，不允许改义/删除。

---

## 3. 表示与不变量

| 成员 | 含义 | 图形队列意图 |
| --- | --- | --- |
| `Vulkan` | Vulkan | 可请求 |
| `Metal` | Metal | 可请求 |
| `Direct3D12` | Direct3D 12 | 可请求 |
| `OpenGL` | OpenGL/OpenGL ES | 可请求 |
| `WebGpu` | WebGPU | 可请求 |
| `ComputeOnly` | 仅计算后端 | 不承诺；请求返回 `Unsupported` |
| `Unknown` | 未识别 | 不承诺；由实现决定 |

不变量：成员固定；只允许追加；值语义；`Unknown` 合法；任何成员都不表示具体厂商/驱动/版本。“可请求”不等于一定创建成功，`GpuDevice.createQueue` 仍可能返回 `Unsupported`。

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
| `gpuBackendName` | 稳定小写名 | `GpuBackend backend` | `String` | 无 |
| `gpuBackendFromName` | 名称解析 | `String name` | `GpuBackend?` | 无；未知返回 null |

说明：

- 名称用于日志/诊断/配置；不是驱动 API 名称。
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
- 接口：`GpuAdapter`、`GpuDevice`、`GpuQueueKind`。

---

## 10. 依赖的特性/接口/类

`GpuAdapter`、`GpuDevice`、`GpuQueueKind`、`GpuQueue`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。
相等：按枚举值比较；可作 `Map`/`Set` 键。

---

## 12. 示例与反例

正确：`adapter.backend() == GpuBackend.Vulkan`；`ComputeOnly` 只请求 `GpuQueueKind.Compute`/`Transfer`；`Unknown` 走保守路径并允许 `Unsupported`。  
反例：把 `Unknown` 当 Vulkan；用后端推断厂商/驱动版本；在 `ComputeOnly` 上请求 `Graphics`；应用扩展枚举。

---

## 13. 测试/场景义务

每个成员名称/解析；大小写/空白归一；未知名称返回 null；`Unknown` 不 panic；
`ComputeOnly` 与 `Graphics` 组合；与 `GpuAdapter`/`GpuDevice` 组合；跨平台后端枚举。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
enum GpuBackend {
    Vulkan,
    Metal,
    Direct3D12,
    OpenGL,
    WebGpu,
    ComputeOnly,
    Unknown,
}

String gpuBackendName(GpuBackend backend) {
    if backend == GpuBackend.Vulkan { return "vulkan" }
    if backend == GpuBackend.Metal { return "metal" }
    if backend == GpuBackend.Direct3D12 { return "direct3d12" }
    if backend == GpuBackend.OpenGL { return "opengl" }
    if backend == GpuBackend.WebGpu { return "webgpu" }
    if backend == GpuBackend.ComputeOnly { return "compute_only" }
    return "unknown"
}

GpuBackend? gpuBackendFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "vulkan" { return GpuBackend.Vulkan }
    if normalized == "metal" { return GpuBackend.Metal }
    if normalized == "direct3d12" { return GpuBackend.Direct3D12 }
    if normalized == "opengl" { return GpuBackend.OpenGL }
    if normalized == "webgpu" { return GpuBackend.WebGpu }
    if normalized == "compute_only" { return GpuBackend.ComputeOnly }
    if normalized == "unknown" { return GpuBackend.Unknown }
    return null
}
```
