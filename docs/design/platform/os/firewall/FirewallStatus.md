# `FirewallStatus`

| 项 | 值 |
| --- | --- |
| 类型 | `class FirewallStatus` |
| 包 | `xdk.os.firewall` |
| 稳定性 | `preview` |
| 依赖 | `FirewallAction` |

---

## 1. 定位

防火墙状态只读快照：后端诊断标签、是否启用、默认入站/出站动作、受管范围规则数、当前进程是否具备修改权限。

不做：规则枚举、实时订阅、流量统计、健康评分、自动修复、后端命令文本。

---

## 2. 设计逻辑

- 由 `FirewallController.status(context)` 返回；是快照，不自动刷新；外部工具或后续写操作会使快照过期。
- `backend` 是固定小写诊断标签：`nftables`、`iptables`、`wfp`、`pf`、`unknown`。它不是命令、路径、可执行句柄或规则表达式；调用方不得用它拼命令或做安全策略分支。
- `defaultInbound`/`defaultOutbound` 表示后端**当前配置的默认策略**，不是原始配置文本；当 `isEnabled == false` 时可能不生效。无法映射到 `FirewallAction` 时，`status` 返回 `Unsupported`，不得猜测 `Allow`。
- `ruleCount` 是受管范围内的逻辑规则数；`Both` 计为一条；不包含平台内置规则或其他管理器的规则。无法计数时返回 `Unsupported`。
- `isPrivileged` 是建议性信息：true 不保证下一次写入成功，false 不替代 OS 的权限判定；不能当作授权凭证。
- 状态可能由多次 OS 查询组合而成，不保证跨字段事务一致；需要精确判断时重新查询。
- 不可变；不包含地址、端口、规则文本或描述；`describe` 可安全用于日志。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_backend` | `String` | final | 五个稳定标签之一 |
| `_isEnabled` | `Bool` | final | 防火墙是否启用 |
| `_defaultInbound` | `FirewallAction` | final | 非 null；配置策略 |
| `_defaultOutbound` | `FirewallAction` | final | 非 null；配置策略 |
| `_ruleCount` | `Int` | final | ≥0；受管逻辑规则数 |
| `_isPrivileged` | `Bool` | final | 建议性权限提示 |

不变量：`backend` 非空且在固定集合内；默认动作非 null；`ruleCount ≥ 0`；快照不可变；不含敏感地址/规则。

---

## 4. 生命周期

构造后不可变；无 close；可共享。快照在构造时冻结；控制器状态或 OS 配置变化后不会自动更新。需要最新状态时重新调用 `status`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `FirewallStatus(...)` | 6 个字段 | `backend` 为五个标签之一；默认动作非 null；`ruleCount ≥ 0` | 非法 → panic |

说明：

- 构造器主要供适配器/测试使用；业务代码通过 `FirewallController.status` 获取。
- `backend` 只接受 `nftables`、`iptables`、`wfp`、`pf`、`unknown`；新增后端标签属于契约变更。
- `isPrivileged` 只是布尔提示，不做权限判断。
- 构造器不查询 OS，不验证规则计数与实际规则列表是否一致。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `backend` | 后端诊断标签 | 无 | `String` | 无 |
| `isEnabled` | 防火墙是否启用 | 无 | `Bool` | 无 |
| `defaultInbound` | 默认入站策略 | 无 | `FirewallAction` | 无 |
| `defaultOutbound` | 默认出站策略 | 无 | `FirewallAction` | 无 |
| `ruleCount` | 受管逻辑规则数 | 无 | `Int` | 无 |
| `isPrivileged` | 是否具备修改权限 | 无 | `Bool` | 无 |
| `describe` | 脱敏单行摘要 | 无 | `String` | 无 |

说明：

- `backend()` 只用于诊断/审计；不要据此选择 nftables/iptables/WFP/PF API，也不要把返回值拼进命令。
- `defaultInbound()`/`defaultOutbound()` 是配置策略；`isEnabled()` 为 false 时可能不生效；若后端没有可表达的默认动作，`status` 已返回 `Unsupported`，不会构造本对象。
- `ruleCount()` 是受管范围计数；不要把它当宿主全部规则数，也不要用于精确容量规划。
- `isPrivileged()` 是 UI 提示；写操作仍以 OS 返回的 `PermissionDenied` 为准。
- `describe()` 只输出后端、启用状态、规则数；不输出默认策略、权限提示、地址、端口、规则文本或规则 ID。

---

## 8. 使用的技术

- 不可变快照；
- `final` 字段；
- 后端标签白名单；
- 诊断摘要脱敏。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Bool、Int；
- 运行时/适配器：防火墙状态查询、默认策略映射、规则计数；
- 接口：`FirewallAction`、`FirewallController`、`OsHost`、`OsCapability`。

---

## 10. 依赖的特性/接口/类

`FirewallAction`、`FirewallController`、`OsHost`、`OsCapability`。

---

## 11. 所有权与并发

不可变；可跨任务共享；无资源；无取消点；跨任务读取安全。
相等：`==` 是引用身份；没有 `equals`；需要比较时逐字段比较；不推荐作 `Map` 键。快照会过期，不适合作为长期缓存键。

---

## 12. 示例与反例

正确：服务器启动读取 `status()`，记录 `describe()`；检查 `isEnabled()` 与 `defaultInbound() == FirewallAction.Deny`；根据 `isPrivileged()` 决定是否展示“需要管理员”提示。  
反例：把 `backend()` 当命令名执行；把 `isPrivileged()` 当授权凭证；假设 `status()` 实时变化；把 `ruleCount()` 当宿主全部规则；把状态快照长期缓存；在日志里附带规则/地址。

---

## 13. 测试/场景义务

五个后端标签；非法/空标签 panic；启用/禁用；三种默认动作组合；`ruleCount` 为 0/大值；
`isPrivileged` true/false；`describe` 不含敏感信息；快照过期；控制器关闭后 `status` 返回 `Unavailable`；
后端无法表达默认策略或无法计数时 `Unsupported`。

---

## 14. XNull 伪代码

非可执行设计伪代码。

```xnull
class FirewallStatus {
    final String _backend
    final Bool _isEnabled
    final FirewallAction _defaultInbound
    final FirewallAction _defaultOutbound
    final Int _ruleCount
    final Bool _isPrivileged

    FirewallStatus(String backend, Bool isEnabled,
                   FirewallAction defaultInbound, FirewallAction defaultOutbound,
                   Int ruleCount, Bool isPrivileged) {
        if backend == null || defaultInbound == null || defaultOutbound == null {
            throw "FirewallStatus: null field"
        }
        if backend != "nftables" && backend != "iptables" && backend != "wfp"
            && backend != "pf" && backend != "unknown" {
            throw "FirewallStatus: unknown backend label"
        }
        if ruleCount < 0 { throw "FirewallStatus: negative count" }
        _backend = backend
        _isEnabled = isEnabled
        _defaultInbound = defaultInbound
        _defaultOutbound = defaultOutbound
        _ruleCount = ruleCount
        _isPrivileged = isPrivileged
    }

    String backend() { return _backend }
    Bool isEnabled() { return _isEnabled }
    FirewallAction defaultInbound() { return _defaultInbound }
    FirewallAction defaultOutbound() { return _defaultOutbound }
    Int ruleCount() { return _ruleCount }
    Bool isPrivileged() { return _isPrivileged }

    String describe() {
        return "firewall backend=" + _backend
            + " enabled=" + str(_isEnabled)
            + " rules=" + str(_ruleCount)
    }
}
```
