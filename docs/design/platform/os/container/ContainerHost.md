# `ContainerHost`

| 项 | 值 |
| --- | --- |
| 类型 | `class ContainerHost` |
| 包 | `xdk.os.container` |
| 稳定性 | `preview` |
| 依赖 | `ContainerInfo`、`Cgroup`、`Namespace`、`Context`、`Error` |

---

## 1. 定位

容器运行环境只读查询控制器：容器快照、cgroup 列表、namespace 列表、当前进程是否容器化。

不做：创建/启动/停止/销毁容器、exec/attach、镜像/编排、cgroup 写入/冻结/杀进程、namespace 进入。

---

## 2. 设计逻辑

- 由 `OsHost.containers(context)` 返回；持有不透明 `Long` 句柄；不暴露 fd/指针/路径句柄。
- `info`/`cgroups`/`namespaces` 首参 `Context`，可阻塞；`isContainerized` 是非阻塞进程级探测，无 `Context`。
- 失败通道：无能力/非 Linux/无适配器 → `Unsupported`；特权读取被拒 → `PermissionDenied`；
  取消 → `Cancelled`；关闭后查询 → `Unavailable`。
- 只读基线：不提供任何写操作；cgroup 冻结/杀进程、容器生命周期是 X/ecosystem。
- 关闭幂等：`close()` 第一次关闭句柄，后续返回 `Ok(unit)`；关闭失败只诊断，不改变已关闭状态。
- `isContainerized` 不依赖句柄；即使 `close()` 后仍返回进程级结果，便于诊断。
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

由 `OsHost.containers(context)` 或测试创建；调用方 `close()`；`close` 幂等；无 `deinit` 依赖。
关闭后 `info`/`cgroups`/`namespaces` 返回 `Unavailable`；`isContainerized` 仍可调用。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ContainerHost(Long handle)` | handle | >0 | ≤0 → panic |

构造器主要供宿主/测试使用；业务代码通过 `OsHost.containers` 获取。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `info` | 容器快照 | `Context context` | `Result<ContainerInfo, Error>` | `Unsupported`/`PermissionDenied`/`Cancelled`；关闭后 `Unavailable` | 阻塞；O(n) 快照 |
| `cgroups` | cgroup 快照 | `Context context` | `Result<List<Cgroup>, Error>` | 同上 | 阻塞；O(n) 复制 |
| `namespaces` | namespace 快照 | `Context context` | `Result<List<Namespace>, Error>` | 同上 | 阻塞；O(n) 复制 |
| `isContainerized` | 是否容器内 | 无 | `Bool` | 无 | 进程级；不依赖句柄；无法判定时 false |
| `close` | 关闭句柄 | 无 | `Result<Unit, Error>` | `Io`（诊断） | 幂等；重复关闭返回 `Ok(unit)` |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 | O(1) |

说明：

- 非容器 Linux：`info` 返回 `isContainerized=false`、`runtime="none"`、空列表；`cgroups`/`namespaces` 返回空列表。
- 非 Linux：容器语义不在基线，查询返回 `Unsupported`；`isContainerized` 返回 false。
- `PermissionDenied` 不重试、不提权；错误详情不含镜像/挂载/环境内容。
- 容器内只返回当前上下文可见的 cgroup/namespace；不承诺宿主全部。

---

## 8. 使用的技术

- 不透明句柄；
- 平台适配器原语；
- `Context`/`Result` 失败通道；
- 幂等关闭；
- 只读快照。

---

## 9. 需要的支撑

- 语言：class、Long、Bool、Result、List；
- 运行时/适配器：`containerInfoRaw`、`containerCgroupsRaw`、`containerNamespacesRaw`、
  `containerIsContainerizedRaw`、`containerCloseRaw`；
- 接口：`Context`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`ContainerInfo`、`Cgroup`、`Namespace`、`OsHost`、`Context`、`Error`。

---

## 11. 所有权与并发

引用语义；控制器由调用方持有；`info`/`cgroups`/`namespaces` 可并发，但平台适配器可能串行化；
`close` 可并发，关闭后查询 `Unavailable`；`isContainerized` 无状态、可并发。
相等：引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：先查 `OsProfile.has(OsCapability.Container)`，再取 `ContainerHost`，用 `defer` 关闭；
容器内只把返回的 cgroup/namespace 当作当前进程可见资源。  
反例：手动构造句柄；close 后继续查询；把 `PermissionDenied` 当空列表；假设非 Linux 可用；
把容器内 cgroup 当宿主全部；用容器 ID 做跨重启主键。

---

## 13. 测试/场景义务

容器/非容器；非 Linux `Unsupported`；无权限 `PermissionDenied`；取消 `Cancelled`；
`info` 空列表；`cgroups`/`namespaces` 空列表；close 幂等；关闭后 `Unavailable`；
`isContainerized` 关闭后仍可调用；并发查询；raw close 失败只诊断；句柄 ≤0 panic。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class ContainerHost {
    final Long _handle
    Bool _open

    ContainerHost(Long handle) {
        if handle <= 0 { throw "ContainerHost: invalid handle" }
        _handle = handle
        _open = true
    }

    Result<ContainerInfo, Error> info(Context context) {
        if context == null { throw "ContainerHost.info: null context" }
        if !_open { return Err(unavailableError("container host")) }
        return containerInfoRaw(context, _handle)
    }

    Result<List<Cgroup>, Error> cgroups(Context context) {
        if context == null { throw "ContainerHost.cgroups: null context" }
        if !_open { return Err(unavailableError("container host")) }
        return containerCgroupsRaw(context, _handle)
    }

    Result<List<Namespace>, Error> namespaces(Context context) {
        if context == null { throw "ContainerHost.namespaces: null context" }
        if !_open { return Err(unavailableError("container host")) }
        return containerNamespacesRaw(context, _handle)
    }

    Bool isContainerized() {
        return containerIsContainerizedRaw()
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        return containerCloseRaw(_handle)
    }

    Bool isOpen() { return _open }
}
```
