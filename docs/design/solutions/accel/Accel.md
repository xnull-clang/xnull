# `Accel`

| 项 | 值 |
| --- | --- |
| 类型 | `class Accel`（静态入口） |
| 包 | `xdk.accel` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Error`、`GpuAdapter`、`GpuBackend`、`Accelerator`、`AcceleratorOptions`、`AcceleratorDevice`、`AcceleratorKind`、`AcceleratorBackend`、`AcceleratorVendor`、`AcceleratorCapability` |

---

## 1. 定位

`xdk.accel` 的静态入口：显式打开加速器设备、构造宿主 CPU 描述符、把 `xdk.os.gpu` 的适配器桥接为加速器描述符。

只做：

- `open(context, accelerator, options)`：能力门控 + 选项校验 + 原生打开；
- `cpu()`：显式宿主 CPU 描述符（不发现、不自动回退）；
- `fromGpuAdapter(adapter, backend)`：只读 GPU 适配器元数据 → 通用描述符；不打开、不共享句柄。

不做：

- 设备枚举/发现/热插拔；
- 全局注册表/缓存/单例设备；
- 自动选择后端/厂商/设备；
- 自动回退到 CPU 或其它设备；
- 打开多个设备/跨设备协同；
- 调度/负载均衡/模型运行时；
- 暴露原生句柄/驱动 SDK。

---

## 2. 设计逻辑

- 无实例状态；所有方法静态；不提供构造器；不可实例化。
- `open` 是唯一打开路径；`Accelerator` 不提供 `open`，避免绕过选项校验与能力门控。
- `open` 要求描述符至少声明 `Compute` 或 `Memory`；两者都没有（例如只有 `Graphics`）返回 `Unsupported`。`Graphics` 在本包永远不是可执行能力。
- `open` 先调用 `acceleratorOptionsCheckOpen(options)`；不适用字段 → `InvalidArgument`；后端不支持 profiling/validation/memory limit → `Unsupported`。
- 打开成功后返回新的 [`AcceleratorDevice`](AcceleratorDevice.md)；每次调用独立，调用方分别关闭；不缓存、不复用。
- `cpu()` 返回合成描述符（ID `"cpu"`、名称 `"host-cpu"`、`Cpu` kind/backend、`Memory`/`Compute` 能力、未知容量/单元数）；打开仍可能返回 `Unsupported`，取决于运行时的 CPU 后端是否存在；它不是自动回退。
- `fromGpuAdapter` 只读取 `GpuAdapter` 的 ID/型号/厂商/驱动版本/显存；不读取原生句柄、不打开设备、不共享 `GpuDevice`。调用方必须显式传入 `AcceleratorBackend`；不从 `GpuBackend` 自动映射，避免把 D3D12/OpenGL/WebGPU 错误映射为计算后端。
- `fromGpuAdapter` 生成的描述符：kind 固定 `Gpu`；backend = 调用方传入；capabilities = `Memory` + `Compute`，并在适配器后端不是 `ComputeOnly` 时附加 `Graphics`（仅描述，不提供渲染入口）；`computeUnitCount = 0`（未知）；`memoryBytes` 取适配器容量提示。
- `cpu()`/`fromGpuAdapter()` 不触发原生调用；只有 `open` 触发。
- 无全局状态；静态方法不持有设备；线程安全取决于底层打开实现，调用方仍应串行化同一后端的打开。
- 不提供 `adapters`/`enumerate`/`discover`；枚举由平台集成层或 `OsHost.gpuAdapters` 显式完成。

---

## 3. 表示与不变量

无实例字段。`Accel` 是静态入口，不持有设备、描述符、缓存或全局注册表。

不变量：

- 所有方法静态；不可实例化；无 close。
- `open` 不修改传入的 `Accelerator`/`AcceleratorOptions`；成功返回独立设备。
- `open` 不缓存设备；重复调用返回多个独立设备。
- `cpu()`/`fromGpuAdapter()` 只构造值对象；不打开设备、不访问原生句柄。
- 静态入口不跨调用保留状态；无单例设备、无全局队列。
- 失败不产生半打开设备；原生打开失败直接返回 `Result` 错误。

---

## 4. 生命周期

静态入口；无实例生命周期、无 close。`open` 返回的设备由调用方持有并关闭；`cpu()`/`fromGpuAdapter()` 返回的描述符是值对象，无生命周期。

---

## 5. 构造契约

无可用的公开构造器；`Accel` 不可实例化。只使用静态方法。

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `open`（静态） | 打开加速器设备 | `Context context, Accelerator accelerator, AcceleratorOptions options` | `Result<AcceleratorDevice, Error>` | `Unsupported`/`PermissionDenied`/`Cancelled`/`InvalidArgument`/`Io`/`OutOfMemory` |
| `cpu`（静态） | 宿主 CPU 描述符 | 无 | `Accelerator` | 无 |
| `fromGpuAdapter`（静态） | GPU 适配器桥接 | `GpuAdapter adapter, AcceleratorBackend backend` | `Accelerator` | null → panic |

说明：

- `open`：
  - `context == null`、`accelerator == null` 或 `options == null` → panic。
  - 描述符既无 `Compute` 也无 `Memory` → `Unsupported`。
  - `memoryLimitBytes > 0` 但描述符无 `Memory` → `Unsupported`。
  - 选项不适用于打开 → `InvalidArgument`；profiling/validation/memory limit 不被后端支持 → `Unsupported`。
  - 后端/平台/权限不允许 → `Unsupported`/`PermissionDenied`；`Context` 取消 → `Cancelled`。
  - 原生打开失败 → `Io`/`OutOfMemory`；不重试、不提权、不换设备。
  - 成功返回独立 `AcceleratorDevice`；调用方关闭；设备不缓存。
- `cpu`：
  - 返回新描述符；ID 固定 `"cpu"`，名称 `"host-cpu"`，vendor `Unknown`，backend/kind `Cpu`，capabilities `Memory`/`Compute`，memoryBytes 0，computeUnitCount 0，runtimeVersion 空串。
  - 不探测 CPU、不读取拓扑、不创建线程池；打开由 CPU 后端决定。
  - 不是自动回退目标；调用方必须显式传给 `open`。
- `fromGpuAdapter`：
  - `adapter == null` 或 `backend == null` → panic。
  - 只读取元数据；不访问原生设备；不打开；不共享 `GpuDevice`。
  - `backend` 是调用方选择；不自动映射；错误选择由 `open` 返回 `Unsupported`。
  - `capabilities` 为 `Memory`/`Compute`，`GpuBackend.ComputeOnly` 时不附加 `Graphics`；`Graphics` 仅描述，不提供渲染。
  - `vendor` 通过 `acceleratorVendorFromText(adapter.vendor())` 归类；`vendorName` 保留原文；空厂商 → `Unknown`；未识别 → `Other`。
  - `memoryBytes` 取 `adapter.memoryBytes()`；0 表示未知；`computeUnitCount` 为 0。
- 不提供 `open` 重载/默认 options；调用方显式传 `AcceleratorOptions.defaults()`。
- 不提供 `close`；设备由调用方关闭。

---

## 8. 使用的技术

- 静态工厂；
- 能力门控；
- 选项适用性校验；
- 描述符桥接；
- 无全局状态；
- `Context`/`Result`。

---

## 9. 需要的支撑

- 语言：class（静态入口）、String、Long、Int、Bool、List、Result；
- 运行时/适配器：
  - `acceleratorOpenRaw(Context context, String acceleratorId, AcceleratorKind kind, AcceleratorBackend backend, AcceleratorOptions options) -> Result<Long, Error>`；
  - 原生打开返回的句柄必须 >0；否则 `Internal`；
- 辅助：`acceleratorVendorFromText`、`GpuAdapter.id`/`model`/`vendor`/`backend`/`memoryBytes`/`driverVersion`；
- 接口：`Context`、`Error`、`BasicError`、`ErrorKind`、`GpuAdapter`、`GpuBackend`、`Accelerator`、`AcceleratorOptions`、`AcceleratorDevice`、`AcceleratorKind`、`AcceleratorBackend`、`AcceleratorVendor`、`AcceleratorCapability`。

---

## 10. 依赖的特性/接口/类

[`Accelerator`](Accelerator.md)、[`AcceleratorDevice`](AcceleratorDevice.md)、[`AcceleratorOptions`](AcceleratorOptions.md)、[`AcceleratorKind`](AcceleratorKind.md)、[`AcceleratorBackend`](AcceleratorBackend.md)、[`AcceleratorVendor`](AcceleratorVendor.md)、[`AcceleratorCapability`](AcceleratorCapability.md)、[`GpuAdapter`](../../platform/os/gpu/GpuAdapter.md)、[`GpuBackend`](../../platform/os/gpu/GpuBackend.md)、`Context`、`Error`。

---

## 11. 所有权与并发

静态入口无状态；可并发调用。`open` 原生实现可能串行化同一后端；调用方应避免对同一设备/后端并发打开造成资源竞争。

`open` 返回独立设备；`cpu()`/`fromGpuAdapter()` 返回独立值对象。无全局缓存/注册表；无循环引用。

不提供 `equals`/`copy`；`Accel` 不是值对象。

---

## 12. 示例与反例

正确：

- NPU 集成层构造 `Accelerator`（kind `Npu`、backend `Custom`、capabilities `Memory`/`Compute`/`Quantized`）→ `Accel.open(context, accelerator, AcceleratorOptions.defaults())`。
- GPU：`OsHost.gpuAdapters(context)` 得到 `GpuAdapter` → `Accel.fromGpuAdapter(adapter, AcceleratorBackend.Vulkan)` → `Accel.open(...)`；与 `xdk.gpu` 的设备是两条独立路径，不共享句柄。
- 显式 CPU：`Accel.open(context, Accel.cpu(), options)`；若 CPU 后端未构建，返回 `Unsupported`，不自动换 GPU。
- 打开带 memory limit/profiling 的选项；不支持时显式失败并调整策略。

反例：

- 期望 `Accel` 枚举所有 GPU/NPU/DSP。
- 把 `GpuBackend.Direct3D12` 自动当 `DirectMl`；或用 `fromGpuAdapter` 不传 backend。
- 把 `Accel.cpu()` 当自动回退；打开失败就静默改用 CPU。
- 把 `GpuAdapter`/`GpuDevice` 与 `Accelerator`/`AcceleratorDevice` 当同一句柄。
- 打开设备后不关闭；重复打开并假设单例。
- 用 `Graphics` 能力在本包做渲染。
- 把 `open` 当设备发现/探测。

---

## 13. 测试/场景义务

`open` 成功/`Unsupported`/`PermissionDenied`/`Cancelled`/`InvalidArgument`/`Io`/`OutOfMemory`；
无 `Compute`/`Memory` 的描述符 → `Unsupported`；仅 `Graphics` → `Unsupported`；
选项适用性/不支持选项；多次 `open` 独立；不缓存；
`cpu()` 字段/能力/打开结果；显式选择、非回退；
`fromGpuAdapter` 字段映射/厂商文本/`ComputeOnly` 无 `Graphics`/显式 backend/不访问原生；
null 参数 panic；静态并发；无设备发现/全局状态；
GPU/NPU/DSP/FPGA/MCU 描述符打开；与 `xdk.os.gpu`/`xdk.gpu` 路径隔离。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class Accel {
    static Result<AcceleratorDevice, Error> open(Context context,
                                                 Accelerator accelerator,
                                                 AcceleratorOptions options) {
        if context == null || accelerator == null || options == null {
            throw "Accel.open: null argument"
        }
        if !accelerator.supports(AcceleratorCapability.Compute)
            && !accelerator.supports(AcceleratorCapability.Memory) {
            return Err(new BasicError(ErrorKind.Unsupported,
                "accelerator has no usable capability"))
        }
        if options.memoryLimitBytes() > 0
            && !accelerator.supports(AcceleratorCapability.Memory) {
            return Err(new BasicError(ErrorKind.Unsupported,
                "memory limit without memory capability"))
        }
        Result<Unit, Error> checked = acceleratorOptionsCheckOpen(options)
        if checked.isErr() { return Err(checked.error()) }
        Result<Long, Error> opened = acceleratorOpenRaw(
            context, accelerator.acceleratorId(), accelerator.kind(),
            accelerator.backend(), options)
        if opened.isErr() { return Err(opened.error()) }
        if opened.value() <= 0 {
            return Err(new BasicError(ErrorKind.Internal, "invalid device handle"))
        }
        AcceleratorDevice device = new AcceleratorDevice(
            opened.value(), accelerator, options)
        return Ok(device)
    }

    static Accelerator cpu() {
        List<AcceleratorCapability> capabilities = [
            AcceleratorCapability.Memory,
            AcceleratorCapability.Compute,
        ]
        return new Accelerator("cpu", "host-cpu", AcceleratorVendor.Unknown,
            "", AcceleratorKind.Cpu, AcceleratorBackend.Cpu, "", 0, 0,
            capabilities)
    }

    static Accelerator fromGpuAdapter(GpuAdapter adapter,
                                      AcceleratorBackend backend) {
        if adapter == null || backend == null {
            throw "Accel.fromGpuAdapter: null argument"
        }
        List<AcceleratorCapability> capabilities = [
            AcceleratorCapability.Memory,
            AcceleratorCapability.Compute,
        ]
        if adapter.backend() != GpuBackend.ComputeOnly {
            capabilities.push(AcceleratorCapability.Graphics)
        }
        AcceleratorVendor vendor = acceleratorVendorFromText(adapter.vendor())
        return new Accelerator(adapter.id(), adapter.model(), vendor,
            adapter.vendor(), AcceleratorKind.Gpu, backend,
            adapter.driverVersion(), adapter.memoryBytes(), 0, capabilities)
    }
}
```
