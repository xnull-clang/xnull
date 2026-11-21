# `IoModel`

| 项 | 值 |
| --- | --- |
| 类型 | `enum IoModel` |
| 包 | `xdk.meta` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

能力画像对 I/O 调度方式的偏好：阻塞、每连接一线程/任务、事件驱动或混合。

不做：实际调度器实现、线程池配置、协议选择、网络 API。

---

## 2. 设计逻辑

- 这是**偏好**，不是实现承诺；实际实现必须在网络包文档中声明采用哪种模型。
- 客户端通常 `Blocking`；服务器可选 `EventDriven`/`ThreadPerConnection`/`Hybrid`。
- 模型影响 `ResourceLimits` 的默认值与关闭策略，但不改变 `Reader/Writer` 合同。
- 不允许应用在运行时切换模型；需要不同模型时创建不同 `CoreProfile`。

---

## 3. 表示与不变量

| 成员 | 含义 | 典型场景 |
| --- | --- | --- |
| `Blocking` | 每个操作阻塞当前任务 | 客户端、工具、简单服务 |
| `ThreadPerConnection` | 每连接一个任务/线程 | 中小服务器、协议网关 |
| `EventDriven` | 单/少事件循环 + 回调/任务 | 高连接数服务器、代理 |
| `Hybrid` | 事件循环 + 工作池 | 混合负载 |

不变量：成员固定；只允许追加；值语义；可作 `Map`/`Set` 键。

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
| `ioModelName` | 稳定小写名 | `IoModel model` | `String` | 无 |
| `ioModelFromName` | 名称解析（大小写不敏感） | `String name` | `IoModel?` | 无；未知返回 null |
| `ioModelSupportsBlocking` | 是否允许阻塞调用 | `IoModel model` | `Bool` | 无 |

---

## 8. 使用的技术

- 简单枚举；
- 名称映射；
- 与 `CoreProfile`/`ResourceLimits` 组合。

---

## 9. 需要的支撑

- 语言：enum、String、Bool；
- 运行时：无；
- 接口：`CoreProfile`。

---

## 10. 依赖的特性/接口/类

`CoreProfile`、`ResourceLimits`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。

---

## 12. 示例与反例

正确：服务器画像选择 `EventDriven`，并在 `HttpServerOptions` 中声明连接上限。  
反例：把 `EventDriven` 当性能保证；在 UI 线程使用 `Blocking` 做长请求；运行时切换模型。

---

## 13. 测试/场景义务

每个成员名称/解析；阻塞兼容性；客户端/服务器默认画像；未知名称；混合模型配置。

---

## 14. XNull 伪代码

```xnull
enum IoModel {
    Blocking,
    ThreadPerConnection,
    EventDriven,
    Hybrid,
}

String ioModelName(IoModel model) {
    if model == IoModel.Blocking { return "blocking" }
    if model == IoModel.ThreadPerConnection { return "thread_per_connection" }
    if model == IoModel.EventDriven { return "event_driven" }
    return "hybrid"
}

IoModel? ioModelFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "blocking" { return IoModel.Blocking }
    if normalized == "thread_per_connection" { return IoModel.ThreadPerConnection }
    if normalized == "event_driven" { return IoModel.EventDriven }
    if normalized == "hybrid" { return IoModel.Hybrid }
    return null
}

Bool ioModelSupportsBlocking(IoModel model) {
    if model == IoModel.EventDriven { return false }
    return true
}
```
