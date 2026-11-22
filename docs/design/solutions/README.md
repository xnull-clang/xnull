# `xdk.solutions` 解决方案层总览

| 项 | 值 |
| --- | --- |
| 范围 | 应用/解决方案层 |
| 层 | L8 solutions，位于 core/net/data 之上、应用之下 |
| 依赖 | `xdk.core`、`xdk.net`、`xdk.os`、`xdk.utils` |
| 被依赖 | 应用、服务、Agent、工具、嵌入式/计算产品 |
| 稳定性 | `preview`；不进入 1.0 公共承诺 |
| 状态 | 9 个包/组、122 个类型文档已完成；不含实现 |

---

## 1. 为什么有 solutions

core/net/os/utils 是通用能力；真实产品还需要**领域组合包**：

- 它们不是新运行时，也不是 core 的替代；
- 每个包只解决一个领域，不把框架、驱动、协议栈塞进 core；
- 它们可以依赖 core/net/os/utils；core/net/os/utils 不得反向依赖 solutions；
- 每个包独立设计、独立验收、独立实现。

---

## 2. 包组

| 包 | 领域 | 类型数 | 依赖 | 说明 |
| --- | --- | ---: | --- | --- |
| `xdk.embedded` | 嵌入式/设备 | 12 | `xdk.device`/`xdk.serial`/`xdk.os` | 板级支持、ADC/PWM/UART/CAN/看门狗/RTC/Flash/低功耗 |
| `xdk.accel` | 加速器 | 14 | `xdk.gpu`/`xdk.os.gpu`/`xdk.tensor` | GPU/NPU/DSP/FPGA/ASIC/LPU/IPU/HPU/DPU/VPU/MCU 统一抽象 |
| `xdk.db` | 数据库应用 | 11 | `xdk.sql` | 连接池、迁移、批量、事务作用域、健康检查；驱动仍为生态 |
| `xdk.ml` | 机器学习 | 20 | `xdk.tensor`/`xdk.linalg`/`xdk.codec` | 模型、推理会话、数据管道、训练抽象 |
| `xdk.agent` | 监控 Agent | 17 |  log +  metrics/trace、`xdk.os` | OTel Collector 风格 Receiver/Processor/Exporter/Pipeline |
| `xdk.api` | API 服务 | 15 | `xdk.net.http`/`xdk.codec`/`xdk.validate` | 路由、中间件、OpenAPI、Problem Details、Auth、限流、CORS、SSE |
| `xdk.numerics` | 数学计算 | 12 | core math/linalg/tensor | 任意精度、特殊函数、积分、优化、ODE、FFT、插值、求根 |
| `xdk.mcp` | MCP | 16 | `xdk.jsonrpc`/`xdk.net.http`/`xdk.codec` | MCP 客户端/服务端、tools/resources/prompts、stdio/HTTP 传输 |
| `xdk.jsonrpc` | JSON-RPC 基础 | 5 | `xdk.codec`/`xdk.io` | JSON-RPC 2.0 请求/响应/错误/Peer |
| `xdk.cli`（增强，计入 ） | CLI/系统工具 | 8 | core sys/io/fs | Shell 执行、命令结果、系统资源快照、运行时上下文 |

---

## 3. 依赖方向

```text
annotations ─┐
core ────────┼─ net/jwt/sql
                ├─ os/gpu/tensor/linalg/geo/serial/device
                └─ utils
                │
                ▼
 embedded / accel / db / ml / agent / api / numerics / mcp
                │
                └─ xdk.cli（增强，仍在  包内）
```

规则：

- solutions 可依赖 core/net/os/utils；core/net/os/utils 不得依赖 solutions。
-  包之间按需依赖，不得成环。
- 驱动、模型运行时、SQL 驱动、协议栈、Web 框架仍为 ecosystem。
- UI/desktop/显示/音频/输入/电源不在 2.x 基线，不进入 solutions。
- `xdk.net.service` 归 L5 网络层，不计入 solutions。

---

## 注解对接（P1）

 注解把应用/解决方案层的路由、依赖注入、ORM、模型、MCP 能力与 Agent 管线声明为**编译期契约**；处理器生成路由表、组件注册、DAO、能力清单，运行时只读生成的静态元数据，不做反射/类路径扫描。

| 包 | 注解 | 编译期检查 / 生成 |
| --- | --- | --- |
| `xdk.api` | `@Api`、`@Operation`、`@Middleware`、`@Inject`、`@Component`、`@Configuration`、`@Bean` | 路由、DI、配置生成 |
| `xdk.db` | `@Entity`、`@Table`、`@Id`、`@Transactional` | ORM/DAO、事务包装 |
| `xdk.ml` | `@ModelSpec`、`@MlPipeline`、`@TensorSpec` | 模型/流水线描述 |
| `xdk.mcp` | `@Tool`、`@Resource`、`@Prompt` | MCP 能力清单 |
| `xdk.agent` | `@AgentReceiver`、`@AgentProcessor`、`@AgentExporter`、`@PipelineSpec` | 采集/处理/导出管线 |

本层领域注解均为 planned；处理器/生成物未实现，不得写成已生效。完整矩阵与处理器规则见 [`ANNOTATION-SYSTEM.md`](../ANNOTATION-SYSTEM.md) §5。领域注解定义在所属包；处理器必须显式启用，生成结果确定、可重现并带来源标记。

## 4. 工作流

| 流 | 范围 | 产物 | 状态 |
| --- | --- | --- | --- |
| -1 | Embedded | `embedded` 包 README + 类型文件 | 已完成 |
| -2 | Accel | `accel` 包 README + 类型文件 | 已完成 |
| -3 | DB | `db` 包 README + 类型文件 | 已完成 |
| -4 | ML | `ml` 包 README + 类型文件 | 已完成 |
| -5 | Agent | `agent` 包 README + 类型文件 | 已完成 |
| -7 | API | `api` 包 README + 类型文件 | 已完成 |
| -8 | Numerics | `numerics` 包 README + 类型文件 | 已完成 |
| -9 | MCP + JSON-RPC | `mcp`、`jsonrpc` 包 README + 类型文件 | 已完成 |
| -10 | CLI 增强 | `../core/cli` 新增类型 + README 更新 | 已完成 |

---

## 5. 执行结果

```text
W1 Embedded    12
W2 Accel       14
W3 DB          11
W4 ML          20
W5 Agent       17
W7 API         15
W8 Numerics    12
W9 JSON-RPC     5 + MCP 16
W10 CLI 增强    8（计入 core，不计入 solutions）
 包合计       122 类型文件
本批新增       143 类型文件
14 段检查：全部通过
命名检查：PASS
相对链接：0 broken
代码/脚本改动：无
```

## 6. 质量门禁

- 每包 README：定位、原则、类型索引、跨类型规则、场景、缺口、安全；
- 每类型 14 段；一类型一文件；
- 公开签名只使用 XNull 语法；无泛型协议/泛型枚举；
- 阻塞方法首参 `Context`；失败 `Result`；资源 `close` 幂等；
- 不重复 core/net/os/utils 已有类型；
- 不把驱动/模型运行时/SQL 驱动/Web 框架塞进公共 API；
- 所有相对链接可达；参数命名检查 PASS；
- 无代码/脚本改动。

---

## 7. 分批与收尾

本文件是总范围；各工作流并行执行，父级统一集成：

1. 校验 10 个工作流的文件与 14 段；
2. 更新  CLI 索引、 总索引、`COVERAGE.md`；
3. 全量命名/链接/伪代码扫描；
4. 输出可编码状态。

“设计完成”不等于实现完成；实现批次另排。

---

## 8. 变更记录

- 2026-11-22：建立 ；完成 Embedded/Accel/DB/ML/Agent/Net Service/API/Numerics/JSON-RPC/MCP 与 CLI 增强设计。