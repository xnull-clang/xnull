# `AcceleratorVendor`

| 项 | 值 |
| --- | --- |
| 类型 | `enum AcceleratorVendor` |
| 包 | `xdk.accel` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

加速器厂商/知识产权提供方的稳定分类：主要 CPU、GPU、NPU、DSP、FPGA、ASIC、MCU 厂商与 IP 提供方，以及 `Unknown`/`Other`。

只做描述性归类；不表示设备可用性、驱动支持、性能、代际、地区或业务关系。

不做：

- 厂商识别/探测；
- 驱动安装/许可；
- 从厂商推断能力、后端或设备型号；
- 覆盖所有小型/地区厂商；
- 把 `Other` 当错误。

---

## 2. 设计逻辑

- 封闭枚举：只列基线能稳定命名的厂商/IP 提供方；应用不能扩展。
- `Unknown`：未报告或无法识别；合法值，不 panic。
- `Other`：已报告但不在此枚举；合法值，配合 `Accelerator.vendorName()` 保留原文。
- 枚举按厂商主体归类，不按品牌/子品牌：例如 AMD 的 Xilinx 产品可归 `Amd` 或 `Xilinx`，由描述符创建方选择并保持稳定；不得在同一设备上摇摆。
- `Arm` 表示 IP 提供方；采用 Arm IP 的 SoC 厂商仍可归自身厂商。
- 厂商与 `AcceleratorKind`/`AcceleratorBackend` 正交；厂商既不保证后端，也不保证能力。
- 名称稳定；只允许追加，不允许改义/删除。
- 值语义；可共享。

---

## 3. 表示与不变量

| 成员 | 含义 | 备注 |
| --- | --- | --- |
| `Unknown` | 未报告/未知 | 默认保守值 |
| `Intel` | Intel | CPU/GPU/NPU/FPGA/oneAPI |
| `Nvidia` | NVIDIA | GPU/DPU/CUDA |
| `Amd` | AMD | CPU/GPU/自适应 SoC；含 AMD 品牌产品 |
| `Apple` | Apple | Metal/Neural Engine |
| `Qualcomm` | Qualcomm | Adreno/Hexagon |
| `Arm` | Arm | CPU/NPU IP |
| `Imagination` | Imagination Technologies | GPU/NNA IP |
| `Google` | Google | TPU 等 |
| `Microsoft` | Microsoft | Maia 等 |
| `Amazon` | Amazon/AWS | Inferentia/Trainium 等 |
| `Samsung` | Samsung | SoC/NPU |
| `Huawei` | Huawei | Ascend 等 |
| `MediaTek` | MediaTek | SoC/APU |
| `Broadcom` | Broadcom | 定制 ASIC/网络 |
| `Marvell` | Marvell | DPU/网络/定制硅 |
| `Nxp` | NXP | MCU/边缘 SoC |
| `TexasInstruments` | Texas Instruments | DSP/MCU |
| `STMicroelectronics` | STMicroelectronics | MCU/边缘 |
| `Infineon` | Infineon | MCU/边缘 |
| `Renesas` | Renesas | MCU/SoC |
| `Microchip` | Microchip | MCU/FPGA |
| `Lattice` | Lattice Semiconductor | FPGA |
| `Xilinx` | Xilinx（AMD 旗下品牌） | FPGA/自适应 SoC |
| `Altera` | Altera | FPGA/自适应 |
| `Cerebras` | Cerebras | 晶圆级 ASIC |
| `Graphcore` | Graphcore | IPU |
| `Groq` | Groq | LPU |
| `SambaNova` | SambaNova | 数据流加速器 |
| `Tenstorrent` | Tenstorrent | AI 加速器/IP |
| `Hailo` | Hailo | 边缘 NPU |
| `Rockchip` | Rockchip | SoC/NPU |
| `Espressif` | Espressif | MCU/Wi-Fi SoC |
| `NordicSemiconductor` | Nordic Semiconductor | MCU/无线 SoC |
| `SiFive` | SiFive | RISC-V IP |
| `Other` | 其它已报告厂商 | 配合 `vendorName()` |

不变量：成员固定；只允许追加；值语义；`Unknown`/`Other` 合法；任何成员都不表示具体设备、驱动、后端或能力。

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
| `acceleratorVendorName` | 稳定小写名 | `AcceleratorVendor vendor` | `String` | 无 |
| `acceleratorVendorFromName` | 稳定名解析 | `String name` | `AcceleratorVendor?` | 无；未知返回 null |
| `acceleratorVendorFromText` | 自由文本归类 | `String text` | `AcceleratorVendor` | 无；空 → `Unknown`，未识别 → `Other` |

说明：

- `acceleratorVendorName` 用于配置/日志；不是公司全称或商标声明。
- `acceleratorVendorFromName` 只接受稳定小写名（如 `"texas_instruments"`、`"nordic_semiconductor"`），未知返回 null。
- `acceleratorVendorFromText` 用于把 `GpuAdapter.vendor()` 等自由文本归类；去空白、转小写；空串 → `Unknown`；未识别非空文本 → `Other`；不抛错。
- `fromText` 的别名只用于常见写法，不做模糊匹配或猜测；无法确定时返回 `Other`，并保留原文到 `Accelerator.vendorName()`。
- 厂商不参与能力门控；不得因厂商是 `Nvidia` 就假设 `Cuda` 可用。

---

## 8. 使用的技术

- 简单枚举；
- 名称映射；
- 自由文本归一/别名表；
- 值语义比较。

---

## 9. 需要的支撑

- 语言：enum、String；
- 运行时：无；
- 接口：`Accelerator`、`AcceleratorDevice`。

---

## 10. 依赖的特性/接口/类

[`Accelerator`](Accelerator.md)、[`AcceleratorDevice`](AcceleratorDevice.md)、[`AcceleratorKind`](AcceleratorKind.md)、[`AcceleratorBackend`](AcceleratorBackend.md)。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。

相等：按枚举值比较；可作 `Map`/`Set` 键。

---

## 12. 示例与反例

正确：`GpuAdapter.vendor()` 为 `"NVIDIA"` → `Nvidia`；`"Advanced Micro Devices"` → `Amd`；空串 → `Unknown`；`"Acme Silicon"` → `Other` 且 `vendorName()` 保留原文；同一设备描述符的厂商归类保持稳定。

反例：把 `Unknown` 当 Intel；把 `Other` 当错误；用厂商推断后端；把子品牌当独立厂商并频繁改名；对 `"TI"` 做模糊匹配到错误厂商；把厂商字段用于权限判断。

---

## 13. 测试/场景义务

每个成员稳定名/解析；大小写/空白；空文本 → `Unknown`；未识别 → `Other`；
常见别名（NVIDIA/AMD/Intel/Qualcomm/Arm/Apple/TI/ST/Nordic）；`Other` 保留原文；
厂商与 kind/backend/capability 组合；`Accel.fromGpuAdapter` 的厂商归类；
同设备多次读取的稳定性；跨平台厂商文本。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
enum AcceleratorVendor {
    Unknown,
    Intel,
    Nvidia,
    Amd,
    Apple,
    Qualcomm,
    Arm,
    Imagination,
    Google,
    Microsoft,
    Amazon,
    Samsung,
    Huawei,
    MediaTek,
    Broadcom,
    Marvell,
    Nxp,
    TexasInstruments,
    STMicroelectronics,
    Infineon,
    Renesas,
    Microchip,
    Lattice,
    Xilinx,
    Altera,
    Cerebras,
    Graphcore,
    Groq,
    SambaNova,
    Tenstorrent,
    Hailo,
    Rockchip,
    Espressif,
    NordicSemiconductor,
    SiFive,
    Other,
}

String acceleratorVendorName(AcceleratorVendor vendor) {
    if vendor == AcceleratorVendor.Unknown { return "unknown" }
    if vendor == AcceleratorVendor.Intel { return "intel" }
    if vendor == AcceleratorVendor.Nvidia { return "nvidia" }
    if vendor == AcceleratorVendor.Amd { return "amd" }
    if vendor == AcceleratorVendor.Apple { return "apple" }
    if vendor == AcceleratorVendor.Qualcomm { return "qualcomm" }
    if vendor == AcceleratorVendor.Arm { return "arm" }
    if vendor == AcceleratorVendor.Imagination { return "imagination" }
    if vendor == AcceleratorVendor.Google { return "google" }
    if vendor == AcceleratorVendor.Microsoft { return "microsoft" }
    if vendor == AcceleratorVendor.Amazon { return "amazon" }
    if vendor == AcceleratorVendor.Samsung { return "samsung" }
    if vendor == AcceleratorVendor.Huawei { return "huawei" }
    if vendor == AcceleratorVendor.MediaTek { return "mediatek" }
    if vendor == AcceleratorVendor.Broadcom { return "broadcom" }
    if vendor == AcceleratorVendor.Marvell { return "marvell" }
    if vendor == AcceleratorVendor.Nxp { return "nxp" }
    if vendor == AcceleratorVendor.TexasInstruments { return "texas_instruments" }
    if vendor == AcceleratorVendor.STMicroelectronics { return "stmicroelectronics" }
    if vendor == AcceleratorVendor.Infineon { return "infineon" }
    if vendor == AcceleratorVendor.Renesas { return "renesas" }
    if vendor == AcceleratorVendor.Microchip { return "microchip" }
    if vendor == AcceleratorVendor.Lattice { return "lattice" }
    if vendor == AcceleratorVendor.Xilinx { return "xilinx" }
    if vendor == AcceleratorVendor.Altera { return "altera" }
    if vendor == AcceleratorVendor.Cerebras { return "cerebras" }
    if vendor == AcceleratorVendor.Graphcore { return "graphcore" }
    if vendor == AcceleratorVendor.Groq { return "groq" }
    if vendor == AcceleratorVendor.SambaNova { return "sambanova" }
    if vendor == AcceleratorVendor.Tenstorrent { return "tenstorrent" }
    if vendor == AcceleratorVendor.Hailo { return "hailo" }
    if vendor == AcceleratorVendor.Rockchip { return "rockchip" }
    if vendor == AcceleratorVendor.Espressif { return "espressif" }
    if vendor == AcceleratorVendor.NordicSemiconductor { return "nordic_semiconductor" }
    if vendor == AcceleratorVendor.SiFive { return "sifive" }
    return "other"
}

AcceleratorVendor? acceleratorVendorFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "unknown" { return AcceleratorVendor.Unknown }
    if normalized == "intel" { return AcceleratorVendor.Intel }
    if normalized == "nvidia" { return AcceleratorVendor.Nvidia }
    if normalized == "amd" { return AcceleratorVendor.Amd }
    if normalized == "apple" { return AcceleratorVendor.Apple }
    if normalized == "qualcomm" { return AcceleratorVendor.Qualcomm }
    if normalized == "arm" { return AcceleratorVendor.Arm }
    if normalized == "imagination" { return AcceleratorVendor.Imagination }
    if normalized == "google" { return AcceleratorVendor.Google }
    if normalized == "microsoft" { return AcceleratorVendor.Microsoft }
    if normalized == "amazon" { return AcceleratorVendor.Amazon }
    if normalized == "samsung" { return AcceleratorVendor.Samsung }
    if normalized == "huawei" { return AcceleratorVendor.Huawei }
    if normalized == "mediatek" { return AcceleratorVendor.MediaTek }
    if normalized == "broadcom" { return AcceleratorVendor.Broadcom }
    if normalized == "marvell" { return AcceleratorVendor.Marvell }
    if normalized == "nxp" { return AcceleratorVendor.Nxp }
    if normalized == "texas_instruments" { return AcceleratorVendor.TexasInstruments }
    if normalized == "stmicroelectronics" { return AcceleratorVendor.STMicroelectronics }
    if normalized == "infineon" { return AcceleratorVendor.Infineon }
    if normalized == "renesas" { return AcceleratorVendor.Renesas }
    if normalized == "microchip" { return AcceleratorVendor.Microchip }
    if normalized == "lattice" { return AcceleratorVendor.Lattice }
    if normalized == "xilinx" { return AcceleratorVendor.Xilinx }
    if normalized == "altera" { return AcceleratorVendor.Altera }
    if normalized == "cerebras" { return AcceleratorVendor.Cerebras }
    if normalized == "graphcore" { return AcceleratorVendor.Graphcore }
    if normalized == "groq" { return AcceleratorVendor.Groq }
    if normalized == "sambanova" { return AcceleratorVendor.SambaNova }
    if normalized == "tenstorrent" { return AcceleratorVendor.Tenstorrent }
    if normalized == "hailo" { return AcceleratorVendor.Hailo }
    if normalized == "rockchip" { return AcceleratorVendor.Rockchip }
    if normalized == "espressif" { return AcceleratorVendor.Espressif }
    if normalized == "nordic_semiconductor" { return AcceleratorVendor.NordicSemiconductor }
    if normalized == "sifive" { return AcceleratorVendor.SiFive }
    if normalized == "other" { return AcceleratorVendor.Other }
    return null
}

AcceleratorVendor acceleratorVendorFromText(String text) {
    if text == null { return AcceleratorVendor.Unknown }
    String normalized = text.trim().toLower()
    if normalized == "" { return AcceleratorVendor.Unknown }
    if normalized == "unknown" { return AcceleratorVendor.Unknown }
    if normalized == "intel" { return AcceleratorVendor.Intel }
    if normalized == "nvidia" { return AcceleratorVendor.Nvidia }
    if normalized == "amd" { return AcceleratorVendor.Amd }
    if normalized == "advanced micro devices" { return AcceleratorVendor.Amd }
    if normalized == "apple" { return AcceleratorVendor.Apple }
    if normalized == "qualcomm" { return AcceleratorVendor.Qualcomm }
    if normalized == "arm" { return AcceleratorVendor.Arm }
    if normalized == "imagination" { return AcceleratorVendor.Imagination }
    if normalized == "imagination technologies" { return AcceleratorVendor.Imagination }
    if normalized == "google" { return AcceleratorVendor.Google }
    if normalized == "microsoft" { return AcceleratorVendor.Microsoft }
    if normalized == "amazon" { return AcceleratorVendor.Amazon }
    if normalized == "aws" { return AcceleratorVendor.Amazon }
    if normalized == "samsung" { return AcceleratorVendor.Samsung }
    if normalized == "huawei" { return AcceleratorVendor.Huawei }
    if normalized == "mediatek" { return AcceleratorVendor.MediaTek }
    if normalized == "broadcom" { return AcceleratorVendor.Broadcom }
    if normalized == "marvell" { return AcceleratorVendor.Marvell }
    if normalized == "nxp" { return AcceleratorVendor.Nxp }
    if normalized == "texas instruments" { return AcceleratorVendor.TexasInstruments }
    if normalized == "ti" { return AcceleratorVendor.TexasInstruments }
    if normalized == "stmicroelectronics" { return AcceleratorVendor.STMicroelectronics }
    if normalized == "st" { return AcceleratorVendor.STMicroelectronics }
    if normalized == "infineon" { return AcceleratorVendor.Infineon }
    if normalized == "renesas" { return AcceleratorVendor.Renesas }
    if normalized == "microchip" { return AcceleratorVendor.Microchip }
    if normalized == "lattice" { return AcceleratorVendor.Lattice }
    if normalized == "xilinx" { return AcceleratorVendor.Xilinx }
    if normalized == "altera" { return AcceleratorVendor.Altera }
    if normalized == "cerebras" { return AcceleratorVendor.Cerebras }
    if normalized == "graphcore" { return AcceleratorVendor.Graphcore }
    if normalized == "groq" { return AcceleratorVendor.Groq }
    if normalized == "sambanova" { return AcceleratorVendor.SambaNova }
    if normalized == "samba nova" { return AcceleratorVendor.SambaNova }
    if normalized == "tenstorrent" { return AcceleratorVendor.Tenstorrent }
    if normalized == "hailo" { return AcceleratorVendor.Hailo }
    if normalized == "rockchip" { return AcceleratorVendor.Rockchip }
    if normalized == "espressif" { return AcceleratorVendor.Espressif }
    if normalized == "nordic" { return AcceleratorVendor.NordicSemiconductor }
    if normalized == "nordic semiconductor" { return AcceleratorVendor.NordicSemiconductor }
    if normalized == "sifive" { return AcceleratorVendor.SiFive }
    if normalized == "si five" { return AcceleratorVendor.SiFive }
    return AcceleratorVendor.Other
}
```
