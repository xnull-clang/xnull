# xdk.config ——  配置快照 v1.0

> **1.x legacy**：本文件是旧 core 包级设计/状态账本，不是 2.x 类型合同。2.x 以 [`core/`](README.md) 的逐包目录与 [`../PACKAGE-MAP.md`](../PACKAGE-MAP.md) 为准；执行层统一为 `xdk.execution`。

> **状态（2026-11-21）**：本文件是  v1 包级设计/实现状态账本。
> 公开类型与方法形态以 [`core/`](README.md) 为准；状态汇总见 [`STATUS.md`](STATUS.md)；
> 本文件的 `当前状态`、源码路径与 K/X 明细继续保留。

| 项 | 值 |
| --- | --- |
| 包 | `xdk.config` |
| 层级 |  |
| 稳定性 | `preview` |
| 依赖 | `xdk.fs`、`xdk.text`、`xdk.sys`；不依赖 codec |
| 被依赖 | cli、log、应用主逻辑 |
| 对应源码 | `src/xdk/config/Config.x` |
| 当前状态 | Verified（mini；内存/环境面） |

## 1. 能力

| 能力 | 说明 | 承载 |
| --- | --- | --- |
| CAP-1 快照 | profile + 有序键值 | `Config` |
| CAP-2 覆盖 | set 替换同键 | `Config.set` |
| CAP-3 读取 | getOr/has/length | `Config` |
| CAP-4 环境白名单 | 仅导入显式键 | `Config.loadEnv` |
| CAP-5 渲染 | profile:key=value,... | `Config.render` |

**非目标**：JSON/TOML/YAML 解码（ codec）、文件监听、远程配置、schema
校验、类型化 getter（X）。

## 2. 契约

```text
class Config {
    Config(String profile)
    Int length()
    Bool has(String key)
    void set(String key, String value)
    String getOr(String key, String fallback)
    void loadEnv(List<String> keys)
    String render()
}
```

- 键值保持插入顺序；`set` 对已存在键原位替换。
- 键必须非空且不含 `=`； 不校验值类型。
- `loadEnv` 只读取白名单键；缺失键不改动原值。
- `render` 用于诊断，不作为稳定序列化格式。
- 无资源、无 `close()`；可变构建期类型，非线程安全。

## 3. 测试义务

- set 覆盖/顺序；
- getOr/has/长度；
- 环境白名单命中/缺失；
- render 格式；
- base/full 输出一致。

场景：`xdk_config.x`。

## 4. 后续（X/）

- `ConfigSource`/`FileSource`/overlay；
- 类型化 getter（Int/Bool/Duration）；
- 校验与错误聚合；
- codec 注入的结构化格式。
