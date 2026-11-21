# `xdk.utils` 工具与集成层总览

| 项 | 值 |
| --- | --- |
| 范围 | 2.x 能力包文档分组：L4 数据/编码 + L7 应用服务 |
| 层 | L4 数据/编码 + L7 应用服务；位于 core/net 之上、solutions 之下 |
| 依赖 | `xdk.core`、`xdk.net`、`xdk.os.*`（按需） |
| 被依赖 | 应用、CLI、服务端、客户端、生态包 |
| 稳定性 | `preview`；不进入 1.0 公共承诺 |
| 文档状态 | 24 个包、158 个类型文件、24 个包 README 已完成；只写设计，不含实现 |

> 全量能力覆盖审计见 [`COVERAGE.md`](../COVERAGE.md)。
> utils 的 API 广度与方法面见 [`API-SURFACE.md`](API-SURFACE.md)；跨域场景与能力分析见 [`SCENARIOS.md`](../SCENARIOS.md)、[`CAPABILITY.md`](../CAPABILITY.md)。


---

## 1. 层定位

utils 不是“杂项工具堆”，而是按单一职责拆分的可复用能力组：

```text
  core      语言/运行时基础
  data      codec/crypto/compress/random/uuid/stats/
            functional/graph/reflect/toml/yaml/xml
  net       网络传输与协议
  os        OS/硬件/GPU/防火墙/容器/虚拟化
  services  validate/cache/queue/schedule/event/resilience/
            metrics/trace/audit/terminal/i18n/test
```

规则：

- utils 文档组可以依赖 core/net/os；core/net/os 不得依赖 utils 文档组。
- 各包单一职责；禁止 `utils.common`/`utils.misc`/`utils.helpers` 式大杂烩。
- 不重复 core/net/os 已有能力；能由 core 组合出来的，不再建包。
- 不提供全局可变状态、隐式初始化、后台线程、自动注册。
- 公共类型一类型一文件；包 README 只做索引/规则/场景/缺口。

---

## 2. 包矩阵

| 包 | 职责 | 类型数 | 状态 | 文档 |
| --- | --- | ---: | --- | --- |
| `xdk.codec` | JSON/CSV/Base64/Hex | 13 | 设计完成 | [`utils/codec/`](codec/README.md) |
| `xdk.crypto` | Hash/HMAC/AEAD/KDF/签名/国密 | 17 | 设计完成 | [`utils/crypto/`](crypto/README.md) |
| `xdk.compress` | gzip/zlib/deflate/zstd/lz4/brotli/zip/tar | 13 | 设计完成 | [`utils/compress/`](compress/README.md) |
| `xdk.random` | PRNG/SecureRandom/采样 | 4 | 设计完成 | [`utils/random/`](random/README.md) |
| `xdk.uuid` | UUID v4/v7、ULID | 3 | 设计完成 | [`utils/uuid/`](uuid/README.md) |
| `xdk.stats` | 摘要/直方图/回归/移动平均 | 7 | 设计完成 | [`utils/stats/`](stats/README.md) |
| `xdk.functional` | eager Seq/生成器/Lazy | 3 | 设计完成 | [`utils/functional/`](functional/README.md) |
| `xdk.resilience` | retry/breaker/rate limit/bulkhead/timeout/fallback | 7 | 设计完成 | [`utils/resilience/`](resilience/README.md) |
| `xdk.validate` | 规则/Schema/错误聚合 | 8 | 设计完成 | [`utils/validate/`](validate/README.md) |
| `xdk.cache` | 并发 LRU+TTL+权重+加载 | 4 | 设计完成 | [`utils/cache/`](cache/README.md) |
| `xdk.queue` | 有界/批处理/延迟队列 | 5 | 设计完成 | [`utils/queue/`](queue/README.md) |
| `xdk.schedule` | cron/命名作业/misfire | 8 | 设计完成 | [`utils/schedule/`](schedule/README.md) |
| `xdk.metrics` | Counter/Gauge/Histogram/Registry | 11 | 设计完成 | [`utils/metrics/`](metrics/README.md) |
| `xdk.trace` | Tracer/Span/Propagator | 9 | 设计完成 | [`utils/trace/`](trace/README.md) |
| `xdk.audit` | 审计事件/脱敏 | 5 | 设计完成 | [`utils/audit/`](audit/README.md) |
| `xdk.terminal` | ANSI/进度/表格/提示 | 8 | 设计完成 | [`utils/terminal/`](terminal/README.md) |
| `xdk.i18n` | 消息目录/复数/数字/日期 | 7 | 设计完成 | [`utils/i18n/`](i18n/README.md) |
| `xdk.test` | 断言/测试注册/运行器 | 7 | 设计完成 | [`utils/test/`](test/README.md) |
| `xdk.event` | 事件总线/订阅 | 3 | 设计完成 | [`utils/event/`](event/README.md) |
| `xdk.reflect` | 类型元数据反射 | 4 | 设计完成 | [`utils/reflect/`](reflect/README.md) |
| `xdk.graph` | 图模型/遍历/拓扑 | 2 | 设计完成 | [`utils/graph/`](graph/README.md) |
| `xdk.yaml` | YAML 多文档/profile/属性源 | 5 | 设计完成 | [`utils/yaml/`](yaml/README.md) |
| `xdk.toml` | TOML ↔ JsonValue | 2 | 设计完成 | [`utils/toml/`](toml/README.md) |
| `xdk.xml` | XML 树/解析/序列化 | 3 | 设计完成 | [`utils/xml/`](xml/README.md) |
| **合计** | | **158** | | |

---

## 3. 边界与去重

| 能力 | 已有归属 |  决策 |
| --- | --- | --- |
| 容器/排序/查找 | `xdk.collections` | 不重复；`functional` 只做惰性/eager 组合 |
| 正则/URL/内嵌资源 | `xdk.text`/`xdk.net.uri`/`xdk.sys` | 不建 `utils.regex`/`utils.url`/`utils.resource` |
| 时间/日期/时长 | `xdk.time` | 不重复；`schedule` 只做作业调度 |
| 文件/IO/路径 | `xdk.io`/`xdk.fs` | 不重复；`compress` 只做编码 |
| 日志/配置/CLI | `xdk.log/config/cli` | 不重复；`audit`/`terminal` 不替代日志/CLI |
| 健康/就绪 | `xdk.runtime` | 不建 health 包；复用 `HealthRegistry` |
| TCP/UDP/TLS/HTTP/WS | `xdk.net.*` | 不重复 |
| JWT | `../jwt` | 不放入 utils |
| TLS/证书链 | `net.tls` | crypto 只提供算法，不建 TLS |
| 驱动/硬件 | `xdk.os.*` | 不放入 utils |

X 扩展面（本批已设计）：

- `xdk.event`：同步事件总线；
- `xdk.reflect`：只读类型元数据；
- `xdk.graph`：无向/有向图与遍历；
- `xdk.compress`：zstd/lz4/brotli 算法类；
- `xdk.yaml`/`xdk.toml`/`xdk.xml`：文档格式编解码。

仍不建包：

- health：复用 `xdk.runtime`；
- resource：复用 `xdk.sys.Resource`。

---

## 注解对接（P1）

 注解把编解码、校验与治理策略声明为**编译期契约**；处理器生成序列化器、校验器、包装器、观测/审计切面、测试清单与作业注册，运行时只读静态注册表，不做反射。

| 包 | 注解 | 编译期检查 / 生成 |
| --- | --- | --- |
| `xdk.codec` | `@Serializable`、`@JsonName` | JSON 编解码器、字段名映射 |
| `xdk.yaml` / `xdk.toml` / `xdk.xml` | `@YamlName`、`@TomlName`、`@XmlName` | 文档字段名映射 |
| `xdk.validate` | `@Validate`、`@Min`、`@Max`、`@Pattern`、`@Email` | 校验器生成 |
| `xdk.cache` / `xdk.resilience` | `@Cacheable`、`@CacheEvict`、`@Retry`、`@CircuitBreaker`、`@RateLimit`、`@Timeout` | 缓存/重试/熔断包装器 |
| `xdk.metrics` / `xdk.trace` / `xdk.audit` | `@Metered`、`@Traced`、`@Audited` | 指标/追踪/审计包装 |
| `xdk.test` / `xdk.schedule` | `@Test`、`@Before`、`@After`、`@Benchmark`、`@Scheduled`、`@Cron` | 测试清单、作业注册 |

完整矩阵见 [`ANNOTATION-SYSTEM.md`](../ANNOTATION-SYSTEM.md) §5。注解只生成显式包装/元数据，不改变类型系统、错误模型或资源所有权。

## 4. 依赖方向

```text
annotations
  └─ xdk.errors/runtime/meta/bytes/text/collections/math/time/io/fs/sys/log/config/cli/execution
       ├─ net.uri/net/tls/http/websocket/mime
       ├─ os.*
       └─ utils.*
       ├─ codec → text/bytes/collections
       ├─ crypto → bytes/random
       ├─ compress → bytes/fs
       ├─ random → math/time/runtime
       ├─ uuid → random
       ├─ stats → collections/math
       ├─ functional → collections
       ├─ resilience → errors/execution/time
       ├─ validate → codec/text/collections
       ├─ cache → execution/runtime
       ├─ queue → execution
       ├─ schedule → execution/time
       ├─ metrics → stats/time/runtime
       ├─ trace → time/runtime/text/collections
       ├─ audit → errors/text
       ├─ terminal → io/text
       ├─ i18n → text/time/codec
       ├─ test → errors/execution/time/collections
       ├─ event → errors/codec/execution
       ├─ reflect → errors
       ├─ graph → errors/collections
       ├─ yaml → codec
       ├─ toml → codec
       └─ xml → errors/bytes
```

规则：

- 同层依赖必须无环；`uuid → random`、`validate → codec`、`metrics → stats` 是允许的向下依赖。
- `trace` 不依赖 `metrics`；`audit` 不依赖 `log`；`test` 不依赖 `terminal`/`i18n`。
- `health` 不建包，复用 `xdk.runtime`。

---

## 5. 批次计划

| 批次 | 范围 | 状态 |
| --- | --- | --- |
| -A 数据 | codec、crypto、compress、random、uuid、stats | 设计完成 |
| -B 流程 | functional、resilience、validate、cache、queue、schedule | 设计完成 |
| -C 可观测 | metrics、trace、audit | 设计完成 |
| -D 集成 | terminal、i18n、test | 设计完成 |
| X 扩展 | event、reflect、graph、zstd/lz4/brotli、yaml/toml/xml | 设计完成 |

说明：

- “设计完成”不等于“实现完成”；`src/xdk` 尚未实现 。
- 实现批次必须同时补场景、FFI/runtime 支撑、门禁与测试。
-  不进入 1.0 公共承诺；是否纳入后续版本由用户签字。

---

## 6. 质量门禁

每个包必须满足：

- 包 README 有定位、原则、类型索引、场景、缺口；
- 每个公开类型独立 PascalCase 文件，14 段；
- 类型索引与文件一一对应；
- 所有相对链接可达；
- 参数命名检查 PASS；
- 无 `Void`、空参数 `Ok()`、`Result<void>`、`self._`、`self(...)`、`new T()`、`// ...`；
- 资源有 `close()`；阻塞方法首参 `Context`；
- 不重复 core/net/os 已有能力。

当前校验：

```text
24 个包 README
158 个类型文件
158/158 14 段
check_doc_naming: PASS
相对链接: 0 broken
src/xdk: 无改动
```

---

## 7. 文档地图

| 文档 | 内容 |
| --- | --- |
| `OVERVIEW.md` | 本文件： 层计划、包矩阵、边界、依赖、批次 |
| `README.md` | utils 层总览、包状态、能力矩阵、去重 |
| `PLAN.md` | utils 包/类型级计划与状态 |
| `WORK-ALLOCATION.md` | 并行工作分配、冲突分析与集成校验 |
| `.<pkg>/README.md` | 包索引 |
| `.<pkg>/<Type>.md` | 单类型契约 |

---

## 8. 变更记录

- 2026-11-21：从 `docs/design/utils` 整理为 `docs/design/solutions/ml`；补齐 utils 层计划、包矩阵、去重边界、依赖与批次；136 个类型文件纳入 utils 计划。
- 2026-11-22：补齐 X 扩展 event/reflect/graph/zstd/lz4/brotli/yaml/toml/xml； 达到 24 包/155 类型。
- 2026-11-22：YAML 提升到 Spring Boot 级：多文档/profile/属性扁平化/合并键； 达到 24 包/158 类型。
