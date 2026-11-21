# `GpuAdapter`

| 项 | 值 |
| --- | --- |
| 类型 | `class GpuAdapter` |
| 包 | `xdk.os.gpu` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Error`、`GpuBackend`、`GpuDevice` |

---

## 1. 定位

GPU 适配器只读快照：适配器 ID、厂商、型号、后端、显存、独显/集显标记、驱动版本；并提供显式打开设备的入口。

不做：驱动安装/更新、设备控制、显示模式、命令提交、显存分配、后端 API 镜像。适配器快照不代表设备已打开。

---

## 2. 设计逻辑

- 不可变快照；由 `OsHost.gpuAdapters(context)` 返回。
- `adapterId` 是适配器关联键；同一宿主会话内稳定，不承诺跨重启/跨进程持久。
- `vendor`/`model`/`driverVersion` 允许空串表示未知；`adapterId` 必须非空。
- `memoryBytes` 用 `Long`；`0` 表示未知/不支持，不表示零容量。
- `isDiscrete`/`isIntegrated` 互斥；两者都为 false 表示虚拟/未知/未报告。
- `open(Context)` 显式打开设备；每次调用返回独立 `GpuDevice`，调用方分别 `close()`。
- `GpuBackend.Unknown` 是合法值；打开可能成功，也可能返回 `Unsupported`，不猜测后端。
- `describe` 只用于诊断/日志，不用于精确容量/性能判断。
- 不可变；无资源句柄；可缓存，但硬件变化后需要重新枚举。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_adapterId` | `String` | final | 非空；适配器关联键 |
| `_vendor` | `String` | final | 可空串；未知 |
| `_model` | `String` | final | 可空串；未知 |
| `_backend` | `GpuBackend` | final | 非 null |
| `_memoryBytes` | `Long` | final | ≥0；0 未知 |
| `_isDiscrete` | `Bool` | final | 独显标记 |
| `_isIntegrated` | `Bool` | final | 集显标记 |
| `_driverVersion` | `String` | final | 可空串；未知 |

不变量：adapterId 非空；backend 非 null；memoryBytes ≥0；`isDiscrete` 与 `isIntegrated` 不同时为 true；字段不可变。

---

## 4. 生命周期

构造后不可变；无 close；可共享。`open` 不改变适配器快照；返回的设备独立关闭。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `GpuAdapter(...)` | 8 个字段 | adapterId 非空；backend 非 null；memoryBytes ≥0；两个布尔不同时为 true | 非法 → panic |

构造器主要供宿主/测试使用；业务代码通过 `OsHost.gpuAdapters(context)` 获取。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `id` | 适配器 ID | 无 | `String` | 无 |
| `vendor` | 厂商 | 无 | `String` | 无 |
| `model` | 型号 | 无 | `String` | 无 |
| `backend` | 后端 | 无 | `GpuBackend` | 无 |
| `memoryBytes` | 显存字节 | 无 | `Long` | 无 |
| `isDiscrete` | 是否独显 | 无 | `Bool` | 无 |
| `isIntegrated` | 是否集显 | 无 | `Bool` | 无 |
| `driverVersion` | 驱动版本 | 无 | `String` | 无 |
| `open` | 打开设备 | `Context context` | `Result<GpuDevice, Error>` | `Unsupported`/`PermissionDenied`/`Cancelled` |
| `describe` | 单行摘要 | 无 | `String` | 无 |
| `equals` | 值比较 | `GpuAdapter other` | `Bool` | null → false |
| `copy` | 复制 | 无 | `GpuAdapter` | 无 |

说明：

- `open` 首参 `Context`；`context == null` 是合同错误（panic）。
- `open` 不缓存设备；多次调用返回多个独立设备，调用方分别关闭。
- 适配器在枚举后消失/驱动重置时，`open` 返回 `Unsupported`；不提供 `Unavailable`，因为快照本身没有生命周期。
- `open` 不预检 `GpuBackend.Unknown`；后端是否可打开由适配器决定。
- `describe` 不包含驱动版本，避免日志泄露过多环境信息。

---

## 8. 使用的技术

- 不可变快照；
- 不透明打开；
- 值比较；
- 字符串描述。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Long、Bool、Result；
- 运行时/适配器：`gpuDeviceOpenRaw(Context context, String adapterId, GpuBackend backend) -> Result<Long, Error>`；
- 原生打开返回的 handle 必须 >0；否则视为适配器内部错误（`GpuDevice` 构造器 panic）；
- 接口：`Context`、`Error`、`BasicError`、`ErrorKind`、`GpuBackend`、`GpuDevice`。

---

## 10. 依赖的特性/接口/类

`GpuBackend`、`GpuDevice`、`GpuMemoryInfo`、`GpuQueue`、`GpuQueueKind`、`OsHost`、`Context`、`Error`。

---

## 11. 所有权与并发

不可变；可跨任务共享；`open` 可并发调用（实现可串行化），每次返回独立设备；快照读取无取消点，`open` 的取消由 `Context` 承担。
相等：`equals` 逐字段比较；`==` 仍是引用身份；不推荐作 `Map` 键，使用 `id()` 作关联键。

---

## 12. 示例与反例

正确：枚举后按 `isDiscrete()`/`memoryBytes()` 选择适配器；`open(context)` 后把设备交给渲染/计算层；每个设备单独 close。  
反例：把 `id()` 当跨重启持久 ID；假设 `vendor`/`model` 非空；假设 `memoryBytes` 是当前可用显存；同时信任 `isDiscrete` 与 `isIntegrated`；打开设备后不关闭；用 `describe()` 做精确计费。

---

## 13. 测试/场景义务

字段读取；空厂商/型号/驱动；负显存 panic；独显+集显同时为 true panic；`open` 成功/`Unsupported`/`PermissionDenied`/`Cancelled`；
多次 `open` 独立；适配器消失后 `open` 失败；`equals`/`copy`；`describe`；容器内只看到可见适配器；`Unknown` 后端打开行为。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class GpuAdapter {
    final String _adapterId
    final String _vendor
    final String _model
    final GpuBackend _backend
    final Long _memoryBytes
    final Bool _isDiscrete
    final Bool _isIntegrated
    final String _driverVersion

    GpuAdapter(String adapterId, String vendor, String model, GpuBackend backend,
               Long memoryBytes, Bool isDiscrete, Bool isIntegrated,
               String driverVersion) {
        if adapterId == null || adapterId == "" || vendor == null || model == null
            || backend == null || driverVersion == null {
            throw "GpuAdapter: invalid field"
        }
        if memoryBytes < 0 {
            throw "GpuAdapter: negative memory"
        }
        if isDiscrete && isIntegrated {
            throw "GpuAdapter: discrete and integrated"
        }
        _adapterId = adapterId
        _vendor = vendor
        _model = model
        _backend = backend
        _memoryBytes = memoryBytes
        _isDiscrete = isDiscrete
        _isIntegrated = isIntegrated
        _driverVersion = driverVersion
    }

    String id() { return _adapterId }
    String vendor() { return _vendor }
    String model() { return _model }
    GpuBackend backend() { return _backend }
    Long memoryBytes() { return _memoryBytes }
    Bool isDiscrete() { return _isDiscrete }
    Bool isIntegrated() { return _isIntegrated }
    String driverVersion() { return _driverVersion }

    Result<GpuDevice, Error> open(Context context) {
        if context == null { throw "GpuAdapter.open: null context" }
        Result<Long, Error> opened = gpuDeviceOpenRaw(context, _adapterId, _backend)
        if opened.isErr() { return Err(opened.error()) }
        GpuDevice device = new GpuDevice(opened.value(), _adapterId, _backend)
        return Ok(device)
    }

    String describe() {
        return "gpu " + _vendor + " " + _model
            + " backend=" + str(_backend)
            + " memory=" + str(_memoryBytes)
    }

    Bool equals(GpuAdapter other) {
        if other == null { return false }
        return _adapterId == other.id()
            && _vendor == other.vendor()
            && _model == other.model()
            && _backend == other.backend()
            && _memoryBytes == other.memoryBytes()
            && _isDiscrete == other.isDiscrete()
            && _isIntegrated == other.isIntegrated()
            && _driverVersion == other.driverVersion()
    }

    GpuAdapter copy() {
        return new GpuAdapter(_adapterId, _vendor, _model, _backend,
            _memoryBytes, _isDiscrete, _isIntegrated, _driverVersion)
    }
}
```
