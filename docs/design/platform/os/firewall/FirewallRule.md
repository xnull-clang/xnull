# `FirewallRule`

| 项 | 值 |
| --- | --- |
| 类型 | `class FirewallRule` |
| 包 | `xdk.os.firewall` |
| 稳定性 | `preview` |
| 依赖 | `FirewallAction`、`FirewallDirection`、`FirewallProtocol` |

---

## 1. 定位

不可变、类型化的防火墙规则值对象：动作、方向、协议、本地/远端端口、远端地址、优先级与描述。

由 `FirewallController.apply(context, rule)` 消费；`FirewallController.rules(context)` 返回带 ID 的实例。调用方可以构造新规则，也可以用 `withId` 派生更新规则。

不做：nftables/iptables/WFP/PF 表达式、shell 命令、NAT/重定向、接口/zone、用户/组、连接状态、时间窗口、限速、日志动作、主机名/地址范围。这些属于适配器内部或 X。

---

## 2. 设计逻辑

- 用 class 而不是 struct：规则是公开 API 的不可变值对象，需要 `id` 语义、`withId` 派生和脱敏 `describe`；不持有资源，不依赖析构。
- `action`/`direction`/`protocol` 使用枚举，禁止用字符串表达动作、方向或协议。
- `_id` 为空表示“尚未应用的新规则”；非空表示控制器分配或更新目标 ID。ID 不透明，不解析、不推导、不由地址/端口派生、不持久化承诺。
- 端口 `0` 表示任意；`localPort` 是本机端口，`remotePort` 是对端端口。入站时 `localPort` 是目的端口，出站时是本机源端口；方向改变角色，不改变字段含义。
- `priority` 数值越小越先评估；相同优先级由后端顺序决定，不承诺稳定。优先级不是安全边界。
- `remoteAddress` 为空表示任意；非空必须是 IP 或 CIDR。构造器只做结构检查，地址解析与协议/端口一致性由控制器执行，失败返回 `InvalidArgument`。
- `description` 单行、可为空；不得写入密钥、令牌、完整规则或敏感地址。
- `describe` 是脱敏摘要：不输出远端地址、端口、描述或 ID，可安全用于日志。
- 不提供“全部放行”便捷构造；完全通配的 `Allow` 必须由调用方显式写出并接受审计。
- 不可变；可跨任务共享；`withId` 返回新实例，不修改原对象。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_id` | `String` | final | 空=新规则；非空=不透明规则 ID |
| `_direction` | `FirewallDirection` | final | 非 null |
| `_action` | `FirewallAction` | final | 非 null |
| `_protocol` | `FirewallProtocol` | final | 非 null |
| `_localPort` | `Int` | final | 0..65535；0=任意 |
| `_remoteAddress` | `String` | final | 空=任意；非空由控制器校验为 IP/CIDR |
| `_remotePort` | `Int` | final | 0..65535；0=任意 |
| `_priority` | `Int` | final | ≥0；数值越小越先评估 |
| `_description` | `String` | final | 单行；可为空；不含敏感信息 |

不变量：

- 所有引用字段非 null；端口在 0..65535；`priority ≥ 0`；`description` 不含 CR/LF。
- `_id` 为空或非空不透明 token；非空 ID 不得有首尾空白，也不得含 CR/LF。
- 构造器保证结构不变量；控制器保证 `remoteAddress` 是合法 IP/CIDR、协议/端口组合合法、后端支持动作/方向/协议。
- 不可变；任何“修改”都返回新实例。

---

## 4. 生命周期

构造后不可变；无 close；可共享。规则对象不会随 OS 变化自动刷新；控制器删除或外部修改后，旧对象仍可读，但其 ID 可能已失效。需要最新状态时重新调用 `rules`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `FirewallRule(...)` | 9 个字段 | 枚举/字符串非 null；端口 0..65535；`priority ≥ 0`；描述单行；ID 为空或无首尾空白/CR/LF | 非法 → panic |

说明：

- `ruleId` 可为空（新规则）；非空时必须是控制器可接受的不透明 ID。
- `remoteAddress` 可为空（任意）；非空时构造器不解析，控制器返回 `InvalidArgument` 表示非法 IP/CIDR。
- `description` 可为空；拒绝 `\n`/`\r`。
- 构造器不查询后端、不判断协议/端口组合、不判断 `Reject`/`Both` 是否受支持。
- 业务代码通常用空 ID 构造新规则；`withId` 只用于派生更新目标，不代表 ID 已存在。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `id` | 规则 ID | 无 | `String` | 无 |
| `direction` | 流量方向 | 无 | `FirewallDirection` | 无 |
| `action` | 处置动作 | 无 | `FirewallAction` | 无 |
| `protocol` | IP 协议 | 无 | `FirewallProtocol` | 无 |
| `localPort` | 本机端口（0=任意） | 无 | `Int` | 无 |
| `remoteAddress` | 远端地址/CIDR（空=任意） | 无 | `String` | 无 |
| `remotePort` | 远端端口（0=任意） | 无 | `Int` | 无 |
| `priority` | 优先级 | 无 | `Int` | 无 |
| `description` | 单行描述 | 无 | `String` | 无 |
| `withId` | 派生带 ID 的副本 | `String ruleId` | `FirewallRule` | null/空/首尾空白/CR/LF → panic |
| `describe` | 脱敏单行摘要 | 无 | `String` | 无 |

说明：

- 所有 getter 返回不可变值；`String` 不可变，无需复制。
- `id()` 可能为空；空 ID 不是错误，表示规则尚未被控制器应用。不得用空 ID 调用 `remove` 并期望删除任意规则。
- `localPort`/`remotePort` 的 0 表示任意，不是“端口 0”。端口 0 本身不是合法服务端口。
- `remoteAddress()` 可能包含敏感地址；`localPort()`/`remotePort()` 是规则细节；三者只在策略计算时使用，不写日志、不进错误详情。
- `withId` 是纯派生：保留全部其他字段，返回新实例；不检查 ID 是否存在于控制器、不检查归属、不修改原对象。传入 null、空串、首尾带空白或含 CR/LF 的 ID 视为合同错误。
- `describe` 只输出动作、方向、协议、远端是否为任意、优先级；不输出地址、端口、描述、ID。
- 没有 `equals`/`copy`：相等是引用身份；需要值比较时逐字段比较；不推荐作 `Map` 键。

---

## 8. 使用的技术

- 不可变值对象；
- `final` 字段；
- 类型化枚举；
- 端口/优先级范围校验；
- 单行描述校验；
- 纯派生（`withId`）；
- 脱敏摘要。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Int、Bool；
- 运行时/适配器：无（控制器负责地址解析与后端调用）；
- 接口：`FirewallAction`、`FirewallDirection`、`FirewallProtocol`、`FirewallController`、`FirewallStatus`。

---

## 10. 依赖的特性/接口/类

`FirewallAction`、`FirewallDirection`、`FirewallProtocol`、`FirewallController`、`FirewallStatus`。

地址/CIDR 校验由 `FirewallController` 通过 `xdk.net` 的 `IpAddress`/`IpPrefix` 完成，不是本类的构造职责。

---

## 11. 所有权与并发

不可变；可跨任务共享；无资源；无取消点；跨任务读取安全。

`withId` 返回新实例，原实例不变；控制器不会修改传入的规则对象。

相等：`==` 是引用身份；没有 `equals`；需要比较时逐字段比较；不推荐作 `Map` 键。规则 ID 也不适合作为跨进程/跨重启的稳定键。

---

## 12. 示例与反例

正确：

```xnull
FirewallRule rule = new FirewallRule("", FirewallDirection.Inbound,
    FirewallAction.Allow, FirewallProtocol.Tcp,
    443, "203.0.113.0/24", 0, 10, "https from office")
Result<String, Error> applied = firewall.apply(context, rule)
```

- 新规则用空 ID；保存 `apply` 返回的 ID；更新时用 `rule.withId(ruleId)` 派生。
- 日志使用 `rule.describe()`；需要诊断地址时显式读取 `remoteAddress()` 并遵守脱敏策略。

反例：

- 把 `"tcp dport 443 accept"` 塞进 `description` 或当成规则；API 不接受原始表达式。
- 期望构造器校验 CIDR；非法地址应由 `apply` 返回 `InvalidArgument`。
- 给 `Icmp` 设置端口；端口与协议不一致应由控制器拒绝。
- 用 `withId` 伪造其他控制器的 ID；未知 ID 更新应得到 `NotFound`。
- 记录 `remoteAddress()`/`remotePort()`/完整规则到日志；`describe()` 已脱敏。
- 假设规则对象会随 OS 自动刷新；删除或外部修改后应重新查询。

---

## 13. 测试/场景义务

- 每个字段 null；空 ID；非空 ID 首尾空白或含 CR/LF；`withId` 的 null/空/空白/CR/LF。
- 端口边界 0、65535、65536；负端口；负优先级；`description` 含 `\n`/`\r`。
- 不可变性；`withId` 不修改原对象；`describe` 不含地址/端口/描述/ID。
- 控制器集成：IPv4、IPv6、CIDR、非法地址；TCP/UDP 端口；ICMP/Any 非零端口；`Both` 展开；`Reject` 不支持；优先级顺序；更新语义；未知 ID。
- 敏感信息：描述/地址/端口不进入 `describe` 或错误详情。

---

## 14. XNull 伪代码

非可执行设计伪代码。

```xnull
class FirewallRule {
    final String _id
    final FirewallDirection _direction
    final FirewallAction _action
    final FirewallProtocol _protocol
    final Int _localPort
    final String _remoteAddress
    final Int _remotePort
    final Int _priority
    final String _description

    FirewallRule(String ruleId, FirewallDirection direction, FirewallAction action,
                 FirewallProtocol protocol, Int localPort, String remoteAddress,
                 Int remotePort, Int priority, String description) {
        if ruleId == null || direction == null || action == null || protocol == null
            || remoteAddress == null || description == null {
            throw "FirewallRule: null field"
        }
        if localPort < 0 || localPort > 65535 {
            throw "FirewallRule: invalid local port"
        }
        if remotePort < 0 || remotePort > 65535 {
            throw "FirewallRule: invalid remote port"
        }
        if priority < 0 { throw "FirewallRule: negative priority" }
        if description.contains("\n") || description.contains("\r") {
            throw "FirewallRule: multi-line description"
        }
        if ruleId != "" && ruleId.trim() != ruleId {
            throw "FirewallRule: invalid rule id"
        }
        if ruleId.contains("\n") || ruleId.contains("\r") {
            throw "FirewallRule: invalid rule id"
        }
        _id = ruleId
        _direction = direction
        _action = action
        _protocol = protocol
        _localPort = localPort
        _remoteAddress = remoteAddress
        _remotePort = remotePort
        _priority = priority
        _description = description
    }

    String id() { return _id }
    FirewallDirection direction() { return _direction }
    FirewallAction action() { return _action }
    FirewallProtocol protocol() { return _protocol }
    Int localPort() { return _localPort }
    String remoteAddress() { return _remoteAddress }
    Int remotePort() { return _remotePort }
    Int priority() { return _priority }
    String description() { return _description }

    FirewallRule withId(String ruleId) {
        if ruleId == null || ruleId == "" || ruleId.trim() != ruleId {
            throw "FirewallRule.withId: invalid rule id"
        }
        if ruleId.contains("\n") || ruleId.contains("\r") {
            throw "FirewallRule.withId: invalid rule id"
        }
        return new FirewallRule(ruleId, _direction, _action, _protocol,
            _localPort, _remoteAddress, _remotePort, _priority, _description)
    }

    String describe() {
        String remote = "any"
        if _remoteAddress != "" { remote = "specified" }
        return "firewall " + str(_action) + " " + str(_direction)
            + " " + str(_protocol)
            + " remote=" + remote
            + " priority=" + str(_priority)
    }
}
```
