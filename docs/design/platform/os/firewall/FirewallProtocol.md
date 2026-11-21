# `FirewallProtocol`

| 项 | 值 |
| --- | --- |
| 类型 | `enum FirewallProtocol` |
| 包 | `xdk.os.firewall` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

防火墙规则匹配的 IP 协议：TCP、UDP、ICMP、任意协议。

不做：协议号、端口范围、ICMP 类型/代码、连接跟踪、应用层识别、SCTP/QUIC 等细分协议。

---

## 2. 设计逻辑

- 只区分基线可移植的协议；协议号由适配器内部映射，不进入公开 API。
- `Tcp`/`Udp` 允许端口匹配；`Icmp`/`Any` 不使用端口，端口必须为 0。
- `Icmp` 覆盖 ICMP 与 ICMPv6 的匹配；类型/代码属于 X。
- `Any` 表示后端支持的全部 IP 协议；不是“任意字段通配”。
- 后端无法表达所选协议时，控制器返回 `Unsupported`，不得悄悄替换成 `Tcp` 或 `Any`。
- 值语义；成员固定，只允许追加；可作 `Map`/`Set` 键。

---

## 3. 表示与不变量

| 成员 | 含义 | 端口约束 |
| --- | --- | --- |
| `Tcp` | TCP | `localPort`/`remotePort` 为 0..65535 |
| `Udp` | UDP | `localPort`/`remotePort` 为 0..65535 |
| `Icmp` | ICMP/ICMPv6 | 两个端口必须为 0 |
| `Any` | 全部支持的 IP 协议 | 两个端口必须为 0 |

不变量：成员固定；只允许追加；值语义；协议与端口组合由控制器校验。

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
| `firewallProtocolName` | 稳定小写名 | `FirewallProtocol protocol` | `String` | null → panic |
| `firewallProtocolFromName` | 名称解析 | `String name` | `FirewallProtocol?` | 无；未知返回 null |

说明：

- 稳定名用于诊断/审计，不用于构造规则表达式。
- `firewallProtocolFromName` 只接受 `tcp`、`udp`、`icmp`、`any`；大小写不敏感。
- 未知名称返回 null；不得默认成 `Any`，避免放宽匹配范围。

---

## 8. 使用的技术

- 简单枚举；
- 名称映射；
- 协议/端口一致性校验。

---

## 9. 需要的支撑

- 语言：enum、String；
- 运行时：无；
- 接口：`FirewallRule`、`FirewallController`。

---

## 10. 依赖的特性/接口/类

`FirewallRule`、`FirewallController`、`FirewallAction`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。
相等：按枚举底层值比较；可作 `Map` 键。

---

## 12. 示例与反例

正确：入站 HTTPS 使用 `Tcp` + `localPort=443`；DNS 使用 `Udp` + `localPort=53`；ICMP 诊断使用 `Icmp` 且端口为 0。  
反例：给 `Icmp` 设置端口；用 `Any` 加端口表达“任意协议 443”；把协议号写进业务；把未知协议静默映射为 `Any`。

---

## 13. 测试/场景义务

每个成员名称/解析；大小写不敏感；未知名称；TCP/UDP 端口边界；
`Icmp`/`Any` 非零端口由控制器返回 `InvalidArgument`；后端不支持协议时 `Unsupported`；
不出现协议号/应用层识别。

---

## 14. XNull 伪代码

非可执行设计伪代码。

```xnull
enum FirewallProtocol {
    Tcp,
    Udp,
    Icmp,
    Any,
}

String firewallProtocolName(FirewallProtocol protocol) {
    if protocol == null { throw "firewallProtocolName: null protocol" }
    if protocol == FirewallProtocol.Tcp { return "tcp" }
    if protocol == FirewallProtocol.Udp { return "udp" }
    if protocol == FirewallProtocol.Icmp { return "icmp" }
    return "any"
}

FirewallProtocol? firewallProtocolFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "tcp" { return FirewallProtocol.Tcp }
    if normalized == "udp" { return FirewallProtocol.Udp }
    if normalized == "icmp" { return FirewallProtocol.Icmp }
    if normalized == "any" { return FirewallProtocol.Any }
    return null
}
```
