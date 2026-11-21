# `FirewallController`

| 项 | 值 |
| --- | --- |
| 类型 | `class FirewallController` |
| 包 | `xdk.os.firewall` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Error`、`FirewallRule`、`FirewallStatus` |

---

## 1. 定位

防火墙控制器：查询宿主状态与受管规则，应用/更新/删除规则，启停防火墙，清空受管规则，并释放不透明句柄。

由 `OsHost.firewall(context)` 在 `Firewall` 能力可用时返回；业务代码不直接构造。控制器绑定一个**受管策略范围**：`rules`/`apply`/`remove`/`flush` 只作用于该范围；`status`/`enable` 是宿主级操作。

不做：nftables/iptables/WFP/PF 表达式、shell 执行、NAT/重定向、代理/VPN/IDS、规则持久化、全局规则注册表、自动提权、自动回滚。

---

## 2. 设计逻辑

- 能力门控：先 `OsProfile.has(OsCapability.Firewall)`，再取控制器；缺失返回 `Unsupported`。
- 不透明 `Long` 句柄：>0；不是 fd、指针或平台句柄；不进入日志。
- 受管范围由适配器定义（例如专用 table/chain/provider/anchor）。这避免 `rules` 被平台上不可表达的内置规则淹没，也避免 `flush` 误删其他管理器的规则。若平台只能全局管理，适配器必须显式声明，`flush` 仍按全局高危操作处理。
- 读操作 `status`/`rules` 不缓存；每次查询 OS。写操作 `apply`/`remove`/`enable`/`flush` 显式命名并审计。
- 规则身份不透明：空 ID 表示创建；非空 ID 表示更新该 ID；未知 ID 更新返回 `NotFound`。不按内容去重，不解析 ID，不由地址/端口派生，不承诺跨重启/跨外部修改稳定。
- 语义校验在控制器：端口范围、协议/端口组合、远端地址 IP/CIDR、ID 形状；非法返回 `InvalidArgument`。后端不支持动作/方向/协议返回 `Unsupported`。
- 默认拒绝心智：不提供“全部放行”便捷方法；完全通配的 `Allow` 必须显式构造并按高风险写操作审计。控制器不自动创建或改写默认拒绝规则；默认拒绝由宿主/上层策略保证，`status` 只报告配置。
- `flush` 高危：只清空受管规则，不改变默认策略、不启停防火墙；必须审计；若后端无法做到范围化清空，返回 `Unsupported`。
- `enable(false)` 高危：关闭宿主防火墙可能暴露全部流量；必须审计；不自动回滚。
- `close` 只释放控制器句柄；不删除规则、不改变防火墙状态；幂等。
- `PermissionDenied` 不自动重试、不提权；`Cancelled` 不保证 OS 未提交，调用方应重新查询。
- 公开 API 不出现原始规则字符串或后端命令；适配器内部完成映射。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_handle` | `Long` | final | >0；不透明；不可日志化 |
| `_open` | `Bool` | 内部 | 构造后 true；close 后 false |

不变量：`_handle > 0`；构造后 `_open == true`；`close` 幂等；关闭后除 `close`/`isOpen` 外方法返回 `Unavailable`；不缓存规则或状态；无全局状态。

---

## 4. 生命周期

由 `OsHost.firewall(context)` 创建；构造后可用。调用方必须 `close()`；`close` 幂等。

- `close` 先标记关闭，再释放底层句柄；释放失败只作诊断，不改变“已关闭”状态，也不重试。
- 关闭后 `status`/`rules`/`apply`/`remove`/`enable`/`flush` 返回 `Unavailable`；`close` 返回 `Ok(unit)`；`isOpen` 返回 false。
- 关闭不删除规则、不启停防火墙；OS 策略继续生效。
- 不依赖析构/finalizer；未 `close` 视为资源泄漏。
- 关闭后不能重新打开；需要新控制器时重新调用 `OsHost.firewall`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `FirewallController(Long handle)` | handle | >0 | ≤0 → panic |

说明：

- 主要供 `OsHost`/测试使用；业务代码通过 `OsHost.firewall(context)` 获取。
- 构造器不查询能力、不查询 OS、不应用规则、不验证句柄是否仍有效。
- 句柄为不透明值；不得从 fd/指针转换，也不得跨进程传递。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `status` | 宿主状态快照 | `Context context` | `Result<FirewallStatus, Error>` | `Unsupported`/`PermissionDenied`/`Cancelled`/`Io`/`Unavailable` |
| `rules` | 受管规则快照 | `Context context` | `Result<List<FirewallRule>, Error>` | 同上 + `Unsupported`（规则不可表达） |
| `apply` | 创建/更新规则 | `Context context, FirewallRule rule` | `Result<String, Error>` | 同上 + `InvalidArgument`/`NotFound` |
| `remove` | 删除规则 | `Context context, String ruleId` | `Result<Bool, Error>` | 同上 |
| `enable` | 启停防火墙 | `Context context, Bool isEnabled` | `Result<Unit, Error>` | 同上 |
| `flush` | 清空受管规则 | `Context context` | `Result<Unit, Error>` | 同上 |
| `close` | 关闭控制器 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 |

### 7.1 `status`

- `context` 为 null → panic；关闭后 → `Unavailable`。
- 每次查询 OS，不缓存；可能由多次 OS 查询组合，字段之间不保证事务一致。
- 读取防火墙状态可能需要管理员权限；无权限返回 `PermissionDenied`，不重试、不提权。
- 返回不可变快照；调用方拥有该对象。

### 7.2 `rules`

- `context` 为 null → panic；关闭后 → `Unavailable`。
- 返回受管范围内的逻辑规则快照；`Both` 是一条逻辑规则，即使后端展开成两条。
- 不包含平台内置规则或其他管理器的规则；空列表表示受管范围当前无规则。
- 不检查启用状态；防火墙禁用时仍返回受管规则。
- 任一可见规则无法忠实表示为 `FirewallRule` 时返回 `Unsupported`，不得静默跳过或近似映射；否则调用方会误以为策略更简单。
- 返回列表是新快照：适配器返回后控制器再复制，调用方拥有；元素不可变，可安全保留。

### 7.3 `apply`

- `context` 或 `rule` 为 null → panic；关闭后 → `Unavailable`。
- 校验顺序：端口范围、优先级、协议/端口组合、远端地址、规则 ID 形状；失败返回 `InvalidArgument`。
- `rule.id()` 为空 → 创建新规则，控制器分配非空 ID 并返回；成功返回空 ID 是适配器错误，调用方不得继续使用。
- `rule.id()` 非空 → 更新该 ID；不存在于受管范围 → `NotFound`。不得静默改为新建，避免调用方以为更新成功却产生重复规则。
- 不按内容去重；相同内容用空 ID 再次 `apply` 会创建第二条规则。需要更新时先用 `rules` 取得 ID。
- 基线不返回 `AlreadyExists`；创建成功返回新 ID，失败返回对应错误；更新始终按非空 ID 定位。
- `Reject`、`Both`、协议或方向不受后端支持时返回 `Unsupported`，不得降级为 `Deny` 或单向规则。
- 不自动启停防火墙：防火墙禁用时规则仍写入/更新受管范围，是否生效由 `enable` 决定。
- 不保证多后端条目原子性；更新/展开失败可能留下部分状态。调用方应重新查询 `rules`，不假设自动回滚。
- 不提供“全部放行”快捷方法；完全通配的 `Allow` 是显式规则，审计标记为高风险。
- 不执行 shell、不拼接原始规则字符串；适配器使用类型化 FFI/库。
- 写操作必须审计：时间、操作、规则 ID（创建成功后的 ID）、动作/结果、错误类别；不记录完整地址/端口/规则文本。

### 7.4 `remove`

- `context` 或 `ruleId` 为 null → panic；关闭后 → `Unavailable`。
- 只删除受管范围内、ID 精确匹配的规则。
- 未知 ID 返回 `Ok(false)`，不是错误；空串、全空白、首尾带空白或含 CR/LF 的 ID 同样视为未知，返回 `Ok(false)`。不使用 `NotFound`。
- 删除成功返回 `Ok(true)`；`Both` 逻辑规则必须删除其全部后端条目，部分失败返回 `Io`，调用方应重新查询。
- 不按内容匹配、不解析 ID、不跨控制器删除。
- 写操作审计；不记录地址/端口/规则文本。

### 7.5 `enable`

- `context` 为 null → panic；关闭后 → `Unavailable`。
- 控制宿主防火墙的启用状态，不只是受管范围；可能影响其他管理器和平台内置规则。
- 幂等：重复调用同一目标状态返回 `Ok(unit)`；适配器可直接调用幂等的 OS 原语。
- `isEnabled == false` 是高危操作：可能暴露全部流量；必须审计并提示调用方二次确认；不自动回滚。
- 无权限返回 `PermissionDenied`；不支持启停返回 `Unsupported`。
- 不自动修改默认策略；启停与默认策略是两件事。

### 7.6 `flush`

- `context` 为 null → panic；关闭后 → `Unavailable`。
- 只清空受管规则；不清空平台内置规则或其他管理器规则。
- 不改变 `isEnabled`，不改变默认入站/出站策略；若后端原生 flush 会重置默认策略，适配器必须保留/恢复默认策略，做不到则返回 `Unsupported`。
- 高危操作：必须审计，建议调用方在 UI/运维流程中要求二次确认；API 不提供“全部放行”参数。
- 空受管范围也返回 `Ok(unit)`，但仍记录尝试与结果。
- 失败可能部分清空；调用方应重新查询 `rules`。

### 7.7 `close`

- 幂等；已关闭时返回 `Ok(unit)`。
- 无 `Context`；实现应快速完成，不无限阻塞。
- 先标记关闭，再调用底层关闭；底层失败返回 `Io` 仅作诊断，后续 `close` 仍返回 `Ok(unit)`，不重试。
- 不删除规则、不启停防火墙；OS 策略继续生效。
- 不依赖析构/finalizer。

### 7.8 `isOpen`

- 无失败；不查询 OS。
- 返回值是建议性状态；与并发 `close` 竞争时可能立即过期。关闭后新调用应以 `Unavailable` 为准。

---

## 8. 使用的技术

- 不透明 `Long` 句柄；
- 受管策略范围；
- `Context`/`Result` 失败通道；
- 类型化规则到后端规则的映射；
- 幂等关闭；
- 审计与脱敏；
- 无 shell、无原始规则字符串。

---

## 9. 需要的支撑

| 原语/接口 | 用途 | 返回 | 失败 |
| --- | --- | --- | --- |
| `firewallStatusRaw(Context context, Long handle)` | 查询宿主状态 | `Result<FirewallStatus, Error>` | `Unsupported`/`PermissionDenied`/`Cancelled`/`Io` |
| `firewallRulesRaw(Context context, Long handle)` | 查询受管规则 | `Result<List<FirewallRule>, Error>` | 同上 |
| `firewallApplyRaw(Context context, Long handle, FirewallRule rule)` | 创建/更新规则 | `Result<String, Error>` | 同上 + `InvalidArgument`/`NotFound` |
| `firewallRemoveRaw(Context context, Long handle, String ruleId)` | 删除规则 | `Result<Bool, Error>` | 同上 |
| `firewallEnableRaw(Context context, Long handle, Bool isEnabled)` | 启停防火墙 | `Result<Unit, Error>` | 同上 |
| `firewallFlushRaw(Context context, Long handle)` | 清空受管规则 | `Result<Unit, Error>` | 同上 |
| `firewallCloseRaw(Long handle)` | 释放句柄 | `Result<Unit, Error>` | `Io` |
| `firewallAddressIsValid(String text)` | 包内地址/CIDR 辅助校验；空串表示任意 | `Bool` | 无 |
| `IpAddress.parse` / `IpPrefix.parse` | 解析远端地址/CIDR | `Result<IpAddress, Error>` / `Result<IpPrefix, Error>` | `InvalidArgument` |
| `unavailableError` | 关闭后错误 | `Error` | 无 |
| `BasicError` / `ErrorKind` | 构造 `InvalidArgument` | `Error` | 无 |

说明：

- 上述 `*Raw` 是 internal 适配器原语，不是公开 API；名称、后端类型和错误文本不进入公开签名。
- 适配器只做 OS 调用与错误映射，不决定策略；无权限不得降级为“尝试提权”。
- `IpAddress`/`IpPrefix` 来自 `xdk.net`，用于 `apply` 的地址校验。
- `firewallAddressIsValid` 是包内辅助函数，随本文档定义；空串返回 true，含 `/` 走 `IpPrefix.parse`，否则走 `IpAddress.parse`。

---

## 10. 依赖的特性/接口/类

`Context`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`、`firewallAddressIsValid`、`FirewallRule`、`FirewallStatus`、`FirewallAction`、`FirewallDirection`、`FirewallProtocol`、`OsHost`、`OsCapability`、`xdk.net` 的 `IpAddress`/`IpPrefix`。

---

## 11. 所有权与并发

引用语义；调用方持有控制器并负责 `close`；不跨进程共享。

- `status`/`rules` 可由多个任务并发调用；适配器可能串行化 OS 查询。
- `apply`/`remove`/`enable`/`flush` 可并发发起，但 OS/后端可能串行化；跨调用的顺序不保证，多规则变更不是事务。
- `close` 不应与进行中的调用无同步并发；调用方需外部同步。通过 `_open` 检查后、进入后端前可能发生 `close`，该调用可能仍到达后端并失败；关闭返回后新调用返回 `Unavailable`。
- `isOpen` 是建议性查询，不能用于同步。
- 无正常路径资源泄漏；规则和防火墙状态在 `close` 后保留，不随控制器释放。
- 相等：引用身份；不推荐作 `Map` 键。

取消：`Cancelled` 只表示调用方取消；OS 操作可能已提交。调用方不得假设自动回滚，应重新查询 `status`/`rules`。

---

## 12. 示例与反例

正确：

```xnull
OsHost host = Os.host()
OsProfile profile = host.profile()
if profile.has(OsCapability.Firewall) {
    Result<FirewallController, Error> opened = host.firewall(context)
    if opened.isOk() {
        FirewallController firewall = opened.value()
        Result<FirewallStatus, Error> status = firewall.status(context)
        FirewallRule rule = new FirewallRule("", FirewallDirection.Inbound,
            FirewallAction.Allow, FirewallProtocol.Tcp,
            443, "203.0.113.0/24", 0, 10, "https from office")
        Result<String, Error> applied = firewall.apply(context, rule)
        Result<Unit, Error> closed = firewall.close()
    }
}
```

- 只在能力存在时取控制器；`apply` 后保存返回的规则 ID；删除时使用该 ID。
- `flush` 前要求二次确认并审计；`enable(false)` 同样按高危操作处理。
- 无权限时把 `PermissionDenied` 原样上抛；不 `sudo`、不重试。

反例：

- 用 `flush` “重置”宿主全部防火墙；它只清空受管规则，不应被当作全局清理。
- 为修复连通性直接 `enable(false)`；这会暴露流量且影响其他规则。
- 用 shell 拼接 `iptables`/`nft` 字符串；API 不接受原始表达式。
- 记录完整规则、地址或端口到日志/错误详情。
- 假设规则 ID 跨重启稳定，或从 ID 推断优先级/顺序。
- 把 `isPrivileged()` 当授权凭证；把 `isOpen()` 当同步原语。
- 取消后假设 `apply` 已回滚；应重新查询。
- `close` 后继续调用 `status`/`apply`；应得到 `Unavailable`。

---

## 13. 测试/场景义务

- `status`/`rules` 成功、空规则、不可表达规则 → `Unsupported`；无权限、取消、关闭后 `Unavailable`。
- `apply` 创建返回非空 ID；非空 ID 更新；未知 ID → `NotFound`；非法 CIDR、ICMP/Any 非零端口、负优先级 → `InvalidArgument`。
- `remove` 已知 ID → true；未知/空/空白 ID → false；`Both` 规则完整删除；部分失败 → `Io`。
- `enable` true/false；幂等；无权限；不支持；`enable(false)` 审计。
- `flush` 只清受管规则；保留启用状态与默认策略；空范围；审计；失败后重新查询。
- `close` 幂等；关闭后方法 `Unavailable`；关闭不删除规则、不改变防火墙状态；底层关闭失败只诊断。
- 并发读；并发写顺序不保证；`close` 与进行中调用竞争；`isOpen` 过期。
- 审计字段：时间、操作、规则 ID、动作/结果、错误类别；不含地址/端口/规则文本。
- 后端差异：nftables/iptables/WFP/PF 的 `Reject`/`Both` 支持差异只在适配器；公开 API 不变。

---

## 14. XNull 伪代码

非可执行设计伪代码。

```xnull
class FirewallController {
    final Long _handle
    Bool _open

    FirewallController(Long handle) {
        if handle <= 0 { throw "FirewallController: invalid handle" }
        _handle = handle
        _open = true
    }

    Result<FirewallStatus, Error> status(Context context) {
        if context == null { throw "FirewallController.status: null context" }
        if !_open { return Err(unavailableError("firewall")) }
        return firewallStatusRaw(context, _handle)
    }

    Result<List<FirewallRule>, Error> rules(Context context) {
        if context == null { throw "FirewallController.rules: null context" }
        if !_open { return Err(unavailableError("firewall")) }
        Result<List<FirewallRule>, Error> result = firewallRulesRaw(context, _handle)
        if result.isErr() { return Err(result.error()) }
        return Ok(result.value().copy())
    }

    Result<String, Error> apply(Context context, FirewallRule rule) {
        if context == null || rule == null {
            throw "FirewallController.apply: null argument"
        }
        if !_open { return Err(unavailableError("firewall")) }
        if rule.localPort() < 0 || rule.localPort() > 65535
            || rule.remotePort() < 0 || rule.remotePort() > 65535 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid port"))
        }
        if rule.priority() < 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "negative priority"))
        }
        if rule.protocol() == FirewallProtocol.Icmp
            || rule.protocol() == FirewallProtocol.Any {
            if rule.localPort() != 0 || rule.remotePort() != 0 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "ports not allowed for protocol"))
            }
        }
        if rule.remoteAddress() != "" {
            if !firewallAddressIsValid(rule.remoteAddress()) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "invalid remote address"))
            }
        }
        if rule.id() != "" && rule.id().trim() != rule.id() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid rule id"))
        }
        if rule.id().contains("\n") || rule.id().contains("\r") {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid rule id"))
        }
        return firewallApplyRaw(context, _handle, rule)
    }

    Result<Bool, Error> remove(Context context, String ruleId) {
        if context == null || ruleId == null {
            throw "FirewallController.remove: null argument"
        }
        if !_open { return Err(unavailableError("firewall")) }
        if ruleId == "" || ruleId.trim() != ruleId {
            return Ok(false)
        }
        if ruleId.contains("\n") || ruleId.contains("\r") {
            return Ok(false)
        }
        return firewallRemoveRaw(context, _handle, ruleId)
    }

    Result<Unit, Error> enable(Context context, Bool isEnabled) {
        if context == null {
            throw "FirewallController.enable: null context"
        }
        if !_open { return Err(unavailableError("firewall")) }
        return firewallEnableRaw(context, _handle, isEnabled)
    }

    Result<Unit, Error> flush(Context context) {
        if context == null {
            throw "FirewallController.flush: null context"
        }
        if !_open { return Err(unavailableError("firewall")) }
        return firewallFlushRaw(context, _handle)
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        return firewallCloseRaw(_handle)
    }

    Bool isOpen() { return _open }
}

Bool firewallAddressIsValid(String text) {
    if text == "" { return true }
    if text.contains("/") {
        Result<IpPrefix, Error> prefix = IpPrefix.parse(text)
        return !prefix.isErr()
    }
    Result<IpAddress, Error> address = IpAddress.parse(text)
    return !address.isErr()
}
```
