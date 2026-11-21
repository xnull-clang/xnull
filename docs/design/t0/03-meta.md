# xdk.meta —— T0 版本与目标平台 v1.0

| 项 | 值 |
| --- | --- |
| 包 | `xdk.meta` |
| 层级 | T0 |
| 稳定性 | `stable` |
| 依赖 | 无（编译期常量；平台/架构/构建模式由 raw FFI 提供） |
| 被依赖 | 诊断、日志、CLI、配置 |
| 对应源码 | `src/xdk/core/meta/Meta.x` |
| 当前状态 | Verified（mini；版本/平台/BuildInfo/构建元数据） |

## 1. 能力

| 能力 | 说明 | 承载 |
| --- | --- | --- |
| CAP-1 语言版本 | 当前 XNull 规范版本 | `languageVersion` |
| CAP-2 XDK 版本 | 当前 XDK 交付版本 | `xdkVersion` |
| CAP-3 目标平台 | 运行平台名 | `targetPlatform` |
| CAP-4 构建信息 | 语言/XDK/编译器/平台/架构/模式聚合 | `BuildInfo`、`buildInfo` |
| CAP-5 构建元数据 | 架构、模式、编译器标识、构建时间 | `targetArch`、`buildMode`、`compilerName`、`compilerVersion`、`buildDate` |

**非目标**：包管理、运行期能力探测（T0-X）、目标能力矩阵的运行时查询。

## 2. 契约

```text
String languageVersion()
String xdkVersion()
String targetPlatform()
String targetArch()
String buildMode()
String compilerName()
String compilerVersion()
String buildDate()

class BuildInfo {
    BuildInfo(String languageVersion, String xdkVersion, String compiler,
              String compilerVersion, String platform, String arch,
              String mode, String builtAt)
    Bool complete()
    String describe()
}
BuildInfo buildInfo()
```

| 函数 | 后置 | 失败 | 稳定性 |
| --- | --- | --- | --- |
| `languageVersion()` | 返回 `"3.4.0"` | 无 | stable |
| `xdkVersion()` | 返回 `"0.1.0"` | 无 | stable |
| `targetPlatform()` | 返回平台名（`macos`/`linux` 等） | 无；未知平台返回 `"unknown"` | stable |
| `targetArch()` | 返回目标架构名（`arm64`/`x86_64` 等） | 无 | stable |
| `buildMode()` | 返回 `"release"` 或 `"debug"` | 无 | stable |
| `compilerName()` | 返回 `"mini"` | 无 | stable |
| `compilerVersion()` | 返回 `"3.4.0"` | 无 | stable |
| `buildDate()` | 返回运行库构建期的 `__DATE__ __TIME__` 文本 | 无 | preview |
| `buildInfo()` | 聚合以上字段；`complete()` 检查全部非空 | 无 | stable |

- 版本字符串是机器可读的 `major.minor.patch`；不包含构建号。
- `targetPlatform` 只用于展示/条件诊断；不得用它替代编译期目标判断。
- `buildDate` 反映 C 运行库的编译时间，不是 XDK 源文件的修改时间；构建可重现
  时它不保证稳定，不得用于业务逻辑或缓存键。
- `BuildInfo.complete()` 对空平台/架构/模式返回 `false`；`describe()` 仅用于诊断。
- 无资源、无 `close()`、无并发状态。

## 3. 测试义务

- 版本字符串非空且三段式；
- 平台名、架构名非空；
- `BuildInfo.complete()`、`describe()` 非空；
- 构建模式只取 `release`/`debug`；
- 构建时间为非空文本；
- base/full 输出一致。

场景：`xdk_meta.x`、`r4/meta_buildinfo.x`。

## 4. 后续（T1）

- 目标能力矩阵的运行时查询；
- 可重现构建时间与构建号（当前 `buildDate` 是编译器时间戳）。
