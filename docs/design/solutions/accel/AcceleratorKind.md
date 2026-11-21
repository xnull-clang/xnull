# `AcceleratorKind`

| 项 | 值 |
| --- | --- |
| 类型 | `enum AcceleratorKind` |
| 包 | `xdk.accel` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

加速器的粗粒度功能类别：CPU、GPU、NPU、DSP、FPGA、ASIC、LPU、IPU、HPU、DPU、VPU、MCU、其它。

只做分类，不做能力承诺、性能排序、代际判断、厂商识别或设备发现。`kind` 说明“这类硬件大致是什么”，不说明它支持哪些内存模型、队列数量、量化格式或可编程性。

不做：

- 从类别推断能力、驱动、指令集、内存一致性或性能；
- 把厂商营销名称强行归类；
- 把一块 SoC 上的多个加速器合并成一个类别；
- 发现、枚举、打开设备；
- 渲染/显示/模型运行时语义。

---

## 2. 设计逻辑

- 封闭枚举：只列 XDK 基线能命名的功能类别；应用不能扩展。
- `Other` 是合法值：无法归入已列类别时使用，不 panic、不猜测。
- 类别是描述性的：同一物理芯片可能同时暴露 CPU、GPU、NPU；每个 `Accelerator` 描述一个可打开的计算目标。
- 类别固定于描述符创建时；设备打开后不再改变。
- 类别与 `AcceleratorBackend` 正交：类别说明硬件功能，后端说明编程/运行时 API 家族。
- 类别与 `AcceleratorCapability` 正交：能力必须逐项声明，不得由类别推导。
- 厂商命名不具权威性：`Ipu`/`Hpu`/`Dpu`/`Vpu` 在不同厂商有不同全称；以 `Accelerator.name()`、`vendorName()` 与 `capabilities()` 为准。
- 值语义；成员只允许追加，不允许改义或删除。

---

## 3. 表示与不变量

| 成员 | 含义 | 备注 |
| --- | --- | --- |
| `Cpu` | 通用主机处理器作为计算目标 | 可显式选择，不表示自动回退 |
| `Gpu` | 面向宽并行/SIMT 的图形与计算处理器 | 本包只使用其计算能力 |
| `Npu` | 神经网络处理单元 | 常见量化与张量运算，不等于通用计算 |
| `Dsp` | 数字信号处理器 | 常见 VLIW/SIMD、音频/视觉/传感器；可能无 MMU |
| `Fpga` | 现场可编程门阵列/自适应逻辑 | 常见位流加载与可重构能力 |
| `Asic` | 专用集成电路 | 固定功能或半定制；不等同于 NPU |
| `Lpu` | 语言处理单元 | 厂商专用，常见于大语言模型推理 |
| `Ipu` | 智能处理单元或基础设施处理单元 | 两种全称都存在；以描述符字段为准 |
| `Hpu` | 厂商专用处理单元（常见 AI 加速） | 不同厂商全称不同；以描述符字段为准 |
| `Dpu` | 数据处理单元 | 常见网络/存储/安全卸载；不是深度学习加速器的默认含义 |
| `Vpu` | 视觉或视频处理单元 | 视觉/图像/视频流水线；不承诺通用计算 |
| `Mcu` | 微控制器单元 | 常见无 OS、无动态加载、内存极小 |
| `Other` | 其它/未归类 | 合法值；不推导任何能力 |

不变量：成员固定；只允许追加；值语义；`Other` 合法；任何成员都不表示具体厂商、驱动、ISA、性能或能力。

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
| `acceleratorKindName` | 稳定小写名 | `AcceleratorKind kind` | `String` | 无 |
| `acceleratorKindFromName` | 名称解析 | `String name` | `AcceleratorKind?` | 无；未知返回 null |

说明：

- 名称用于日志、诊断、配置；不是厂商产品名或驱动名。
- 解析只接受稳定名，去除首尾空白并转小写；不做模糊匹配。
- 未知名称返回 null；调用方决定是否使用 `Other`，解析函数不擅自替换。
- 类别名称不随版本变化；新增类别只追加。

---

## 8. 使用的技术

- 简单枚举；
- 名称映射；
- 值语义比较；
- 描述性分类。

---

## 9. 需要的支撑

- 语言：enum、String；
- 运行时：无；
- 接口：`Accelerator`、`AcceleratorBackend`、`AcceleratorCapability`。

---

## 10. 依赖的特性/接口/类

[`Accelerator`](Accelerator.md)、[`AcceleratorBackend`](AcceleratorBackend.md)、[`AcceleratorCapability`](AcceleratorCapability.md)、[`AcceleratorDevice`](AcceleratorDevice.md)。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。

相等：按枚举值比较；可作 `Map`/`Set` 键。

---

## 12. 示例与反例

正确：`accelerator.kind() == AcceleratorKind.Npu` 后仍检查 `accelerator.supports(AcceleratorCapability.Quantized)`；`Ipu` 描述符同时记录厂商与名称；无法归类时使用 `Other` 并保留 `name()`/`vendorName()`。

反例：看到 `Npu` 就假设支持 INT8；看到 `Gpu` 就假设有图形队列；把 `Dpu` 当深度学习加速器；把 `Mcu` 字符串拼写当稳定名；根据类别选择量化格式；应用自行扩展枚举。

---

## 13. 测试/场景义务

每个成员的稳定名与解析；大小写/空白归一；未知名称返回 null；`Other` 不 panic；
同一 SoC 的 CPU/GPU/NPU 多描述符；`Ipu`/`Hpu`/`Dpu`/`Vpu` 歧义场景；`Mcu` 受限场景；
类别与能力矩阵的组合；`Accelerator`/`AcceleratorDevice` 字段一致性；跨平台枚举。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
enum AcceleratorKind {
    Cpu,
    Gpu,
    Npu,
    Dsp,
    Fpga,
    Asic,
    Lpu,
    Ipu,
    Hpu,
    Dpu,
    Vpu,
    Mcu,
    Other,
}

String acceleratorKindName(AcceleratorKind kind) {
    if kind == AcceleratorKind.Cpu { return "cpu" }
    if kind == AcceleratorKind.Gpu { return "gpu" }
    if kind == AcceleratorKind.Npu { return "npu" }
    if kind == AcceleratorKind.Dsp { return "dsp" }
    if kind == AcceleratorKind.Fpga { return "fpga" }
    if kind == AcceleratorKind.Asic { return "asic" }
    if kind == AcceleratorKind.Lpu { return "lpu" }
    if kind == AcceleratorKind.Ipu { return "ipu" }
    if kind == AcceleratorKind.Hpu { return "hpu" }
    if kind == AcceleratorKind.Dpu { return "dpu" }
    if kind == AcceleratorKind.Vpu { return "vpu" }
    if kind == AcceleratorKind.Mcu { return "mcu" }
    return "other"
}

AcceleratorKind? acceleratorKindFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "cpu" { return AcceleratorKind.Cpu }
    if normalized == "gpu" { return AcceleratorKind.Gpu }
    if normalized == "npu" { return AcceleratorKind.Npu }
    if normalized == "dsp" { return AcceleratorKind.Dsp }
    if normalized == "fpga" { return AcceleratorKind.Fpga }
    if normalized == "asic" { return AcceleratorKind.Asic }
    if normalized == "lpu" { return AcceleratorKind.Lpu }
    if normalized == "ipu" { return AcceleratorKind.Ipu }
    if normalized == "hpu" { return AcceleratorKind.Hpu }
    if normalized == "dpu" { return AcceleratorKind.Dpu }
    if normalized == "vpu" { return AcceleratorKind.Vpu }
    if normalized == "mcu" { return AcceleratorKind.Mcu }
    if normalized == "other" { return AcceleratorKind.Other }
    return null
}
```
