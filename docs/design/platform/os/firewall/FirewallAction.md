# `FirewallAction`

| 项 | 值 |
| --- | --- |
| 类型 | `enum FirewallAction` |
| 包 | `xdk.os.firewall` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

防火墙规则的最终处置动作：放行、静默丢弃、主动拒绝。

不做：日志动作、NAT/重定向、限速、标记、优先级、审计策略；这些属于上层策略或 X。

---

## 2. 设计逻辑

- 只表达“匹配后如何处置”，不承载平台动作位、规则表达式或命令文本。
- `Deny` 与 `Reject` 必须区分：前者静默丢弃，后者尽量返回拒绝响应（TCP RST 或 ICMP 不可达），便于对端快速失败。
- 不设 `Unknown`：后端存在无法映射的动作时，控制器返回 `Unsupported`，不得猜测为 `Allow`，也不得把 `Reject` 静默降级为 `Deny`。
- 默认拒绝心智：`Allow` 必须显式出现在规则里；API 不提供“全部放行”便捷方法。
- 值语义；成员固定，只允许追加；可作 `Map`/`Set` 键。

---

## 3. 表示与不变量

| 成员 | 含义 | 后端约束 |
| --- | --- | --- |
| `Allow` | 放行匹配流量 | 所有后端 |
| `Deny` | 静默丢弃，不返回响应 | 所有后端 |
| `Reject` | 丢弃并尽量返回拒绝响应 | 后端不支持主动拒绝时返回 `Unsupported` |

不变量：成员固定；只允许追加；值语义；`Reject` 不得被实现静默降级。

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
| `firewallActionName` | 稳定小写名 | `FirewallAction action` | `String` | null → panic |
| `firewallActionFromName` | 名称解析 | `String name` | `FirewallAction?` | 无；未知返回 null |

说明：

- 稳定名用于诊断/审计，不用于构造规则表达式。
- `firewallActionFromName` 只接受 `allow`、`deny`、`reject`；大小写不敏感，不接受 `drop`、`block` 等别名。
- 未知名称返回 null，由适配器决定映射到 `Unsupported`；不得默认成 `Allow`。

---

## 8. 使用的技术

- 简单枚举；
- 名称映射；
- 值语义。

---

## 9. 需要的支撑

- 语言：enum、String；
- 运行时：无；
- 接口：`FirewallRule`、`FirewallStatus`。

---

## 10. 依赖的特性/接口/类

`FirewallRule`、`FirewallStatus`、`FirewallController`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。
相等：按枚举底层值比较；可作 `Map` 键。

---

## 12. 示例与反例

正确：`rule.action() == FirewallAction.Deny`；默认入站策略为 `Deny` 时，服务器启动显式添加最小 `Allow` 规则。  
反例：把 `Reject` 当 `Deny` 静默处理；把未知后端动作当成 `Allow`；用字符串 `"drop"` 或 `"accept"` 代替枚举；在业务里新增 `Log`/`Nat` 动作。

---

## 13. 测试/场景义务

每个成员名称/解析；大小写不敏感；未知名称；后端无主动拒绝时 `apply` 返回 `Unsupported`；
`Deny` 与 `Reject` 可区分；默认策略使用三种动作；不出现 `Unknown` 成员。

---

## 14. XNull 伪代码

非可执行设计伪代码。

```xnull
enum FirewallAction {
    Allow,
    Deny,
    Reject,
}

String firewallActionName(FirewallAction action) {
    if action == null { throw "firewallActionName: null action" }
    if action == FirewallAction.Allow { return "allow" }
    if action == FirewallAction.Deny { return "deny" }
    return "reject"
}

FirewallAction? firewallActionFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "allow" { return FirewallAction.Allow }
    if normalized == "deny" { return FirewallAction.Deny }
    if normalized == "reject" { return FirewallAction.Reject }
    return null
}
```
