# XDK 设计文档入口

| 项 | 值 |
| --- | --- |
| 状态 | 1.x 已发布；B0–B4 已完成；C7 合同已整合待 B5；B5–B10 未开工 |
| 1.x 基线 | [`t0/`](t0/00-overview.md) + `src/xdk`；14 包 / 160 symbols |
| 2.x 目标 | **75 包 / 698 类型**；见 [`PACKAGE-MAP.md`](PACKAGE-MAP.md) |
| 计划总览 | [`PLAN.md`](PLAN.md)；当前位置、下一步、未开工范围 |
| 架构 | [`ARCHITECTURE.md`](ARCHITECTURE.md) |
| 一致性 | [`DESIGN-CONSISTENCY.md`](DESIGN-CONSISTENCY.md) |
| 执行 | [`EXECUTION-PLAN.md`](EXECUTION-PLAN.md)；B4 已完成，下一步 B5 |
| 1.x 旧档 | [`LEGACY-1.0.md`](LEGACY-1.0.md) |
| 第一实现层 | 注解；先编译器，后 XDK |

---

## 1. 先看哪几份

| 顺序 | 文档 | 用途 |
| ---: | --- | --- |
| 1 | [`PLAN.md`](PLAN.md) | 执行总览：现在在哪、下一步、未开工范围、门禁与更新规则 |
| 2 | [`ARCHITECTURE.md`](ARCHITECTURE.md) | 2.x 分层、包/类角色、抽象边界、注解优先 |
| 3 | [`PACKAGE-MAP.md`](PACKAGE-MAP.md) | 75 包/698 类型的逐包角色、依赖、阶段 |
| 4 | [`EXECUTION-PLAN.md`](EXECUTION-PLAN.md) | 批次顺序、任务板、派工模板、门禁与证据 |
| 5 | [`DEBT-REGISTER.md`](DEBT-REGISTER.md) | 债务台账：四类债、B4 完成、B4-01/B4-02 关闭、B5–B10 后续 |
| 6 | [`ANNOTATION-SYSTEM.md`](ANNOTATION-SYSTEM.md) + [`ANNOTATION-PLAN.md`](ANNOTATION-PLAN.md) + [`ANNOTATION-CATALOG.md`](ANNOTATION-CATALOG.md) | 注解语义、实施计划、全量目录 |
| 7 | [`DESIGN-CONSISTENCY.md`](DESIGN-CONSISTENCY.md) | 已知冲突、决定、改名、缺失原语 |
| 8 | 各领域 README/类型合同 | 逐包/逐类型契约 |
| 9 | [`LEGACY-1.0.md`](LEGACY-1.0.md) | 1.x 已发布基线，不参与 2.x 排序 |

> `PLAN.md` 是总览；`ARCHITECTURE.md`/`PACKAGE-MAP.md` 是架构/包权威，`EXECUTION-PLAN.md` 是批次权威，`DEBT-REGISTER.md` 是债表/B4 入口权威。总览与权威文档冲突时，以权威文档为准。

> `API-SURFACE.md`、`SCENARIOS.md`、`CAPABILITY.md`、`COVERAGE.md` 是广度/场景/覆盖对照，不反向覆盖逐类型合同。

---

## 2. 领域地图

| 层 | 目录 | 内容 |
| --- | --- | --- |
| 注解 | [`annotations/`](annotations/OVERVIEW.md) | 注解元模型、保留/目标、构建期处理器、运行时注册表 |
| L1 运行时/执行 | [`core/runtime/`](core/runtime/README.md)、[`core/execution/`](core/execution/README.md) | 运行时信息、`RuntimeMonitor`、`Context`、任务、同步 |
| L2 core 基础 | [`core/`](core/OVERVIEW.md) | errors/meta/bytes/text/collections/math/time |
| L3 core 系统 | [`core/`](core/OVERVIEW.md) | io/fs/sys/log/config/cli |
| L4 数据/编码 | [`utils/`](utils/OVERVIEW.md) | codec/crypto/compress/random/uuid/stats/functional/graph/reflect/toml/yaml/xml |
| L5 网络/数据 | [`network/`](network/README.md) | net/uri/mime/tls/http/websocket/net.service/jwt/sql |
| L6 平台/计算 | [`platform/`](platform/README.md) | os.* + gpu/tensor/linalg/geo/serial/device |
| L7 应用服务 | [`utils/`](utils/OVERVIEW.md) | validate/cache/queue/schedule/event/resilience/metrics/trace/audit/terminal/i18n/test |
| L8 解决方案 | [`solutions/`](solutions/README.md) | api/db/ml/agent/numerics/jsonrpc/mcp/accel/embedded |

> 目录名只表达文档分组，不是包名前缀。包名以 `PACKAGE-MAP.md` 为准，例如 `xdk.codec`、`xdk.execution`，不是 `xdk.codec`、`xdk.execution`。

---

## 3. 计数

| 层 | 包 | 类型 |
| --- | ---: | ---: |
| annotations | 1 | 14 |
| L1 runtime/execution | 2 | 25 |
| L2 core foundation | 7 | 80 |
| L3 core system | 6 | 81 |
| L4 data/encoding | 12 | 76 |
| L5 network/data | 9 | 125 |
| L6 platform/compute | 17 | 93 |
| L7 application services | 12 | 82 |
| L8 solutions | 9 | 122 |
| **合计** | **75** | **698** |

1.x 另有 25 篇 legacy 文档（`t0/` 22 + 3 篇根级发布文档），不计入 2.x 类型数。见 [`LEGACY-1.0.md`](LEGACY-1.0.md)。

---

## 4. 文档规则

- 一个公开 class/protocol/enum 一个 PascalCase 文件；
- 每个类型 14 段契约；
- 包 README 只做索引、边界、场景、缺口；
- 协议非泛型；泛型用于 class/函数/方法；
- 阻塞操作接受 `Context`；失败用 `Result`；资源有幂等 `close()`；
- 无全局状态、无运行时反射、无隐式注解扫描；
- 注解由编译期处理器生成代码/元数据，运行时只读注册表；
- 公共包名是能力名；`xdk.core`/`xdk.utils` 只作层名；
- 同一简单名只能有一个语义 owner；冲突登记在 `DESIGN-CONSISTENCY.md`。

---

## 5. 权威顺序

1. 语言规范 S0–S9；
2. [`ARCHITECTURE.md`](ARCHITECTURE.md) 与 [`PACKAGE-MAP.md`](PACKAGE-MAP.md)（架构/包边界）；
3. [`ANNOTATION-SYSTEM.md`](ANNOTATION-SYSTEM.md)（注解语义）；
4. 各领域 README / 逐类型合同；
5. [`DESIGN-CONSISTENCY.md`](DESIGN-CONSISTENCY.md)（冲突决定与改名）；
6. [`API-SURFACE.md`](API-SURFACE.md)、[`SCENARIOS.md`](SCENARIOS.md)、[`CAPABILITY.md`](CAPABILITY.md)、[`COVERAGE.md`](COVERAGE.md)（广度/场景/覆盖对照）；
7. [`LEGACY-1.0.md`](LEGACY-1.0.md) 与 `t0/`（1.x 已发布事实）。

冲突时，优先级高的文件胜出；低优先级文件必须回链，不复制第二份契约。

---

## 6. 实施顺序

```text
P0 架构冻结
  → P1 注解（编译器/元模型/处理器）
    → P2 执行/core 前置
      → P3 core
        → P4 数据/编码
          → P5 网络/数据
            → P6 平台/计算
              → P7 应用服务
                → P8 solutions
```

详细批次、任务板、派工模板与 CR-0 门禁见 [`EXECUTION-PLAN.md`](EXECUTION-PLAN.md)；架构出口见 [`ARCHITECTURE.md`](ARCHITECTURE.md) §11 与 [`PACKAGE-MAP.md`](PACKAGE-MAP.md) §13。

> 注解是第一个实现层：没有编译器注解管线，后续 `@Serializable`/`@Validate`/`@HttpRoute`/`@Sql` 只能手写或退化为运行时反射。P1 先做 mini 的 lexer/parser/AST/语义/处理器，再落 `xdk.annotations` 14 类型。
