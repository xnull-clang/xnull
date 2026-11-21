# `HealthState`

| 项 | 值 |
| --- | --- |
| 类型 | `enum HealthState` |
| 包 | `xdk.runtime` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

健康/就绪状态：启动中、健康、降级、不健康、停止中、已停止。

不做：HTTP 健康端点、指标导出、告警、依赖注入。

---

## 2. 设计逻辑

- 状态是**快照值**，不是控制器；由 `HealthReport` 携带。
- 顺序固定，只允许追加；`healthStateRank` 用于聚合取最严重状态。
- `isReady` 与 `isHealthy` 分开：降级仍可服务，未健康/停止不可服务。
- 不把错误分类塞进枚举；具体错误在 `HealthReport.message/details`。
- 可作 `Map`/`Set` 键；值语义。

---

## 3. 表示与不变量

| 成员 | 含义 | rank | ready |
| --- | --- | --- | --- |
| `Healthy` | 正常 | 0 | true |
| `Degraded` | 降级但可服务 | 1 | true |
| `Starting` | 启动中 | 2 | false |
| `Stopping` | 停止中 | 3 | false |
| `Stopped` | 已停止 | 4 | false |
| `Unhealthy` | 不可服务 | 5 | false |

不变量：成员固定；只允许追加；rank 唯一；值语义。

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

## 7. 方法面

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `healthStateName` | 稳定小写名 | `HealthState state` | `String` | 无 |
| `healthStateFromName` | 名称解析 | `String name` | `HealthState?` | 无；未知返回 null |
| `healthStateRank` | 严重度 | `HealthState state` | `Int` | 无 |
| `healthStateIsHealthy` | 是否健康 | `HealthState state` | `Bool` | 无 |
| `healthStateIsReady` | 是否可服务 | `HealthState state` | `Bool` | 无 |
| `healthStateIsTerminal` | 是否终态 | `HealthState state` | `Bool` | 无 |

---

## 8. 使用的技术

- 简单枚举；
- 名称/严重度映射；
- 聚合比较。

---

## 9. 需要的支撑

- 语言：enum、String、Int、Bool；
- 运行时：无；
- 接口：`HealthReport`、`HealthRegistry`。

---

## 10. 依赖的特性/接口/类

`HealthReport`、`HealthRegistry`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。
相等：按枚举底层值比较；可作 `Map` 键。

---

## 12. 示例与反例

正确：`healthStateIsReady(HealthState.Degraded)` 为 true。  
反例：把 `Degraded` 当不可服务；把 `Stopped` 当健康；应用扩展枚举。

---

## 13. 测试/场景义务

每个成员名称/解析；rank 顺序；healthy/ready/terminal；未知名称；聚合比较。

---

## 14. XNull 伪代码

```xnull
enum HealthState {
    Healthy,
    Degraded,
    Starting,
    Stopping,
    Stopped,
    Unhealthy,
}

String healthStateName(HealthState state) {
    if state == HealthState.Healthy { return "healthy" }
    if state == HealthState.Degraded { return "degraded" }
    if state == HealthState.Starting { return "starting" }
    if state == HealthState.Stopping { return "stopping" }
    if state == HealthState.Stopped { return "stopped" }
    return "unhealthy"
}

HealthState? healthStateFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "healthy" { return HealthState.Healthy }
    if normalized == "degraded" { return HealthState.Degraded }
    if normalized == "starting" { return HealthState.Starting }
    if normalized == "stopping" { return HealthState.Stopping }
    if normalized == "stopped" { return HealthState.Stopped }
    if normalized == "unhealthy" { return HealthState.Unhealthy }
    return null
}

Int healthStateRank(HealthState state) {
    if state == HealthState.Healthy { return 0 }
    if state == HealthState.Degraded { return 1 }
    if state == HealthState.Starting { return 2 }
    if state == HealthState.Stopping { return 3 }
    if state == HealthState.Stopped { return 4 }
    return 5
}

Bool healthStateIsHealthy(HealthState state) {
    return state == HealthState.Healthy
}

Bool healthStateIsReady(HealthState state) {
    return state == HealthState.Healthy || state == HealthState.Degraded
}

Bool healthStateIsTerminal(HealthState state) {
    return state == HealthState.Stopped
}
```
