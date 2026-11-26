# L8 关闭记录（Solutions 层）

| 项 | 值 |
| --- | --- |
| 里程碑 | L8 solutions |
| 状态 | **Closed（8/10 包 implemented；2 包硬件阻塞）** |
| 日期 | 2026-11-26 |
| 基线 | `main`；以 `src/xdk/xdk2-packages.tsv` 为准 |
| 退出标准 | 每个 L8 包要么 implemented + 场景/门禁，要么有明确原语阻塞清单；不允许“下批再做”式占位 |

---

## 1. 包结论

| 包 | 文档类型 | 状态 | 说明 |
| --- | ---: | --- | --- |
| `xdk.auth` | 6 | implemented | AuthScheme/Credential/Principal/Authenticator/AuthService/AuthHeaders；Bearer/JWT/API key |
| `xdk.jsonrpc` | 5 | implemented | Id/Error/Request/Response/Peer；消息模型与 Peer |
| `xdk.db` | 11 | implemented | 值/池/批量/映射/Database/健康/实体注解/迁移子集；内存驱动 |
| `xdk.api` | 15 | implemented | ProblemDetails/路由/上下文/OpenAPI/ApiServer/SseStream（同步 chunked） |
| `xdk.ml` | 20 | implemented（合同） | 模型/会话/数据管道/损失；无宿主运行时，`openSession/run` 返回 Unsupported |
| `xdk.numerics` | 12 | implemented（类型） | BigInt/积分/优化/ODE/FFT/信号/特殊函数/BigFloat 算术；BigFloat exp/log/pow planned |
| `xdk.mcp` | 16 | implemented | 消息模型 + Stdio/Client/Server/Registry/HttpTransport（JSON + 完整 SSE 体） |
| `xdk.agent` | 17 | implemented 11/17 | 遥测核心/管线/配置/Agent；HostMetrics/FileLog/批处理/限流/OTLP/Prometheus 未实现 |
| `xdk.accel` | 14 | **blocked** | 需要 Metal/CUDA/ROCm/Vulkan 设备/内存/内核/栅栏原语 |
| `xdk.embedded` | 12 | **blocked** | 需要 GPIO/I2C/SPI/UART/ADC/PWM/Watchdog/RTC/Flash 原语 |

---

## 2. 明确阻塞（不是“没做”，是缺底层能力）

- `xdk.accel`：见 `docs/design/platform/HARDWARE-PRIMITIVES.md` §2。
- `xdk.embedded`：见同文 §3。
- `xdk.agent.HostMetricsReceiver`：需要 `xdk.os.host`（IOKit/sysctl 主机模型）。
- `xdk.agent.FileLogReceiver`：需要路径匹配/文件 tail 合同（`PathMatcher`）。
- `xdk.ml` 运行时：需要宿主注入推理适配器。
- `xdk.numerics.BigFloat` 超越函数：`exp/log/pow` 需要任意精度级数与范围约减，当前返回 Unsupported。

---

## 3. 验证

- `xdk2.sh`：71 scenarios PASS
- `xdk2_extra.sh`、`xdk_core.sh`、完整 `xdk.sh`、`annotation_platform/m7_gate.sh` PASS
- `check_doc_naming`、`check_links`、`check_ui_scope`、`check_annotation_surface`、`check.py`、`git diff --check` PASS
- 关键端到端：API SSE（chunked 事件/id/多行/注释/终止块）、ApiServer auth/rate/CORS/validation/OpenAPI、MCP Client↔Server、BigInt/BigFloat、FFT/滤波、特殊函数数值断言

---

## 4. 下一计划

L8 关闭后进入整体计划：B5–B10（`docs/design/EXECUTION-PLAN.md`）。
B5 先处理 L1–L3 core 15 包 2.x 实现/验证；硬件阻塞包只在补齐对应原语后重开。
