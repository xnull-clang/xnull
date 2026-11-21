# `AcceleratorCapability`

| 项 | 值 |
| --- | --- |
| 类型 | `enum AcceleratorCapability` |
| 包 | `xdk.accel` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

加速器描述符声明的能力类别：内存、计算、图形、可重构、量化、低功耗、其它。

只做能力门控与描述；不表示性能、版本、扩展、精度格式、队列数量或一定可执行。能力必须由描述符逐项声明，不能从 `AcceleratorKind`、`AcceleratorBackend` 或 `AcceleratorVendor` 推导。

不做：

- 能力探测/基准测试；
- 具体 dtype、指令、扩展或驱动版本；
- 渲染/显示/呈现；
- 权限、配额或安全策略；
- 自动降级或模拟。

---

## 2. 设计逻辑

- 封闭枚举：只列基线能命名的能力；应用不能扩展。
- `Memory`：支持设备可见内存分配/主机可见访问/数据传输；不含具体一致性模型。
- `Compute`：支持程序加载、内核创建与命令派发；不含具体数值格式。
- `Graphics`：设备具备图形流水线能力；本包只报告，不提供任何渲染/显示/呈现入口。消费图形能力应使用图形栈，而不是 `xdk.accel`。
- `Reconfigurable`：支持可重构逻辑/位流加载；典型为 FPGA/自适应 SoC；不保证任意位流可加载。
- `Quantized`：具备原生量化数值路径；不承诺 INT5/INT8/FP8 等具体格式；具体格式由程序/后端决定。
- `LowPower`：面向低功耗/常开场景；不提供电源管理、频率或热控制。
- `Other`：厂商特定能力；无语义、不可用于门控；必须配合描述符名称/文档理解。
- 能力缺失 → 对应操作返回 `Unsupported`；不得静默模拟或改用其它设备。
- 能力存在不等于操作一定成功；后端仍可返回 `Unsupported`/`PermissionDenied`/`OutOfMemory`/`Busy`。
- 值语义；成员只允许追加。

---

## 3. 表示与不变量

| 成员 | 含义 | 门控的操作 | 备注 |
| --- | --- | --- | --- |
| `Memory` | 设备可见内存能力 | `allocateMemory`、`read`/`write`、内存类内核绑定 | 不含统一地址空间承诺 |
| `Compute` | 通用内核执行能力 | `createProgram`、`createKernel`、`createQueue`、`createCommandBuffer`、`dispatch` | 不含具体 dtype |
| `Graphics` | 图形流水线能力 | 本包无操作；仅描述/筛选 | 不暴露渲染/显示 |
| `Reconfigurable` | 可重构逻辑/位流能力 | 位流类 `createProgram` | 常见 FPGA；可能独占 |
| `Quantized` | 原生量化路径 | 量化程序/内核（由后端识别） | 不承诺具体格式 |
| `LowPower` | 低功耗/常开定位 | 本包无专用操作；仅描述/筛选 | 不提供电源控制 |
| `Other` | 厂商特定能力 | 无通用门控 | 不可推导语义 |

不变量：成员固定；只允许追加；值语义；任何能力都不表示具体格式、版本、性能或一定成功；`Graphics` 在本包中永远不是可执行入口。

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
| `acceleratorCapabilityName` | 稳定小写名 | `AcceleratorCapability capability` | `String` | 无 |
| `acceleratorCapabilityFromName` | 名称解析 | `String name` | `AcceleratorCapability?` | 无；未知返回 null |

说明：

- 名称用于日志/配置/诊断；不是驱动扩展名或 dtype 名。
- 解析只接受稳定名，去除首尾空白并转小写；未知返回 null。
- `low_power` 是稳定名；`graphics` 只描述，不产生渲染 API。
- 能力列表由 `Accelerator` 去重后保存；重复声明不增加语义。

---

## 8. 使用的技术

- 简单枚举；
- 名称映射；
- 能力集合/门控；
- 值语义比较。

---

## 9. 需要的支撑

- 语言：enum、String；
- 运行时：无；
- 接口：`Accelerator`、`AcceleratorDevice`、`AcceleratorProgram`、`AcceleratorCommandBuffer`。

---

## 10. 依赖的特性/接口/类

[`Accelerator`](Accelerator.md)、[`AcceleratorDevice`](AcceleratorDevice.md)、[`AcceleratorProgram`](AcceleratorProgram.md)、[`AcceleratorCommandBuffer`](AcceleratorCommandBuffer.md)、[`AcceleratorKind`](AcceleratorKind.md)。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。

相等：按枚举值比较；可作 `Map`/`Set` 键。

---

## 12. 示例与反例

正确：`accelerator.supports(AcceleratorCapability.Compute)` 通过后才创建程序/队列；FPGA 位流程序前检查 `Reconfigurable`；NPU 量化路径前检查 `Quantized`，仍由后端校验具体格式；`Graphics` 只用于日志/筛选，不尝试在本包渲染。

反例：看到 `Gpu` 就认为一定支持 `Compute`；看到 `Quantized` 就传 INT5；用 `Other` 做门控；缺少 `Memory` 仍调用 `allocateMemory`；把 `LowPower` 当电源管理 API；把 `Graphics` 当渲染入口；能力检查通过后假设一定成功。

---

## 13. 测试/场景义务

每个成员名称/解析；大小写/空白；未知名称返回 null；能力列表去重/顺序；
`Memory`/`Compute` 缺失时对应操作 `Unsupported`；`Graphics` 无渲染入口；
`Reconfigurable` 位流/独占/`Busy`；`Quantized` 具体格式差异；`LowPower` 无电源 API；
`Other` 不可门控；能力存在但后端拒绝；能力与 kind/backend/vendor 组合。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
enum AcceleratorCapability {
    Memory,
    Compute,
    Graphics,
    Reconfigurable,
    Quantized,
    LowPower,
    Other,
}

String acceleratorCapabilityName(AcceleratorCapability capability) {
    if capability == AcceleratorCapability.Memory { return "memory" }
    if capability == AcceleratorCapability.Compute { return "compute" }
    if capability == AcceleratorCapability.Graphics { return "graphics" }
    if capability == AcceleratorCapability.Reconfigurable { return "reconfigurable" }
    if capability == AcceleratorCapability.Quantized { return "quantized" }
    if capability == AcceleratorCapability.LowPower { return "low_power" }
    return "other"
}

AcceleratorCapability? acceleratorCapabilityFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "memory" { return AcceleratorCapability.Memory }
    if normalized == "compute" { return AcceleratorCapability.Compute }
    if normalized == "graphics" { return AcceleratorCapability.Graphics }
    if normalized == "reconfigurable" { return AcceleratorCapability.Reconfigurable }
    if normalized == "quantized" { return AcceleratorCapability.Quantized }
    if normalized == "low_power" { return AcceleratorCapability.LowPower }
    if normalized == "other" { return AcceleratorCapability.Other }
    return null
}
```
