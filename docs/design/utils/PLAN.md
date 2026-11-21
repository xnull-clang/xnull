# `xdk.utils` 计划与状态

| 项 | 值 |
| --- | --- |
| 层 | L4 数据/编码 + L7 应用服务（文档分组 `utils/`） |
| 范围 | 24 个 2.x 能力包 |
| 类型文件 | 158 |
| 包 README | 24 |
| 状态 | 设计完成；实现未开始 |
| 权威 | 类型契约以各包 `<Type>.md` 为准；包边界以 [`../PACKAGE-MAP.md`](../PACKAGE-MAP.md) 为准 |

---

## 1. 包状态

| 包 | 类型数 | 批次 | 状态 |
| --- | ---: | --- | --- |
| `xdk.codec` | 13 | -A | 设计完成 |
| `xdk.crypto` | 17 | -A | 设计完成 |
| `xdk.compress` | 13 | -A | 设计完成 |
| `xdk.random` | 4 | -A | 设计完成 |
| `xdk.uuid` | 3 | -A | 设计完成 |
| `xdk.stats` | 7 | -A | 设计完成 |
| `xdk.functional` | 3 | -B | 设计完成 |
| `xdk.resilience` | 7 | -B | 设计完成 |
| `xdk.validate` | 8 | -B | 设计完成 |
| `xdk.cache` | 4 | -B | 设计完成 |
| `xdk.queue` | 5 | -B | 设计完成 |
| `xdk.schedule` | 8 | -B | 设计完成 |
| `xdk.metrics` | 11 | -C | 设计完成 |
| `xdk.trace` | 9 | -C | 设计完成 |
| `xdk.audit` | 5 | -C | 设计完成 |
| `xdk.terminal` | 8 | -D | 设计完成 |
| `xdk.i18n` | 7 | -D | 设计完成 |
| `xdk.test` | 7 | -D | 设计完成 |
| `xdk.event` | 3 | X | 设计完成 |
| `xdk.reflect` | 4 | X | 设计完成 |
| `xdk.graph` | 2 | X | 设计完成 |
| `xdk.yaml` | 5 | X | 设计完成 |
| `xdk.toml` | 2 | X | 设计完成 |
| `xdk.xml` | 3 | X | 设计完成 |
| **合计** | **158** | | |

---

## 2. 批次

| 批次 | 范围 | 设计 | 实现 |
| --- | --- | --- | --- |
| -A 数据 | codec/crypto/compress/random/uuid/stats | 完成 | 未开始 |
| -B 流程 | functional/resilience/validate/cache/queue/schedule | 完成 | 未开始 |
| -C 可观测 | metrics/trace/audit | 完成 | 未开始 |
| -D 集成 | terminal/i18n/test | 完成 | 未开始 |
| X 扩展 | event/reflect/graph/zstd/lz4/brotli/yaml/toml/xml | 设计完成 | 未开始 |

---

## 3. 类型清单

### -A 数据

```text
codec (13): Json, JsonValue, JsonObject, JsonArray, JsonNumber, JsonKind,
            JsonOptions, Csv, CsvOptions, CsvReader, CsvWriter, Base64, Hex
crypto (17): HashAlgorithm, Hash, Hmac, ChecksumAlgorithm, Checksum, KdfAlgorithm,
             Kdf, CipherAlgorithm, CipherPadding, Cipher, AsymmetricAlgorithm,
             KeyPair, PublicKey, PrivateKey, SignatureScheme, Asymmetric, ConstantTime
compress (13): CompressionLevel, Gzip, Zlib, Deflate, Zstd, Lz4, Brotli, ZipArchive, ZipEntry,
               ZipOptions, ZipWriter, Tar, TarEntry
random (4): RandomSource, Random, SecureRandom, WeightedChoice
uuid (3): UuidVersion, Uuid, Ulid
stats (7): RunningStats, Summary, HistogramBucket, Histogram, Regression,
           MovingAverage, Ema
```

### -B 流程

```text
functional (3): Seq, Sequences, Lazy
resilience (7): Retry, CircuitState, CircuitBreaker, RateLimiter, Bulkhead, Timeout, Fallback
validate (8): Rule, Rules, FieldRule, Schema, ValidationContext, ValidationError,
              ValidationResult, Validator
cache (4): CacheOptions, EvictionReason, CacheStats, Cache
queue (5): DropPolicy, QueueStats, BoundedQueue, BatchQueue, DelayQueue
schedule (8): ScheduleKind, Schedule, CronExpression, MisfirePolicy, Job,
              JobHandle, SchedulerOptions, Scheduler
```

### -C 可观测

```text
metrics (11): MetricKind, MetricSample, MetricFamily, Metric, Counter, Gauge,
              Histogram, Timer, Registry, Exporter, MetricsFormat
trace (9): SpanKind, SpanStatus, SpanContext, SpanEvent, TraceOptions, Sampler,
           Propagator, Span, Tracer
audit (5): AuditLevel, AuditEvent, AuditSink, AuditLogger, Redactor
```

### -D 集成

```text
terminal (8): Terminal, Ansi, Color, Style, ProgressBar, Spinner, Prompt, Table
i18n (7): Locale, MessageCatalog, MessageFormatter, PluralRules, NumberFormat,
           DateFormat, Translator
test (7): Assert, Test, TestSuite, TestRunner, TestResult, TestStatus, TestContext
```

### X 扩展

```text
event (3): Event, EventSubscription, EventBus
reflect (4): ReflectKind, MemberInfo, TypeInfo, Reflect
graph (2): GraphEdge, Graph
compress 扩展 (3): Zstd, Lz4, Brotli
yaml (5): Yaml, YamlOptions, YamlDocument, YamlPropertySource, YamlVersion
toml (2): Toml, TomlOptions
xml (3): Xml, XmlElement, XmlOptions
```

---

## 4. 不建包/延后

| 能力 | 决策 |
| --- | --- |
| health | 不建包；复用 `xdk.runtime` 的 `HealthState`/`HealthReport`/`HealthCheck`/`HealthRegistry` |
| resource | 不建包；`xdk.sys.Resource` 已覆盖 |
| regex | 不建包；`xdk.text.Regex` 已覆盖 |
| `utils.url` | 不建包；`net.uri` 已覆盖 |
| `xdk.jwt` | ，独立于 utils |

---

## 5. 验收

```text
24 个包 README
158 个类型文件
158/158 14 段
check_doc_naming: PASS
相对链接: 0 broken
src/xdk: 无改动
```

“设计完成”不表示实现完成；实现批次必须同时补场景、FFI/runtime 支撑、门禁与测试。
