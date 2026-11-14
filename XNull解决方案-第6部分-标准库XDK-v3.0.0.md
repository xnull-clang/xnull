# XNull 解决方案 第 6 部分：标准库 XDK

| 项 | 值 |
| --- | --- |
| 文档编号 | 第 6 部分（S6） |
| 文档版本 | 3.0.0 |
| 规范状态 | 草案（包目录与分层合同；符号级 API 随实现追加） |
| 发布日期 | 2026-11-15 |
| 适用对象 | XNull 语言实现与标准库作者 |
| 相关部分 | 第 1 部分 v3.4.0；第 2 部分 v3.4.0；第 3 部分 v3.2.0；第 4 部分 v1.2.0；第 5 部分 v1.3.0；第 7 部分 v2.0.0 |

版本规则：修订号用于不改变语义的澄清，次版本用于向后兼容的新增，主版本用于破坏性变更。历史版本见 git 记录。

## 0. 定位

XDK 是应用代码与运行时之间的**唯一公共接口**。本部分规定 XDK 的分层、包目录、包间依赖、合同原则、应用边界映射与版本规则。

- **类型与算法在库里**：包、类型、函数、容器算法、文本处理、文件与网络能力都由库提供；
- **编译器不做库的活**：只做语法、类型检查、字面量脱糖、`for-in` 脱糖与代码生成；
- **运行时不实现库算法**：只提供内存、句柄、调度、诊断、FFI 原语；
- **包名是库的公开结构**：不是编译器内建类型；编译器只把 `import xdk.a.b` 解析到源码。

## 1. 分层模型

```text
┌─────────────────────────────────────────────────────┐
│ L0 应用代码                                          │
└───────────────────────┬─────────────────────────────┘
                        │ 只经 L1
┌───────────────────────▼─────────────────────────────┐
│ L1 公共 API 层（本部分第 4 节的包目录）               │
└───────────────────────┬─────────────────────────────┘
                        │ 只调 L2
┌───────────────────────▼─────────────────────────────┐
│ L2 原语层：内存/句柄/调度/诊断/FFI 合同              │
└───────────────────────┬─────────────────────────────┘
                        │ 唯一接触原生世界
┌───────────────────────▼─────────────────────────────┐
│ L3 操作系统 / 原生世界（C ABI）                       │
└─────────────────────────────────────────────────────┘
```

规则：

- **单向依赖**：L0 → L1 → L2 → L3；禁止反向、跨层或绕过。
- **L1 是开发者可见面**：所有公开类型、函数、错误面、取消面、资源面都在 L1。
- **L2 不含领域策略**：不实现集合、文本、文件、网络算法。
- **L3 只经 FFI 合同进入**：三合同面、租约与错误码映射（第 7 部分附录 A）。

## 2. 层间合同

### 2.1 L1 公共 API 层

- 可失败操作返回 `Result<T, E>`；错误类型遵守第 4 部分。
- 可阻塞操作的首参是 `Context`；挂起点可取消，以 `Cancelled` 报告。
- 持有 OS 资源的类型必须提供显式 `close()`；不得以 `deinit` 作为唯一关闭路径。
- 无全局可变单例；无隐式初始化/清理钩子；无线程局部隐式状态。
- 每个 API 标注稳定性：`stable` / `preview` / `internal`。

### 2.2 L2 原语层

- 只提供原语，不定义领域 API 名称。
- 原语合同必须声明：阻塞分类、租约/所有权、错误码映射、可取消性。
- 原语不得暴露给应用代码；L1 负责把原语翻译成领域 API。

### 2.3 编译器、运行时与库的分工

- **编译器**：语法、类型检查、字面量脱糖（`[...]` → `List.of` / `Set.of`，`[k:v]` → `Map.of`）、`for-in` 脱糖（`iterator()` / `Iterator<T>`）、代码生成。编译器只识别脱糖目标名与迭代方法形状，不维护库类型成员表。
- **运行时**：内存、句柄、调度、诊断、FFI 原语。运行时不实现集合、文本、文件、网络等库算法。
- **库**：所有类型与算法；包目录见 §4；API 以源码为权威。

### 2.4 L3 原生边界

- 只经第 7 部分附录 A 的 FFI 合同进入。
- 不允许“任意原生函数直调”；每个入口都是声明式合同对象。
- 原生能力进入 XNull 后必须适配本语言的错误、资源、取消合同。

## 3. 合同原则

以下七条适用于 L1 的全部包：

1. **错误合同**：一切可失败操作返回 `Result`；禁止用 panic 表达可恢复失败。
2. **资源合同**：持有 OS 资源的类型必须有 `close()`；关闭失败不等于未关闭。
3. **取消合同**：可阻塞操作携带 `Context`；挂起点可取消并以 `Cancelled` 报告。
4. **命名合同**：类型 PascalCase；方法小驼峰动词开头；布尔读访问 `isX` / `hasX`；私有内部名 `_name`。
5. **无隐式合同**：无全局可变状态、无隐式初始化/清理、无线程局部隐式状态。
6. **稳定性行**：每个 API 标注 `stable` / `preview` / `internal`；preview 可在次版本变更，internal 非承诺。
7. **架构知情**：每个包必须声明能力、层级、依赖、稳定性；实现不得隐藏对 L2/L3 的依赖。

## 4. 包目录

包目录是库的公开结构。`T0` 核心、`T1` 应用、`T2` 平台/计算；`生态` 不属于 XDK。

### 4.1 T0 核心包

任何程序都可依赖；稳定优先。

| 包 | 职责 | 关键类型 / API | 依赖 |
| --- | --- | --- | --- |
| `xdk.errors` | 错误协议、分类、观测 | `Error`、`ErrorKind`、`wrap` / `mapErr` / `report` | L2 诊断 |
| `xdk.runtime` | 诊断、退出、时钟 | `diagnose`、`exit`、`nowMono`、`nowWall` | L2 |
| `xdk.meta` | 语言/XDK 版本、构建信息、目标平台 | `languageVersion`、`xdkVersion`、`targetPlatform` | 无 |
| `xdk.log` | 结构化日志 | `Logger`、`Level`、字段、sink | `errors`、`runtime`、`text`、`time` |
| `xdk.config` | 配置快照与覆盖 | `Config`、profile、环境变量白名单 | `fs`、`text`、`codec` |
| `xdk.text` | 文本、编码、格式化、解析 | `Text`、`StringBuilder`、UTF 转换、`formatInt`、`parseInt` | `errors`、`bytes` |
| `xdk.bytes` | 字节缓冲区与位操作 | `Bytes`、`ByteBuffer`、端序、位运算 | `errors` |
| `xdk.collections` | 容器与算法 | `List`、`Map`、`Set`、`Iterator`、`sort` / `groupBy` / `dedup` | `errors` |
| `xdk.math` | 数值函数与常量 | 三角/指数/对数/取整、`Int128` 运算 | `errors` |
| `xdk.time` | 时间与日期 | `Instant`、`Duration`、`DateTime`、`TimeZone` | `runtime`、`errors` |
| `xdk.io` | 流与缓冲区 | `Reader`、`Writer`、`Stream`、`Buffered*` | `bytes`、`errors` |
| `xdk.fs` | 文件、目录、路径 | `File`、`Dir`、`Path`、临时文件、原子写 | `io`、`errors` |
| `xdk.sys` | 进程、环境、平台、信号 | `Process`、`Env`、`platform`、`signal` | `runtime`、`errors` |
| `xdk.tasks` | 任务与结构化并发 | `Task`、`TaskGroup`、`Context` | `errors`、`runtime` |
| `xdk.sync` | 互斥、通道、原子 | `Mutex`、`Channel`、`AtomicInt` / `AtomicBool` / `AtomicRef` | `errors`、`tasks` |
| `xdk.cli` | 命令行解析与用法 | `Args`、`Command`、`usage`、退出码映射 | `text`、`sys` |

### 4.2 T1 应用包

服务、工具、网络与数据应用使用；按需引入。

| 包 | 职责 | 关键类型 / API | 依赖 |
| --- | --- | --- | --- |
| `xdk.regex` | 正则表达式 | `Regex`、编译、匹配、替换 | `text`、`errors` |
| `xdk.codec` | 数据编码 | JSON、CSV、Base64、Hex、URL 编码 | `text`、`bytes`、`collections` |
| `xdk.random` | 伪随机与种子 | `Random`、`nextInt`、`nextDouble` | `math`、`time` |
| `xdk.stats` | 统计 | 均值、中位数、分位数、直方图 | `collections`、`math` |
| `xdk.crypto` | 密码学 | SHA-1/256/512、HMAC、AES、KDF、常量时间比较 | `bytes`、`errors` |
| `xdk.compress` | 压缩 | gzip、zlib、zip | `bytes`、`io` |
| `xdk.uuid` | 唯一标识 | UUID v4/v7、ULID | `random`、`time` |
| `xdk.i18n` | 国际化 | 消息目录、复数、locale | `text`、`codec` |
| `xdk.validate` | 校验 | 字段规则、schema、错误聚合 | `text`、`collections` |
| `xdk.resource` | 内嵌资源 | `resourceExists`、`readResource`、`listResources` | `bytes`、`errors` |
| `xdk.terminal` | 终端 | TTY、ANSI、进度、提示 | `io`、`sys` |
| `xdk.test` | 测试 | 断言、测试注册、runner 钩子 | `errors`、`text` |
| `xdk.net` | 网络基础 | 地址、Socket、DNS | `io`、`bytes`、`tasks` |
| `xdk.net.uri` | URI/URL | 解析、构造、编码 | `text` |
| `xdk.net.http` | HTTP | 客户端、服务端、头部、Cookie、multipart | `net`、`text`、`codec`、`tasks` |
| `xdk.net.tls` | TLS | 证书、配置、握手 | `net`、`crypto` |
| `xdk.net.websocket` | WebSocket | 握手、帧、关闭 | `net.http`、`bytes` |
| `xdk.net.mime` | MIME | 媒体类型、扩展名映射 | `text` |
| `xdk.executor` | 执行器 | 专用执行器、线程归属 | `tasks`、`sync` |
| `xdk.timer` | 定时器 | 定时、周期、截止 | `tasks`、`time` |
| `xdk.metrics` | 指标 | Counter、Gauge、Histogram | `sync`、`time` |
| `xdk.trace` | 链路追踪 | Span、上下文传播 | `tasks`、`time` |
| `xdk.health` | 健康检查 | readiness、liveness | `time`、`metrics` |
| `xdk.audit` | 审计 | 事件、字段、脱敏 | `log`、`time` |
| `xdk.schedule` | 调度 | cron、周期任务 | `time`、`tasks` |
| `xdk.sql` | SQL 接口 | 连接、语句、参数、事务 | `net`、`io`、`codec` |
| `xdk.cache` | 进程内缓存 | LRU、TTL | `collections`、`time` |
| `xdk.queue` | 进程内队列 | 有界队列、批量、关闭 | `sync`、`tasks` |

### 4.3 T2 平台与计算包

平台相关或重计算；按目标平台稳定。

| 包 | 职责 | 关键类型 / API | 依赖 |
| --- | --- | --- | --- |
| `xdk.ui` | 窗口与应用生命周期 | `Window`、`App`、`onAttach` / `onDetach` / `dispose` | `gfx`、`input`、`tasks` |
| `xdk.gfx` | 2D 图形 | 画布、颜色、几何、路径 | `math`、`image` |
| `xdk.image` | 图像 | PNG/JPEG 解码与编码、像素缓冲 | `bytes`、`io` |
| `xdk.font` | 字体与排版 | 字体加载、字形、文本布局 | `bytes`、`gfx` |
| `xdk.input` | 输入 | 键盘、鼠标、触摸、快捷键 | 无（事件源） |
| `xdk.clipboard` | 剪贴板 | 文本/二进制读写 | `ui` |
| `xdk.serial` | 串口 | 打开、读写、超时 | `io`、`sys` |
| `xdk.device` | 设备与传感器 | GPIO、I2C、SPI、摄像头 | `sys`、`tasks` |
| `xdk.geo` | 地理 | 坐标、距离、投影、路径 | `math`、`collections` |
| `xdk.tensor` | CPU 张量 | 形状、步长、逐元素、矩阵乘 | `math`、`bytes` |
| `xdk.linalg` | 线性代数 | 分解、求解、特征值 | `tensor`、`math` |

### 4.4 生态（不属于 XDK）

以下能力由第三方库或应用提供，不进入 XDK：

- 数据库驱动（PostgreSQL/MySQL/SQLite 等具体驱动；`xdk.sql` 只提供通用接口）；
- 协议栈（MQTT、SIP、Modbus、OPC-UA、GB28181 等）；
- Web 框架、RPC 框架、模板引擎；
- ML 训练框架、GPU 算子、模型运行时；
- 包管理器、构建插件、IDE 插件生态；
- 领域库（量化因子库、机器人 SLAM、图像识别模型等）。

## 5. 应用边界映射

S0 的应用方向与包目录一一对应；不是每个程序都要引入全部包。

| 应用方向 | 主要包 |
| --- | --- |
| 企业业务系统 | `errors`、`runtime`、`log`、`config`、`collections`、`text`、`codec`、`time`、`uuid`、`validate`、`i18n`、`metrics`、`trace`、`health`、`audit`、`sql`、`cache`、`queue` |
| 网络服务与网关 | `net`、`net.uri`、`net.http`、`net.tls`、`net.mime`、`net.websocket`、`tasks`、`sync`、`executor`、`timer`、`metrics`、`trace`、`health` |
| 物联网与设备接入 | `net`、`serial`、`device`、`codec`、`time`、`tasks`、`log` |
| 数据处理与量化 | `collections`、`math`、`stats`、`random`、`codec`、`time`、`tensor`、`linalg` |
| 规则、流程与领域引擎 | `collections`、`text`、`validate`、`schedule`、`log`、`metrics` |
| 数据库、缓存与消息 | `sql`、`cache`、`queue`、`codec`、`crypto`、`net` |
| CPU 算法与仿真 | `math`、`linalg`、`tensor`、`stats`、`random`、`time` |
| AI 应用与智能体 | `net.http`、`codec`、`tensor`、`linalg`、`tasks`、`log`、`trace`、`crypto` |
| 桌面与图形程序 | `ui`、`gfx`、`image`、`font`、`input`、`clipboard`、`fs`、`config` |
| 机器人与边缘应用 | `device`、`serial`、`geo`、`tasks`、`time`、`math`、`log` |
| 语言与编译器工具 | `fs`、`io`、`text`、`codec`、`cli`、`terminal`、`log`、`test` |
| 本地工具与运维程序 | `cli`、`terminal`、`fs`、`io`、`sys`、`config`、`log`、`codec` |

## 6. 依赖规则

1. **分层方向**：T0 只能依赖 T0 与 L2；T1 只能依赖 T0/T1 与 L2；T2 只能依赖 T0/T1/T2 与 L2。
2. **禁止反向**：T0 不得依赖 T1/T2；T1 不得依赖 T2。
3. **禁止环**：包依赖图必须无环；环是规范错误。
4. **禁止 util 包**：不得新增 `util`、`common`、`misc`、`helpers`、`base` 这类无单一职责的包。
5. **依赖声明**：每个包的文档头必须列出能力、Tier、依赖、稳定性；未登记的依赖视为合同违规。
6. **内部包**：`xdk.internal.*` 不是公共 API，应用不得导入；内部包不受稳定性承诺。

## 7. 命名与粒度

- 包名全小写、点分隔：`xdk.<domain>` 或 `xdk.<domain>.<sub>`。
- 一个包一个职责；包内符号超过约 100 个时，按能力拆分，不按“类型/函数”拆分。
- 包名表达能力，不表达实现层次：用 `net.http`，不用 `net.impl.http`。
- 稳定 API 不允许把内部类型暴露到公开签名；公开签名只能使用同包或更低层的公开类型。

## 8. 版本与稳定性

- 新增包：库次版本；新增能力：库次版本；删除、改名、合并包：库主版本。
- T0 包优先稳定；T1 包可以 `preview`；T2 包按平台标注。
- 包改名不影响编译器：编译器只按 `import` 路径解析源码；包名变更属于库版本变更。
- 每个公开符号必须有稳定性标记；`preview` 可在次版本变更，`internal` 不承诺。
