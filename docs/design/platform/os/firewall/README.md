# `xdk.os.firewall` 防火墙规则与状态

| 项 | 值 |
| --- | --- |
| 包 | `xdk.os.firewall` |
| 层 | os / `xdk.os` |
| 依赖 | `xdk.core`、`xdk.os`、`xdk.net` |
| 能力 | `Firewall` |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 定位

OS 防火墙的类型化规则、状态查询与控制；Linux nftables/iptables、Windows WFP、macOS PF 的公共抽象。

控制器绑定一个**受管策略范围**：`rules`/`apply`/`remove`/`flush` 只作用于该范围；`status`/`enable` 是宿主级操作。这样既能表达应用自己的最小规则，也不会把平台上不可表达的内置规则或其他管理器的规则混进来。受管范围由适配器定义；若平台只能全局管理，适配器必须显式声明，`flush` 仍按全局高危操作处理。

不做：包过滤引擎实现、IPS/IDS、代理、VPN、审计平台、原生规则字符串、内核模块、NAT/重定向、接口/zone、规则持久化、自动提权。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 特权显式 | 修改规则/启停/flush 通常需要管理员或 root；`PermissionDenied` 不伪装、不重试、不提权 |
| 类型化规则 | 只用 `FirewallRule`；地址/CIDR、协议/端口由控制器校验；不接受 shell 或原生表达式 |
| 默认拒绝 | 默认拒绝心智；不提供“全部放行”便捷方法；完全通配的 `Allow` 必须显式构造并按高风险审计；不自动改写默认策略 |
| 受管范围 | 控制器绑定受管策略范围；`rules`/`flush` 只作用于该范围；`status`/`enable` 是宿主级 |
| 审计 | `apply`/`remove`/`enable`/`flush` 必须可审计；`flush` 与 `enable(false)` 是高危操作 |
| 脱敏 | 地址/端口/规则/描述不入日志；`describe` 脱敏；错误详情不含敏感地址 |
| 无自动提权/重试 | `PermissionDenied` 直接返回；不自动 sudo/polkit/UAC，不做隐式重试 |
| 后端透明 | 公开 API 不出现 nftables/iptables/WFP/PF 命令或规则表达式；后端标签只作诊断 |
| 不透明句柄 | 控制器用 `Long` 句柄；不暴露 fd/指针；`close` 幂等 |

---

## 3. 类型索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `FirewallAction` | enum | Allow/Deny/Reject | [`FirewallAction.md`](FirewallAction.md) |
| `FirewallDirection` | enum | Inbound/Outbound/Both | [`FirewallDirection.md`](FirewallDirection.md) |
| `FirewallProtocol` | enum | Tcp/Udp/Icmp/Any | [`FirewallProtocol.md`](FirewallProtocol.md) |
| `FirewallRule` | class | 类型化规则值对象 | [`FirewallRule.md`](FirewallRule.md) |
| `FirewallStatus` | class | 防火墙状态快照 | [`FirewallStatus.md`](FirewallStatus.md) |
| `FirewallController` | class | 查询/应用/删除/启停/清空 | [`FirewallController.md`](FirewallController.md) |

枚举的稳定名称辅助函数见各枚举文件 §7；控制器方法、参数、返回与失败详见各类型文件，本文不重复方法表。

---

## 4. 跨类型规则

- **能力门控**：先 `OsProfile.has(OsCapability.Firewall)`，再调用 `OsHost.firewall(context)`；缺失返回 `Unsupported`。能力存在仍可能 `PermissionDenied`。
- **规则 ID**：新规则 `id` 为空；`apply` 成功返回非空 ID。ID 不透明、控制器/受管范围作用域内有效，不解析、不由地址/端口派生、不跨重启持久化承诺、不从 ID 推断顺序。
- **创建与更新**：`apply` 对空 ID 创建新规则；对非空 ID 更新该规则；未知 ID 返回 `NotFound`。不按内容去重，不返回 `AlreadyExists`，不静默把更新改成新建。
- **规则校验**：端口 0..65535；`priority ≥ 0`；`Tcp`/`Udp` 可用端口，`Icmp`/`Any` 端口必须为 0；`remoteAddress` 为空=任意，否则必须是 IP/CIDR。非法返回 `InvalidArgument`。
- **方向语义**：`Inbound`/`Outbound` 以本机为参照；`Both` 是一条逻辑规则，后端可展开为两条；不支持时返回 `Unsupported`，不得只应用单方向。
- **状态快照**：`FirewallStatus` 是快照，不自动刷新；`backend` 是受控诊断标签，不是命令、路径或规则表达式；默认策略无法映射或规则数无法获取时 `status` 返回 `Unsupported`，不猜测 `Allow`。
- **受管范围**：`rules` 只返回控制器受管范围内的规则；任一规则无法忠实表示时返回 `Unsupported`，不静默跳过。`ruleCount` 同样是受管范围计数。
- **删除语义**：`remove` 对未知/空/空白/含 CR/LF 的 ID 返回 `Ok(false)`，不是错误，不使用 `NotFound`；成功删除返回 `Ok(true)`；`Both` 规则必须删除全部后端条目。
- **启停与规则**：`apply`/`remove`/`flush` 不改变启用状态；防火墙禁用时规则仍可在受管范围写入或删除，是否生效由 `enable` 决定。
- **高危写操作**：`flush` 只清空受管规则，不改变启用状态和默认策略，必须审计；`enable(false)` 关闭宿主防火墙，必须审计并提示二次确认；两者都不自动回滚。
- **关闭语义**：`close` 只释放控制器，不删除规则、不启停防火墙；幂等；关闭后除 `close`/`isOpen` 外返回 `Unavailable`。
- **失败与取消**：`PermissionDenied` 不重试、不提权；`Cancelled` 不保证 OS 未提交；`Unsupported` 不降级模拟。调用方应重新查询 `status`/`rules`，不假设自动回滚。
- **日志与错误**：审计记录时间、操作、规则 ID、动作/结果、错误类别；不记录完整地址、端口、规则文本或描述。`describe` 已脱敏，可直接用于日志。
- **无 shell/原生字符串**：适配器使用类型化 FFI/库，不执行 shell，不把 nftables/iptables/WFP/PF 表达式穿过公开 API。

---

## 5. 场景

- **服务器启动**：读取 `status`；确认 `isEnabled` 且默认入站为 `Deny`；按配置应用最小入站规则（例如 TCP 443 来自指定 CIDR）；失败则拒绝启动或告警，不自动关闭防火墙。
- **运维 CLI**：列出受管规则；按 ID 删除；`flush` 前要求二次确认并审计；不把 `flush` 当全局防火墙重置。
- **桌面程序**：通常只读 `status`；不自动修改防火墙；需要时展示 `isPrivileged` 提示并由用户显式操作。
- **安装器**：应用最小规则；失败回滚自己创建的规则；不回滚/不修改其他管理器的规则；不 `enable(false)` 换取连通性。
- **权限/取消**：无管理员权限时暴露 `PermissionDenied`；取消后重新查询规则，确认 OS 是否已提交；不重试提权。

---

## 6. 安全义务

- 默认拒绝：不提供 `allowAll` 一类便捷方法；完全通配的 `Allow` 是显式规则，按高风险写操作审计；控制器不自动创建或改写默认拒绝规则。
- 所有写操作审计：时间、操作、规则 ID、动作/结果、错误类别；不记录完整地址、端口、规则文本、描述。
- 禁止 shell：不执行 `iptables`/`nft`/`netsh`/`pfctl` 字符串；使用类型化 FFI/库。
- 需要管理员/root：`PermissionDenied` 不重试、不自动提权；不通过 setuid/守护进程绕过权限。
- `flush`：只清空受管范围；保留启用状态与默认策略；调用方/运维流程要求显式确认；审计；后端无法范围化清空时返回 `Unsupported`。
- `enable(false)`：关闭宿主防火墙可能暴露全部流量；必须审计并提示；不自动回滚。
- 规则 ID：不透明；删除前校验存在性；不解析、不伪造、不跨控制器假设归属。
- 错误与日志：不包含敏感地址/端口/规则；`describe` 脱敏；后端错误文本先清洗再映射。
- `close` 不改变 OS 策略；规则继续生效；未 `close` 视为资源泄漏。
- 取消不等于回滚：`Cancelled` 后重新查询；不假设部分写入已撤销。
- 无全局状态：控制器由 `OsHost` 返回；不提供全局规则注册表或全局防火墙修改入口。

---

## 7. 缺口

| 项 | 决策 |
| --- | --- |
| nftables 完整表达式/集合/映射 | X |
| Windows WFP 过滤器细分 | X |
| macOS PF 锚点/表 | X |
| 防火墙事件/日志流 | X |
| 接口/zone/用户/组/连接状态/时间窗/限速 | X |
| Reject 响应类型/ICMP 类型代码 | X |
| 主机名/地址范围/地理位置 | X/ecosystem；基线只接受 IP/CIDR |
| NAT/重定向 | 不做 |
| VPN/代理/IDS | ecosystem |
| 规则持久化/跨重启规则 ID | 适配器/OS 负责；不承诺 |
| 全局规则/其他管理器规则枚举 | X |
| 原生规则字符串/后端命令 | 不暴露 |

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | 无领域注解 |
| 本包消费 | `@Value`、`@Builder`、`@Audited` |
| 处理器 | 标准 A8 / 审计处理器 |
| 生成物 | 规则值语义、规则构造、变更审计 |
| 状态 | 无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `FirewallRule`/`FirewallStatus` | `@Value`/`@Builder` | 值语义/构造 |
| `FirewallController` 变更方法 | `@Audited` | 审计事件 |

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../../ANNOTATION-CATALOG.md)。
