# `xdk.agent` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.agent` |
| 层 | L8 solutions |
| 依赖 | `xdk.errors`、`xdk.execution`、`xdk.runtime`、`xdk.time`、`xdk.io`、`xdk.fs`、`xdk.log`、`xdk.text`、`xdk.collections`、`xdk.net.http`、`xdk.metrics`、`xdk.trace`、`xdk.os.host`、`xdk.os.cpu`、`xdk.os.memory`、`xdk.os.storage` |
| 被依赖 | 应用、边缘/节点 Agent、网关/Collector、运维与诊断工具 |
| 稳定性 | `preview`；不进入 1.0 公共承诺 |
| 文档原则 | 包级说明在本 README；一个类型一个 PascalCase 文件；每个类型 14 段 |

---

## 1. 包定位

`xdk.agent` 是进程内/节点侧的**遥测采集与转发 Agent**：按 OpenTelemetry Collector 的
Receiver → Processor → PipelineExporter 模型组织三类遥测，提供显式生命周期、有限队列、背压与健康面。

它解决的是：

- 应用只负责产生指标/追踪/日志，不把每个后端 SDK 塞进业务进程；
- 节点 Agent 统一采集主机指标、文件日志，并转发到 OTLP/Prometheus 目标；
- 采集、批处理、限流、导出可以独立替换与测试；
- 失败可见：背压、丢弃、关闭、就绪状态都有明确结果与计数。

它不解决的是：

- 不是日志门面：`xdk.log.Logger` 负责进程内日志，`FileLogReceiver` 只负责读文件；
- 不是指标库：`Metric`/`Registry` 仍归 `xdk.metrics`；
- 不是追踪实现：`Tracer`/`Span` 仍归 `xdk.trace`；
- 不是后端 SDK：不嵌入 Jaeger/Zipkin/Datadog/云厂商 SDK；
- 不是完整 OTel Collector 发行版：不做扩展注册表、远程配置、服务发现、pprof/zpages。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| OTel Collector 形状 | 每种遥测一条管线：接收器 → 处理器 → 导出器；连接器可选，连接两条管线 |
| 显式对象图 | Agent、管线、组件都是显式实例；无全局 Agent、全局组件注册表、隐式单例 |
| 非泛型协议 | `Receiver`/`Processor`/`PipelineExporter`/`Connector` 不带类型参数，统一面向 `TelemetryBatch` |
| 类型闭合 | `TelemetryKind` 固定 Metrics/Traces/Logs；组件与管线必须同 kind；连接器可跨 kind |
| 不可变批次 | `TelemetryRecord`/`TelemetryBatch` 构造后不可变；列表与 Map 读取返回副本 |
| 生命周期显式 | `start` → `stop`（停止入口）→ `drain`（冲刷在途）→ `close`（释放）；close 幂等 |
| Context 先行 | 所有可阻塞方法首参 `Context`；取消返回 `Cancelled`，超时返回 `Timeout` |
| Result 失败 | 可恢复失败用 `Result`；合同错误 panic；不吞导出/读取错误 |
| 有界与背压 | 接收器/处理器/导出器队列有上限；满队列返回 `Busy` 或按显式策略丢弃并计数 |
| 丢弃显式 | 不静默丢数据；策略只有 reject/drop_oldest/drop_newest，丢弃数可读 |
| 配置显式 | `AgentConfig` 是对象图；默认不读远程配置、不监听配置中心 |
| 复用 core/net/os/utils | 指标/追踪/日志/文件/OS 能力复用现有类型，不复制算法与数据模型 |
| 无后端 SDK | OTLP/Prometheus 只定义线格式与传输合同；具体编解码/HTTP 由本包或应用实现 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `TelemetryKind` | enum | Metrics/Traces/Logs | [`TelemetryKind.md`](TelemetryKind.md) |
| `TelemetryRecord` | class | 不可变单条遥测记录 | [`TelemetryRecord.md`](TelemetryRecord.md) |
| `TelemetryBatch` | class | 不可变同 kind 批次 | [`TelemetryBatch.md`](TelemetryBatch.md) |
| `Receiver` | protocol | 采集入口与推送合同 | [`Receiver.md`](Receiver.md) |
| `Processor` | protocol | 批处理/限流/变换合同 | [`Processor.md`](Processor.md) |
| `PipelineExporter` | protocol | 远端/本地导出合同 | [`PipelineExporter.md`](PipelineExporter.md) |
| `Connector` | protocol | 跨管线连接合同 | [`Connector.md`](Connector.md) |
| `AgentPipeline` | class | 一条 kind 管线的装配与运行 | [`AgentPipeline.md`](AgentPipeline.md) |
| `AgentConfig` | class | 显式 Agent 配置对象图 | [`AgentConfig.md`](AgentConfig.md) |
| `Agent` | class | Agent 生命周期与管线所有权 | [`Agent.md`](Agent.md) |
| `HostMetricsReceiver` | class | 主机 CPU/内存/磁盘/网络指标 | [`HostMetricsReceiver.md`](HostMetricsReceiver.md) |
| `FileLogReceiver` | class | 文件 tail/解析/日志批次 | [`FileLogReceiver.md`](FileLogReceiver.md) |
| `BatchProcessor` | class | 按条数/时间/上限批处理 | [`BatchProcessor.md`](BatchProcessor.md) |
| `MemoryLimiterProcessor` | class | 软/硬内存上限与背压 | [`MemoryLimiterProcessor.md`](MemoryLimiterProcessor.md) |
| `OtlpExporter` | class | OTLP/HTTP JSON 推送 | [`OtlpExporter.md`](OtlpExporter.md) |
| `PrometheusExporter` | class | Prometheus 文本抓取视图 | [`PrometheusExporter.md`](PrometheusExporter.md) |
| `AgentHealth` | class | Agent 就绪/存活/丢弃/错误快照 | [`AgentHealth.md`](AgentHealth.md) |

索引共 17 个类型文件；每个类型一个 PascalCase 文件。包 README 只做索引、跨类型规则、场景与缺口，
不复制类型方法表或伪代码。

---

## 4. 能力与边界

### 4.1 本包提供

| 能力 | 承载类型 | 说明 |
| --- | --- | --- |
| 三类遥测统一信封 | `TelemetryKind`、`TelemetryRecord`、`TelemetryBatch` | 批次内 kind 一致；资源属性在批次级 |
| 组件协议 | `Receiver`、`Processor`、`PipelineExporter`、`Connector` | 非泛型，统一 `TelemetryBatch` |
| 管线编排 | `AgentPipeline` | 接收、处理、fan-out 导出、连接器出入口 |
| Agent 生命周期 | `Agent` | start/stop/drain/close、失败回滚、连接器所有权 |
| 显式配置 | `AgentConfig` | 管线/连接器/默认溢出策略；无远程拉取 |
| 主机指标 | `HostMetricsReceiver` | cpu/memory/load/filesystem/network/paging/processes/system |
| 文件日志 | `FileLogReceiver` | glob tail、偏移、multiline、行上限、文件属性 |
| 批处理 | `BatchProcessor` | 条数/时间/最大批次/有界 pending |
| 内存保护 | `MemoryLimiterProcessor` | 软/硬限制、拒绝或显式丢弃 |
| OTLP 推送 | `OtlpExporter` | OTLP/HTTP JSON，队列、重试、drain |
| Prometheus 抓取 | `PrometheusExporter` | 最新指标视图与文本渲染；HTTP 由应用接线 |
| 健康面 | `AgentHealth` | 实现 `HealthCheck`，供 `HealthRegistry` 聚合 |

### 4.2 本包不做

- 不做采样、tail sampling、概率采样处理器；
- 不做属性/资源变换处理器的完整 DSL；
- 不做 OTLP/gRPC、OTLP/protobuf、OTLP/file exporter；
- 不做 Prometheus HTTP 服务器、Push Gateway、远程写；
- 不做持久化发送队列、磁盘 WAL、跨重启 offset 存储；
- 不做认证扩展、OIDC/OAuth2、服务发现、pprof/zpages；
- 不做远程配置、配置热更新、配置中心监听；
- 不做自动 instrumentation、字节码注入、全局 Tracer/Logger；
- 不复制 `Registry`/`Histogram`/`Span`/`LogRecord` 的模型与算法。

---

## 5. 跨类型规则

### 5.1 kind 一致性

- 一个 `TelemetryBatch` 只能包含一种 `TelemetryKind`；
- `Receiver.kind()`、`Processor.kind()`、`PipelineExporter.kind()` 必须与所属 `AgentPipeline.kind()` 相同；
- `Connector.inputKind()` 对接源管线 kind，`Connector.outputKind()` 对接目标管线 kind；
- 不允许 `Traces` 批次进入 metrics 导出器；违反是合同错误（panic）或配置错误（`InvalidArgument`），
  由构造/启动阶段拒绝，不在热路径猜测。

### 5.2 不可变与复制

- `TelemetryRecord` 构造时复制属性 Map、事件列表；读取返回副本；
- `TelemetryBatch` 构造时复制资源 Map、记录列表；读取返回副本；
- `AgentConfig`/`AgentPipeline` 构造时复制组件列表；
- `with*`/`merge`/`split` 返回新批次，不修改原批次；
- 记录内部的 `MetricFamily`、`SpanContext`、`SpanEvent`、`LogRecord` 本身不可变，可安全共享。

### 5.3 生命周期顺序

标准顺序：

```text
构造 → start → 运行 → stop（停止入口）→ drain（冲刷在途）→ close（释放）
```

规则：

- `start` 非阻塞，失败返回 `Result`；重复 `start` 返回 `Ok(unit)`；
- `stop` 只停止入口，不丢弃已接收数据；可重复；
- `drain` 冲刷缓冲并等待下游；可重复；取消返回 `Cancelled`；
- `close` 幂等；未 drain 的数据按显式策略丢弃并计数；
- 关闭后 `start`/`export`/`process` 返回 `Unavailable`；
- Agent 的 `stop` 负责按依赖顺序编排组件的 stop/drain/close；
- `close` 不是 `drain` 的替代；需要零丢失时必须先 `drain`。

### 5.4 背压与丢弃

- 接收器/导出器/批处理器队列有界；容量在构造器显式给出；
- 队列满时默认返回 `Busy`，由上游重试或降速；
- 允许的丢弃策略固定为：

| 策略 | 行为 | 计数 |
| --- | --- | --- |
| `reject` | 不接收新批次，返回 `Busy` | 不计丢弃，计拒绝 |
| `drop_oldest` | 移除最旧批次，接收新批次 | 增加丢弃条数 |
| `drop_newest` | 保留旧批次，丢弃新批次 | 增加丢弃条数 |

- 丢弃必须可通过组件诊断方法或 `AgentHealth` 观察；不允许静默丢弃；
- 下游错误沿调用链返回；接收器可重试、暂停读取或按策略丢弃；
- 重试可能造成重复投递；导出语义是 at-least-once，不承诺 exactly-once。

### 5.5 连接器与所有权

- `Connector` 同时具有“导出侧” `consume` 与“接收侧” `start`；
- 一个连接器实例必须且只能接入一条源管线和一条目标管线；
- 源管线把 `Connector` 放在 `outputConnectors`，目标管线放在 `inputConnectors`；
- `Agent` 拥有连接器生命周期，只 `start`/`drain`/`close` 一次；
- `AgentPipeline` 只引用连接器，不关闭连接器；
- 连接器不得形成环；跨 kind 只允许显式声明且由 Agent 启动时校验。

### 5.6 错误映射

| 场景 | 分类 |
| --- | --- |
| null/空名称/非法配置 | 合同错误 panic；配置构建可返回 `InvalidArgument` |
| 未启动/已关闭 | `Unavailable` |
| 队列满/内存软限制 | `Busy` |
| Context 取消 | `Cancelled` |
| 读取/写入失败 | `Io` |
| 远端网络失败 | `Network` |
| 请求超时 | `Timeout` |
| 编码/解码失败 | `DataCorrupted` |
| 平台/能力缺失 | `Unsupported` |
| 内部不变量破坏 | `Internal` |

### 5.7 健康聚合

- `AgentHealth` 实现 `xdk.runtime.HealthCheck`，`check()` 返回 `HealthReport`；
- 管线健康取所有组件最严重状态；任一组件 `Unhealthy` 则 Agent `Unhealthy`；
- 启动中 `Starting`、停止中 `Stopping`、已停止 `Stopped` 均不可就绪；
- 降级 `Degraded` 仍可服务，但 `isHealthy()` 为 false；
- 队列丢弃/导出失败使 Agent 进入 `Degraded` 或 `Unhealthy`，取决于是否仍有可用路径。

### 5.8 无全局状态

- 无 `AgentRegistry`、无全局 `Receiver`/`PipelineExporter` 注册表、无全局配置；
- 每个应用/测试显式构造 `AgentConfig` 与 `Agent`；
- 组件实例不跨 Agent 共享；共享 `MetricFamily`/`SpanContext`/`LogRecord` 值对象是允许的；
- 测试可注入 fake `OsHost`、内存 `PipelineExporter`、固定 `Context`。

---

## 6. 行业调研与对齐

### 6.1 OpenTelemetry Collector

参考架构：

- Collector 以 pipeline 组织数据：receivers → processors → exporters；
- pipeline 的 kind 是 traces/metrics/logs 之一；组件必须支持该 kind；
- 同一 receiver 可被多条 pipeline 引用；同一 exporter 可服务多条 pipeline；
- 同一 processor 名称在多条 pipeline 中会得到**独立实例**，状态不共享；
- exporters 前有 fan-out：每个 exporter 收到一份数据；
- connectors 同时是 exporter 和 receiver，连接两条管线，可同 kind 或跨 kind；
- extensions 提供健康检查、pprof、zpages 等非遥测能力；
- service 段是启用开关：只配置不启用不会运行；
- 生命周期由 Collector 启动/关闭统一编排，receiver/processor/exporter 有 Start/Shutdown。

XNull 对齐与取舍：

| OTel 能力 | `xdk.agent` 对齐 |
| --- | --- |
| pipelines per signal | `AgentPipeline` + `TelemetryKind` |
| receivers/processors/exporters | `Receiver`/`Processor`/`PipelineExporter` 协议 |
| fan-out | `AgentPipeline` 向多个 exporter/connector 顺序 fan-out |
| connectors | `Connector` 协议；Agent 拥有生命周期；基线无内置实现 |
| service/extensions | 基线只保留 `AgentHealth`；无扩展注册表 |
| component instances | 显式对象；每个 pipeline 独立处理器实例 |
| Start/Shutdown | `start`/`stop`/`drain`/`close` 四段式 |
| config providers | 不做；`AgentConfig` 是对象图，无远程配置 |

### 6.2 组件语义

| 组件 | OTel 语义 | 本包实现/决策 |
| --- | --- | --- |
| hostmetrics | 周期 scrape CPU/内存/磁盘/网络/负载/分页/进程；scraper 可配 | `HostMetricsReceiver`；基线 cpu/memory/load/filesystem/network/paging/processes/system；逐进程 `process` 为 X |
| filelog | tail/解析文件；偏移、multiline、编码、上限、轮转 | `FileLogReceiver`；内存偏移、glob、multiline、行上限；持久化 offset 为 X |
| batch | 按条数/时间/最大批次聚合；建议在 memory_limiter 之后 | `BatchProcessor`；条数/时间/最大批次/有界 pending |
| memory_limiter | 软/硬限制；超限拒绝并迫使上游重试 | `MemoryLimiterProcessor`；超限返回 `Busy` 或显式丢弃；不做强制 GC |
| otlp | OTLP/gRPC 或 OTLP/HTTP 推送；TLS、重试、队列 | `OtlpExporter`；基线 OTLP/HTTP JSON；gRPC/protobuf 为 X |
| prometheus | 暴露 `/metrics` 供抓取；常量标签、命名空间、过期 | `PrometheusExporter`；提供最新指标视图与文本渲染；HTTP 服务由应用接线 |
| health_check | 扩展提供健康端点 | `AgentHealth` 实现 `HealthCheck`；HTTP 端点由应用接线 |

### 6.3 Agent 模式

- 节点 Agent：每台主机/容器旁路部署，采集宿主指标与本地日志，批量推送到网关；
- 网关模式：接收 OTLP，做批处理/限流/路由，再导出到后端；
- sidecar 模式：应用容器旁路，文件日志与主机指标按容器可见范围采集；
- 约束：Agent 不接管应用生命周期；应用可独立运行；Agent 失败不阻塞业务请求。

### 6.4 参考来源

- OpenTelemetry Collector Architecture：<https://opentelemetry.io/docs/collector/architecture/>
- OpenTelemetry Collector Configuration：<https://opentelemetry.io/docs/collector/configuration/>
- OpenTelemetry Collector Connector README：<https://github.com/open-telemetry/opentelemetry-collector/blob/main/connector/README.md>
- Host Metrics Receiver：<https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/hostmetricsreceiver>
- File Log Receiver：<https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/filelogreceiver>
- Batch Processor：<https://github.com/open-telemetry/opentelemetry-collector/tree/main/processor/batchprocessor>
- Memory Limiter Processor：<https://github.com/open-telemetry/opentelemetry-collector/tree/main/processor/memorylimiterprocessor>
- OTLP PipelineExporter：<https://github.com/open-telemetry/opentelemetry-collector/tree/main/exporter/otlpexporter>
- Prometheus PipelineExporter：<https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/exporter/prometheusexporter>
- OTLP 规范：<https://opentelemetry.io/docs/specs/otel/protocol/>

---

## 7. 场景

### S1：节点主机指标

应用构造 `OsHost` 与 `HostMetricsReceiver`，接入 metrics 管线，经 `MemoryLimiterProcessor`、
`BatchProcessor` 后由 `OtlpExporter` 推送。采集失败只影响该次 scrape，Agent 保持运行并上报
`Degraded`。

### S2：文件日志 tail

`FileLogReceiver` 监控 `/var/log/app/*.log`，按行生成 `LogRecord`，附带 `log.file.name`/
`log.file.path` 属性；下游忙时暂停读取而不是无限堆积；关闭前 `drain` 冲刷最后一批。

### S3：网关接收 OTLP

网关模式由应用提供 OTLP receiver 实现（X），批次进入 `AgentPipeline`；本包基线提供
`OtlpExporter` 作为出口，形成“接收 → 批处理 → 推送”的网关路径。

### S4：Prometheus 抓取

`PrometheusExporter` 接收 metrics 批次并保存最新样本；应用的 HTTP handler 调用
`scrape(context, writer)` 输出 Prometheus 文本。导出器不拥有 HTTP 服务器。

### S5：背压

内存软限制触发，`MemoryLimiterProcessor.process` 返回 `Busy`；`BatchProcessor` 不缓存更多，
接收器暂停或按策略丢弃；`AgentHealth` 记录拒绝/丢弃计数，就绪状态降级。

### S6：优雅停机

`Agent.stop(context)` 停止所有接收器，`drain` 冲刷处理器与导出器，连接器按依赖顺序 drain，
最后 `close` 释放资源。重复 `stop` 返回同一结果；未 `drain` 的队列在 `close` 时丢弃并计数。

### S7：连接器

应用实现一个 `Connector`，把 traces 管线的事件计数为 metrics；源管线把它放在
`outputConnectors`，目标管线放在 `inputConnectors`；`Agent` 只启动/关闭该连接器一次。

### S8：健康接入

`Agent.health()` 返回 `AgentHealth`；应用把它注册到 `xdk.runtime.HealthRegistry`，
由现有健康端点/探针读取 `check()`，不新增 HTTP 健康服务器。

---

## 8. 依赖与顺序

```text
core：errors / execution / runtime / time / io / fs / log / text / collections
net：http
os：host / cpu / memory / storage
utils：metrics / trace
        │
        ▼
 agent：TelemetryKind / TelemetryRecord / TelemetryBatch
          Receiver / Processor / PipelineExporter / Connector
          AgentPipeline / AgentConfig / Agent / AgentHealth
          HostMetricsReceiver / FileLogReceiver
          BatchProcessor / MemoryLimiterProcessor
          OtlpExporter / PrometheusExporter
        │
        ▼
应用：进程内 Agent、节点 daemon、网关、sidecar
```

规则：

- `xdk.agent` 可依赖 core/net/os/utils；core/net/os/utils 不得反向依赖本包；
- 指标/追踪/日志模型只引用，不复制；
- 不把 `xdk.net.http` 作为公开参数类型；`OtlpExporter` 内部组合 HTTP 客户端；
- `PrometheusExporter` 不依赖 HTTP 服务器类型，应用负责接线；
- 本包不进入 `xdk.core`、`xdk.net` 的依赖链。

---

## 9. 缺口与决策

| 项 | 决策 |
| --- | --- |
| OTLP/gRPC | 基线不做；X 增加协议实现，不改 `PipelineExporter` 协议 |
| OTLP/protobuf | 基线不做；只做 OTLP/HTTP JSON |
| Prometheus HTTP 服务器 | 不做；`scrape` 写调用方 `Writer` |
| 持久化发送队列/WAL | 不做；队列在内存，重启丢失 |
| filelog 持久化 offset | 不做；重启按 `startAt` 重新定位 |
| filelog 压缩/header/operators | 基线不做；X |
| 强制 GC | XNull 无公开强制 GC 原语；内存限制器只拒绝/丢弃，不调用 GC |
| tail sampling / 采样处理器 | 不做；X |
| attributes/resource 处理器 | 基线不内置；应用可实现 `Processor` |
| extensions 注册表 | 不做；健康检查用 `AgentHealth` 显式接入 |
| 远程配置 | 禁止默认；对象图由应用构造 |
| 配置热更新 | 不做；变更需重建 Agent |
| exactly-once | 不承诺；导出为 at-least-once，重试可能重复 |
| 多 Agent 全局注册 | 禁止；每个 Agent 独立 |
| 连接器内置实现 | 基线只定义协议；count/router 等由应用/X 实现 |
| 逐进程指标 | X；权限与基数风险高 |
| 组件级健康聚合 | `AgentHealth` 记录 Agent 生命周期/就绪数；逐组件用 `AgentPipeline.health()` |
| TLS/认证 | 基线用显式 headers/HttpClient 配置；认证扩展 X |

---

## 10. 安全

| 面 | 默认 | 规则 |
| --- | --- | --- |
| 监听地址 | 不监听；Prometheus 由应用接线 | 应用默认绑定 `127.0.0.1`，不默认 `0.0.0.0` |
| 文件读取 | 只读；不删除、不改权限 | 不跟随未声明的 symlink；路径由应用显式给出 |
| 敏感日志 | 不自动脱敏 | 应用在 `FileLogReceiver` 前/后加处理器；错误不包含日志正文 |
| 导出认证 | 显式 headers | 不记录 token/密码；不把 headers 写进错误描述 |
| 远程配置 | 禁止 | 不从网络拉配置；不监听配置中心 |
| 队列内存 | 有界 | 容量/条数/字节上限显式；超限按策略 |
| 主机指标 | 只读 | 不写 `/proc`/`/sys`；不提升权限；容器内只报可见范围 |
| 健康端点 | 应用接线 | 不暴露堆栈、配置、token；只报状态/计数 |
| 连接器环 | 启动拒绝 | Agent 校验连接器唯一入/出与无环 |
| 关闭 | 幂等 | 关闭后不接受新数据；未 drain 数据丢弃计数 |

---

## 11. 验收谓词

- 17 个类型文件齐全，README 索引与文件一一对应；
- 每个类型 14 段齐全；协议非泛型；枚举成员固定；
- `TelemetryBatch` 内 kind 一致；构造后不可变；列表/Map 返回副本；
- 所有可阻塞方法首参 `Context`；可恢复失败返回 `Result`；
- `start`/`stop`/`drain`/`close` 语义与幂等性在每类中写明；
- 队列有界，满队列与丢弃策略显式，丢弃可计数；
- 无全局 Agent/注册表/默认组件；`AgentConfig` 显式；
- OTLP/Prometheus 只做线格式与协议，不引入后端 SDK；
- 无错误的构造器自调用、私有字段 `self` 访问、泛型占位构造、省略号伪代码、Python 式条件表达式；
- 参数为完整英文名；尺寸 `Long`、计数 `Int`；
- 相对链接可达；不修改 / 总 README、不改代码/测试/脚本。

---

## 12. 变更记录

- 2026-11-22：首版。定义 `xdk.agent` 的 17 个类型、Collector 风格管线、显式生命周期、
  有界队列/背压/丢弃策略、健康面与安全边界。

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | `@AgentReceiver`、`@AgentProcessor`、`@AgentExporter`、`@PipelineSpec` |
| 本包消费 | `@Value`、`@Builder`、`@Metered`、`@Traced` |
| 处理器 | AgentAnnotationProcessor（Validate/Generate） |
| 生成物 | 管线/组件注册、观测元数据 |
| 状态 | 领域注解 planned；A8 派生 implemented（含限制）；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| receiver 类 | `@AgentReceiver` | receiver 表 |
| processor 类 | `@AgentProcessor` | processor 表 |
| exporter 类 | `@AgentExporter` | exporter 表 |
| 管线类 | `@PipelineSpec` | 管线表 |

### 声明

```x
@Target(Type)
@Retention(Runtime)
@annotation AgentReceiver {
    final String name
}

@Target(Type)
@Retention(Runtime)
@annotation AgentProcessor {
    final String name
}

@Target(Type)
@Retention(Runtime)
@annotation AgentExporter {
    final String name
}

@Target(Type)
@Retention(Runtime)
@annotation PipelineSpec {
    final String name
}
```

声明文件：每个注解单独一个 PascalCase 文件；处理器为构建期类型；生成代码在 `<package>/generated/`。

### 使用

```x
@AgentReceiver("otlp")
class OtlpReceiver {
    // ...
}

@AgentProcessor("redact")
class RedactProcessor {
    // ...
}

@AgentExporter("otlp")
class OtlpExporter {
    // ...
}

@PipelineSpec("traces")
class TracePipeline {
    // ...
}
```

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
