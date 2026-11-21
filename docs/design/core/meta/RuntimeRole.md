# `RuntimeRole`

| 项 | 值 |
| --- | --- |
| 类型 | `enum RuntimeRole` |
| 包 | `xdk.meta` |
| 稳定性 | `stable` |
| 依赖 | 无 |

---

## 1. 定位

程序在构建时的角色标记：客户端、服务器、工具或库。角色决定默认能力集合、资源上限、
I/O 偏好和关闭策略，不决定运行时权限。

不做：用户身份、部署环境、进程权限、租户、许可证。

---

## 2. 设计逻辑

- 角色是**构建/装配期**概念；进程启动后只读。
- 一个可执行程序只有一个主角色；库本身是 `Library`，由宿主决定最终角色。
- 角色不替代 `Capability`：角色给默认值，能力给精确允许项。
- 角色不替代运行时探测：目标不支持时仍返回 `Unsupported`/`Network`。
- `xdk.meta` 不依赖其他包；角色名称由本包顶层函数提供。

---

## 3. 表示与不变量

| 成员 | 含义 | 默认 I/O | 默认关闭 |
| --- | --- | --- | --- |
| `Client` | 出站客户端/SDK | `Blocking` | `Immediate` |
| `Server` | 长期运行的服务/代理 | `EventDriven` | `Deadline` |
| `Tool` | 一次性命令行/批处理 | `Blocking` | `Immediate` |
| `Library` | 被嵌入的库 | `Blocking` | `Immediate` |

不变量：成员固定；只允许追加；值语义；可比较；可作 `Map`/`Set` 键。

---

## 4. 生命周期

值类型；无构造器、无 close；可跨任务只读共享。

---

## 5. 构造契约

枚举项直接使用，无构造器。

---

## 6. 字段表

无实例字段。

---

## 7. 方法面

`RuntimeRole` 没有实例方法。名称与解析由 `xdk.meta` 顶层函数提供：

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `runtimeRoleName` | 稳定小写名 | `RuntimeRole role` | `String` | 无 |
| `runtimeRoleDisplayName` | 显示名 | `RuntimeRole role` | `String` | 无 |
| `runtimeRoleFromName` | 名称解析（大小写不敏感） | `String name` | `RuntimeRole?` | 无；未知返回 null |

---

## 8. 使用的技术

- 简单枚举；
- 字符串名称映射；
- 与 `Capability`/`CoreProfile` 组合。

---

## 9. 需要的支撑

- 语言：enum、String、Bool；
- 运行时：无；
- 接口：`Capability`、`CoreProfile`。

---

## 10. 依赖的特性/接口/类

`Capability`、`CoreProfile`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。

---

## 12. 示例与反例

正确：`CoreProfile.server()` 使用 `RuntimeRole.Server` 默认值。  
反例：把 `Client` 当权限系统；在运行时把 `Server` 改成 `Client`；一个进程同时声明两个主角色。

---

## 13. 测试/场景义务

每个成员名称/显示名；大小写不敏感解析；未知名称返回 null；客户端/服务器默认画像；
工具/库默认画像；枚举 switch 穷尽性。

---

## 14. XNull 伪代码

```xnull
enum RuntimeRole {
    Client,
    Server,
    Tool,
    Library,
}

String runtimeRoleName(RuntimeRole role) {
    if role == RuntimeRole.Client { return "client" }
    if role == RuntimeRole.Server { return "server" }
    if role == RuntimeRole.Tool { return "tool" }
    return "library"
}

String runtimeRoleDisplayName(RuntimeRole role) {
    if role == RuntimeRole.Client { return "Client" }
    if role == RuntimeRole.Server { return "Server" }
    if role == RuntimeRole.Tool { return "Tool" }
    return "Library"
}

RuntimeRole? runtimeRoleFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "client" { return RuntimeRole.Client }
    if normalized == "server" { return RuntimeRole.Server }
    if normalized == "tool" { return RuntimeRole.Tool }
    if normalized == "library" { return RuntimeRole.Library }
    return null
}
```
