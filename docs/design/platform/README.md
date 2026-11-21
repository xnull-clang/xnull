# platform 领域（os/gpu/tensor/linalg/geo/serial/device）

| 项 | 值 |
| --- | --- |
| 范围 | `xdk.os`、`xdk.gpu`、`xdk.tensor`、`xdk.linalg`、`xdk.geo`、`xdk.serial`、`xdk.device` |
| 层 | 平台/计算层；可选，不进 core |
| 依赖 | `xdk.core`；按需依赖 `xdk.net`/L4/L7 服务包 |
| 被依赖 | 应用、服务器运维工具 |
| 稳定性 | `preview`；不进入 1.0 公共承诺 |
| 当前状态 | 17 个包/子包、93 个类型文档已完成；UI/desktop/显示/音频/输入/电源服务已从本基线移除；只写设计，不含实现 |
| 文档原则 | 包级说明在包 README；类型文件按 domain 逐步落地 |

> 全量能力覆盖审计见 [`COVERAGE.md`](../COVERAGE.md)。


---

## 1. 层定位

平台层不是“更大的 core”，而是**可选平台服务层**：

```text
L8  solutions            应用组合
L7  services             缓存/队列/指标/追踪/审计
L6  platform             os/gpu/tensor/linalg/geo/serial/device
L5  network              net/http/ws/tls/jwt/sql
L4  data/encoding        codec/crypto/compress/random/stats
L3  core system          io/fs/sys/log/config/cli
L2  core foundation      errors/meta/bytes/text/collections/math/time
L1  runtime/execution    RuntimeMonitor/Context/tasks/sync
L0  language/compiler    annotations
────────────────────────────────
  xdk.os / xdk.gpu / xdk.tensor / xdk.linalg / xdk.geo / xdk.serial / xdk.device
```

规则：

- 平台包可以依赖 L1–L6；L1–L6 不得依赖平台包。
- 平台包按需导入；未导入不影响 core 程序。
-  不重复 core/net 已有类型：文件、进程、TCP/UDP/TLS、HTTP/WS 仍在原层。
- 平台包的 OS 差异由 `xdk.os` 内部的适配器吸收；公开 API 不出现 `/sys`、`nftables`、`X11`、`IOKit`、`DXGI` 等平台类型/字符串。
- 驱动、厂商 SDK、裸设备访问不进平台公共 API；由 ecosystem/FFI 适配。

---

## 2. 包组

| 包组 | 职责 | 状态 |
| --- | --- | --- |
| `xdk.os` | OS 身份/能力、CPU/内存/硬件/GPU/防火墙/容器/虚拟化/服务 | 设计完成 |
| `xdk.gpu` | 高层 GPU 计算：buffer/program/pipeline/command/fence | 设计完成 |
| `xdk.tensor` | CPU 张量 | 设计完成 |
| `xdk.linalg` | 向量/矩阵/分解/求解 | 设计完成 |
| `xdk.geo` | 坐标/边界/路径/多边形/投影 | 设计完成 |
| `xdk.serial` | 串口打开/读写/枚举 | 设计完成 |
| `xdk.device` | GPIO/I2C/SPI/相机控制面 | 设计完成 |


---

## 3. 设计原则

| 原则 | 说明 |
| --- | --- |
| 可选 | 不进入核心安装包；按平台/产品裁剪 |
| 可失败 | 不支持 → `Unsupported`；无权限 → `PermissionDenied`；不 panic |
| 可取消 | 可阻塞探测/控制首参 `Context` |
| 不透明句柄 | 设备/控制器不暴露裸 fd/指针 |
| 只读优先 | 硬件清单默认只读；写操作显式命名并审计 |
| 无全局驱动 | 由 `OsHost`/控制器持有；不提供全局注册表 |
| 不重复 | 不复制 `File`/`Process`/`TcpStream`/`HttpServer` |
| 安全默认 | 防火墙/服务/裸设备默认拒绝；私钥/序列号/MAC 不入日志 |

---

## 注解对接（P1）

 注解把 FFI 布局、设备入口与 GPU/张量算子声明为**编译期契约**；处理器生成布局校验、设备注册表、kernel/算子包装，运行时只读生成元数据，不做反射。

| 领域 | 注解 | 编译期检查 / 生成 |
| --- | --- | --- |
| FFI/布局 | `@Packed`、`@Align`、`@NativeLayout` | 结构体布局/对齐校验、native 绑定 |
| 设备/串口 | `@Device`、`@Gpio`、`@I2cAddress`、`@SerialPort` | 设备/引脚/地址注册与参数检查 |
| GPU/张量/线代 | `@GpuKernel`、`@TensorOp`、`@LinalgOp` | kernel/算子入口与包装生成 |

完整矩阵见 [`ANNOTATION-SYSTEM.md`](../ANNOTATION-SYSTEM.md) §5。注解不替代显式设备/流/缓冲 API；处理器不得执行网络/任意文件写入，也不得在运行时反射扫描。

## 4. 文档索引

| 文档 | 内容 |
| --- | --- |
| `os/PLAN.md` | `xdk.os` 类型文档批次计划与状态 |
| `os/WORK-ALLOCATION.md` | 并行工作分配、冲突分析与集成校验 |
| `os/README.md` | `xdk.os` 包设计、类型索引、`OsHost` 服务面、场景、安全 |
| `os/OsKind.md` | OS 类型枚举 |
| `os/OsFamily.md` | OS 家族枚举 |
| `os/OsCapability.md` | OS/硬件能力枚举 |
| `os/OsInfo.md` | OS 版本/内核/发行版/会话快照 |
| `os/OsProfile.md` | OS 能力画像 |
| `os/host/README.md` | 宿主聚合包 |
| `os/host/OsHost.md` | 平台宿主协议 |
| `os/host/Os.md` | 静态入口 |
| `os/cpu/README.md` | CPU 拓扑/亲和性/特性 |
| `os/memory/README.md` | 物理内存/NUMA/映射 |
| `os/hardware/README.md` | 主板/BIOS/PCI/USB/传感器 |
| `os/storage/README.md` | 存储设备/分区/SMART |
| `os/gpu/README.md` | GPU 适配器/设备/队列 |
| `os/firewall/README.md` | 防火墙规则/状态/控制 |
| `os/container/README.md` | 容器/cgroup/namespace |
| `os/virt/README.md` | hypervisor/VM |
| `os/service/README.md` | 系统服务管理 |
| `gpu/README.md` | 高层 GPU 计算 |
| `tensor/README.md` | CPU 张量 |
| `linalg/README.md` | 线性代数 |
| `geo/README.md` | 地理坐标/路径/投影 |
| `serial/README.md` | 串口 |
| `device/README.md` | GPIO/I2C/SPI/相机控制面 |

---

## 5. 变更记录

- 2026-11-21：首版。确定平台层、`xdk.os` 包组、OS/硬件/GPU/防火墙边界。
- 2026-11-22：补齐 `xdk.gpu`/`xdk.tensor`/`xdk.linalg`/`xdk.geo`/`xdk.serial`/`xdk.device`；UI/desktop 服务从 2.x 基线移除。
