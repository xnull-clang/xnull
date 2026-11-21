# xdk.config —— T0 配置快照 v1.0

| 项 | 值 |
| --- | --- |
| 包 | `xdk.config` |
| 层级 | T0 |
| 稳定性 | `preview` |
| 依赖 | `xdk.fs`、`xdk.text`、`xdk.sys`；不依赖 codec |
| 被依赖 | cli、log、应用主逻辑 |
| 对应源码 | `src/xdk/config/Config.x` |
| 当前状态 | Verified（mini；Config/MapSource/FileSource/overlay） |

## 1. 能力

| 能力 | 说明 | 承载 |
| --- | --- | --- |
| CAP-1 快照 | profile + 有序键值 | `Config` |
| CAP-2 覆盖 | set 替换同键 | `Config.set` |
| CAP-3 读取 | getOr/has/length | `Config` |
| CAP-4 环境白名单 | 仅导入显式键 | `Config.loadEnv` |
| CAP-5 渲染 | profile:key=value,... | `Config.render` |
| CAP-6 来源 | 内存/文件 key=value 源 | `ConfigSource`、`MapSource`、`FileSource` |
| CAP-7 合并/校验 | overlay 与最小键校验 | `Config.overlay`、`Config.setChecked`、`Config.apply` |

**非目标**：JSON/TOML/YAML 解码（T1 codec）、文件监听、远程配置、schema
校验、类型化 getter（T1）。

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
    Config copy()
    Result<Unit, Error> setChecked(String key, String value)
    Result<Unit, Error> apply(ConfigSource source)
    Config overlay(Config other)
}

class ConfigEntry { ConfigEntry(String key, String value) }
protocol ConfigSource { Result<List<ConfigEntry>, Error> load(); }
class MapSource implements ConfigSource { MapSource(List<ConfigEntry> entries) }
class FileSource implements ConfigSource { FileSource(String path) }
```

- 键值保持插入顺序；`set` 对已存在键原位替换。
- 键必须非空且不含 `=`；T0 不校验值类型。
- `loadEnv` 只读取白名单键；缺失键不改动原值。
- `render` 用于诊断，不作为稳定序列化格式。
- `ConfigEntry` 是 key/value 值对象；`FileSource` 解析 `key=value`，忽略空行与 `#` 注释。
- `setChecked` 拒绝空 key 和含 `=` 的 key；`apply` 逐条应用 source，遇错返回 `Err`。
- `overlay` 返回新快照，`other` 覆盖同键。
- 无资源、无 `close()`；可变构建期类型，非线程安全。

## 3. 测试义务

- set 覆盖/顺序；
- getOr/has/长度；
- 环境白名单命中/缺失；
- render 格式；
- MapSource/FileSource 加载与注释/空行；
- overlay 覆盖与 setChecked 非法 key；
- 非法文件行返回 `InvalidArgument`；
- base/full 输出一致。

场景：`xdk_config.x`。

## 4. 后续（T1）

- 类型化 getter（Int/Bool/Duration）；
- schema 校验与错误聚合；
- codec 注入的结构化格式。
