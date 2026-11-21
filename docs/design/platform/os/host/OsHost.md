# `OsHost`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol OsHost` |
| 包 | `xdk.os.host` |
| 稳定性 | `preview` |
| 依赖 | `OsProfile`、`Context`、`Error`、各 domain 类型 |

---

## 1. 定位

OS 平台宿主合同：提供 OS 画像与可选平台服务的入口。每个 OS 有一个内部适配器实现；
测试可以注入 fake 实现。

不做：具体 syscall、驱动、厂商 SDK、全局注册表、权限提升。

---

## 2. 设计逻辑

- 非泛型协议；`profile()` 非阻塞；所有服务探测/控制首参 `Context`。
- 服务方法按能力返回 `Result<T, Error>`：无能力/无实现 → `Unsupported`；无权限 → `PermissionDenied`；
  取消 → `Cancelled`；超时 → `Timeout`。
- `close()` 幂等；关闭后服务方法返回 `Unavailable`；`profile()` 仍可返回快照。
- 宿主不拥有控制器内部资源：`FirewallController`/`ServiceManager`/`GpuDevice`
  等由调用方 `close()`；宿主关闭不自动关闭已返回的控制器（避免 use-after-close 语义模糊）。
- 实现可以是无状态适配器；`close()` no-op，`isOpen()` 恒 true。
- 无全局宿主；`Os.host()` 返回适配器，调用方持有。

---

## 3. 表示与不变量

协议无字段。实现必须保证：

- `profile()` 返回稳定快照；
- `close()` 幂等；
- 关闭后服务方法 `Unavailable`；
- 不返回裸 fd/指针；
- 不修改全局系统状态（除显式控制器方法）。

---

## 4. 生命周期

由 `Os.host()` 或测试创建；调用方按需 `close()`；close 幂等；无 `deinit` 依赖。

---

## 5. 构造契约

协议无构造；实现定义。

---

## 6. 字段表

无协议字段。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `profile` | OS 画像 | 无 | `OsProfile` | 无 |
| `close` | 关闭宿主 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 |
| `cpuTopology` | CPU 拓扑 | `Context context` | `Result<CpuTopology, Error>` | `Unsupported`/`PermissionDenied`/`Cancelled` |
| `cpuAffinity` | 亲和性控制器 | `Context context` | `Result<CpuAffinity, Error>` | 同上 |
| `physicalMemory` | 物理内存 | `Context context` | `Result<PhysicalMemory, Error>` | 同上 |
| `hardwareInventory` | 主板/BIOS/PCI/USB/传感器 | `Context context` | `Result<HardwareInventory, Error>` | 同上 |
| `storageInventory` | 存储/分区/SMART | `Context context` | `Result<StorageInventory, Error>` | 同上 |
| `gpuAdapters` | GPU 适配器 | `Context context` | `Result<List<GpuAdapter>, Error>` | 同上 |
| `firewall` | 防火墙控制器 | `Context context` | `Result<FirewallController, Error>` | 同上 |
| `containers` | 容器宿主 | `Context context` | `Result<ContainerHost, Error>` | 同上 |
| `virtualization` | 虚拟化宿主 | `Context context` | `Result<VirtualizationHost, Error>` | 同上 |
| `services` | 系统服务管理 | `Context context` | `Result<ServiceManager, Error>` | 同上 |
| `sensors` | 传感器读数 | `Context context` | `Result<List<SensorReading>, Error>` | 同上 |

说明：

- 每个方法先检查 `OsProfile.has(对应 OsCapability)`；缺失返回 `Unsupported`，不尝试猜测。
- 返回的控制器/设备句柄由调用方关闭；`OsHost.close()` 不替调用方关闭。
- 列表返回空列表表示“支持但当前没有设备”；`Unsupported` 表示“能力不存在”。
- 权限由 OS 决定；`PermissionDenied` 不带敏感信息。
- 探测可以阻塞；`Context` 取消后应尽快返回 `Cancelled`。

---

## 8. 使用的技术

- 非泛型协议；
- 平台适配器；
- 能力门控；
- Context/Result；
- 不透明句柄。

---

## 9. 需要的支撑

- 语言：protocol、Result、Context、List；
- 运行时：`nativeOsHost()`、各 `*Raw` 适配器原语；
- 接口：`OsProfile`、`OsInfo`、`OsCapability`、各 domain 类型。

---

## 10. 依赖的特性/接口/类

`OsProfile`、`OsInfo`、`OsCapability`、`CpuTopology`、`CpuAffinity`、`PhysicalMemory`、
`HardwareInventory`、`StorageInventory`、`GpuAdapter`、`FirewallController`、`ContainerHost`、
`VirtualizationHost`、`ServiceManager`、`SensorReading`、`Context`、`Error`。

---

## 11. 所有权与并发

协议实现可跨任务共享；服务方法可并发，但具体控制器可能限制并发（见各类型）。
`close` 可并发；关闭后服务方法 `Unavailable`；返回的控制器独立关闭。
相等：协议无值语义；实现身份由具体类决定。

---

## 12. 示例与反例

正确：

```xnull
OsHost host = Os.host()
defer { host.close() }
OsProfile profile = host.profile()
if profile.has(OsCapability.CpuTopology) {
    Result<CpuTopology, Error> topology = host.cpuTopology(ctx)
}
```

反例：把 `OsHost` 当全局单例；关闭后继续探测；不关闭控制器；用 `profile` 能力代替权限检查；
在 core 中依赖 `OsHost`。

---

## 13. 测试/场景义务

每个服务方法：有能/无能/无权限/取消/超时；宿主 close 幂等；关闭后 `Unavailable`；
控制器所有权；并发调用；fake host；服务器/WASM 能力矩阵。

---

## 14. XNull 伪代码

```xnull
protocol OsHost {
    OsProfile profile();
    Result<Unit, Error> close();
    Bool isOpen();

    Result<CpuTopology, Error> cpuTopology(Context context);
    Result<CpuAffinity, Error> cpuAffinity(Context context);
    Result<PhysicalMemory, Error> physicalMemory(Context context);
    Result<HardwareInventory, Error> hardwareInventory(Context context);
    Result<StorageInventory, Error> storageInventory(Context context);
    Result<List<GpuAdapter>, Error> gpuAdapters(Context context);
    Result<FirewallController, Error> firewall(Context context);
    Result<ContainerHost, Error> containers(Context context);
    Result<VirtualizationHost, Error> virtualization(Context context);
    Result<ServiceManager, Error> services(Context context);
    Result<List<SensorReading>, Error> sensors(Context context);
}
```
