# `ServiceState`

| 项 | 值 |
| --- | --- |
| 类型 | `enum ServiceState` |
| 包 | `xdk.os.service` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

系统服务生命周期状态：运行、停止、启动中、停止中、失败、未知。

不做：进程状态、服务健康、开机启用状态、依赖排序、退出码解释。

---

## 2. 设计逻辑

- 只表达 OS 适配器观察到的粗粒度状态；不承诺与进程表一一对应。
- `Running`/`Stopped`/`Failed` 是稳定观测；`Starting`/`Stopping` 是过渡态；`Unknown` 表示无法判定。
- 开机启用是 `ServiceInfo.isEnabled`，不是 `ServiceState` 的成员。
- `Failed` 表示 OS 报告失败状态；进程一次退出不一定进入 `Failed`。
- 值语义；成员固定，只允许追加；未知平台映射到 `Unknown`，不 panic。

---

## 3. 表示与不变量

| 成员 | 含义 |
| --- | --- |
| `Running` | 正在运行/active |
| `Stopped` | 已停止/inactive/未加载 |
| `Starting` | 启动请求已提交，尚未进入 `Running` |
| `Stopping` | 停止请求已提交，尚未进入 `Stopped` |
| `Failed` | OS 报告失败状态 |
| `Unknown` | 无法判定、不可读或平台不提供 |

不变量：成员固定；只允许追加；无载荷；值语义；状态是观测快照，不是控制命令。

---

## 4. 生命周期

值类型；无构造器、无 close；可共享。

---

## 5. 构造契约

枚举项直接使用，无构造器。

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

枚举无实例方法；包级辅助函数如下。

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `serviceStateName` | 稳定小写名 | `ServiceState state` | `String` | 无 |
| `serviceStateFromName` | 名称解析 | `String stateName` | `ServiceState?` | 无；未知返回 null |
| `serviceStateIsStable` | 是否稳定观测 | `ServiceState state` | `Bool` | 无 |

说明：

- 名称为稳定小写 ASCII，不做本地化；用于日志/诊断，不用于持久化协议。
- `Running`/`Stopped`/`Failed` 为稳定观测；`Starting`/`Stopping`/`Unknown` 不是。
- `Unknown` 必须重新查询，不得当作 `Stopped` 或 `Running`。

---

## 8. 使用的技术

- 简单枚举；
- 名称映射；
- 稳定态判定。

---

## 9. 需要的支撑

- 语言：enum、String、Bool；
- 运行时：无；
- 接口：`ServiceInfo`、`ServiceManager`。

---

## 10. 依赖的特性/接口/类

`ServiceInfo`、`ServiceManager`、`OsHost`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。
相等：按枚举底层值比较；可作 `Map` 键。

---

## 12. 示例与反例

正确：`info.state() == ServiceState.Running`；`Unknown` 时重新查询；用 `serviceStateIsStable` 判断是否稳定观测，`Unknown` 仍需重新查询。  
反例：把 `Unknown` 当 `Stopped`；用 `state` 推断开机启用；把 `Failed` 当进程退出码；应用扩展枚举。

---

## 13. 测试/场景义务

每个成员名称/解析/稳定态；未知名称；`Unknown` 不 panic；systemd/launchd/SCM 状态映射；
`Running`/`Stopped`/`Starting`/`Stopping`/`Failed` 过渡；与 `ServiceInfo`/`ServiceManager` 组合。

---

## 14. XNull 伪代码

非可执行设计伪代码。

```xnull
enum ServiceState {
    Running,
    Stopped,
    Starting,
    Stopping,
    Failed,
    Unknown,
}

String serviceStateName(ServiceState state) {
    if state == ServiceState.Running { return "running" }
    if state == ServiceState.Stopped { return "stopped" }
    if state == ServiceState.Starting { return "starting" }
    if state == ServiceState.Stopping { return "stopping" }
    if state == ServiceState.Failed { return "failed" }
    return "unknown"
}

ServiceState? serviceStateFromName(String stateName) {
    if stateName == null { return null }
    String normalized = stateName.trim().toLower()
    if normalized == "running" { return ServiceState.Running }
    if normalized == "stopped" { return ServiceState.Stopped }
    if normalized == "starting" { return ServiceState.Starting }
    if normalized == "stopping" { return ServiceState.Stopping }
    if normalized == "failed" { return ServiceState.Failed }
    if normalized == "unknown" { return ServiceState.Unknown }
    return null
}

Bool serviceStateIsStable(ServiceState state) {
    if state == ServiceState.Running { return true }
    if state == ServiceState.Stopped { return true }
    if state == ServiceState.Failed { return true }
    return false
}
```
