# `xdk.utils` 层设计

| 项 | 值 |
| --- | --- |
| 范围 | 2.x 能力包文档分组：L4 数据/编码 + L7 应用服务 |
| 依赖 | `xdk.core`；按需 `xdk.net`/`xdk.os` |
| 被依赖 | 应用/生态 |
| 稳定性 | `preview`；设计完成，实现未开始 |
| 文档原则 | 每包 README + 每类型一个 PascalCase 文件 |

---

## 1. 定位

`xdk.utils` 不是“小工具集合”，而是可独立依赖的标准工具库组。目标不是“有几个 helper 能跑”，而是覆盖 JDK、.NET、Go、C++ STL、Python 标准库中常用的**通用能力面**：

- 数据：JSON/CSV/Base64/Hex、YAML/TOML/XML、crypto、compress、random、uuid、stats、validate；
- 运行时：cache、queue、schedule、metrics、trace、audit、event、reflect、graph；
- 集成：terminal、i18n、test。

`health` 不建包，复用 `xdk.runtime`。

`xdk.core` 已经提供的基础能力不重复设计；utils 只补 core 没有、且跨应用复用的库。

---

## 2. 边界与去重

| 已有能力 | 归属 | utils 决策 |
| --- | --- | --- |
| 容器/迭代/排序 | `xdk.collections` | 不重复 |
| 正则 | `xdk.text.Regex` | 不建 `utils.regex` |
| URL/百分号编码 | `net.uri` | 不建 `utils.url` |
| 内嵌资源 | `sys.Resource` | 不建 `utils.resource` |
| 时间/日期/时长 | `xdk.time` | 不重复；调度器只做任务调度 |
| IO/文件/路径 | `xdk.io`/`xdk.fs` | 不重复 |
| 日志/配置/CLI | `xdk.log/config/cli` | 不重复 |
| TCP/UDP/TLS/HTTP/WS | `net.*` | 不重复 |

参考对象：

- JDK：`java.util`、`java.time`、`java.util.zip`、`java.security`、`java.util.regex`；
- .NET：`System.Text.Json`、`System.Security.Cryptography`、`System.IO.Compression`、`System.Collections.Concurrent`、`System.Diagnostics`；
- Go：`encoding/*`、`crypto/*`、`compress/*`、`math/rand`、`regexp`、`sync`、`container/*`；
- C++ STL：`<random>`、`<regex>`、`<chrono>`、`<filesystem>`、`<algorithm>`、`<numeric>`；
- Python：`json/csv/base64/hashlib/hmac/secrets/random/uuid/gzip/zipfile/tarfile/statistics/queue/dataclasses`。

---

## 3. 包目录与状态

| 包 | 职责 | 对齐 | 状态 |
| --- | --- | --- | --- |
| `xdk.codec` | JSON/CSV/Base64/Hex | .NET Json、Go encoding、Python json/csv | 设计完成 |
| `xdk.uuid` | UUID v4/v7、ULID | JDK UUID、.NET Guid、Go/Python uuid | 设计完成 |
| `xdk.random` | PRNG/SecureRandom/采样 | JDK Random、.NET Random、Go math/rand、C++ random | 设计完成 |
| `xdk.functional` | eager Seq/生成器/Lazy | Guava FluentIterable/Streams、Commons Lang Streams、samber/lo、more-itertools、range-v3 | 设计完成 |
| `xdk.resilience` | retry/circuit breaker/rate limiter/bulkhead/timeout/fallback | Polly、resilience4j、tenacity、Guava RateLimiter | 设计完成 |
| `xdk.crypto` | Hash/HMAC/AES/ChaCha/SM2/SM3/SM4/ZUC/KDF/常量时间/校验和 | JCA、.NET Cryptography、Go crypto、Python hashlib、GB/T 32905/32907/32918 | 设计完成 |
| `xdk.compress` | gzip/zlib/deflate/zstd/lz4/brotli/zip/tar | JDK zip、.NET Compression、Go compress、zstd/lz4/brotli | 设计完成 |
| `xdk.stats` | 流式摘要/直方图/回归/移动平均 | Python statistics、Commons Math | 设计完成 |
| `xdk.validate` | 规则/Schema/错误聚合 | Jakarta Validation、.NET DataAnnotations、pydantic | 设计完成 |
| `xdk.cache` | 并发 LRU+TTL+权重+加载 | Caffeine、MemoryCache、Guava Cache | 设计完成 |
| `xdk.queue` | 有界丢弃/批处理/延迟队列 | JDK BlockingQueue、.NET Channels、Python queue | 设计完成 |
| `xdk.schedule` | cron/命名作业/misfire | Quartz、ScheduledExecutor、robfig/cron | 设计完成 |
| `xdk.metrics` | Counter/Gauge/Histogram/Registry | Micrometer、System.Diagnostics.Metrics | 设计完成 |
| `xdk.trace` | Tracer/Span/Propagator | OpenTelemetry、Activity | 设计完成 |
| `xdk.audit` | 审计事件/脱敏 | 安全审计 | 设计完成 |
| `xdk.terminal` | ANSI/进度/表格/提示 | 终端工具 | 设计完成 |
| `xdk.i18n` | 消息目录/复数/格式 | .NET Globalization、ICU | 设计完成 |
| `xdk.test` | 断言/测试注册/运行器 | JUnit、xUnit、Go testing、pytest | 设计完成 |
| `xdk.event` | 事件总线/订阅 | Guava EventBus、Commons Event | 设计完成 |
| `xdk.reflect` | 类型元数据反射 | Guava Reflect、Commons Lang reflect、.NET Reflection | 设计完成 |
| `xdk.graph` | 图模型/遍历/拓扑 | Guava Graph | 设计完成 |
| `xdk.yaml` | YAML 多文档/profile/属性源 | SnakeYAML、Spring Boot YamlPropertySourceLoader | 设计完成 |
| `xdk.toml` | TOML ↔ JsonValue | BurntSushi/toml、Python tomllib | 设计完成 |
| `xdk.xml` | XML 树/解析/序列化 | JAXP、Go encoding/xml、Python ElementTree | 设计完成 |

> JWT 不属于 utils：独立包 `xdk.jwt`（已设计，见 [`network/jwt/README.md`](../network/jwt/README.md)）。

> 层计划见 [`OVERVIEW.md`](OVERVIEW.md)；包/类型计划见 [`PLAN.md`](PLAN.md)；并行工作分配见 [`WORK-ALLOCATION.md`](WORK-ALLOCATION.md)。
> health 不单独建包：`xdk.runtime` 已有完整 `HealthState`/`HealthReport`/`HealthCheck`/`HealthRegistry`。

---

## 4. 参考能力矩阵

| 能力 | JDK | .NET | Go | C++ | Python | XDK |
| --- | --- | --- | --- | --- | --- | --- |
| JSON | 无内建 | System.Text.Json | encoding/json | 无标准 | json | codec |
| CSV | 无内建 | 无内建 | encoding/csv | 无标准 | csv | codec |
| Base64/Hex | Base64/HexFormat | Convert | encoding/base64/hex | 无标准 | base64/binascii | codec |
| 哈希/HMAC | JCA | Cryptography | crypto/* | 无标准 | hashlib/hmac | crypto |
| 对称加密 | JCA | Cryptography | crypto/cipher | 无标准 | cryptography 第三方 | crypto |
| KDF | JCA | Cryptography | crypto/* | 无标准 | hashlib.scrypt | crypto |
| 随机 | Random/SecureRandom | Random | math/rand, crypto/rand | `<random>` | random/secrets | random |
| UUID | UUID | Guid | 第三方 | 无标准 | uuid | uuid |
| 压缩 | zip/gzip | Compression | compress/* | 无标准 | gzip/zipfile | compress |
| 统计 | 无内建 | 无内建 | 无内建 | `<numeric>` | statistics | stats |
| 校验 | 无内建 | DataAnnotations | 无内建 | 无标准 | 无标准 | validate |
| 缓存 | 无内建 | MemoryCache | 无内建 | 无标准 | lru_cache | cache |
| 队列 | java.util.concurrent | Channels | channels | 无标准 | queue | queue |
| 调度 | ScheduledExecutor | Timer | time.Ticker | 无标准 | sched | schedule |
| 指标/追踪 | 无内建/第三方 | Metrics/Activity | expvar/otel | 无标准 | 无标准 | metrics/trace |
| 健康 | 无内建 | HealthChecks | 无内建 | 无标准 | 无标准 | health |
| 终端/i18n | 无内建/第三方 | Console/Globalization | 无内建 | 无标准 | 无标准 | terminal/i18n |
| 测试 | JUnit 第三方 | xUnit 第三方 | testing | 无标准 | unittest/pytest | test |

结论：XDK 不能把 utils 做成“少量 helper”；必须按上述能力面逐包补齐，且明确设计完成面与 X。

---

## 4.1 GitHub 实际对标

只参考官网不够；按 GitHub 仓库真实目录/类名补充。已核对：

| 仓库 | 实际能力（目录/类） | 对 XDK 的结论 |
| --- | --- | --- |
| `google/guava` | `cache`、`collect`、`hash`、`io`、`math`、`net`、`primitives`、`reflect`、`util.concurrent`、`graph`、`eventbus`、`escape/html/xml` | functional/lazy、resilience、cache 已补；仍缺 event/reflect/graph，hash 仍可扩展 |
| `apache/commons-lang` | `builder`、`compare`、`concurrent`、`event`、`exception`、`function`、`mutable`、`reflect`、`stream`、`text`、`time`、`tuple`、`util` | functional/stream 基础已补；mutable/builder 工具仍缺，text/time 已由 core 覆盖 |
| `abseil/abseil-cpp` | `algorithm`、`container`、`crc`、`hash`、`random`、`status`、`strings`、`synchronization`、`time`、`types`、`utility` | 缺 CRC/hash 扩展、latched/notification、string utilities（core 部分有） |
| `golang/go/src` | `archive/tar`、`compress/{bzip2,flate,gzip,lzw,zlib}`、`crypto/*`、`encoding/{base32,base64,binary,csv,hex,json,pem,xml}`、`hash/*`、`maps/slices/structs/iter`、`uuid/unique/weak` | crypto/compress/tar 已扩展；functional 已补 eager/Lazy，iter 与 bzip2/lzw 仍 X |
| `dotnet/runtime/src/libraries` | `System.Text.Json`、`Security.Cryptography`、`IO.Compression`、`Formats.Tar`、`IO.Hashing`、`Collections.Concurrent/Immutable`、`Threading.Channels/RateLimiting`、`Diagnostics.Metrics/Activity`、`Linq` | tar/CRC64/rate limiting/functional 已补；brotli、metrics/trace 仍缺 |
| `python/cpython/Lib` | `json/csv/base64/hashlib/hmac/secrets/random/uuid/gzip/zipfile/tarfile/statistics/queue/sched/itertools/functools` | codec/crypto/compress/functional/stats/queue/schedule 已补；iter 仍 X |
| `ben-manes/caffeine` / `cachetools/cachetools` | LoadingCache、TTL、权重、统计、淘汰监听 | cache 已补 TTL/权重/统计/监听；single-flight 仍 X |
| `App-vNext/Polly` / `resilience4j` / `jd/tenacity` | Retry、CircuitBreaker、Timeout、Bulkhead、RateLimiter、Fallback、Hedging | 新增 `xdk.resilience` |
| `go-playground/validator` / `pydantic` / `FluentValidation` | 字段规则、跨字段、嵌套、错误聚合 | validate 已支持规则/Schema/嵌套/错误聚合；跨字段用 custom |
| `samber/lo` / `more-itertools` / `boltons` | filter/map/flatMap/group/chunk/window/zip/uniq/partition/lazy | 新增 `xdk.functional` |
| `Textualize/rich` / `jedib0t/go-pretty` | 表格、进度、列表、树、文本样式 | terminal 要覆盖 table/progress/tree |
| `open-telemetry/opentelemetry-go` / `prometheus/client_golang` | Meter/Tracer/Span/Exporter/Registry | metrics/trace 需独立包，不做日志别名 |
| `robfig/cron` | cron 表达式/调度 | schedule 已补 cron/句柄/misfire；分布式/持久化 X |
| `facebook/zstd` / `lz4/lz4` | zstd/lz4 压缩 | compress 已补 zstd/lz4/brotli |

结论：utils 文档组的 24 个包、158 个类型文件均已完成设计；`health` 复用 `xdk.runtime`；X 扩展已纳入。设计完成不等于实现完成。

## 5. 完成标准

每个包必须：

- README 有类型索引、能力/非目标、场景、缺口；
- 每个公开类型独立 PascalCase 文件，14 项设计；
- 明确设计完成面与 X；
- 无 `Void`、空参数 `Ok()`、`Result<void>`、`self._`、`self(...)`、`new T()`、`// ...`；
- 资源有生命周期/close；阻塞有 Context；
- 不重复 core/net 已有能力。

---

## 6. 依赖与顺序

```text
core/bytes/text/collections/math/time/errors
  ├─ xdk.codec
  ├─ xdk.random → xdk.uuid
  ├─ xdk.functional
  ├─ xdk.crypto → xdk.compress
  ├─ xdk.resilience
  ├─ xdk.stats / validate / cache / queue / schedule
  └─ xdk.metrics / trace / audit / terminal / i18n / test
  └─ xdk.event / reflect / graph / yaml / toml / xml
  └─ health → xdk.runtime（不建包）
```

utils 文档组的 24 个包设计完成；JWT 独立在 `../network/jwt`；X 扩展已纳入；实现另排。
