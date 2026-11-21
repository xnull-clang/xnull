# `Accelerator`

| 项 | 值 |
| --- | --- |
| 类型 | `class Accelerator` |
| 包 | `xdk.accel` |
| 稳定性 | `preview` |
| 依赖 | `AcceleratorKind`、`AcceleratorBackend`、`AcceleratorVendor`、`AcceleratorCapability` |

---

## 1. 定位

加速器只读描述符：加速器 ID、展示名、厂商、类别、后端、运行时版本、容量提示、计算单元数、能力集合。

只做描述与能力门控；不打开设备、不枚举设备、不分配内存、不提交命令、不拥有原生资源。描述符可由集成层根据平台信息或厂商运行时构造，也可由 [`Accel`](Accel.md) 从 GPU 适配器桥接。

不做：

- 设备发现/枚举/热插拔；
- 驱动安装、权限提升；
- 设备打开（统一走 [`Accel.open`](Accel.md)）；
- 性能基准、代际判断、能力探测；
- 从类别/厂商/后端推导能力；
- 原生句柄、寄存器、驱动 SDK 暴露。

---

## 2. 设计逻辑

- 不可变快照；构造后不刷新；硬件变化后由集成层重新构造。
- `acceleratorId` 是关联键；同一宿主会话内稳定，不承诺跨重启/跨进程持久。
- `name`/`vendorName`/`runtimeVersion` 允许空串表示未知；`acceleratorId` 必须非空。
- `vendor` 是稳定枚举；`vendorName` 保留自由文本，二者可不一致（例如 `Other` + `"Acme Silicon"`）。
- `kind`/`backend` 是开放选择后的描述；不承诺打开成功；打开时仍可能 `Unsupported`/`PermissionDenied`。
- `memoryBytes` 是容量提示，`Long` 字节；0 表示未知/不支持，不表示零容量；不是当前可用内存。
- `computeUnitCount` 是后端定义的计算单元数（SM/CU/tile/core 等），`Int`；0 表示未知；不可跨厂商比较。
- `capabilities` 是去重后的能力集合；空集合合法，但打开时至少需要 `Compute` 或 `Memory`，否则 `Unsupported`。
- `supports` 只查声明集合；不触发探测；能力存在仍可能被后端拒绝。
- 不校验 `kind`/`backend`/`vendor` 组合；描述符由集成层保证语义一致；不一致组合在打开时由后端返回 `Unsupported`，本包不做猜测性修正。
- 不提供 `open`：打开统一走 `Accel.open`，以保证选项校验与能力门控只有一条路径。
- 不可变；无 close；可共享；`capabilities()` 返回副本。
- 值语义；`equals` 逐字段比较，`copy` 返回独立描述符。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_acceleratorId` | `String` | final | 非空；关联键；不持久 |
| `_name` | `String` | final | 可空串；展示名/型号 |
| `_vendor` | `AcceleratorVendor` | final | 非 null |
| `_vendorName` | `String` | final | 可空串；自由文本厂商名 |
| `_kind` | `AcceleratorKind` | final | 非 null；创建后固定 |
| `_backend` | `AcceleratorBackend` | final | 非 null；创建后固定 |
| `_runtimeVersion` | `String` | final | 可空串；运行时/SDK 版本，不是驱动安装状态 |
| `_memoryBytes` | `Long` | final | ≥0；0 未知/不支持 |
| `_computeUnitCount` | `Int` | final | ≥0；0 未知 |
| `_capabilities` | `List<AcceleratorCapability>` | final | 非 null；去重；可空 |

不变量：

- `acceleratorId` 非空；`vendor`/`kind`/`backend` 非 null；能力列表元素非 null。
- `memoryBytes ≥ 0`；`computeUnitCount ≥ 0`。
- 能力列表去重并保持首次出现顺序；重复声明不增加语义。
- 字段不可变；`capabilities()` 返回副本。
- 描述符不持有原生句柄、指针、fd 或 SDK 对象。
- 描述符不保证设备存在；打开时重新验证。

---

## 4. 生命周期

构造后不可变；无 close；可共享。设备打开后，描述符仍是独立快照；设备不修改描述符。硬件变化后旧描述符不会自动更新，调用方需重新构造。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Accelerator(String acceleratorId, String name, AcceleratorVendor vendor, String vendorName, AcceleratorKind kind, AcceleratorBackend backend, String runtimeVersion, Long memoryBytes, Int computeUnitCount, List<AcceleratorCapability> capabilities)` | 10 个字段 | ID 非空；枚举非 null；字符串/列表非 null；字节/计数 ≥0；能力元素非 null | 非法 → panic |

构造器主要供宿主/集成层/测试使用；业务代码从平台集成、`Accel.cpu()` 或 `Accel.fromGpuAdapter()` 获取描述符。

---

## 6. 字段表

见 §3；字段私有。不暴露内部注册表、原生设备索引或驱动句柄。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `acceleratorId` | 关联键 | 无 | `String` | 无 |
| `name` | 展示名/型号 | 无 | `String` | 无 |
| `vendor` | 厂商枚举 | 无 | `AcceleratorVendor` | 无 |
| `vendorName` | 厂商自由文本 | 无 | `String` | 无 |
| `kind` | 功能类别 | 无 | `AcceleratorKind` | 无 |
| `backend` | 后端家族 | 无 | `AcceleratorBackend` | 无 |
| `runtimeVersion` | 运行时版本 | 无 | `String` | 无 |
| `memoryBytes` | 容量提示 | 无 | `Long` | 无 |
| `computeUnitCount` | 计算单元数 | 无 | `Int` | 无 |
| `capabilities` | 能力集合副本 | 无 | `List<AcceleratorCapability>` | 无 |
| `supports` | 是否声明某能力 | `AcceleratorCapability capability` | `Bool` | null → panic |
| `describe` | 单行摘要 | 无 | `String` | 无 |
| `equals` | 值比较 | `Accelerator other` | `Bool` | null → false |
| `copy` | 复制 | 无 | `Accelerator` | 无 |

说明：

- 所有纯读取方法无阻塞、无取消点。
- `memoryBytes` 不是可用内存；需要当前值时用 [`AcceleratorDevice.availableMemoryBytes`](AcceleratorDevice.md)。
- `computeUnitCount` 语义由后端定义，不能用于跨设备性能比较。
- `supports` 线性扫描；不触发原生查询；null panic。
- `describe` 用于日志；包含 ID/kind/backend/vendor/name/memory/computeUnits，不包含能力列表全文，避免日志过长。
- `equals` 比较所有字段；能力列表按顺序逐元素比较；`copy` 返回独立快照。
- 不提供 `open`/`close`/`refresh`；打开走 `Accel.open`，刷新由集成层重新构造。
- 不提供 `isDiscrete`/`isIntegrated`；跨类别语义不稳定，需要时由集成层编码到 `name` 或扩展描述。

---

## 8. 使用的技术

- 不可变快照；
- 值对象；
- 能力集合去重；
- 值比较；
- 字符串描述；
- 枚举组合。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Long、Int、Bool、List；
- 辅助：`unit` 值（仅其他类型的静态函数使用）；
- 运行时：无直接原生调用；描述符由集成层构造；
- 接口：`AcceleratorKind`、`AcceleratorBackend`、`AcceleratorVendor`、`AcceleratorCapability`、`Accel`。

---

## 10. 依赖的特性/接口/类

[`Accel`](Accel.md)、[`AcceleratorDevice`](AcceleratorDevice.md)、[`AcceleratorKind`](AcceleratorKind.md)、[`AcceleratorBackend`](AcceleratorBackend.md)、[`AcceleratorVendor`](AcceleratorVendor.md)、[`AcceleratorCapability`](AcceleratorCapability.md)。

---

## 11. 所有权与并发

不可变值；可跨任务共享；无资源；无取消点。`capabilities()` 返回副本；`copy()` 返回独立值。

相等：`equals` 逐字段比较；`==` 是引用身份；推荐用 `acceleratorId()` 作关联键，而不是把描述符当长期持久 ID。

---

## 12. 示例与反例

正确：集成层构造 NPU 描述符并声明 `Memory`/`Compute`/`Quantized`；打开前 `supports(Compute)`；用 `kind`/`backend`/`vendor` 做日志与筛选；用 `memoryBytes` 做容量提示；`copy()` 后独立修改列表副本。

反例：从 `Npu` 推断一定支持 INT8；从 `Nvidia` 推断一定可用 CUDA；把 `memoryBytes` 当当前空闲内存；把 `acceleratorId` 当跨重启持久 ID；打开设备后继续依赖旧描述符的容量；在描述符里塞原生句柄；把空能力集合当“默认全支持”。

---

## 13. 测试/场景义务

10 字段构造；空 ID panic；负内存/计数 panic；能力列表去重/顺序；空能力集合；
`supports` 命中/未命中/null panic；`capabilities()` 副本独立；
`equals`/`copy`；`describe` 不含敏感信息；大 `Long` 容量；
GPU/NPU/DSP/FPGA/MCU 描述符；`Accel.cpu()`/`Accel.fromGpuAdapter()` 生成字段；
描述符与设备打开后的字段一致性；重新构造后旧快照不刷新。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class Accelerator {
    final String _acceleratorId
    final String _name
    final AcceleratorVendor _vendor
    final String _vendorName
    final AcceleratorKind _kind
    final AcceleratorBackend _backend
    final String _runtimeVersion
    final Long _memoryBytes
    final Int _computeUnitCount
    final List<AcceleratorCapability> _capabilities

    Accelerator(String acceleratorId, String name, AcceleratorVendor vendor,
                String vendorName, AcceleratorKind kind,
                AcceleratorBackend backend, String runtimeVersion,
                Long memoryBytes, Int computeUnitCount,
                List<AcceleratorCapability> capabilities) {
        if acceleratorId == null || acceleratorId == "" || name == null
            || vendor == null || vendorName == null || kind == null
            || backend == null || runtimeVersion == null || capabilities == null {
            throw "Accelerator: invalid field"
        }
        if memoryBytes < 0 || computeUnitCount < 0 {
            throw "Accelerator: negative value"
        }
        List<AcceleratorCapability> normalized = []
        Int index = 0
        while index < capabilities.length() {
            AcceleratorCapability capability = capabilities.get(index)
            if capability == null { throw "Accelerator: null capability" }
            Bool exists = false
            Int scan = 0
            while scan < normalized.length() {
                if normalized.get(scan) == capability { exists = true; break }
                scan = scan + 1
            }
            if !exists { normalized.push(capability) }
            index = index + 1
        }
        _acceleratorId = acceleratorId
        _name = name
        _vendor = vendor
        _vendorName = vendorName
        _kind = kind
        _backend = backend
        _runtimeVersion = runtimeVersion
        _memoryBytes = memoryBytes
        _computeUnitCount = computeUnitCount
        _capabilities = normalized
    }

    String acceleratorId() { return _acceleratorId }
    String name() { return _name }
    AcceleratorVendor vendor() { return _vendor }
    String vendorName() { return _vendorName }
    AcceleratorKind kind() { return _kind }
    AcceleratorBackend backend() { return _backend }
    String runtimeVersion() { return _runtimeVersion }
    Long memoryBytes() { return _memoryBytes }
    Int computeUnitCount() { return _computeUnitCount }
    List<AcceleratorCapability> capabilities() { return _capabilities.copy() }

    Bool supports(AcceleratorCapability capability) {
        if capability == null { throw "Accelerator.supports: null capability" }
        Int index = 0
        while index < _capabilities.length() {
            if _capabilities.get(index) == capability { return true }
            index = index + 1
        }
        return false
    }

    String describe() {
        return "accel " + _acceleratorId
            + " kind=" + str(_kind)
            + " backend=" + str(_backend)
            + " vendor=" + str(_vendor)
            + " name=" + _name
            + " memory=" + str(_memoryBytes)
            + " units=" + str(_computeUnitCount)
    }

    Bool equals(Accelerator other) {
        if other == null { return false }
        if _acceleratorId != other.acceleratorId()
            || _name != other.name()
            || _vendor != other.vendor()
            || _vendorName != other.vendorName()
            || _kind != other.kind()
            || _backend != other.backend()
            || _runtimeVersion != other.runtimeVersion()
            || _memoryBytes != other.memoryBytes()
            || _computeUnitCount != other.computeUnitCount() {
            return false
        }
        List<AcceleratorCapability> otherCapabilities = other.capabilities()
        if _capabilities.length() != otherCapabilities.length() { return false }
        Int index = 0
        while index < _capabilities.length() {
            if _capabilities.get(index) != otherCapabilities.get(index) { return false }
            index = index + 1
        }
        return true
    }

    Accelerator copy() {
        return new Accelerator(_acceleratorId, _name, _vendor, _vendorName,
            _kind, _backend, _runtimeVersion, _memoryBytes,
            _computeUnitCount, _capabilities)
    }
}
```
