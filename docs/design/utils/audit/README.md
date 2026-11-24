# `xdk.audit` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.audit` |
| 层 | L7 应用服务（文档分组 `utils/`） |
| 依赖 | `xdk.errors`、`xdk.text` |
| 被依赖 | 应用、服务端、合规审计管道、证书/权限/管理操作 |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |
| 实现状态 | M10.1：`AuditLevel`/`AuditEvent`/`AuditSink`/`AuditRedactor`/`AuditLogger` implemented；sink 调用在状态 monitor 外、由独立 sink monitor 串行化 |

---

## 1. 包定位

`xdk.audit` 提供**合规审计事件**的创建、同步写入和脱敏：

- `AuditLevel`：Info/Warning/Critical；
- `AuditEvent`：不可变事件快照；
- `AuditSink`：非泛型输出协议；
- `AuditLogger`：同步、线程安全的审计入口；
- `AuditRedactor`：按插入顺序应用的正则脱敏器。

审计不是调试日志的别名：它记录“谁对什么做了什么、结果如何”，用于合规、追责和安全调查；不记录调试轨迹，也不按级别丢弃事件。

不做：通用日志、级别过滤、采样、异步队列、重试、轮转、远程传输、格式化、告警路由、全局 redactor 规则、审计策略引擎、事件签名/哈希链。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 审计非日志 | 不依赖 `xdk.log`，不复用 `Logger`/`Level`/`Sink`；语义、生命周期和失败处理独立 |
| 事件不可变 | `AuditEvent` 构造后不可变；`withField`/`withLevel` 返回新事件 |
| 同步、不丢弃 | `AuditLogger.log` 同步调用 sink；没有内部队列、采样或静默丢弃 |
| 错误不吞 | sink 的 `write`/`flush` 错误原样返回；关闭后的调用返回 `Unavailable` |
| 显式生命周期 | `AuditSink.close` 与 `AuditLogger.close` 幂等；关闭后写入失败而非静默成功 |
| 脱敏局部 | `AuditRedactor` 的规则按实例持有；无全局 PII 模式；规则按插入顺序应用 |
| 线程安全 | `AuditLogger`/`AuditRedactor` 用运行时监视器保护状态；sink 调用被串行化 |
| 无全局状态 | 无全局 logger、全局 sink、全局 redactor、全局注册表 |
| 最小依赖 | 仅依赖 `errors` 与 `text`（`Regex`）；时间/同步使用运行时原语 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `AuditLevel` | enum | Info/Warning/Critical | [`AuditLevel.md`](AuditLevel.md) |
| `AuditEvent` | class | 不可变审计事件 | [`AuditEvent.md`](AuditEvent.md) |
| `AuditSink` | protocol | 写入/刷新/关闭/可用 | [`AuditSink.md`](AuditSink.md) |
| `AuditLogger` | class | 同步审计入口/生命周期 | [`AuditLogger.md`](AuditLogger.md) |
| `AuditRedactor` | class | 局部正则脱敏 | [`AuditRedactor.md`](AuditRedactor.md) |

X：异步/批量 sink、文件轮转、远程传输、结构化策略、字段键脱敏、捕获组替换、墙钟时间戳、事件签名。

---

## 4. 顶层函数

无。所有行为由五个类型承载；不提供包级全局 logger 或全局 redactor。

---

## 5. 技术/支撑/依赖

- 技术：不可变快照、防御性复制、单调时间戳、同步 sink 写入、正则替换、监视器同步、幂等关闭。
- 支撑：`RuntimeMonitor`、`nowMono`（运行时原语，不计入公共包依赖）、`BasicError`、`ErrorKind.Unavailable`、`Regex.replaceAll`。
- 依赖：`xdk.errors`（`Error`/`BasicError`/`ErrorKind`/`Result`/`Unit`）、`xdk.text`（`Regex`）。
- 明确不依赖：`xdk.log`、`xdk.io`、`xdk.fs`、`xdk.net`；需要文件/网络/轮转时由应用实现 `AuditSink`。

---

## 6. 场景

### A1：管理操作审计

应用提供一个 `AuditSink` 实现并注入 `new AuditLogger(sink)`；`logger.logAction("alice","role.grant","project/42","success")`；`logger.flush()`。

### A2：敏感字段脱敏

`AuditRedactor redactor = new AuditRedactor()`；编译 `Regex` 后 `redactor.addPattern(pattern, "token=[REDACTED]")`；`logger.withRedactor(redactor)`；之后 `log` 自动脱敏 actor/action/resource/outcome 和字段值。

### A3：写入失败

sink 返回 `Err`；`log` 返回同一个错误；调用方告警或重试；logger 保持打开；不静默丢弃。

### A4：关闭

`logger.close()` 先停止接受新事件，再 `flush`，再 `sink.close`；重复 close 返回 `Ok(unit)`；close 后的 `log`/`flush` 返回 `Unavailable`。

### A5：自定义 sink

应用实现 `AuditSink`（内存、文件、HTTP、消息队列）；不要求继承 `xdk.log.Sink`；一个 sink 由一个 logger 独占时无需线程安全。

### A6：测试

用内存 sink 捕获事件；用完整 `AuditEvent` 构造器注入固定 `timestampMono`；断言脱敏结果和错误传播。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 与日志的关系 | 独立包；不依赖 `xdk.log`；`AuditLevel` 不是 `Level`，不提供转换 |
| `AuditRedactor` 命名 | 审计专用脱敏器；不复用日志包 X 的 `Redactor`；规则与生命周期独立 |
| `AuditLogger.withField` | 变异当前 logger，返回同一实例，支持链式调用；不是不可变派生 |
| `AuditLogger.withRedactor` | 变异当前 logger，返回同一实例；替换已有 redactor；null 拒绝 |
| `AuditEvent.withField`/`withLevel` | 不可变派生，返回新事件；与 logger 的变异式 `with*` 明确区分 |
| 默认字段优先级 | logger 字段先合并，事件同名字段优先；合并后再脱敏 |
| 脱敏范围 | actor/action/resource/outcome 与字段值；字段键不改写，避免键冲突和消费方破坏 |
| 替换语义 | `Regex.replaceAll` 字面替换；不支持 `$1` 捕获组展开；X |
| 空替换 | 拒绝；避免把 actor/action/outcome 脱敏成空串，破坏事件不变量 |
| 规则顺序 | 按加入顺序；后一条规则看到前一条的输出 |
| 全局规则 | 禁止；每个 `AuditRedactor` 独立；共享实例的修改对所有持有者可见 |
| 采样/过滤 | 不做；所有级别都写入；审计不能因级别被丢弃 |
| 异步/批量 | 不做；同步写入，背压由调用方承担；X |
| 自动 flush | `log` 不自动 flush；在合规检查点显式 `flush`，`close` 会 flush |
| Sink close 返回 | `void`；close 不报告错误；logger 在 close 前 flush 并保留 flush 错误 |
| 写入失败 | 原样返回；不重试、不包装、不关闭 logger；调用方决定重试/告警 |
| 关闭后行为 | `log`/`flush` 返回 `Unavailable`；`withField`/`withRedactor` panic；`isClosed` 为 true |
| 时间戳 | 只有单调毫秒；无墙钟/ISO 文本；避免时钟回拨影响排序；墙钟由 sink/应用补充 |
| `describe` 格式 | 人类可读摘要，不是 JSON/CSV；sink 应结构化序列化字段 |
| 线程安全 | logger 串行化 sink 调用；sink 被多个 logger 共享时必须自行同步；禁止重入 |
| 文件/网络/轮转 | 不做内置 sink；由应用实现 `AuditSink`；X |
| 事件签名/哈希链 | X；当前不提供防篡改证明 |

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | `@Audited` |
| 本包消费 | `@Value`、`@Builder` |
| 处理器 | AuditAnnotationProcessor（Validate/Generate） |
| 生成物 | 审计包装器/脱敏元数据 |
| 状态 | `@Audited` implemented (M10.2)；A8 派生 implemented（含限制）；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 敏感方法 | `@Audited` | 审计事件 |
| `AuditEvent` | `@Value`/`@Builder` | 值语义/构造 |

### 声明

```x
@Target(Method)
@Retention(Source)
@annotation Audited {
    final String action
}
```

声明文件：每个注解单独一个 PascalCase 文件；处理器为构建期类型；生成代码在 `<package>/generated/`。

### 使用

```x
class UserService {
    @Audited("user.delete")
    void delete(Long recordId) {
        // ...
    }
}
```

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
