# `ExecutionProvider`

| 项 | 值 |
| --- | --- |
| 类型 | `enum ExecutionProvider` |
| 包 | `xdk.ml` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

推理执行提供者家族：CPU、CUDA、ROCm、DirectML、OpenVINO、NPU、DSP、FPGA、适配器自定义。

只说明“希望由哪类硬件/运行时后端执行”，不承诺本机可用、算子覆盖、版本兼容或性能。可用性由运行时适配器在 `Ml.openSession` 时显式返回 `Unsupported`/`Unavailable`。

不做：设备枚举、驱动安装、算子分区、显存分配、内核编译、性能调优、自动选择最优设备。

---

## 2. 设计逻辑

- 提供者必须显式：`SessionOptions.providers()` 是有序优先级列表；不读取全局环境变量或隐式默认设备。
- 提供者与 `ModelFormat` 正交：格式说明容器，提供者说明执行后端。
- CPU 是基线提供者；没有可用加速器时是否回退由 `SessionOptions.enableCpuFallback()` 明确控制。
- `Other` 允许厂商私有后端；语义由适配器与调用方约定。
- 提供者顺序是会话级合同：靠前的提供者优先；运行时适配器决定节点级回退。
- 枚举不携带设备索引/厂商/版本；这些通过 `SessionOptions.providerOptions()` 的键值传递。
- 成员只允许追加，不允许改义/删除；名称是日志/配置合同。

---

## 3. 表示与不变量

| 成员 | 序号 | 稳定名 | 家族 | 边界 |
| --- | ---: | --- | --- | --- |
| `Cpu` | 0 | `"cpu"` | CPU | 总是可声明；适配器可拒绝不支持的算子 |
| `Cuda` | 1 | `"cuda"` | NVIDIA GPU | 不保证 CUDA 驱动/版本存在 |
| `Rocm` | 2 | `"rocm"` | AMD GPU | 不保证 ROCm 驱动/版本存在 |
| `DirectMl` | 3 | `"directml"` | Windows DirectML | 不保证 DirectML 设备存在 |
| `OpenVino` | 4 | `"openvino"` | Intel CPU/GPU/NPU | 具体设备由适配器选项决定 |
| `Npu` | 5 | `"npu"` | 神经加速器 | 厂商私有语义由适配器解释 |
| `Dsp` | 6 | `"dsp"` | 数字信号处理器 | 厂商私有语义由适配器解释 |
| `Fpga` | 7 | `"fpga"` | 现场可编程门阵列 | 比特流/编程模型不属于本包 |
| `Other` | 8 | `"other"` | 适配器定义 | 必须由调用方保证适配器理解 |

不变量：成员固定；序号 0..8 固定；稳定名唯一；`Cpu` 与 `Other` 合法；提供者不隐含格式、任务、设备索引或厂商版本。

---

## 4. 生命周期

值类型；无构造器、无 close；可自由复制、共享、作为 `Map`/`Set` 键。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| 枚举成员 | 无 | 九个成员之一 | 不存在非法成员 |
| `executionProviderFromName` | `String name` | 任意文本 | null/未知/空白 → `null` |

枚举成员直接使用；不允许 `new ExecutionProvider()`，不允许应用扩展成员。

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

`ExecutionProvider` 没有实例方法。相关顶层函数：

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `executionProviderName` | 稳定小写名 | `ExecutionProvider executionProvider` | `String` | null → panic | 用于日志/配置 |
| `executionProviderFromName` | 名称解析 | `String name` | `ExecutionProvider?` | 无 | 去空白、忽略大小写；未知 → `null` |

说明：

- 提供者名称不包含设备序号；设备通过 `providerOptions` 选择，例如 `"cuda.device_id"`。
- `executionProviderFromName("gpu")` 返回 `null`；不把泛称猜成 CUDA。
- 顺序由 `SessionOptions.providers()` 的列表顺序表达，不由枚举序号表达。

---

## 8. 使用的技术

- 简单枚举 + 固定序号；
- 名称双向映射；
- 提供者与格式/设备选项解耦；
- 有序优先级列表。

---

## 9. 需要的支撑

- 语言：enum、String；
- 运行时：字符串去空白、小写；
- 接口：[`SessionOptions`](SessionOptions.md)、[`InferenceSession`](InferenceSession.md)、[`Ml`](Ml.md)。

---

## 10. 依赖的特性/接口/类

[`SessionOptions`](SessionOptions.md)、[`InferenceSession`](InferenceSession.md)、[`Ml`](Ml.md)。

不依赖 CUDA/ROCm/DirectML/OpenVINO 头文件、厂商 SDK 或 GPU 驱动类型。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。  
相等：按枚举值比较；可作 `Map`/`Set` 键。

---

## 12. 示例与反例

正确：`sessionOptions.providers() == [ExecutionProvider.Cuda, ExecutionProvider.Cpu]` 表示先尝试 CUDA，必要时回退 CPU；CUDA 设备索引用 `providerOptions` 显式传入；私有加速器用 `ExecutionProvider.Other` 并由适配器解释。  
反例：把 `ExecutionProvider.Cuda` 当“CUDA 一定可用”；用 `"gpu"` 字符串隐式选择设备；在没有 CPU 回退时假设未覆盖算子会自动成功；把提供者顺序当枚举序号；用 `Other` 表示“没有提供者”。

---

## 13. 测试/场景义务

九个成员的名称/序号；`executionProviderFromName` 的大小写、空白、未知、空串；`Cpu` 单独使用；CUDA+CPU 顺序；无 CPU 且无回退；`Other` 不 panic；提供者与 `ModelFormat` 组合；枚举值可作 `Map` 键；不出现第十个成员。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
enum ExecutionProvider {
    Cpu = 0,
    Cuda = 1,
    Rocm = 2,
    DirectMl = 3,
    OpenVino = 4,
    Npu = 5,
    Dsp = 6,
    Fpga = 7,
    Other = 8,
}

String executionProviderName(ExecutionProvider executionProvider) {
    if executionProvider == null {
        throw "executionProviderName: null provider"
    }
    if executionProvider == ExecutionProvider.Cpu { return "cpu" }
    if executionProvider == ExecutionProvider.Cuda { return "cuda" }
    if executionProvider == ExecutionProvider.Rocm { return "rocm" }
    if executionProvider == ExecutionProvider.DirectMl { return "directml" }
    if executionProvider == ExecutionProvider.OpenVino { return "openvino" }
    if executionProvider == ExecutionProvider.Npu { return "npu" }
    if executionProvider == ExecutionProvider.Dsp { return "dsp" }
    if executionProvider == ExecutionProvider.Fpga { return "fpga" }
    return "other"
}

ExecutionProvider? executionProviderFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "cpu" { return ExecutionProvider.Cpu }
    if normalized == "cuda" { return ExecutionProvider.Cuda }
    if normalized == "rocm" { return ExecutionProvider.Rocm }
    if normalized == "directml" { return ExecutionProvider.DirectMl }
    if normalized == "openvino" { return ExecutionProvider.OpenVino }
    if normalized == "npu" { return ExecutionProvider.Npu }
    if normalized == "dsp" { return ExecutionProvider.Dsp }
    if normalized == "fpga" { return ExecutionProvider.Fpga }
    if normalized == "other" { return ExecutionProvider.Other }
    return null
}
```
