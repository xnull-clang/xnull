# `NetServiceState`

| 项 | 值 |
| --- | --- |
| 类型 | `enum NetServiceState` |
| 包 | `xdk.net.service` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

网络服务实例的生命周期状态：已创建、启动中、运行、排空、已停止、失败、已关闭。

不做：OS 服务状态、进程状态、健康评分、连接状态、TLS 握手状态、客户端重连状态。

本类型与 [`xdk.os.service.NetServiceState`](../../platform/os/service/ServiceState.md) 同名但语义不同：后者是操作系统服务管理器（systemd/launchd/SCM）的观测快照，含 `Unknown`；本类型是 `xdk.net.service` 实例的内部生命周期，不含 `Unknown`。两者不得混用，导入时使用完整包名消歧。

---

## 2. 设计逻辑

- 只表达本地服务实例的粗粒度生命周期；不做平台映射。
- `Created` 是构造后的初始态；`Starting` 覆盖 bind/connect 与首次启动。
- `Running` 表示服务端正在接受或客户端已有活动连接。
- `Draining` 表示停止新工作并处理存量：服务端停止接受并排空活动会话；客户端在此态立即关闭连接，过渡很短。
- `Stopped` 表示干净停止，资源可能仍可 `close()`；可继续调用 `close()`。`Server`/`NetworkService` 不得从 `Stopped` 重新 serve/start；`Client` 允许在 `Stopped` 上重试 `connect`/`reconnect`。
- `Failed` 表示不可恢复的启动/运行失败；不允许回到 `Running`，只能 `close()`。
- `Closed` 是终态；`close()` 幂等，重复关闭保持 `Closed`。
- 值语义；成员固定，只允许追加；无载荷。

状态迁移：

| 起始 | 事件 | 目标 |
| --- | --- | --- |
| `Created` | 启动成功 | `Starting`（或直接 `Running`） |
| `Starting` | 绑定/连接/首个任务成功 | `Running` |
| `Starting` | 失败且未留下资源 | `Stopped`（允许重试） |
| `Starting` | 失败且资源已创建 | `Failed` |
| `Running` | 优雅停机开始 | `Draining` |
| `Running` | 立即关闭 | `Closed` |
| `Running` | 不可恢复错误 | `Failed` |
| `Draining` | 排空完成 | `Stopped` |
| `Draining` | 超时/取消后强制关闭 | `Stopped` |
| `Draining` | 立即关闭 | `Closed` |
| `Stopped` | 客户端重试 connect/reconnect | `Starting` |
| `Stopped` | 关闭资源 | `Closed` |
| `Failed` | 关闭资源 | `Closed` |
| `Closed` | 任意 | `Closed` |

不变量：迁移只能按表进行；`Closed` 后不再进入其他状态；`Failed` 不是重新启动入口；`Server`/`NetworkService` 不得从 `Stopped` 重启，`Client` 的 `Stopped` 允许连接重试。

---

## 3. 表示与不变量

| 成员 | 含义 |
| --- | --- |
| `Created` | 已构造，尚未绑定/连接/启动 |
| `Starting` | 绑定、连接或后台任务启动中 |
| `Running` | 服务端接受中，或客户端已连接 |
| `Draining` | 停止新工作；服务端排空，客户端立即关闭 |
| `Stopped` | 干净停止；资源可能尚未释放；客户端可重试连接 |
| `Failed` | 不可恢复失败；只能关闭 |
| `Closed` | 已关闭；终态 |

不变量：成员固定；只允许追加；无载荷；值语义；状态是本地快照，不是 OS 观测。

---

## 4. 生命周期

枚举值本身无生命周期；服务实例负责迁移。`NetServiceState` 值可长期保存用于日志/诊断，但过期快照不得当作当前状态。

---

## 5. 构造契约

枚举成员直接使用，无构造器。

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

枚举无实例方法；包级辅助函数如下。

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `serviceStateName` | 稳定小写名 | `NetServiceState state` | `String` | 无 |
| `serviceStateFromName` | 名称解析 | `String stateName` | `NetServiceState?` | 无；未知返回 null |
| `serviceStateIsTerminal` | 是否终态 | `NetServiceState state` | `Bool` | 无 |
| `serviceStateCanServe` | 是否可服务 | `NetServiceState state` | `Bool` | 无 |
| `serviceStateIsActive` | 是否活动/过渡 | `NetServiceState state` | `Bool` | 无 |

说明：

- 名称为稳定小写 ASCII，用于日志/诊断，不用于协议或持久化。
- `serviceStateIsTerminal` 仅 `Closed` 为 true；`Stopped`/`Failed` 仍需 `close()`。
- `serviceStateCanServe` 仅 `Running` 为 true；`Draining` 虽仍处理存量会话，但不再接受新连接。
- `serviceStateIsActive` 对 `Starting`、`Running`、`Draining` 为 true；用于判断是否需要等待/取消。
- 未知名称返回 null，不 panic，不映射到任意成员。

---

## 8. 使用的技术

- 简单枚举；
- 稳定名称映射；
- 状态迁移表；
- 稳定态/过渡态判定。

---

## 9. 需要的支撑

- 语言：enum、String、Bool、可空引用；
- 运行时：`toLowerAscii`；
- 接口：`NetworkService`、`Server`、`Client`。

---

## 10. 依赖的特性/接口/类

`NetworkService`、`Server`、`Client`、`toLowerAscii`。

---

## 11. 所有权与并发

值语义；无资源；可共享；可作 `Map` 键；无取消点。
相等：按枚举底层值比较。

---

## 12. 示例与反例

正确：`service.state() == NetServiceState.Running` 表示可接受；`Draining` 时只等待存量会话；`Stopped` 后再 `close()`。  
反例：把 `Stopped` 当终态而不 `close()`；从 `Failed` 直接重新 `startServer`；把本类型与 `xdk.os.service.NetServiceState` 混用；把 `Draining` 当“仍可接受新连接”。

---

## 13. 测试/场景义务

每个成员名称/解析；未知名称返回 null；终态/可服务/活动判定；完整迁移表；重复 `close` 保持 `Closed`；启动失败按宿主回退 `Created`（未进入 `Starting`）或 `Stopped`（已进入 `Starting`）与进入 `Failed` 的分支；服务端 `Stopped` 不可重新 serve；客户端 `Stopped` 可重试连接；服务端排空/超时/取消；客户端连接失败/关闭；与 `NetworkService.state()` 组合。

---

## 14. XNull 伪代码

```xnull
enum NetServiceState {
    Created,
    Starting,
    Running,
    Draining,
    Stopped,
    Failed,
    Closed,
}

String serviceStateName(NetServiceState state) {
    if state == NetServiceState.Created { return "created" }
    if state == NetServiceState.Starting { return "starting" }
    if state == NetServiceState.Running { return "running" }
    if state == NetServiceState.Draining { return "draining" }
    if state == NetServiceState.Stopped { return "stopped" }
    if state == NetServiceState.Failed { return "failed" }
    return "closed"
}

NetServiceState? serviceStateFromName(String stateName) {
    if stateName == null { return null }
    String normalized = toLowerAscii(stateName.trim())
    if normalized == "created" { return NetServiceState.Created }
    if normalized == "starting" { return NetServiceState.Starting }
    if normalized == "running" { return NetServiceState.Running }
    if normalized == "draining" { return NetServiceState.Draining }
    if normalized == "stopped" { return NetServiceState.Stopped }
    if normalized == "failed" { return NetServiceState.Failed }
    if normalized == "closed" { return NetServiceState.Closed }
    return null
}

Bool serviceStateIsTerminal(NetServiceState state) {
    return state == NetServiceState.Closed
}

Bool serviceStateCanServe(NetServiceState state) {
    return state == NetServiceState.Running
}

Bool serviceStateIsActive(NetServiceState state) {
    return state == NetServiceState.Starting
        || state == NetServiceState.Running
        || state == NetServiceState.Draining
}
```
