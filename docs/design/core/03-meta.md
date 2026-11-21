# xdk.meta ——  版本与目标平台 v1.0

> **1.x legacy**：本文件是旧 core 包级设计/状态账本，不是 2.x 类型合同。2.x 以 [`core/`](README.md) 的逐包目录与 [`../PACKAGE-MAP.md`](../PACKAGE-MAP.md) 为准；执行层统一为 `xdk.execution`。

> **状态（2026-11-21）**：本文件是  v1 包级设计/实现状态账本。
> 公开类型与方法形态以 [`core/`](README.md) 为准；状态汇总见 [`STATUS.md`](STATUS.md)；
> 本文件的 `当前状态`、源码路径与 K/X 明细继续保留。

| 项 | 值 |
| --- | --- |
| 包 | `xdk.meta` |
| 层级 |  |
| 稳定性 | `stable` |
| 依赖 | 无（编译期常量；平台名由 raw FFI 提供） |
| 被依赖 | 诊断、日志、CLI、配置 |
| 对应源码 | `src/xdk/core/meta/Meta.x` |
| 当前状态 | Verified（mini） |

## 1. 能力

| 能力 | 说明 | 承载 |
| --- | --- | --- |
| CAP-1 语言版本 | 当前 XNull 规范版本 | `languageVersion` |
| CAP-2 XDK 版本 | 当前 XDK 交付版本 | `xdkVersion` |
| CAP-3 目标平台 | 运行平台名 | `targetPlatform` |

**非目标**：包管理、构建元数据、运行期能力探测（X）。

## 2. 契约

```text
String languageVersion()
String xdkVersion()
String targetPlatform()
```

| 函数 | 后置 | 失败 | 稳定性 |
| --- | --- | --- | --- |
| `languageVersion()` | 返回 `"3.4.0"` | 无 | stable |
| `xdkVersion()` | 返回 `"0.1.0"` | 无 | stable |
| `targetPlatform()` | 返回平台名（`macos`/`linux` 等） | 无；未知平台返回 `"unknown"` | stable |

- 版本字符串是机器可读的 `major.minor.patch`；不包含构建号。
- `targetPlatform` 只用于展示/条件诊断；不得用它替代编译期目标判断。
- 无资源、无 `close()`、无并发状态。

## 3. 测试义务

- 版本字符串非空且三段式；
- 平台名非空；
- base/full 输出一致。

场景：`xdk_meta.x`。

## 4. 后续（X）

- `BuildInfo`（语言/XDK/编译器/平台/架构/模式）；
- 目标能力矩阵；
- 构建元数据。
