# XDK 能力覆盖审计

| 项 | 值 |
| --- | --- |
| 目的 | 回答 XDK 能力设计是否完整、还差哪些包 |
| 范围 | annotations、core、net/jwt/sql、os/平台/计算、utils、solutions（另计） |
| 依据 | S7 包目录、API 面分层能力、各层 README、实际类型文件 |
| 结论口径 | **设计完成** ≠ **实现完成** ≠ **场景验证通过** |
| 日期 | 2026-11-22 |

> 注解系统架构与 XDK 对接矩阵见 [`ANNOTATION-SYSTEM.md`](ANNOTATION-SYSTEM.md)；旧计划 [`ANNOTATION-PLAN.md`](ANNOTATION-PLAN.md) 保留为历史。

---

## 1. 现状盘点

| 层 | 包/组 | 类型文档 | 设计状态 | 实现状态 |
| --- | --- | ---: | --- | --- |
| L0 annotations | 1 | 14 | 设计基线（元模型/处理器合同） | 14 类型 + 编译器注解管线 + Registry + A8 5 个派生已实现；处理器调度/领域处理器未实现 |
| L1 runtime/execution | 2 | 25 | 设计完成 | 1.x runtime 部分；execution 为 tasks/sync 合并 |
| L2 core foundation | 7 | 80 | 设计完成 | 1.x 多数 Verified，部分 Partial |
| L3 core system | 6 | 81 | 设计完成 | 1.x 多数 Verified，部分 Partial |
| L4 data/encoding | 12 | 76 | 设计完成 | 未实现 |
| L5 network/data | 9 | 125 | 设计完成 | 未实现 |
| L6 platform/compute | 17 | 93 | 非 UI 部分设计完成；desktop 已移除 | 未实现 |
| L7 application services | 12 | 82 | 设计完成 | 未实现 |
| L8 solutions | 9 | 122 | 设计完成 | 未实现 |
| **总计** | **75 包/组** | **698** | | |

说明：

- 2.x core 的 15 包 = L1 `runtime`/`execution` + L2 `errors/meta/bytes/text/collections/math/time` + L3 `io/fs/sys/log/config/cli`；`tasks/sync` 合并为 `execution`。
- L4 + L7 是旧的 utils 24 包 / 158 类型：L4 数据/编码 12/76，L7 应用服务 12/82；文档仍在 `utils/` 目录下。
- L5 的 9 包是 `net/uri/mime/tls/http/websocket/net.service/jwt/sql`；`xdk.net.service` 从 solutions 归位到网络层。
- L6 的 17 个包/子包是 `os`、`os.host` + `cpu/memory/hardware/storage/gpu/firewall/container/virt/service` + `gpu/tensor/linalg/geo/serial/device`。
- L8 的 9 包是 `embedded/accel/db/ml/agent/api/numerics/jsonrpc/mcp`；`xdk.cli` 增强计入 core。
- annotations 独立 1 包，含 14 个元模型/元注解/处理器合同类型；逻辑上先于 core 的 `errors`。
- desktop 移除后：os 66→52，platform 107→93，总类型 712→698，包 76→75。
- 合计 **75 包/组 / 698 类型**；1.x 的 25 篇 legacy 文档另计，见 `LEGACY-1.0.md`。

---

## 2. 对照 S7 / API 面目录

### 2.1 annotations + core：基本闭合

| S7/API 面要求 | 现状 | 判断 |
| --- | --- | --- |
| annotations | 14 类型 | 完整（14 类型 + A8 已实现；领域处理器 planned） |
| errors/runtime/meta | 已有 | 完整 |
| bytes/text/collections/math/time | 已有 | 完整 |
| io/fs/sys/log/config/cli | 已有 | 完整 |
| tasks/sync/executor/timer | execution + time 承载 | 已合并，不缺口 |
| regex | `xdk.text.Regex` | 已合并，不缺口 |
| resource | `xdk.sys.Resource` | 已合并，不缺口 |
| health | `xdk.runtime.Health*` | 已合并，不缺口 |

结论：**annotations + core 设计闭合**；缺口在 core 的扩展面（时区库、完整 Unicode/ICU、Regex 全量、atomic/temp/walk/glob、PTY/信号等）与实现，不是“缺包”。编译器注解管线、Registry 与 A8 派生已实现；处理器调度器和领域处理器仍未实现。

### 2.2 net/jwt/sql：9 包 / 125 类型

| S7/API 面要求 | 现状 | 判断 |
| --- | --- | --- |
| net.uri/net/net.tls | 已有 | 完整 |
| net.http/net.websocket/net.mime | 已有 | 完整（HTTP3/QUIC 不做） |
| net.service | 已有 | 连接/会话/重连/背压/停机；归 L5 网络层 |
| jwt | 已有 | 完整（JWE/JWK 拉取为扩展） |
| sql | 已有 | 通用 SQL 接口完整；驱动为 ecosystem |
| auth/oauth/oidc | 未列入 S7 | 可作扩展/生态 |

结论：**网络、JWT、SQL 接口设计完成**；OAuth/OIDC、SOCKS、Unix domain、raw socket、ICMP、TUN/TAP、QUIC 为扩展/生态。

### 2.3 os/平台/计算：非 UI 部分已补齐

| 能力 | 现有覆盖 | 判断 |
| --- | --- | --- |
| OS 身份/CPU/内存/主板/PCI/USB/存储 | `xdk.os.*` | 已设计（只读基础） |
| GPU 低层 + 高层计算 | `xdk.os.gpu` + `xdk.gpu` | 已设计（计算基线） |
| 串口/GPIO/I2C/SPI/相机 | `xdk.serial` + `xdk.device` | 已设计（控制面） |
| geo | `xdk.geo` | 已设计 |
| tensor/linalg | `xdk.tensor` + `xdk.linalg` | 已设计 |
| UI/desktop/显示/音频/输入/电源 | 无 | **2.x 已移除** |

结论：**os/平台/计算的 17 包设计完成**；desktop/UI/图形/媒体/输入栈已从本基线移除。

### 2.4 utils：24 包 / 158 类型（文档分组）

| API 面 utils 要求 | 现状 | 判断 |
| --- | --- | --- |
| codec/crypto/compress/random/uuid/stats | 已有 | 完成 |
| functional/resilience/validate/cache/queue/schedule | 已有 | 完成 |
| metrics/trace/audit/terminal/i18n/test | 已有 | 完成 |
| regex | xdk.text | 已合并 |
| health | xdk.runtime | 已合并 |
| resource | xdk.sys | 已合并 |
| event/reflect/graph | 已设计 | 完成 |
| yaml/toml/xml | 已设计 | 完成 |
| zstd/lz4/brotli | 已设计（compress 内） | 完成 |

结论：**utils 24 包设计完成**；按架构分为 L4 数据/编码 12/76 与 L7 应用服务 12/82；具体 exporter/CLDR/HSM/并行 runner 等深水区仍为扩展。

### 2.5 solutions：9 包/组 / 122 类型

| 包 | 能力 | 状态 |
| --- | --- | --- |
| `xdk.embedded` | 板级支持、ADC/PWM/UART/CAN/看门狗/RTC/Flash/低功耗 | 设计完成 |
| `xdk.accel` | GPU/NPU/DSP/FPGA/ASIC/LPU/IPU/HPU/DPU/VPU/MCU 统一加速器 | 设计完成 |
| `xdk.db` | 连接池、迁移、批量、事务、健康检查 | 设计完成 |
| `xdk.ml` | 模型/推理/数据管道/训练抽象 | 设计完成（autograd 为扩展） |
| `xdk.agent` | OTel Collector 风格 Receiver/Processor/Exporter/Pipeline | 设计完成 |
| `xdk.api` | 路由、中间件、OpenAPI、Problem Details、Auth、限流、CORS、SSE | 设计完成 |
| `xdk.numerics` | 任意精度、特殊函数、积分、优化、ODE、FFT、插值、求根 | 设计完成 |
| `xdk.jsonrpc` | JSON-RPC 2.0 | 设计完成 |
| `xdk.mcp` | MCP 客户端/服务端、tools/resources/prompts、stdio/HTTP | 设计完成 |

结论：solutions 9 包/组设计完成；`xdk.net.service` 归 L5 网络层；UI/desktop 已从 2.x 基线移除。

---

## 3. 按应用场景看完整性

| 场景 | 现有能力 | 缺口 | 判断 |
| --- | --- | --- | --- |
| CLI/数据工具 | core + utils codec/stats/regex/terminal | 无阻塞缺口 | 设计够用 |
| API 服务 | net.http + TLS + JWT + sql + utils validate/cache/queue/metrics/trace | OAuth/OIDC、Prometheus/OTLP exporter | 设计基本够用 |
| 网络客户端 | net.http/ws/tls + JWT | SOCKS、HTTP3/QUIC（扩展） | 主流场景够用 |
| 监控 Agent | os + net + utils metrics/stats | 系统服务/容器控制面 | 设计够用 |
| 嵌入式/设备 | os.hardware + serial/device/embedded | 高级控制面/驱动 | 设计基线够用 |
| GPU/计算 | os.gpu + gpu/tensor/linalg + accel | 渲染/交换链/训练引擎 | 计算基线够用 |
| 数据库/后台 | sql + db | 具体驱动、迁移生态 | 设计基线够用 |

---

## 4. 明确不做/延后

- UI/desktop/显示/音频/输入/电源：不在 2.x 基线；不排期、不立 3.x 议题。
- 数据库驱动（PostgreSQL/MySQL/SQLite）、模型运行时、Web 框架、协议栈：ecosystem。
- 分布式调度/持久化/集群：归 solutions 扩展。
- 具体 metrics/trace exporter、CLDR、HSM/FIPS：扩展面。

---

## 5. 现有包内的主要缺口

| 层 | 缺口 |
| --- | --- |
| core | 时区数据库、完整 Unicode/ICU、Regex 全量、atomic/temp/walk/glob、PTY/信号完整面、内嵌资源完整面、注解处理器调度/生成/领域处理器 |
| net/jwt/sql | TLS 证书链/OCSP/CRL/会话缓存、HTTP/2 细节、HTTP/3/QUIC（不做）、SOCKS/Unix domain/raw socket（扩展） |
| os/平台/计算 | desktop/UI/gfx/image/font/input/clipboard 已移除；容器/VM 控制面扩展；GPU 渲染/显示/交换链不在 2.x |
| utils | metrics/trace 只有模型/协议，无具体 exporter；cache 单飞扩展；schedule 持久化/分布式扩展；i18n locale 数据扩展；test 并行/隔离扩展 |
| solutions | ML autograd/训练引擎扩展；MCP tasks/流式/订阅扩展；API OAuth/OIDC/身份提供方扩展；Agent 持久 checkpoint/远程配置扩展 |

---

## 6. 结论

### 6.1 “设计完整”分层回答

- **annotations**：1 包 / 14 类型已实现；编译器注解管线、Registry 与 A8 派生已实现；处理器调度、领域处理器未完成。
- **core**：15 包 / 186 类型，声明包设计闭合；包内扩展面与实现未完成。
- **net/jwt/sql**：9 包 / 125 类型（含 `xdk.net.service`）；网络 + JWT + SQL 接口设计完成；OAuth/OIDC/QUIC 等为扩展/生态。
- **os/平台/计算**：17 包 / 93 类型，非 UI 平台/计算包设计完成；UI/desktop 已从 2.x 移除，不计入完成度。
- **utils**：24 包 / 158 类型，按架构分为 L4 数据/编码 12/76 与 L7 应用服务 12/82；exporter/CLDR/HSM/并行 runner 等仍为扩展。
- **solutions**：9 包/组 / 122 类型；ML autograd、MCP tasks/流式、API OAuth 等仍为扩展。
- **整体 XDK**：作为“注解 + 核心 + 网络 + OS/平台/计算 + 服务”非 UI 标准库，设计覆盖已大幅补齐；UI/桌面/图形/媒体明确不在 2.x。

### 6.2 不能说的话

- 不能说“全部完成”：utils/solutions 扩展仍有深水区；UI/desktop 不在 2.x，不是“待完成项”。
- 不能说“所有注解都可用”：编译器内建、Registry 与 A8 已实现；领域处理器仍为 planned；领域注解不得写成已生效。
- 不能说“设计完成 = 实现完成”：net/os/utils/solutions 均未实现；core 仍有 Partial。
- 不能说“缺包都是遗漏”：UI/desktop 是主动移除；扩展面已登记。

---

## 7. 建议的下一批

| 产品方向 | 下一批 |
| --- | --- |
| UI/桌面/图形/媒体 | 不在 2.x；不排期、不设计 |
| 纯服务端/CLI | 不补 os/平台；优先补 utils exporter、core 扩展缺口 |
| 数据/后台 | 具体 SQL 驱动（生态）→ OAuth/OIDC（扩展）→ metrics/trace exporter |
| 嵌入式/设备 | 补 `xdk.device` 高级面：PWM/中断/相机控制/PTP |
| GPU/计算 | `xdk.gpu` 计算基线已够；渲染/显示/交换链不在 2.x；训练/推理仍为生态 |
| solutions 深水区 | ML autograd、MCP tasks/流式、API OAuth/OIDC、Agent 持久 checkpoint/远程配置 |

---

## 8. 验收依据

```text
L0 annotations: 1 包 / 14 类型
L1 runtime/execution: 2 包 / 25 类型
L2 core foundation: 7 包 / 80 类型
L3 core system: 6 包 / 81 类型
core 小计: 15 包 / 186 类型
L4 data/encoding: 12 包 / 76 类型
L5 network/data: 9 包 / 125 类型
L6 platform/compute: 17 包/子包 / 93 类型
L7 application services: 12 包 / 82 类型
L8 solutions: 9 包/组 / 122 类型
总计: 75 包/组 / 698 类型文档
```

本审计只判断“设计与包覆盖”，不代表实现、场景或性能验证。
