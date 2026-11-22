# `xdk.metrics` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.metrics` |
| 层 | L7 应用服务（文档分组 `utils/`） |
| 依赖 | `xdk.errors`、`xdk.execution`、`xdk.runtime`、`xdk.time`、`xdk.io`、`xdk.collections`、`xdk.math`、`xdk.stats` |
| 被依赖 | 应用、客户端/服务端观测、导出适配器 |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

进程内指标模型与导出合同：

- 四种指标：`Counter`、`Gauge`、`Histogram`、`Timer`；
- 不可变快照：`MetricSample`、`MetricFamily`；
- 非泛型指标合同：`Metric`；
- 注册表：`Registry`；
- 导出：`Exporter`、`MetricsFormat`。

职责边界：

- 只记录可聚合数值，不记录离散事件/级别；`metrics` 不是 `log` 的别名，也不依赖 `log`。
- 指标对象与注册表都是显式实例；没有全局注册表、全局导出器或隐式单例。
- 直方图桶数学复用 `xdk.stats.BucketHistogram`；分布摘要复用 `xdk.stats.Summary`，本包不复制算法。
- 导出只定义协议与数据模型；具体编码器/传输由应用或 X 扩展提供。

不做：

- 抓取 HTTP 服务、Push Gateway、告警、仪表盘；
- 时序数据库、持久化、跨进程/分布式聚合；
- exemplars、OpenTelemetry 协议、Trace 关联；
- 动态桶、精确直方图分位；
- 日志门面、审计、健康检查（分别归 `log`/`audit`/`runtime`）；
- 全局注册表或“默认”指标。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 非泛型协议 | XNull 禁止泛型协议；`Metric`/`Exporter` 不带类型参数 |
| 显式实例 | 注册表由调用方持有；不提供全局访问器 |
| 不可变快照 | `MetricSample`/`MetricFamily` 构造后不可变；读接口返回副本 |
| 算法复用 | 桶计数委托 `stats.BucketHistogram`；时长分位委托 `stats.Summary` |
| 冲突可见 | 注册冲突返回 `Result`，不静默覆盖 |
| 线程安全 | 指标与注册表均可跨任务共享；快照弱一致 |
| 无 log 依赖 | 指标不写日志；错误用 `Result`/panic 表达 |
| 格式分离 | 数据模型与导出编码分离；格式由 `MetricsFormat` 显式选择 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `MetricKind` | enum | Counter/Gauge/Histogram/Timer | [`MetricKind.md`](MetricKind.md) |
| `MetricSample` | class | 不可变单点样本 | [`MetricSample.md`](MetricSample.md) |
| `MetricFamily` | class | 不可变族快照 | [`MetricFamily.md`](MetricFamily.md) |
| `Metric` | protocol | 非泛型指标合同 | [`Metric.md`](Metric.md) |
| `Counter` | class | 单调累计 | [`Counter.md`](Counter.md) |
| `Gauge` | class | 瞬时值 | [`Gauge.md`](Gauge.md) |
| `Histogram` | class | 固定边界桶分布 | [`Histogram.md`](Histogram.md) |
| `Timer` | class | 单调时钟时长统计 | [`Timer.md`](MetricTimer.md) |
| `Registry` | class | 线程安全指标注册表 | [`Registry.md`](Registry.md) |
| `Exporter` | protocol | 格式/导出/flush/close 合同 | [`Exporter.md`](Exporter.md) |
| `MetricsFormat` | enum | Text/Json/Prometheus | [`MetricsFormat.md`](MetricsFormat.md) |

索引共 11 个类型文件；每个类型一个 PascalCase 文件。

X：具体 Prometheus/JSON/Text 导出器、OpenTelemetry 适配、固定内存分位、exemplars、分布式聚合。

---

## 4. 顶层函数

`metricKindName`/`metricsFormatName` 是包内辅助函数，仅用于诊断/导出前缀，不构成独立入口；除此之外无顶层函数。

---

## 5. 技术/支撑/依赖

- 技术：加锁累加、固定边界桶计数、流式摘要/分位、快照、注册表冲突检测、格式编码。
- 支撑：`RuntimeMonitor.enter/exit`、`nowMono`、`isNaN`/`isFinite`、`sortedBy`、`Duration`、`Writer.writeAll`。
- 依赖：`errors`、`execution`、`runtime`、`time`、`io`、`collections`、`math`、`xdk.stats`。
- 明确不依赖：`xdk.log`、`xdk.net`、`xdk.fs`（导出器由调用方提供 Writer）。

| 依赖 | 用途 |
| --- | --- |
| `xdk.errors` | `Error`、`Result`、`BasicError`、`ErrorKind` |
| `xdk.execution` | `Context` |
| `xdk.runtime` | `RuntimeMonitor`、`nowMono` |
| `xdk.time` | `Duration` |
| `xdk.io` | `Writer`、`Context.background`、`toUtf8` |
| `xdk.collections` | `Map`、`List`、`sortedBy` |
| `xdk.math` | `isNaN`、`isFinite` |
| `xdk.stats` | `Histogram`、`Summary`、`HistogramBucket` |

---

## 6. 场景

### M1：HTTP 请求计数

```xnull
Registry registry = new Registry()
Counter requests = new Counter("http_requests", "HTTP requests", "1", [:])
Result<Unit, Error> added = registry.register(requests)
if added.isErr() { return 1 }
requests.inc()
```

需要按方法/状态分标签时，直接构造并 `register`；同族所有序列必须使用相同 help/unit：

```xnull
Counter getRequests = new Counter("http_requests", "HTTP requests", "1", ["method":"GET","status":"200"])
Result<Unit, Error> labeled = registry.register(getRequests)
if labeled.isErr() { return 1 }
getRequests.inc()
```

如果不需要自定义 help/unit，`registry.counter("http_requests")` 是空元数据的快捷路径；同族混用非空与空 help/unit 会返回 `AlreadyExists`。

### M2：请求延迟直方图

```xnull
Result<Histogram, Error> created = registry.histogram("request_ms", [5.0, 10.0, 25.0, 50.0])
if created.isErr() { return 1 }
Histogram latency = created.value()
latency.observe(12.0)
Double p95 = latency.percentile(95.0)
```

同一族不同标签使用独立 `Histogram` 实例并 `register`；边界与 help/unit 必须一致（便捷方法创建空 help/unit）。

### M3：调用计时

```xnull
Result<Timer, Error> created = registry.timer("operation")
if created.isErr() { return 1 }
Timer timer = created.value()
Long start = timer.start()
Result<Unit, Error> result = operation()
Duration elapsed = timer.stop(start)
if result.isErr() { return 1 }
```

`stop` 自动记录；`observe(Duration)` 用于外部已有时长。

### M4：导出

```xnull
static Int exportMetrics(Exporter exporter, Registry registry, Writer writer) {
    Result<Unit, Error> exported = exporter.export(context, registry, writer)
    if exported.isErr() {
        diagnose("metrics export: " + exported.error().describe())
        return 1
    }
    Result<Unit, Error> flushed = writer.flush()
    if flushed.isErr() {
        diagnose("metrics flush: " + flushed.error().describe())
        return 1
    }
    return 0
}
```

调用方拥有 Writer；导出器不关闭它。具体 `Exporter` 实现由应用或 X 提供。

### M5：测试隔离

每个测试创建独立 `Registry`，结束时 `clear()`；不使用全局注册表，避免测试间污染。

### M6：冲突处理

```xnull
Result<Counter, Error> counter = registry.counter("latency")
Result<Histogram, Error> histogram = registry.histogram("latency", [10.0])
```

第二个调用返回 `AlreadyExists`，不覆盖原 Counter。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 全局注册表 | 禁止；每个应用/测试自建 `Registry` |
| 标签 | 指标构造器接收标签；`register` 登记带标签序列；便捷方法只创建空标签序列 |
| 直方图算法 | 委托 `xdk.stats.BucketHistogram`；本包只加标签/快照面 |
| 直方图分位 | 桶级近似，p 使用 0..100；不承诺精确 |
| Timer 分位 | 委托 `xdk.stats.Summary`，精确但内存随样本增长；X 再补固定内存方案 |
| Timer 单位 | 固定 `"ms"`；不做秒/毫秒自动换算 |
| 非有限值 | `MetricSample.value` 允许 NaN/±Inf；导出器按格式编码 |
| 注册冲突 | 返回 `AlreadyExists`；同族同标签重复登记幂等 |
| 快照一致性 | 注册表快照弱一致；不阻塞并发登记/移除 |
| 线程安全 | 指标与注册表均线程安全；导出器实例不保证并发 export |
| Exporter 取消 | 协议无 `Context`；实现用 `Context.background()`，取消由调用方/Writer 负责 |
| 具体导出器 | 不在本包定义；由应用或 X 实现 |
| `le` 标签 | Histogram 保留；用户标签不得使用 |
| 指标命名/转义 | 本包做基本校验；Prometheus 名称清洗/转义由导出器负责 |
| 与 log 的关系 | 无依赖；metrics 不是 log 别名 |

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | `@Metered` |
| 本包消费 | `@Value`、`@Builder` |
| 处理器 | MetricsAnnotationProcessor（Validate/Generate） |
| 生成物 | 指标注册/包装器 |
| 状态 | 领域注解 planned；A8 派生 implemented（含限制）；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 服务方法 | `@Metered` | 指标包装 |
| `MetricSample`/`MetricFamily`/`Histogram` | `@Value`/`@Builder` | 值语义/构造 |

### 声明

```x
@Target(Method)
@Retention(Source)
@annotation Metered {
    final String name
    final String unitName = ""
}
```

声明文件：每个注解单独一个 PascalCase 文件；处理器为构建期类型；生成代码在 `<package>/generated/`。

### 使用

```x
class UserService {
    @Metered("user.find", "requests")
    User find(Long id) {
        // ...
    }
}
```

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
