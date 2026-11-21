# `ServiceManager`

| 项 | 值 |
| --- | --- |
| 类型 | `class ServiceManager` |
| 包 | `xdk.os.service` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Error`、`ServiceInfo`、`ServiceState` |

---

## 1. 定位

系统服务控制器：枚举服务、查询状态、启动、停止、重启、设置开机启用、关闭；适配 systemd、launchd、Windows SCM。

不做：服务编排、容器编排、进程守护、日志采集、unit/plist 写入、任意命令执行、环境变量/命令行检查、依赖排序、健康检查。

---

## 2. 设计逻辑

- 由 `OsHost.services(context)` 返回；调用前先检查 `OsCapability.ServiceManager`。
- 持有不透明 `Long` 句柄；句柄由适配器解释；公开 API 不暴露 fd/指针/OS 对象。
- 启动/停止/重启/启用通常需要管理员/root；`PermissionDenied` 不重试、不提权。
- 所有接收服务名的方法使用 `serviceName`，进入适配器前做白名单校验；禁止 shell 拼接。
- 只提供类型化动词；不提供命令/参数入口；不写 unit/plist。
- `start` 成功表示观察到 `Running`；`stop` 成功表示观察到 `Stopped`；`restart` 先停后启；`enable` 只持久化开机启用，不启动。
- 已是目标状态时幂等成功；过渡态等待目标或 `Context` 取消/超时。
- `services`/`status` 每次查询 OS，不缓存；`ServiceInfo` 是快照。
- 写操作可能长时间阻塞；`Context` 可取消，但 OS 操作可能已提交。
- `close` 幂等；关闭后除 `isOpen`（false）与重复 `close`（`Ok(unit)`）外的操作返回 `Unavailable`。
- 写操作必须审计；不记录环境变量、密钥、完整命令行。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_handle` | `Long` | final | >0；不透明；适配器解释 |
| `_open` | `Bool` | 内部 | 初始 true；close 后 false |

不变量：`handle > 0`；不暴露原始句柄；`close` 后 `_open == false`；`close` 幂等；
不缓存 `ServiceInfo`；不提供全局注册表；所有名称参数在边界校验。

---

## 4. 生命周期

由 `OsHost.services` 创建并转移给调用方；调用方持有并 `close()`；`OsHost` 不替调用方关闭。
`close` 幂等；无 finalizer 依赖；关闭后除 `isOpen`（false）与重复 `close`（`Ok(unit)`）外的操作 `Unavailable`；进程退出时 OS 回收句柄，但设计仍要求显式关闭。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ServiceManager(Long handle)` | handle | >0 | ≤0 → panic |

说明：构造器主要供宿主/适配器/测试使用；业务代码通过 `OsHost.services` 获取。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `services` | 服务列表快照 | `Context context` | `Result<List<ServiceInfo>, Error>` | `Unsupported`/`PermissionDenied`/`Cancelled`/`Timeout`/`Unavailable`/`Io` |
| `status` | 单个服务快照 | `Context context, String serviceName` | `Result<ServiceInfo, Error>` | 同上 + `InvalidArgument`/`NotFound` |
| `start` | 启动并等待 Running | `Context context, String serviceName` | `Result<Unit, Error>` | 同上 + `InvalidArgument`/`NotFound`/`Unavailable` |
| `stop` | 停止并等待 Stopped | `Context context, String serviceName` | `Result<Unit, Error>` | 同上 |
| `restart` | 先停后启并等待 Running | `Context context, String serviceName` | `Result<Unit, Error>` | 同上 |
| `enable` | 设置开机启用 | `Context context, String serviceName, Bool isEnabled` | `Result<Unit, Error>` | 同上 |
| `close` | 关闭控制器 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 |

操作语义：

| 方法 | 成功条件 | 已满足目标 |
| --- | --- | --- |
| `start` | 观察到 `Running` | `Running` → `Ok(unit)` |
| `stop` | 观察到 `Stopped` | `Stopped` → `Ok(unit)` |
| `restart` | 先 `stop` 后 `start`，观察到 `Running` | `Stopped` → 只 `start` |
| `enable` | OS 持久化目标启用值 | 已是目标值 → `Ok(unit)` |

规则：

- `context`/`serviceName` 为 null 是合同错误（panic）；随后检查 `_open`，关闭后返回 `Unavailable`；打开后非法名称返回 `InvalidArgument`。
- 名称必须非空、≤255，只允许 `[A-Za-z0-9_.@-]`；不拼接 shell；前导 `-` 由适配器用 OS API 或 `--` 安全传递。
- `services` 只返回名称合法的服务；空列表 = 支持但当前无可表示服务（可能全部被名称过滤）；顺序不承诺；无重复名称。
- `status` 每次查询 OS；未知服务 `NotFound`；`pid == 0` 表示未运行或未知；返回 `Failed` 状态是成功结果，不是错误。
- `start` 对 `Running` 幂等；对 `Starting` 等待 `Running`/`Failed`；对 `Stopping` 等待 `Stopped` 后启动；`Failed`/`Unknown` 尝试启动。
- `stop` 对 `Stopped` 幂等；对 `Stopping` 等待 `Stopped`；对 `Starting` 等待 `Running`/`Failed` 后停止；`Failed`/`Unknown` 尝试停止。
- `restart` 在 `Starting`/`Stopping` 时先等待 `Running`/`Stopped`/`Failed`（或 `Context` 限时）；`stop` 失败则不执行 `start`。
- `start` 期间服务进入 `Failed` → `Unavailable`；错误消息只含服务名/状态，不含环境或命令行。
- `start`/`stop`/`restart` 不改变 `isEnabled`；`enable` 不启动/停止服务；`isEnabled=false` 禁用开机启动；幂等。
- `close` 先置 `_open=false`，再调用适配器释放；适配器失败只返回 `Io` 诊断；重复 `close` 返回 `Ok(unit)`。
- 取消/超时不保证 OS 未提交；调用方应重新 `status` 确认。

错误映射：

| 情况 | 错误 |
| --- | --- |
| 能力不存在/适配器不支持 | `Unsupported` |
| 名称非法 | `InvalidArgument` |
| 服务不存在 | `NotFound` |
| 无管理员/root 权限 | `PermissionDenied` |
| `Context` 取消 | `Cancelled` |
| 截止时间到 | `Timeout` |
| 控制器已关闭/`start`/`restart` 期间服务进入失败 | `Unavailable` |
| OS/适配器调用失败 | `Io` |

不重试 `PermissionDenied`；不自动提权；错误详情不含原始命令/环境/密钥。

---

## 8. 使用的技术

- 不透明句柄；
- 名称白名单校验；
- 状态等待与幂等；
- Context/Result；
- 幂等关闭；
- 写操作审计；
- 平台适配器（systemd/launchd/SCM）。

---

## 9. 需要的支撑

- 语言：class、final 字段、Long、Bool、String、Int、List、Result、Context；
- 运行时/适配器：
  - `serviceListRaw(Context context, Long handle)` → `Result<List<ServiceInfo>, Error>`；枚举、去重并过滤非白名单名称；
  - `serviceStatusRaw(Context context, Long handle, String serviceName)` → `Result<ServiceInfo, Error>`；映射 `NotFound`；
  - `serviceStartRaw(Context context, Long handle, String serviceName)` → `Result<Unit, Error>`；启动并等待 `Running`，`Failed` → `Unavailable`；
  - `serviceStopRaw(Context context, Long handle, String serviceName)` → `Result<Unit, Error>`；停止并等待 `Stopped`；
  - `serviceRestartRaw(Context context, Long handle, String serviceName)` → `Result<Unit, Error>`；先停后启并等待 `Running`；
  - `serviceEnableRaw(Context context, Long handle, String serviceName, Bool isEnabled)` → `Result<Unit, Error>`；只持久化启用值；
  - `serviceCloseRaw(Long handle)` → `Result<Unit, Error>`；释放句柄；
  - 审计 sink（runtime/log）：记录动作/服务名/结果/时间，不记录环境/密钥/命令行；
- 接口：`Context`、`Error`、`BasicError`、`ErrorKind`、`ServiceInfo`、`ServiceState`、`OsHost`、`OsCapability`、`OsProfile`；
- 辅助函数：`isValidServiceName`（见 `ServiceInfo.md`）、`unavailableError`、`invalidServiceNameError`（本文件包内辅助函数）。

---

## 10. 依赖的特性/接口/类

`Context`、`Error`、`BasicError`、`ErrorKind`、`ServiceInfo`、`ServiceState`、`OsHost`、`OsCapability`、`OsProfile`、`isValidServiceName`、`unavailableError`、`invalidServiceNameError`、`serviceListRaw`、`serviceStatusRaw`、`serviceStartRaw`、`serviceStopRaw`、`serviceRestartRaw`、`serviceEnableRaw`、`serviceCloseRaw`。

---

## 11. 所有权与并发

引用语义；调用方持有控制器；不共享所有权；无全局注册表；持有期间必须 `close()`。
方法可并发调用；OS 可能串行化同一服务的操作；`close` 可与其他方法并发；并发 `close` 必须保证只调用一次适配器释放，其余调用返回 `Ok(unit)`；关闭后新操作 `Unavailable`，`isOpen` 返回 false，重复 `close` 返回 `Ok(unit)`；
已进入适配器的调用可能完成、失败或取消，调用方应在 `close` 前停止发起新操作。
不重入；无回调；不缓存服务状态；`_open` 的实现必须保证跨线程可见（互斥或原子）。
相等：引用身份；不推荐作 `Map` 键；按服务名索引时使用 `ServiceInfo.name`。

---

## 12. 示例与反例

正确：先 `profile.has(OsCapability.ServiceManager)`；`host.services(context)` 成功后调用 `manager.start(context, "nginx.service")`；
成功表示观察到 `Running`；随后 `manager.status(context, "nginx.service")` 确认；最后 `manager.close()`。
安装器：`manager.enable(context, "agent.service", true)`；失败时 `manager.enable(context, "agent.service", false)` 回滚启用，必要时再 `stop`。

反例：把 `"nginx; rm -rf /"` 当服务名（`InvalidArgument`）；以为 `enable` 会启动服务；以为 `start` 会开机启用；
写 unit/plist；用 shell 执行 `systemctl` 字符串；`PermissionDenied` 后提权重试；记录服务环境变量/命令行；
关闭后继续调用；`Running` 时断言 `pid() > 0`；用 `displayName` 作控制键。

---

## 13. 测试/场景义务

能力缺失 → `Unsupported`；无权限 → `PermissionDenied`；空列表；`status` 存在/不存在；`NotFound`；
非法名称（空、256 字符、空格、`/`、`\`、`;`、`$`、反引号、换行、非 ASCII）；前导 `-` 名称的安全传递；
关闭后非法名称也返回 `Unavailable`（null 仍 panic）；
`start` 已运行/启动中/停止中/失败/未知；`stop` 已停止/停止中/启动中；`restart` 运行/停止；
`enable(true/false)` 幂等且不启动；`close` 幂等；关闭后除 `isOpen`/重复 `close` 外全部 `Unavailable`；关闭失败只诊断；
取消/超时；并发调用；审计记录且无环境/密钥/命令行；列表名称全部合法且无重复；
`pid == 0`；状态映射；适配器不回显原始命令。

---

## 14. XNull 伪代码

非可执行设计伪代码。

```xnull
class ServiceManager {
    final Long _handle
    Bool _open

    ServiceManager(Long handle) {
        if handle <= 0 { throw "ServiceManager: invalid handle" }
        _handle = handle
        _open = true
    }

    Result<List<ServiceInfo>, Error> services(Context context) {
        if context == null { throw "ServiceManager.services: null context" }
        if !_open { return Err(unavailableError("service manager")) }
        return serviceListRaw(context, _handle)
    }

    Result<ServiceInfo, Error> status(Context context, String serviceName) {
        if context == null || serviceName == null {
            throw "ServiceManager.status: null argument"
        }
        if !_open { return Err(unavailableError("service manager")) }
        if !isValidServiceName(serviceName) {
            return Err(invalidServiceNameError())
        }
        return serviceStatusRaw(context, _handle, serviceName)
    }

    Result<Unit, Error> start(Context context, String serviceName) {
        if context == null || serviceName == null {
            throw "ServiceManager.start: null argument"
        }
        if !_open { return Err(unavailableError("service manager")) }
        if !isValidServiceName(serviceName) {
            return Err(invalidServiceNameError())
        }
        return serviceStartRaw(context, _handle, serviceName)
    }

    Result<Unit, Error> stop(Context context, String serviceName) {
        if context == null || serviceName == null {
            throw "ServiceManager.stop: null argument"
        }
        if !_open { return Err(unavailableError("service manager")) }
        if !isValidServiceName(serviceName) {
            return Err(invalidServiceNameError())
        }
        return serviceStopRaw(context, _handle, serviceName)
    }

    Result<Unit, Error> restart(Context context, String serviceName) {
        if context == null || serviceName == null {
            throw "ServiceManager.restart: null argument"
        }
        if !_open { return Err(unavailableError("service manager")) }
        if !isValidServiceName(serviceName) {
            return Err(invalidServiceNameError())
        }
        return serviceRestartRaw(context, _handle, serviceName)
    }

    Result<Unit, Error> enable(Context context, String serviceName,
                               Bool isEnabled) {
        if context == null || serviceName == null {
            throw "ServiceManager.enable: null argument"
        }
        if !_open { return Err(unavailableError("service manager")) }
        if !isValidServiceName(serviceName) {
            return Err(invalidServiceNameError())
        }
        return serviceEnableRaw(context, _handle, serviceName, isEnabled)
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        return serviceCloseRaw(_handle)
    }

    Bool isOpen() { return _open }
}

Error invalidServiceNameError() {
    return new BasicError(ErrorKind.InvalidArgument, "invalid service name")
}
```
