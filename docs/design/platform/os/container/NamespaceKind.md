# `NamespaceKind`

| 项 | 值 |
| --- | --- |
| 类型 | `enum NamespaceKind` |
| 包 | `xdk.os.container` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

Linux namespace 类型分类：PID、挂载、网络、用户、UTS、IPC、cgroup、时间、其他。

不做：namespace 创建/进入、隔离策略、权限模型、cgroup 控制。

---

## 2. 设计逻辑

- 只区分 namespace 的**内核对象类型**；具体标识与可见性由 `Namespace` 承载。
- 成员对应 Linux `CLONE_NEW*` 语义；非 Linux 平台不定义新成员，适配器返回 `Unsupported` 或不填充快照。
- `Other` 是合法值：未知/新增 namespace 类型映射到 `Other`，不 panic、不猜测。
- 值语义；可作 `Map`/`Set` 键；成员固定，只允许追加。
- 名称映射使用稳定小写名；显示名不进入协议。

---

## 3. 表示与不变量

| 成员 | 含义 | Linux 线索 |
| --- | --- | --- |
| `Pid` | PID namespace | `pid` |
| `Mount` | 挂载 namespace | `mnt` |
| `Network` | 网络 namespace | `net` |
| `User` | 用户 namespace | `user` |
| `Uts` | UTS（主机名/域名） | `uts` |
| `Ipc` | System V IPC/POSIX 消息队列 | `ipc` |
| `Cgroup` | cgroup namespace | `cgroup` |
| `Time` | 时间 namespace | `time` |
| `Other` | 其他/未知 | 适配器自定义 |

不变量：成员固定；只允许追加；值语义；`Other` 不携带额外语义。

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

枚举无实例方法；以下为包级辅助函数。

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `namespaceKindName` | 稳定小写名 | `NamespaceKind kind` | `String` | 无 |
| `namespaceKindFromName` | 名称解析 | `String name` | `NamespaceKind?` | 无；null/未知返回 null |

`namespaceKindName` 返回 `pid`/`mount`/`network`/`user`/`uts`/`ipc`/`cgroup`/`time`/`other`；
`namespaceKindFromName` 同时接受 `mnt` 与 `net` 别名，大小写不敏感。

---

## 8. 使用的技术

- 简单枚举；
- 名称映射；
- Linux namespace 分类。

---

## 9. 需要的支撑

- 语言：enum、String；
- 运行时：无；
- 接口：`Namespace`、`ContainerInfo`。

---

## 10. 依赖的特性/接口/类

`Namespace`、`ContainerInfo`、`ContainerHost`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。
相等：按枚举底层值比较；可作 `Map` 键。

---

## 12. 示例与反例

正确：`namespace.kind() == NamespaceKind.Pid`；日志用 `namespaceKindName(kind)`。  
反例：把 `Other` 当错误；用字符串比较代替枚举；假设所有平台都有 `Time` namespace。

---

## 13. 测试/场景义务

每个成员名称/解析；`mnt`/`net` 别名；大小写与空白；未知名称；null；`Other`；
与 `Namespace`/`ContainerInfo` 组合；非 Linux 适配器不返回伪成员。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
enum NamespaceKind {
    Pid,
    Mount,
    Network,
    User,
    Uts,
    Ipc,
    Cgroup,
    Time,
    Other,
}

String namespaceKindName(NamespaceKind kind) {
    if kind == NamespaceKind.Pid { return "pid" }
    if kind == NamespaceKind.Mount { return "mount" }
    if kind == NamespaceKind.Network { return "network" }
    if kind == NamespaceKind.User { return "user" }
    if kind == NamespaceKind.Uts { return "uts" }
    if kind == NamespaceKind.Ipc { return "ipc" }
    if kind == NamespaceKind.Cgroup { return "cgroup" }
    if kind == NamespaceKind.Time { return "time" }
    return "other"
}

NamespaceKind? namespaceKindFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "pid" { return NamespaceKind.Pid }
    if normalized == "mount" || normalized == "mnt" {
        return NamespaceKind.Mount
    }
    if normalized == "network" || normalized == "net" {
        return NamespaceKind.Network
    }
    if normalized == "user" { return NamespaceKind.User }
    if normalized == "uts" { return NamespaceKind.Uts }
    if normalized == "ipc" { return NamespaceKind.Ipc }
    if normalized == "cgroup" { return NamespaceKind.Cgroup }
    if normalized == "time" { return NamespaceKind.Time }
    if normalized == "other" { return NamespaceKind.Other }
    return null
}
```
