# `xdk.log` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.log` |
| 层 | `xdk.core` / L3 |
| 依赖 | `xdk.errors`、`xdk.runtime`、`xdk.text`、`xdk.time`、`xdk.io` |
| 被依赖 | `config`、`cli`、`net` |
| 稳定性 | 基础 `stable`；结构化/Sink `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

`xdk.log` 提供分级日志：Level/Field/Record/Sink/Formatter/Logger/Factory，以及过滤、脱敏、采样管道。

不做：全局 logger、远程日志协议、文件轮转完整实现、JSON 格式化。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 显式 logger | 无全局单例；Factory 由调用方持有 |
| 结构化 | Field/Record；纯文本也走 Formatter |
| 不改变控制流 | 日志失败只诊断，不抛业务错误 |
| 无隐式上下文 | 不读环境/全局变量；字段显式 |
| 资源 close | Sink 可持资源；close 幂等 |
| 非线程安全 | Sink 线程安全由实现声明 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `Level` | enum | 日志级别 | [`Level.md`](Level.md) |
| `Field` | class | 键值字段 | [`Field.md`](Field.md) |
| `LogRecord` | class | 日志记录 | [`LogRecord.md`](LogRecord.md) |
| `Sink` | protocol | 输出目标 | [`Sink.md`](Sink.md) |
| `ConsoleSink` | class | 控制台输出 | [`ConsoleSink.md`](ConsoleSink.md) |
| `MemorySink` | class | 内存记录 | [`MemorySink.md`](MemorySink.md) |
| `Formatter` | protocol | 记录→文本 | [`Formatter.md`](Formatter.md) |
| `TextFormatter` | class | 文本格式 | [`TextFormatter.md`](TextFormatter.md) |
| `Logger` | class | 级别/字段/输出 | [`Logger.md`](Logger.md) |
| `LoggerFactory` | class | 命名 logger 管理 | [`LoggerFactory.md`](LoggerFactory.md) |
| `Filter` | protocol | 记录过滤 | [`Filter.md`](Filter.md) |
| `PredicateFilter` | class | predicate 过滤 | [`PredicateFilter.md`](PredicateFilter.md) |
| `KeepAllFilter` | class | 默认全保留 | [`KeepAllFilter.md`](KeepAllFilter.md) |
| `Redactor` | protocol | 文本脱敏 | [`Redactor.md`](Redactor.md) |
| `ReplaceRedactor` | class | 子串替换脱敏 | [`ReplaceRedactor.md`](ReplaceRedactor.md) |
| `IdentityRedactor` | class | 默认不脱敏 | [`IdentityRedactor.md`](IdentityRedactor.md) |
| `Sampler` | protocol | 记录采样 | [`Sampler.md`](Sampler.md) |
| `EveryNSampler` | class | 每 N 条采样 | [`EveryNSampler.md`](EveryNSampler.md) |
| `KeepAllSampler` | class | 默认全采样 | [`KeepAllSampler.md`](KeepAllSampler.md) |

X 未纳入本批：`FileSink`、`RotatingFileSink`、`AsyncSink`、`MultiSink`、`JsonFormatter`。它们必须在后续批次单独设计，不得塞进现有类。

---

## 4. 技术/支撑/依赖

- 技术：级别比较、结构化字段、Sink 协议、Formatter、有界内存队列。
- 支撑：`Stdio`、`StringBuilder`、`time.nowMono/nowWall`、`Context`（异步 sink）。
- 依赖：`errors`、`runtime`、`text`、`time`、`io`、`Level`、`Field`、`LogRecord`、`Sink`、`Formatter`、`Filter`、`Redactor`、`Sampler`。

---

## 5. 场景

### L1：CLI 日志

`Logger` + `ConsoleSink`；级别过滤；stdout/stderr 选择由 sink 决定。

### L2：测试断言

`MemorySink`；`records()` 快照；容量/丢弃。

### L3：结构化字段

`Logger.withField`；`LogRecord.fields`；Formatter 输出 `key=value`。

### L4：服务边界

日志失败不改变 Result；`Context` 取消不阻塞日志。

---

## 6. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 全局 logger | 禁止 |
| 文件 sink/轮转 | X |
| 异步 sink | X |
| 过滤链 | 单个 `Filter`；`PredicateFilter`/`KeepAllFilter` 已纳入；多过滤器组合 X |
| 脱敏/采样 | 已纳入：`Redactor`/`ReplaceRedactor`/`IdentityRedactor`、`Sampler`/`EveryNSampler`/`KeepAllSampler` |
| JSON 格式 | X（依赖 codec） |
| 线程安全 | 实现声明；默认非线程安全 |
| 日志失败 | 诊断，不抛业务错误 |

## 9. 1.x 管道合同（C7）

1.x 已实现、2.x 必须保留的日志管道：

| 环节 | 2.x 合同 | 失败/边界 |
| --- | --- | --- |
| 级别阈值 | `Logger.enabled(level)`；`level >= minimum` | 不进入后续环节 |
| 过滤 | [`Filter.md`](Filter.md)；`PredicateFilter`/`KeepAllFilter` | `record == null` → `false`；拒绝不进入 sampler/redactor/sink |
| 采样 | [`Sampler.md`](Sampler.md)；`EveryNSampler`/`KeepAllSampler` | `EveryNSampler(interval)` ≤0 → panic；`count()` 按实例 |
| 脱敏 | [`Redactor.md`](Redactor.md)；`ReplaceRedactor`/`IdentityRedactor` | message 与每个 `Field.value` 都改写；空 needle no-op |
| 输出 | `Sink.write(LogRecord)` | 失败只诊断，不改变业务控制流 |

固定顺序：**级别阈值 → Filter.allow → Sampler.keep → Redactor → Sink**。`Logger` 默认 `KeepAllFilter`/`KeepAllSampler`/`IdentityRedactor`；`withFilter/withRedactor/withSampler` 返回新 `Logger` 并保留其余配置。

示例：

```xnull
Logger logger = new Logger("app", Level.Info)
    .withFilter(new PredicateFilter((LogRecord record) -> record.level() == Level.Error))
    .withSampler(new EveryNSampler(10))
    .withRedactor(new ReplaceRedactor("secret", "***"))
```

测试义务：阈值/过滤/采样/脱敏/输出五段顺序；filter 拒绝不进入 sampler；sampler 只统计通过前置条件的记录；redactor 同时改 message 与字段值；默认三件套保持旧行为；派生 Logger 独立配置。

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | 无领域注解 |
| 本包消费 | `@Value`、`@Builder`、`@Override` |
| 处理器 | 标准 A8 / 编译器内建 |
| 生成物 | 日志记录值语义、Sink/Formatter/Filter 签名校验 |
| 状态 | 无领域注解；A8 派生 planned；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `Field`/`LogRecord`/`TextFormatter` | `@Value` | 值语义成员 |
| `LogRecord` 构造 | `@Builder` | 多字段构造 |
| `Sink`/`Formatter`/`Filter`/`Redactor`/`Sampler` 实现 | `@Override` | 签名校验 |

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
