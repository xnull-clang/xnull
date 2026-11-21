# `AcceleratorBackend`

| 项 | 值 |
| --- | --- |
| 类型 | `enum AcceleratorBackend` |
| 包 | `xdk.accel` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

加速器后端家族：CUDA、ROCm、SYCL、OpenCL、Vulkan、Metal、DirectML、oneAPI、厂商自定义运行时、CPU。

只说明加速器通过哪类编程/运行时 API 家族访问；不承诺版本、扩展、能力、厂商、性能或可用性。后端不等于驱动、设备型号、指令集或操作系统。

不做：

- 驱动安装/更新；
- 后端原生句柄、扩展字符串、编译器选项的类型化暴露；
- 从后端推断厂商或能力；
- 自动选择后端或静默回退；
- 图形/显示/模型运行时语义。

---

## 2. 设计逻辑

- 封闭枚举：只列 XDK 基线能命名的后端家族；应用不能扩展。
- 没有 `Unknown`：无法归类的后端使用 `Custom`；`Custom` 不携带任何能力或可打开性承诺。
- `Cuda` 面向 NVIDIA CUDA 运行时/驱动 API；`Rocm` 面向 AMD ROCm/HIP 生态；`OpenCl` 面向 Khronos OpenCL；`Vulkan` 面向 Vulkan compute；`Metal` 面向 Apple Metal；`DirectMl` 面向 Windows DirectML；`Cpu` 面向宿主 CPU 执行。
- `Sycl` 表示 Khronos SYCL 编程模型实现；`OneApi` 表示 Intel oneAPI 原生运行时/Level Zero 路径。二者可能指向同一设备，但不是同义词；不得自动互相替换或回退。
- `DirectMl` 不是 Direct3D 12；`Vulkan` 不是 OpenGL；`Cpu` 不是“默认回退”的同义词，必须显式选择。
- 后端与 `AcceleratorKind` 正交：例如 NPU 可能通过 `Custom`、`OneApi` 或 `Sycl` 暴露；GPU 可能通过 `Cuda`、`Rocm`、`Vulkan`、`Metal`、`DirectMl`、`Sycl` 或 `OpenCl` 暴露。
- 后端与 `AcceleratorVendor` 正交；`Vulkan`/`OpenCl` 可跨厂商，`Cuda`/`Rocm`/`Metal`/`DirectMl` 有现实平台约束。
- 值语义；成员只允许追加，不允许改义或删除。

---

## 3. 表示与不变量

| 成员 | 含义 | 现实约束/备注 |
| --- | --- | --- |
| `Cuda` | NVIDIA CUDA 运行时/驱动 API 家族 | 通常仅 NVIDIA；版本/能力由设备决定 |
| `Rocm` | AMD ROCm/HIP 运行时家族 | 通常仅 AMD；不承诺所有 AMD 设备 |
| `Sycl` | Khronos SYCL 实现 | 可由多个厂商实现；扩展/能力差异大 |
| `OpenCl` | Khronos OpenCL | 跨厂商；3.0 可选特性差异大 |
| `Vulkan` | Vulkan compute | 跨厂商；需显式计算队列/能力 |
| `Metal` | Apple Metal | 通常仅 Apple 平台 |
| `DirectMl` | Windows DirectML | 通常仅 Windows；不是 D3D12 本身 |
| `OneApi` | Intel oneAPI 原生运行时/Level Zero 路径 | 与 `Sycl` 不同层；不自动替换 |
| `Custom` | 厂商自定义/未归类运行时 | 无保证；可能只能在特定设备打开 |
| `Cpu` | 宿主 CPU 执行 | 显式计算目标；不是自动回退 |

不变量：成员固定；只允许追加；值语义；`Custom` 合法；任何成员都不表示具体厂商、驱动、版本、扩展或能力；后端不保证打开成功。

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
| `acceleratorBackendName` | 稳定小写名 | `AcceleratorBackend backend` | `String` | 无 |
| `acceleratorBackendFromName` | 名称解析 | `String name` | `AcceleratorBackend?` | 无；未知返回 null |

说明：

- 名称用于日志/配置/诊断；不是驱动 API 名称，也不是厂商产品名。
- 解析只接受稳定名，去除首尾空白并转小写；未知名称返回 null。
- `rocm` 是稳定名；显示层可写 ROCm。`directml`、`oneapi` 同理。
- 不从 `xdk.os.gpu` 的 `GpuBackend` 自动映射：`Accel.fromGpuAdapter` 要求调用方显式传入 `AcceleratorBackend`，避免把 D3D12、OpenGL、WebGPU 等错误映射成计算后端。

---

## 8. 使用的技术

- 简单枚举；
- 名称映射；
- 值语义比较；
- 后端/厂商/能力正交建模。

---

## 9. 需要的支撑

- 语言：enum、String；
- 运行时：无；
- 接口：`Accelerator`、`AcceleratorDevice`、`AcceleratorProgram`。

---

## 10. 依赖的特性/接口/类

[`Accelerator`](Accelerator.md)、[`AcceleratorDevice`](AcceleratorDevice.md)、[`AcceleratorProgram`](AcceleratorProgram.md)、[`AcceleratorKind`](AcceleratorKind.md)、[`AcceleratorVendor`](AcceleratorVendor.md)。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。

相等：按枚举值比较；可作 `Map`/`Set` 键。

---

## 12. 示例与反例

正确：桌面 NVIDIA GPU 用 `Cuda` 或 `Vulkan`，由调用方显式选择；Apple 设备用 `Metal`；Windows 通用 GPU 可用 `DirectMl`；Intel NPU 可能通过 `OneApi` 或 `Custom` 暴露；未知厂商运行时用 `Custom` 并保留 `vendorName()`。

反例：把 `GpuBackend.Direct3D12` 自动当 `DirectMl`；把 `Sycl` 与 `OneApi` 当同义词；`Cuda` 打不开就静默改用 `Cpu`；用后端推断量化能力；在非 Windows 上假设 `DirectMl` 可用；把 `Custom` 当“一定可用”。

---

## 13. 测试/场景义务

每个成员名称/解析；大小写/空白归一；未知名称返回 null；`Custom` 不 panic；
`Sycl` 与 `OneApi` 区分；`Cuda`/`Rocm`/`Metal`/`DirectMl` 平台约束；
`Vulkan`/`OpenCl` 跨厂商组合；`Cpu` 显式选择；`Accel.fromGpuAdapter` 显式后端；
后端与 kind/vendor/capability 的组合；无自动回退。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
enum AcceleratorBackend {
    Cuda,
    Rocm,
    Sycl,
    OpenCl,
    Vulkan,
    Metal,
    DirectMl,
    OneApi,
    Custom,
    Cpu,
}

String acceleratorBackendName(AcceleratorBackend backend) {
    if backend == AcceleratorBackend.Cuda { return "cuda" }
    if backend == AcceleratorBackend.Rocm { return "rocm" }
    if backend == AcceleratorBackend.Sycl { return "sycl" }
    if backend == AcceleratorBackend.OpenCl { return "opencl" }
    if backend == AcceleratorBackend.Vulkan { return "vulkan" }
    if backend == AcceleratorBackend.Metal { return "metal" }
    if backend == AcceleratorBackend.DirectMl { return "directml" }
    if backend == AcceleratorBackend.OneApi { return "oneapi" }
    if backend == AcceleratorBackend.Custom { return "custom" }
    return "cpu"
}

AcceleratorBackend? acceleratorBackendFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "cuda" { return AcceleratorBackend.Cuda }
    if normalized == "rocm" { return AcceleratorBackend.Rocm }
    if normalized == "sycl" { return AcceleratorBackend.Sycl }
    if normalized == "opencl" { return AcceleratorBackend.OpenCl }
    if normalized == "vulkan" { return AcceleratorBackend.Vulkan }
    if normalized == "metal" { return AcceleratorBackend.Metal }
    if normalized == "directml" { return AcceleratorBackend.DirectMl }
    if normalized == "oneapi" { return AcceleratorBackend.OneApi }
    if normalized == "custom" { return AcceleratorBackend.Custom }
    if normalized == "cpu" { return AcceleratorBackend.Cpu }
    return null
}
```
