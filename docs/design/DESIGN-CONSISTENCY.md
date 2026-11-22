# 2.x 设计一致性表

| 项 | 值 |
| --- | --- |
| 目的 | 把 15 份全量审计的冲突落成“谁和谁冲突、以谁为准、改哪份文件” |
| 范围 | `docs/design` 的 2.x 设计树；1.x `t0` 只作兼容基线 |
| 权威 | [`ARCHITECTURE.md`](ARCHITECTURE.md) + [`PACKAGE-MAP.md`](PACKAGE-MAP.md) + 逐类型合同 |
| 状态 | Draft for P0 sign-off；`已冻结` 项才可进入实现 |
| 原则 | 先改名/回写，再实现；不带着已知冲突写代码 |

> **2026-11-22 执行状态**：S1/S2 包名归一、S4 desktop 清理、S8 legacy 分层、P0 计数/链接、C7 的 1.x 核心回写、A1/A5/A7/A8 注解文档、P0.5 类型文件改名均已执行；B0 收口。表中状态词表示“决定是否冻结”，不表示所有实现已完成。

---

## 0. 使用规则

1. 本表不是 API 文档；类型签名以逐类型 `.md` 为准。
2. 同一冲突在多处出现时，只改“权威文件”，其他文件回链，不复制第二份契约。
3. `已冻结` = P0 已决定，可以直接实现；`回写` = 目标已定，但源文件还需要改；`延期` = 明确不进 2.x 首批。
4. 任何新冲突必须先登记本表，再改文档/代码。
5. 1.x 的 `t0` + `src/xdk` 是已发布事实，不用 2.x 设计反向覆盖；2.x 破坏性变化走 2.0 迁移。

---

## 1. 结构性冲突

| # | 冲突 | 现状 | 决定 | 改哪份 | 状态 |
| --- | --- | --- | --- | --- | --- |
| S1 | `xdk.core.*` / `xdk.utils.*` 被当成包名 | docs 335 处使用；源码真实包名是 `xdk.errors`、`xdk.log` 等 | 2.x 包名去前缀：`xdk.errors`、`xdk.codec`；`xdk.core`/`xdk.utils` 只作层名 | 全量设计文档 + `PACKAGE-MAP.md` | 回写 |
| S2 | `xdk.execution` 不存在 | docs 使用；源码是 `xdk.tasks`/`xdk.sync` 内建 | 2.x 统一 `xdk.execution`；`tasks`/`sync` 仅 1.x 兼容 | 全量设计文档 + `src/xdk/PLAN.md` | 回写 |
| S3 | 包数 14 / 15 / 16 三种口径 | 1.x 14 公开包；2.x core 15（含 execution）；旧 API-SURFACE 含 tasks/sync | 1.x=14 公开包；2.x core=15 包（runtime+execution+13）；总 75 包/698 类型 | `COVERAGE.md`、`PACKAGE-MAP.md`、`API-SURFACE.md` | P0 冻结 |
| S4 | desktop/UI 残留 | 15 个文件已删；`OsCapability`、`OsHost` 文档、`PLATFORM-BOUNDARY`、`platform/README` 仍有成员/方法/计数 | 2.x 永久移除 desktop/UI；`OsInfo.desktop` 仅保留为 OS 会话字符串，不是 UI 服务 | `platform/os/OsCapability.md`、`platform/os/README.md`、`platform/README.md`、`core/PLATFORM-BOUNDARY.md` | 回写 |
| S5 | `xdk.net.service` 层级 | 包名是 network，但计数在 solutions | 归 L5 网络层；L5=9/125，L8=9/122，总数不变 | `PACKAGE-MAP.md`、`COVERAGE.md`、`solutions/README.md` | P0 冻结 |
| S6 | `xdk.reflect` 是否算反射 | 名字像运行时反射；实际只读类型元数据 | 保留 `xdk.reflect`；只读解析/成员查询，不做动态调用/构造/类加载；注解查询只走 `AnnotationRegistry` | `utils/reflect/README.md`、`ANNOTATION-SYSTEM.md` | P0 冻结 |
| S7 | `API-SURFACE.md` 旧名/旧类型 | 仍列 `Aes`、`LruCache`、`TtlCache`、`Stats`、`tasks/sync`、URL codec 等 | 不再手写；按逐类型合同生成；旧文件只作广度对照 | `API-SURFACE.md`、`utils/API-SURFACE.md`、`core/API-SURFACE.md` | 回写 |
| S8 | 852/854 文件与 25 旧档混在一起 | 新树/1.x 旧档同目录，README 未分层 | 1.x 25 篇标记 legacy；2.x 计数只算类型合同 | `README.md`、`LEGACY-1.0.md`、`COVERAGE.md` | 回写 |
| S9 | 目录 ≠ 包名 | `docs/design/utils/` 下是 24 个不同能力包 | 目录只作文档分组；包名按能力命名；不建 `utils.common` 大杂烩 | `README.md`、各域 README | P0 冻结 |

---

## 2. Core 冲突

| # | 冲突 | 现状 | 决定 | 改哪份 | 状态 |
| --- | --- | --- | --- | --- | --- |
| C1 | `Reader`/`Writer` class → protocol | 1.x 是 class；2.x 文档要求 protocol | 2.x 用 protocol + `ByteArrayReader/Writer`、`StringReader/Writer`；1.x class 提供适配器 | `core/io/Reader.md`、`Writer.md`、`PACKAGE-MAP.md` | 已冻结 |
| C2 | `readU8` EOF：panic vs 0 | 1.x 文档写 EOF panic；2.x 文档写 0=EOF | 2.x 统一 0=EOF；需要严格读取用 `readExactly`/checked 变体返回 `Result` | `core/io` 类型合同 | 已冻结 |
| C3 | `FileMode` → `OpenOptions` | 1.x 有 `FileMode`；2.x 新增 `OpenOptions` | 2.x `OpenOptions` builder；`FileMode` 1.x deprecated 适配 | `core/fs/OpenOptions.md`、`FileMode.md` | 已冻结 |
| C4 | `CommandMatch` → `ParseResult` | 1.x CLI 用 `CommandMatch`；2.x 用 `ParseResult` | 2.x `ParseResult`；1.x `CommandMatch` 别名/适配 | `core/cli` | 已冻结 |
| C5 | `Pair` 固定 vs 泛型 | 源码 `Pair(String, Int)`；2.x 文档 `Pair<A,B>` | 2.x 泛型 `Pair<A,B>`；1.x 固定 `Pair` deprecated；`Entry<K,V>` 保留 | `core/collections/Pair.md`、`geo/linalg/tensor` | 已冻结 |
| C6 | `Map.put` 返回 | 文档写 `Bool`；旧 API 面写 `V?` | 冻结 `Bool`（替换 true、插入 false）；`putIfAbsent` 返回旧值 `V?`；`remove` 返回 `Bool` | `core/collections/Map.md`、`API-SURFACE.md` | 已冻结 |
| C7 | 2.x core 文档比 1.x 旧 | 新 core 删掉 `RuntimeStats/stats`、`joinWith`/`Entry`、log `Filter/Redactor/Sampler`、CLI 短选项/补全、sys 进程组/stdio、`sleepContext`、`buildDate`、`setChecked/apply`、`addDetailed` | 2.x 先从 1.x 同步已实现能力，再加新类型；不得删已实现 API | `core/*/README.md`、`core/*.md` | 回写 |
| C8 | `ConfigSource.load` 是否带 `Context` | 1.x 无 Context；2.x 文档带 Context | 2.x 带 `Context`；1.x 提供无 Context 适配 | `core/config/ConfigSource.md` | 已冻结 |
| C9 | `Sink.write` 是否返回 `Result` | 1.x log Sink 可能无返回；2.x 文档要求 Result | 2.x `Result<Unit, Error>`；日志失败不改变业务控制流 | `core/log/Sink.md` | 已冻结 |
| C10 | `Process.id` 类型 | 1.x 可能是 `Int`；2.x 文档 `Long` | 2.x `Long`；1.x 适配/收窄检查 | `core/sys/Process.md` | 已冻结 |
| C11 | `RuntimeMonitor` 不存在 | audit/cache/event/metrics/queue 都依赖它；runtime/FFI 没有 | P2 在 `xdk.runtime` 实现内部原语 + `monitor*Raw`；不计入 8 个公开类型 | `core/runtime/README.md`、`src/ffi/runtime_raw.xfb` | P2 |
| C12 | `List.copy()` 未确认 | 平台/矩阵文档大量使用 | P2 在 core collections 确认/实现；未实现前文档改 `toList()` 或显式复制 | `core/collections/List.md` | P2 |
| C13 | `isFinite` 缺失 | 2.x math 文档使用；1.x math 源码无 | P2 补 `isFinite/isNaN` 到 `xdk.math` | `core/math/README.md`、`src/xdk/core/math/Math.x` | P2 |
| C14 | `PI` vs `PI()` | 源码是函数 `PI()`；平台文档用裸 `PI` | 统一 `PI()`；数学常量用函数，避免与字段混淆 | `core/math`、`platform/geo/Geo.md` | 回写 |
| C15 | `Bytes.alloc/empty` 缺失 | 2.x bytes 文档有；源码只有 `fromString/fromUtf8` 等 | P2 补 `Bytes.alloc/empty`，或文档改用现有构造 | `core/bytes/Bytes.md` | P2 |
| C16 | `unavailableError/cancelledError` 缺失 | 2.x execution 文档定义；1.x errors 源码无 | P2 补顶层函数到 `xdk.execution`/`xdk.errors`，二选一并冻结 | `core/execution/README.md`、`core/errors/Errors.x` | P2 |

---

## 3. 注解冲突

| # | 冲突 | 现状 | 决定 | 改哪份 | 状态 |
| --- | --- | --- | --- | --- | --- |
| A1 | 目标集合 7 vs 11 | `ANNOTATION-PLAN.md` 写 7 个；`ANNOTATION-SYSTEM.md`/`AnnotationTarget` 写 11 个 | 以 11 个为准：`Package/Type/Annotation/TypeParameter/Field/Method/Constructor/Deinit/Parameter/TypeUse/EnumItem` | `ANNOTATION-PLAN.md` | 回写 |
| A2 | `@Repeatable` 无效果 vs 可用 | 旧计划写“保留但无效果”；新系统写允许重复并保序 | 2.x 支持重复并保序；未标 `@Repeatable` 的重复是错误 | `ANNOTATION-PLAN.md`、`ANNOTATION-SYSTEM.md` | 已冻结 |
| A3 | `@Override` 是否强制 | 旧计划 D1 写“无需强制”；系统表写“强制” | 使用 `@Override` 时强制签名匹配；不要求每个实现都标注 | `ANNOTATION-PLAN.md`、`ANNOTATION-SYSTEM.md` | 已冻结 |
| A4 | `@MustUse` 是否用户注解 | 旧计划把它列入内建注解表 | `@MustUse` 是语言规则，不是 `@annotation`；不得当普通注解使用 | `ANNOTATION-PLAN.md`、`ANNOTATION-SYSTEM.md` | 已冻结 |
| A5 | 诊断码缺失 | S2 §12 没有稳定诊断码表 | P1.0 冻结 `AN00xx` 诊断码表；见 `ANNOTATION-PLAN.md` §10 | `ANNOTATION-PLAN.md` | 回写 |
| A6 | 编译器 0 支持 | `src/mini/main.x` 无 `@annotation`/注解 AST/解析/处理器 | P1 先做 lexer/parser/AST，再做语义/常量/内建/元数据/处理器；14 类型不是第一步 | `src/mini`、`ANNOTATION-PLAN.md` | P1 |
| A7 | 处理器阶段/轮次未冻结 | 文档有 Resolve/Validate/Generate/Finalize，但没有固定点/失败原子性规则 | P1.0 冻结：多轮固定点、生成失败不落半成品、处理器显式启用、确定性输出 | `ANNOTATION-SYSTEM.md` | 回写 |
| A8 | 运行时注册表格式未冻结 | 只写“编译器生成静态表” | P1.0 冻结版本号、排序、目标索引、重复项保留规则；运行时只读 | `annotations/AnnotationRegistry.md`、`ANNOTATION-SYSTEM.md` | 回写 |

---

## 4. Network 冲突

| # | 冲突 | 现状 | 决定 | 改哪份 | 状态 |
| --- | --- | --- | --- | --- | --- |
| N1 | HTTP/2 模型缺伪头/END_STREAM | 设计有 `Http2Session/Stream`，但头模型没有伪头与流结束表示 | P5 前补 `Http2Headers`/`endStream` 显式字段；HTTP/1.1 先实现，HTTP/2 最后 | `network/net/http` | 延期到 P5 |
| N2 | TLS `PrivateKey` 与 crypto 同名 | `net.tls.PrivateKey` 与 `crypto.PrivateKey` 都是私钥句柄 | `xdk.crypto.PrivateKey` 为 owner；TLS 消费它；若必须保留 TLS 句柄，改名 `TlsPrivateKey` | `network/net/tls/PrivateKey.md`、`utils/crypto/PrivateKey.md` | P0 冻结 |
| N3 | `ReconnectPolicy` 同名 | WebSocket 与 `net.service` 各有一个 | WebSocket 保留 `ReconnectPolicy`；`net.service` 改名 `ServiceReconnectPolicy` | `solutions/net-service/ReconnectPolicy.md` | P0 改名 |
| N4 | `ServiceState` 同名 | `os.service` 与 `net.service` 各有一个 | `os.service` 保留 `ServiceState`；`net.service` 改名 `NetServiceState` | `solutions/net-service/ServiceState.md` | P0 改名 |
| N5 | JWT 依赖 crypto/codec | L5 依赖 L4，层级正确；但文档写成 `xdk.crypto` | 改 `xdk.crypto`/`xdk.codec`；JWT 不自己实现密码学 | `network/jwt/README.md` | 回写 |
| N6 | SQL 驱动边界 | `xdk.sql` 只有接口，驱动在生态 | 保持：核心不绑定 PostgreSQL/MySQL/SQLite 驱动；`xdk.db` 只做池/迁移/映射 | `network/sql/README.md`、`solutions/db/README.md` | 已冻结 |
| N7 | WebSocket 正常关闭 vs 错误 | 文档已写“正常关闭不是 Err” | 保持；关闭码/原因显式，不混入传输错误 | `network/net/websocket` | 已冻结 |
| N8 | `net.service` 归位 | 计数在 solutions | 归 L5；见 S5 | `PACKAGE-MAP.md`、`COVERAGE.md` | P0 冻结 |

---

## 5. Platform 冲突

| # | 冲突 | 现状 | 决定 | 改哪份 | 状态 |
| --- | --- | --- | --- | --- | --- |
| P1 | `Pair` 泛型 | geo 需要 `Pair<Double,Double>`；源码固定 | 见 C5；geo 用泛型 `Pair` 或专用 `GeoPoint`，不用 `Entry` 替代 | `platform/geo/Geo.md`、`core/collections/Pair.md` | 已冻结 |
| P2 | `Bytes.alloc/empty` | tensor/serial/device 伪代码依赖 | 见 C15；P2 补 | `core/bytes/Bytes.md` | P2 |
| P3 | `isFinite` | linalg/geo/tensor 值校验依赖 | 见 C13；P2 补 | `core/math` | P2 |
| P4 | `PI` vs `PI()` | `Geo.md` 用裸 `PI` | 见 C14；统一 `PI()` | `platform/geo/Geo.md` | 回写 |
| P5 | `unavailableError/cancelledError` | 平台伪代码直接用 | 见 C16；P2 补 | `core/execution/README.md` | P2 |
| P6 | 适配器注入 vs 包级 raw | `platform/README` 说无全局注册表；serial/device/gpu 的 raw 面是包级自由函数 | P6 前冻结注入模型：`OsHost`/controller 参数，或编译期后端选择；不允许全局可变驱动表 | `platform/README.md`、`platform/*/README.md` | P6 前 |
| P7 | 错误分类不统一 | `Unsupported` 同时表示“平台无能力”和“数学输入不支持”；串口读超时 `Ok(0)`，GPIO/I2C/SPI/GPU 超时 `Timeout`；句柄 ≤0 有 `Io`/`Internal` 两种 | P6 前冻结一张错误映射表：无能力 `Unsupported`、无权限 `PermissionDenied`、超时 `Timeout`、取消 `Cancelled`、数据损坏 `DataCorrupted`、非法参数 `InvalidArgument` | `platform/*/README.md` | P6 前 |
| P8 | 枚举 null/未知成员 fallback 不一致 | `tensorDTypeByteWidth(null)` 返回 1、`geoProjectionName(null)` 返回 `"utm"`、`serialParityName(null)` 返回 `"space"`；其他返回 `"unknown"/"other"` | 统一 null → `"unknown"`（或 panic，按函数合同）；未来成员 → `"other"`；不得把 null 映射成合法成员 | `platform/tensor/TensorDType.md`、`platform/geo/GeoProjection.md`、`platform/serial/*` | 回写 |
| P9 | 生命周期不对称 | Camera 关闭后可重开；GPIO/I2C/SPI 关闭即终止；空路径有的 `trim()==""`，有的 `==""` | 按包冻结：一次性句柄关闭不可重开；可重开句柄显式 `reopen`；路径统一 `trim()==""` | `platform/device/*`、`platform/serial/*` | P6 前 |
| P10 | §10 “依赖”表成环 | `Eigen↔Svd`、`Lu↔Qr`、`DeviceBus↔DeviceManager`、`GpuBuffer↔GpuFence` | §10 改名为“相关类型”，不是 import DAG；实现按正文 §9/§10 裁剪 | `platform/*/*.md` | 回写 |
| P11 | TensorView 溢出/stride 0 | `offset + Σ((dim-1)*stride)` 未防 `Long` 溢出；stride 0 等价广播，但 tensor 文档说不做广播 | P6 前补溢出检查；stride 0 要么明确允许只读广播，要么拒绝；与 README 二选一 | `platform/tensor/TensorView.md`、`tensor/README.md` | P6 前 |
| P12 | GPU 双对象模型 | `xdk.gpu` 与 `xdk.accel` 各有 Program/CommandBuffer/Fence | 刻意分离：`xdk.gpu` 是计算基线；`xdk.accel` 组合/适配，不互操作；文档明确 | `platform/gpu/README.md`、`solutions/accel/README.md` | 已冻结 |
| P13 | `OsCapability` 含 desktop 成员 | Display/Desktop/Audio/Input/Power/Thermal 仍在枚举 | 删除这些成员；`OsInfo.desktop` 只作会话字符串；平台文档同步 | `platform/os/OsCapability.md` 等 | 回写 |

---

## 6. Data / Services 冲突

| # | 冲突 | 现状 | 决定 | 改哪份 | 状态 |
| --- | --- | --- | --- | --- | --- |
| U1 | API-SURFACE 旧名 | `Aes`/`LruCache`/`TtlCache`/`LoadingCache`/`Stats`/`UrlCodec`/`JsonString` 等 | 以类型合同为准；P0 后按合同重生成；旧名不进实现 | `utils/API-SURFACE.md`、`API-SURFACE.md` | 回写 |
| U2 | 24 vs 25 包 | `utils/README.md` 表含 `health` 行，但正文说 24 包；`API-SURFACE` 又设 regex/health/resource | 24 包；`regex`→`xdk.text`，`health`→`xdk.runtime`，`resource`→`xdk.sys` | `utils/README.md`、`utils/API-SURFACE.md`、`utils/OVERVIEW.md` | 回写 |
| U3 | event 依赖不一致 | README 写 `xdk.runtime` + `xdk.codec`；WORK-ALLOCATION 写不复用 xdk.runtime；OVERVIEW 写 execution | 统一 `xdk.errors` + `xdk.runtime` + `xdk.codec`；不依赖 `xdk.execution`；同步 `WORK-ALLOCATION-EXTENDED` | `utils/event/README.md`、`utils/WORK-ALLOCATION-EXTENDED.md`、`utils/OVERVIEW.md` | 回写 |
| U4 | cache vs core LRUCache | `core.LRUCache` 已有 `getOrLoad`/hits/misses/evictions；`xdk.cache.Cache` 又做 LRU/TTL/权重/loader | core `LRUCache` = 单线程容器原语；`xdk.cache.Cache` = 线程安全服务 + TTL/权重；loader 返回类型差异写入合同 | `core/collections/LRUCache.md`、`utils/cache/README.md` | 已冻结 |
| U5 | crypto 依赖 random 但 API 不接收 RNG | README 要求密钥/nonce 用 `SecureRandom`；`Cipher/Kdf/Asymmetric` 无 `RandomSource` 参数 | 2.x 显式注入 `RandomSource` 到需要 nonce 的方法，或内部使用 `SecureRandom` 并在合同写明；二选一并冻结 | `utils/crypto/*.md` | P4 前 |
| U6 | `KdfAlgorithm` 死枚举 | `KdfAlgorithm` 说被 `Kdf` 使用，但 `Kdf` 没有 `derive`，参数也不接收枚举 | 增加 `Kdf.derive(KdfAlgorithm,...)` 作为通用入口，或删除 `KdfAlgorithm`；保留 typed 方法时必须让枚举有实际用途 | `utils/crypto/Kdf.md`、`KdfAlgorithm.md` | P4 前 |
| U7 | `AsymmetricAlgorithm.Sm9` 标 X | 枚举有 `Sm9`，README 又把 SM9 列为 X | 未实现前从枚举移除；不能用 `Unsupported` 假装 K 面支持 | `utils/crypto/AsymmetricAlgorithm.md` | 回写 |
| U8 | Tar PAX 矛盾 | `TarEntry` 说不做 PAX；`Tar` 说支持 PAX 长名称/长路径 | 支持 PAX 长名称/长路径，更新 `TarEntry`；或删除 `Tar` 的 PAX 承诺；二选一 | `utils/compress/Tar.md`、`TarEntry.md` | P4 前 |
| U9 | `SecureRandom.nextInt(max)` 负值/模偏差 | 伪代码用有符号 `%`；合同写 `[0,max)` | 改为无符号/拒绝采样；`nextInt(max)` 必须非负且无模偏差；补测试 | `utils/random/SecureRandom.md`、`Random.md` | 回写 |
| U10 | Timer 失败语义 | `stop` 一处写负起点 panic，一处写时钟回退钳 0 | 只有 `startMono < 0` panic；`nowMono < startMono` 钳 0，不 panic | `utils/metrics/Timer.md` | 回写 |
| U11 | CompressionLevel 映射 | deflate 有 0/1/3/6/9；zstd/lz4/brotli 只写“稳定子集”；`None` 语义不一 | P4 前给每个算法一张映射表；`None` 统一“不压缩/仅容器”或明确 Unsupported | `utils/compress/CompressionLevel.md`、`Zstd/Lz4/Brotli.md` | P4 前 |
| U12 | CacheStats reset 归属 | 旧 API 把 reset 放 `CacheStats`；类型文档是 `Cache.resetStats()` | `CacheStats` 不可变；`Cache.resetStats()` 负责重置 | `utils/cache/Cache.md`、`CacheStats.md` | 已冻结 |
| U13 | AuditEvent 构造 7 vs 4 参 | 类型文档 7 参；旧 API 4 参 | 7 参为 canonical；4 参便捷构造改 `AuditEvent.of(...)` | `utils/audit/AuditEvent.md` | 回写 |
| U14 | `Histogram` 同名 | `metrics.Histogram` 与 `stats.Histogram` | stats 改名 `BucketHistogram`；metrics 保留 `Histogram` | `utils/stats/Histogram.md` | P0 改名 |
| U15 | `Timer` 同名 | `time.Timer` 与 `metrics.Timer` | metrics 改名 `MetricTimer`；time 保留 `Timer` | `utils/metrics/Timer.md` | P0 改名 |
| U16 | `Redactor` 同名 | `log.Redactor`（1.x 已实现）与 `audit.Redactor` | log 保留 `Redactor`；audit 改名 `AuditRedactor` | `utils/audit/Redactor.md` | P0 改名 |
| U17 | metrics 依赖 stats 实现 | `metrics` 依赖 `stats.Histogram/Summary`，但 stats 未实现 | P4 先实现 stats，再实现 metrics；metrics 不复制桶算法 | `utils/metrics/README.md` | P4 |
| U18 | i18n 缺 core 前置 | 需要 `TimeZone`/`DateTimeFormatter`/`Decimal`/`RoundingMode`/`OpenOptions`；src 无 | P3 补 core 类型；i18n 的 Locale/PluralRules 可先做 | `core/time`、`core/math`、`core/fs` | P3/P7 |
| U19 | raw 原语缺失 | JSON/CSV/Base64、zstd/lz4/brotli、zip/tar、cipher/KDF/非对称、per-instance RNG | P4 分批补 FFI；Base64/Hex 可纯 XDK 先做；没有 raw 不写假实现 | `src/ffi/*.xfb`、`utils/*/README.md` | P4 |
| U20 | event 被 codec 反阻塞 | `Event` payload 固定 `JsonValue`，codec 未实现 | 先做 codec 的 Json 最小面，再做 event；或把 Event payload 改为不透明 `Bytes`（不推荐） | `utils/event/Event.md` | P4/P7 |
| U21 | `xdk.reflect` 注解查询 | 旧计划说 reflect 不返回注解；注解系统有 `AnnotationRegistry` | 保持分离：reflect 只读类型元数据；注解查询只走 `AnnotationRegistry` | `utils/reflect/README.md`、`ANNOTATION-SYSTEM.md` | 已冻结 |
| U22 | terminal 是否 UI | `xdk.terminal` 有进度条/表格/提示，但不是桌面 UI | 保留为 CLI 呈现；不做全屏 TUI/raw mode/PTY/窗口；不进入 desktop 计划 | `utils/terminal/README.md` | 已冻结 |

---

## 7. Solutions 冲突

| # | 冲突 | 现状 | 决定 | 改哪份 | 状态 |
| --- | --- | --- | --- | --- | --- |
| X1 | ML `BatchProcessor` 超 pending 上限 | 设计允许 pending 超上限 | P8 前定义硬上限/背压/拒绝策略；不得无界增长 | `solutions/ml/*` | P8 前 |
| X2 | `DatabasePool` 双重关闭 | 池与连接都可能 close 同一资源 | 池拥有连接；连接 close 幂等；池 close 先停止借出，再关闭空闲，再排空/强制；重复 close 无副作用 | `solutions/db/DatabasePool.md` | P8 前 |
| X3 | `SseStream` 失败面偏窄 | 只覆盖部分写/关闭错误 | 补 write/flush/close/取消/背压错误；SSE 事件编码失败显式返回 | `solutions/api/SseStream.md` | P8 前 |
| X4 | `Agent` 启动失败回滚不完整 | 组件启动失败可能留下半启动管线 | 定义启动顺序 + 逆序回滚；失败不返回半成品；关闭幂等 | `solutions/agent/*` | P8 前 |
| X5 | API “无注解扫描” vs 注解矩阵 | `api/README` 写无反射/无注解扫描；`ANNOTATION-SYSTEM` 写 `@HttpRoute` 生成路由 | 注解处理器在构建期生成显式 `ApiRoute` 注册代码；运行时仍无扫描/反射；文档统一措辞 | `solutions/api/README.md`、`ANNOTATION-SYSTEM.md` | 回写 |
| X6 | `Exporter` 同名 | `metrics.Exporter` 与 `agent.Exporter` | agent 改名 `PipelineExporter`；metrics 保留 `Exporter` | `solutions/agent/*` | P0 改名 |
| X7 | `Batch` 同名 | `db.Batch` 与 `ml.Batch` | 改名 `DbBatch`/`MlBatch`，或始终包名限定；优先改名 | `solutions/db/*`、`solutions/ml/*` | P0 改名 |
| X8 | `Signal` 同名 | `sys.Signal` 与 `numerics.Signal` | numerics 改名 `SignalBuffer`；sys 保留 `Signal` | `solutions/numerics/*` | P0 改名 |
| X9 | `net.service` 层级 | 见 S5 | 归 L5；solutions 只剩 9 包/122 类型 | `solutions/README.md`、`COVERAGE.md` | P0 冻结 |

---

## 8. 同名冲突登记

| 简单名 | owner | 冲突方 | 处理 |
| --- | --- | --- | --- |
| `Histogram` | `xdk.metrics` | `xdk.stats` | stats → `BucketHistogram` |
| `Timer` | `xdk.time` | `xdk.metrics` | metrics → `MetricTimer` |
| `Redactor` | `xdk.log` | `xdk.audit` | audit → `AuditRedactor` |
| `PrivateKey` | `xdk.crypto` | `xdk.net.tls` | TLS 消费 crypto；必要时 `TlsPrivateKey` |
| `ReconnectPolicy` | `xdk.net.websocket` | `xdk.net.service` | service → `ServiceReconnectPolicy` |
| `ServiceState` | `xdk.os.service` | `xdk.net.service` | net → `NetServiceState` |
| `Signal` | `xdk.sys` | `xdk.numerics` | numerics → `SignalBuffer` |
| `Exporter` | `xdk.metrics` | `xdk.agent` | agent → `PipelineExporter` |
| `Batch` | 无全局 owner | `xdk.db` / `xdk.ml` | `DbBatch` / `MlBatch` |
| `Event` | `xdk.event` | `xdk.log.LogRecord`/`AuditEvent` | 语义不同，保持独立；文档说明三者边界 |
| `Context` | `xdk.execution` | HTTP/API 的请求上下文 | HTTP/API 用 `ApiContext`/`HttpExchange`，不复用 `Context` |
| `Error` | `xdk.errors` | 各包 `*Error` 诊断 | 各包诊断类型用 `*Error` 全名；不遮蔽 `xdk.errors.Error` |

---

## 9. 缺失原语 / 依赖

| 缺失 | 阻塞 | 计划 |
| --- | --- | --- |
| `RuntimeMonitor` + `monitor*Raw` | audit/cache/event/metrics/queue | P2 |
| `Context` 截止时间/`RuntimeMonitor.wait(Context)` | DelayQueue、resilience timeout、scheduler | P2 |
| `Json`/`Csv`/`Base64`/`Hex` raw 或纯 XDK 实现 | event、jwt、http、api、mcp、db | P4，Json/Base64 先行 |
| 泛型 `Pair<A,B>` | geo、tensor、linalg、collections | P2 |
| `Bytes.alloc/empty` | tensor/serial/device | P2 |
| `isFinite/isNaN` | linalg/geo/tensor/metrics | P2 |
| `TimeZone`/`DateTimeFormatter`/`Decimal`/`RoundingMode` | i18n、schedule、format | P3 |
| `OpenOptions` | i18n/fs 配置 | P3 |
| per-instance `RandomHandle` + OS CSPRNG | random/uuid/crypto | P4 |
| crypto raw（AES/SM4/ChaCha20/KDF/RSA/ECC/Ed25519/SM2/KeyHandle） | crypto/jwt/tls | P4/P5 |
| compress raw（zstd/lz4/brotli/zip/tar） | compress | P4 |
| TLS raw（证书/私钥/握手/信任库） | net.tls | P5 |
| OS/硬件 raw（cpu/memory/pci/usb/storage/gpu/firewall/container/virt/service） | os.* | P6 |
| serial/device raw（termios/GPIO/I2C/SPI/camera） | serial/device | P6 |
| GPU raw（buffer/program/pipeline/command/fence） | gpu/accel | P6 |

---

## 10. 文档编辑队列

### 10.1 P0 必改

1. 全量 `xdk.core.*` / `xdk.utils.*` 包名归一（见 S1/S2）。
2. `platform/os/OsCapability.md` 删除 desktop 成员；`platform/os/README.md`、`platform/os/host/README.md`、`platform/README.md`、`core/PLATFORM-BOUNDARY.md`、`core/README.md`、`core/OVERVIEW.md` 清理 desktop 引用。
3. `COVERAGE.md` 改为 75/698，按 L0–L8 重新分组；`net.service` 从 solutions 移到 network。
4. `README.md` 增加 ARCHITECTURE/PACKAGE-MAP/DESIGN-CONSISTENCY/LEGACY-1.0；更新权威顺序与计数。
5. `API-SURFACE.md`、`utils/API-SURFACE.md` 加“旧版广度稿/按合同生成”横幅；旧名不删，但不得作为实现依据。
6. `ANNOTATION-PLAN.md` 修正 7/11 目标、`@Repeatable`、`@Override`、`@MustUse`、诊断码、阶段。
7. `solutions/README.md` 移除 `net.service` 计数；`network/README.md` 增加 `net.service` 行。
8. `utils/OVERVIEW.md`、`utils/README.md` 24 包口径统一；去掉 `health` 行/说明。

### 10.2 P0.5 改名批次

按 `PACKAGE-MAP.md` §12 执行类型文件改名与引用替换：

- `stats/Histogram.md` → `BucketHistogram.md`
- `metrics/Timer.md` → `MetricTimer.md`
- `audit/Redactor.md` → `AuditRedactor.md`
- `net-service/ReconnectPolicy.md` → `ServiceReconnectPolicy.md`
- `net-service/ServiceState.md` → `NetServiceState.md`
- `numerics/Signal.md` → `SignalBuffer.md`
- `agent/Exporter.md` → `PipelineExporter.md`
- `db/Batch.md` → `DbBatch.md`；`ml/Batch.md` → `MlBatch.md`

### 10.3 P1 前

- `ANNOTATION-PLAN.md` §10 诊断码表冻结；
- `ANNOTATION-SYSTEM.md` §5 矩阵包名归一；
- `annotations/README.md` 的包名/顺序/链接补全；
- 编译器注解 AST/解析工作项拆到可提交批次。

---

## 11. 冻结检查

```text
S1–S9 全部有决定；无“待定”进入实现
C1–C16 全部有 owner/阶段
A1–A8 全部有 owner/阶段
N1–N8 / P1–P13 / U1–U22 / X1–X9 全部有 owner/阶段
同名冲突登记表覆盖全部重复简单名
缺失原语表覆盖所有跨包阻塞
文档编辑队列的 P0 项全部完成
```

> 本表签字后，才允许开 P1；P1 不依赖 core 实现，但依赖本表的包名/诊断码/处理器语义冻结。
