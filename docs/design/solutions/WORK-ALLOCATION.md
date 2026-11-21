# solutions 工作分配与执行分析

> **历史记录**：本表是 2026-11-21 批次；`xdk.net.service` 已归 L5 网络层，solutions 现为 9 包 / 122 类型。当前包/阶段/计数以 [`../PACKAGE-MAP.md`](../PACKAGE-MAP.md) 为准。

| 项 | 值 |
| --- | --- |
| 目的 | 8 个领域 + MCP + CLI 增强一次并行完成 |
| 方法 | 盘点 → 行业调研 → 依赖/冲突分析 → 并行写包 → 统一集成 |
| 约束 | 只写设计；不改代码/测试/脚本；共享 README 由集成者最后修改 |

---

## 1. 盘点

| 流 | 包 | 类型数 | 行业参考 |
| --- | --- | ---: | --- |
| W1 | `xdk.embedded` | 12 | Zephyr、embedded-hal、ESP-IDF、STM32 HAL |
| W2 | `xdk.accel` | 14 | SYCL/oneAPI、CUDA、OpenCL、Vulkan compute、ONNX EP |
| W3 | `xdk.db` | 11 | JDBC、ADO.NET、database/sql、HikariCP、Flyway/Alembic |
| W4 | `xdk.ml` | 20 | ONNX Runtime、PyTorch C++、TFLite、Hugging Face |
| W5 | `xdk.agent` | 17 | OpenTelemetry Collector、Prometheus、Fluent Bit |
| W6 | `xdk.net.service` | 13 | Go net/http、Netty、Tokio、Kestrel |
| W7 | `xdk.api` | 15 | FastAPI、ASP.NET Core、Spring Boot、OpenAPI 3.1、RFC 7807 |
| W8 | `xdk.numerics` | 12 | BLAS/LAPACK、Eigen、SciPy、Boost.Math、GSL、FFTW、GMP/MPFR |
| W9 | `xdk.jsonrpc` + `xdk.mcp` | 5 + 16 | JSON-RPC 2.0、MCP 2025-11-25/2026-07-28 |
| W10 | `xdk.cli` 增强 | 8 | Cobra、picocli、clap、System.CommandLine |

---

## 2. 冲突分析

- 各工作流目录互不相交；W10 只改 `../core/cli`。
- 共享文件由集成者修改：
  - `docs/design/README.md`
  - `docs/design/COVERAGE.md`
  - `docs/design/core/cli/README.md`（仅 W10 可改，集成者复核）
- 不重复既有包：
  - embedded 复用 `xdk.device`/`xdk.serial`；
  - accel 复用 `xdk.gpu`/`xdk.os.gpu`/`xdk.tensor`；
  - db 复用 `xdk.sql`；
  - ml 复用 `xdk.tensor`/`xdk.linalg`；
  - agent 复用 core log + utils metrics/trace；
  - net.service 复用 `xdk.net`；
  - api 复用 `xdk.net.http`；
  - numerics 复用 core math/linalg；
  - mcp 复用 `xdk.jsonrpc`；
  - cli 复用 core `sys`/`io`/`fs`。
- 驱动/模型运行时/SQL 驱动/Web 框架/UI 不进 solutions 公共 API。

---

## 3. 每包标准

- 包 README：定位、原则、类型索引、跨类型规则、场景、缺口、安全；
- 每类型 14 段；一类型一文件；
- XNull 语法；非泛型协议；阻塞首参 `Context`；`Result` 失败；`close` 幂等；
- 不透明句柄；不暴露裸 fd/指针/驱动 SDK；
- 行业调研来源写入 README；
- 链接可达；参数命名检查 PASS。

---

## 4. 集成校验

1. 统计 10 个工作流文件齐全；
2. 14 段检查；
3. `check_doc_naming.py docs/design`；
4. 相对链接 0 broken；
5. 扫描非 XNull 写法；
6. 更新  总索引、 CLI 索引、`COVERAGE.md`；
7. 确认无代码/脚本改动。

---

## 5. 验收结果

```text
10 个工作流全部完成
135 个  类型文件 + 8 个 CLI 增强类型 = 143 个新增类型文件
14 段检查：全部通过
命名检查：PASS
相对链接：0 broken
代码/脚本改动：无
```

“设计完成”不等于实现完成；`src/xdk` 尚未实现 。
