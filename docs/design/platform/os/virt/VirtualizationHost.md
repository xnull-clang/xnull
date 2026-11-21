# `VirtualizationHost`

| 项 | 值 |
| --- | --- |
| 类型 | `class VirtualizationHost` |
| 包 | `xdk.os.virt` |
| 稳定性 | `preview` |
| 依赖 | `Hypervisor`、`VirtualMachine`、`Context`、`Error` |

---

## 1. 定位

虚拟化环境只读查询控制器：hypervisor 列表、VM 列表、当前 OS 是否在 VM 内、当前 hypervisor 名。

不做：创建/启动/停止/暂停/恢复 VM、快照/克隆/迁移、设备直通、虚拟磁盘/网络、hypervisor 管理 API。

---

## 2. 设计逻辑

- 由 `OsHost.virtualization(context)` 返回；持有不透明 `Long` 句柄；不暴露 fd/指针/管理连接。
- `hypervisors`/`virtualMachines` 首参 `Context`，可阻塞；`isVirtualized`/`hypervisorName` 是非阻塞进程级探测，无 `Context`。
- 失败通道：无能力/平台不支持 → `Unsupported`；管理面/VM 清单被拒 → `PermissionDenied`；
  取消 → `Cancelled`；关闭后列表查询 → `Unavailable`。
- `isVirtualized` 表示当前 OS 是否运行在 VM 内；无法判定时 false，不 panic。
- `hypervisorName` 是当前客户机 hypervisor 的稳定小写名；裸机/未知时为空串。
- 空列表表示“支持但当前无可见 hypervisor/VM”；`Unsupported` 表示能力不存在/平台不支持。
- 只读基线：不提供任何 VM 控制；生命周期/快照/迁移是 X/ecosystem。
- 关闭幂等：`close()` 第一次关闭句柄，后续返回 `Ok(unit)`；关闭失败只诊断，不改变已关闭状态。
- `isVirtualized`/`hypervisorName` 不依赖句柄；即使 `close()` 后仍返回进程级结果，便于诊断。
- 为什么是 class：持有不透明句柄与 open 状态；不是 protocol 因为公开面是具体控制器，平台适配器在 internal 实现。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_handle` | `Long` | final | >0；不透明 |
| `_open` | `Bool` | 内部 | 是否可用 |

不变量：`handle>0`；构造后 `open=true`；`close` 后 `open=false`；`close` 幂等；句柄不进入公开签名。

---

## 4. 生命周期

由 `OsHost.virtualization(context)` 或测试创建；调用方 `close()`；`close` 幂等；无 `deinit` 依赖。
关闭后 `hypervisors`/`virtualMachines` 返回 `Unavailable`；`isVirtualized`/`hypervisorName` 仍可调用。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `VirtualizationHost(Long handle)` | handle | >0 | ≤0 → panic |

构造器主要供宿主/测试使用；业务代码通过 `OsHost.virtualization` 获取。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `hypervisors` | hypervisor 快照 | `Context context` | `Result<List<Hypervisor>, Error>` | `Unsupported`/`PermissionDenied`/`Cancelled`；关闭后 `Unavailable` | 阻塞；O(n) 复制 |
| `virtualMachines` | VM 快照 | `Context context` | `Result<List<VirtualMachine>, Error>` | 同上 | 阻塞；O(n) 复制 |
| `isVirtualized` | 是否在 VM 内 | 无 | `Bool` | 无 | 进程级；不依赖句柄；无法判定时 false |
| `hypervisorName` | 当前 hypervisor 名 | 无 | `String` | 无 | 进程级；裸机/未知空串 |
| `close` | 关闭句柄 | 无 | `Result<Unit, Error>` | `Io`（诊断） | 幂等；重复关闭返回 `Ok(unit)` |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 | O(1) |

说明：

- 裸机：`isVirtualized=false`，`hypervisorName=""`；`hypervisors` 可返回本机宿主 hypervisor（`isHost=true`），也可为空。
- 客户机：`isVirtualized=true`，`hypervisorName` 为客户机 hypervisor 稳定名；`hypervisors` 可含 `isHost=false` 的条目。
- `PermissionDenied` 不重试、不提权；错误详情不含 VM 名称/磁盘/网络信息。
- VM/容器内只返回当前上下文可见的 VM；不承诺宿主全部 VM 或宿主总资源。

---

## 8. 使用的技术

- 不透明句柄；
- 平台适配器原语；
- `Context`/`Result` 失败通道；
- 幂等关闭；
- 只读快照。

---

## 9. 需要的支撑

- 语言：class、Long、Bool、String、Result、List；
- 运行时/适配器：`virtHypervisorsRaw`、`virtMachinesRaw`、`virtIsVirtualizedRaw`、
  `virtHypervisorNameRaw`、`virtCloseRaw`；
- 接口：`Context`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`Hypervisor`、`VirtualMachine`、`OsHost`、`Context`、`Error`。

---

## 11. 所有权与并发

引用语义；控制器由调用方持有；`hypervisors`/`virtualMachines` 可并发，但平台适配器可能串行化；
`close` 可并发，关闭后列表查询 `Unavailable`；`isVirtualized`/`hypervisorName` 无状态、可并发。
相等：引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：先查 `OsProfile.has(OsCapability.Virtualization)`，再取 `VirtualizationHost`，用 `defer` 关闭；
用 `isVirtualized()` 调整时钟/许可策略；VM 内只把返回的 VM 当作当前可见资源。  
反例：手动构造句柄；close 后继续查询；把 `PermissionDenied` 当空列表；假设裸机列表为空；
把 VM 配置内存当宿主总量；把 `Unknown` 状态当停止；用 VM 名称做跨重启主键。

---

## 13. 测试/场景义务

裸机/客户机；KVM/Hyper-V/Xen/VMware/Parallels/QEMU TCG；空 hypervisor/VM 列表；
`isVirtualized` true/false；`hypervisorName` 裸机/客户机；平台不支持 `Unsupported`；
无权限 `PermissionDenied`；取消 `Cancelled`；close 幂等；关闭后 `Unavailable`；
进程级方法关闭后仍可调用；并发查询；raw close 失败只诊断；句柄 ≤0 panic。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class VirtualizationHost {
    final Long _handle
    Bool _open

    VirtualizationHost(Long handle) {
        if handle <= 0 { throw "VirtualizationHost: invalid handle" }
        _handle = handle
        _open = true
    }

    Result<List<Hypervisor>, Error> hypervisors(Context context) {
        if context == null { throw "VirtualizationHost.hypervisors: null context" }
        if !_open { return Err(unavailableError("virtualization host")) }
        return virtHypervisorsRaw(context, _handle)
    }

    Result<List<VirtualMachine>, Error> virtualMachines(Context context) {
        if context == null { throw "VirtualizationHost.virtualMachines: null context" }
        if !_open { return Err(unavailableError("virtualization host")) }
        return virtMachinesRaw(context, _handle)
    }

    Bool isVirtualized() {
        return virtIsVirtualizedRaw()
    }

    String hypervisorName() {
        return virtHypervisorNameRaw()
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        return virtCloseRaw(_handle)
    }

    Bool isOpen() { return _open }
}
```
