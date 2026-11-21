# `FirewallDirection`

| 项 | 值 |
| --- | --- |
| 类型 | `enum FirewallDirection` |
| 包 | `xdk.os.firewall` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

防火墙规则的流量方向：进入本机、离开本机、双向。

不做：转发/路由、接口/zone、用户/组、连接状态、时间窗口、NAT。

---

## 2. 设计逻辑

- 方向以**本机**为参照，不以网卡或网络命名空间为参照。
- `Inbound` 匹配进入本机的流量；`Outbound` 匹配本机发起的流量。
- `Both` 表示一个逻辑规则同时覆盖两个方向；适配器可以展开为两条后端条目，但对调用方仍是一个规则 ID。
- 不设 `Forward`：路由器/网关/NAT 转发不属于基线；需要时走 X。
- `Both` 若无法被后端忠实表达，返回 `Unsupported`，不得只应用一个方向。
- 值语义；成员固定，只允许追加；可作 `Map`/`Set` 键。

---

## 3. 表示与不变量

| 成员 | 含义 | 端口语义 |
| --- | --- | --- |
| `Inbound` | 进入本机 | `localPort` 是本机目的端口 |
| `Outbound` | 离开本机 | `localPort` 是本机源端口 |
| `Both` | 双向 | 一个逻辑规则；两个方向都按本机/对端角色解释 |

不变量：成员固定；只允许追加；值语义；`Both` 不得只应用单方向。

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

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `firewallDirectionName` | 稳定小写名 | `FirewallDirection direction` | `String` | null → panic |
| `firewallDirectionFromName` | 名称解析 | `String name` | `FirewallDirection?` | 无；未知返回 null |

说明：

- 稳定名用于诊断/审计，不用于构造规则表达式。
- `firewallDirectionFromName` 只接受 `inbound`、`outbound`、`both`；大小写不敏感。
- 未知名称返回 null；不得默认成 `Inbound`，避免把出站规则误当入站规则。

---

## 8. 使用的技术

- 简单枚举；
- 名称映射；
- 方向语义。

---

## 9. 需要的支撑

- 语言：enum、String；
- 运行时：无；
- 接口：`FirewallRule`、`FirewallController`。

---

## 10. 依赖的特性/接口/类

`FirewallRule`、`FirewallController`、`FirewallStatus`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。
相等：按枚举底层值比较；可作 `Map` 键。

---

## 12. 示例与反例

正确：服务器只开放入站 443 时使用 `Inbound`；客户端出站限制使用 `Outbound`；需要对称规则时使用 `Both` 并确认后端支持。  
反例：把 `Both` 当两次独立 `apply`；用 `Outbound` 表达入站；假设 `Forward` 存在；用方向推断接口/zone。

---

## 13. 测试/场景义务

每个成员名称/解析；大小写不敏感；未知名称；入站/出站端口角色；
`Both` 展开与删除；后端不支持 `Both` 时 `Unsupported`；不得出现 `Forward` 成员。

---

## 14. XNull 伪代码

非可执行设计伪代码。

```xnull
enum FirewallDirection {
    Inbound,
    Outbound,
    Both,
}

String firewallDirectionName(FirewallDirection direction) {
    if direction == null { throw "firewallDirectionName: null direction" }
    if direction == FirewallDirection.Inbound { return "inbound" }
    if direction == FirewallDirection.Outbound { return "outbound" }
    return "both"
}

FirewallDirection? firewallDirectionFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "inbound" { return FirewallDirection.Inbound }
    if normalized == "outbound" { return FirewallDirection.Outbound }
    if normalized == "both" { return FirewallDirection.Both }
    return null
}
```
