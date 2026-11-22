# `xdk.os.service` 系统服务管理

| 项 | 值 |
| --- | --- |
| 包 | `xdk.os.service` |
| 层 | os / `xdk.os` |
| 依赖 | `xdk.core`、`xdk.os` |
| 能力 | `ServiceManager` |
| 稳定性 | `preview` |

---

## 1. 定位

系统服务/守护进程的查询与控制：systemd、launchd、Windows SCM 的公共抽象。

不做：服务编排、容器编排、进程守护库、日志采集、单元/plist 文件解析或写入、shell 命令拼接、
服务环境/命令行检查、依赖排序、健康检查。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 特权显式 | 启动/停止/重启/启用/禁用通常需要管理员；`PermissionDenied` 不重试、不提权 |
| 名称白名单 | 服务名非空、≤255、只允许 `[A-Za-z0-9_.@-]`；禁止 shell 拼接 |
| 只读优先 | 列表/状态只读；写操作显式命名并审计 |
| 状态与启用分离 | `ServiceState` 表示当前运行状态；`isEnabled` 只表示开机启用 |
| 平台透明 | systemd/launchd/SCM 适配器；公开 API 不出现平台类型 |
| 无全局 | 由 `OsHost` 返回控制器；调用方持有并 `close()` |
| 快照 | `ServiceInfo` 是快照；不自动刷新；控制后重新查询 |
| 幂等 | 启动已运行服务、停止已停止服务、重复 `close` 均成功 |
| 可取消 | 长操作接收 `Context`；取消不保证 OS 未提交 |
| 审计 | 写操作记录动作/服务名/结果；不记录环境变量/密钥/命令行 |

---

## 3. 类型索引

| 类型 | 种类 | 职责 | 文件 |
| --- | --- | --- | --- |
| `ServiceState` | enum | 服务生命周期状态 | [`ServiceState.md`](ServiceState.md) |
| `ServiceInfo` | class | 单个服务只读快照 | [`ServiceInfo.md`](ServiceInfo.md) |
| `ServiceManager` | class | 枚举/查询/启动/停止/重启/启用/关闭 | [`ServiceManager.md`](ServiceManager.md) |

---

## 4. 跨类型规则

- 先 `OsProfile.has(OsCapability.ServiceManager)`，再调用 `OsHost.services(context)`；缺失返回 `Unsupported`。
- `ServiceManager` 是不透明 `Long` 句柄控制器；调用方 `close()`；`OsHost.close()` 不替调用方关闭。
- 服务名在进入适配器前校验；非法返回 `InvalidArgument`；`ServiceInfo` 构造器拒绝非法名称。
- `ServiceInfo.state` 与 `ServiceInfo.isEnabled` 独立；`Running` 不表示开机启用，启用不表示正在运行。
- `pid == 0` 表示未运行或未知；`Running` 时也可能为 0（OS 未暴露）。
- `start` 成功 = 观察到 `Running`；`stop` 成功 = 观察到 `Stopped`；`restart` = 先停后启；`start`/`stop` 不改变 `isEnabled`；`enable` 只持久化启用，不启动。
- `services` 返回快照；空列表 = 支持但当前无可表示服务（可能全部被名称过滤）；顺序不承诺；无重复名称。
- 非白名单名称的 OS 服务不进入类型化列表；需要用平台工具查看。
- 关闭后除 `isOpen`（false）与重复 `close`（`Ok(unit)`）外的操作返回 `Unavailable`；`close` 幂等。
- 不写 unit/plist；不执行任意命令；不读取/记录环境变量、密钥、完整命令行。

---

## 5. 场景

- 服务器运维：列出/查询/启动/停止服务；需要管理员；写操作审计；失败回滚。
- 安装器：`enable` 设置开机启用；安装失败时传 `isEnabled=false` 回滚启用，必要时再 `stop`；不写 unit/plist。
- 监控：周期查询 `status`；`pid == 0` 只表示未运行/未知；不因 `Unknown` 推断停止。
- 桌面/容器：通常 `Unsupported`；不假设 systemd/launchd/SCM 存在。
- 失败/取消：`PermissionDenied` 不重试；`Cancelled` 后重新查询，OS 操作可能已提交。

---

## 6. 安全义务

| 义务 | 规则 |
| --- | --- |
| 特权 | 写操作可能需管理员；不自动提权；`PermissionDenied` 不重试 |
| 名称 | 白名单校验；禁止 shell；适配器使用 OS API 或安全参数传递；前导 `-` 需 `--`/API 保护 |
| 任意执行 | 不提供命令/参数入口；不写 unit/plist |
| 审计 | `start`/`stop`/`restart`/`enable` 记录时间、服务名、动作、结果；幂等 no-op 也记录 |
| 脱敏 | 不记录环境变量、密钥、完整命令行；错误详情不含原始命令 |
| 句柄 | `close()` 释放；关闭失败只诊断 |
| 容器 | 仅在 OS 暴露服务管理器时支持；否则 `Unsupported` |
| 输入 | `serviceName` 来自不可信来源时必须校验；`displayName` 不作控制键 |

---

## 7. 缺口

| 项 | 决策 |
| --- | --- |
| unit/plist 写入 | ecosystem/安装器 |
| 服务日志 | `xdk.log`/journald 适配器 X |
| 依赖/排序/健康 | X |
| 清除失败状态（reset-failed） | X |
| 列表分页/过滤 | X；当前返回全量可见列表 |
| 每用户服务（systemd --user、launchd user agent、Windows 每用户服务） | X |
| 服务创建/删除 | ecosystem |
| 非白名单名称 | 不暴露；平台工具查看 |
| 启用三态（enabled/disabled/unknown） | `isEnabled` 为 `Bool`；未知按 false |
| 启用语义平台差异（systemd symlink/launchd override/SCM start type） | 适配器映射；只承诺 OS 报告值 |
| 环境/命令行检查 | 不提供 |
| 容器内服务管理 | 通常 `Unsupported` |
| reload/重载配置 | X |
| 服务事件/热更新 | X |
| 超时策略 | 由 `Context` 决定；无全局默认 |

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | 无领域注解 |
| 本包消费 | `@Value`、`@Builder` |
| 处理器 | 标准 A8 |
| 生成物 | 服务信息值语义 |
| 状态 | 无领域注解；A8 派生 planned；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `ServiceInfo` | `@Value` | 值语义成员 |

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../../ANNOTATION-CATALOG.md)。
