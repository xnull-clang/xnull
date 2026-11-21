# `YamlOptions`

| 项 | 值 |
| --- | --- |
| 类型 | `class YamlOptions` |
| 包 | `xdk.yaml` |
| 稳定性 | `preview` |
| 依赖 | `YamlVersion` |

---

## 1. 定位

YAML 解析/生成选项：版本、深度/字节/文档/别名预算、重复键、锚点、合并键、标准标签、profile 键。

不做：缩进宽度、注释保留、Schema、任意标签白名单、流式配置、占位符解析。

---

## 2. 设计逻辑

- 可变 builder；`Yaml` 在入口复制，后续修改不影响已开始调用。
- 默认：YAML 1.1、深度 128、16 MiB、128 文档、1000 别名、拒绝重复键、允许锚点/合并键/标准标签、profile 键为空。
- `profileKey` 为空表示不提取 profile；Spring Boot 用法设置 `spring.config.activate.on-profile`。
- `maxAliases=0` 表示禁用别名（即使 `allowAnchors=true`）；`allowMergeKeys` 仅在锚点/别名可用时有意义。
- `Yaml11` 下 `yes/no/on/off` 为 bool；`Yaml12` 下为 string。
- 无 close；非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_version` | `YamlVersion` | 1.1/1.2 |
| `_maxDepth` | `Int` | 容器最大嵌套深度，根为 1 |
| `_maxBytes` | `Long` | 解析输入/生成输出 UTF-8 上限 |
| `_maxDocuments` | `Int` | 多文档数量上限 |
| `_maxAliases` | `Int` | 别名解析次数上限；0 禁用 |
| `_allowDuplicateKeys` | `Bool` | 重复键后者覆盖 |
| `_allowAnchors` | `Bool` | 是否允许锚点/别名 |
| `_allowMergeKeys` | `Bool` | 是否允许 `<<` 合并键 |
| `_allowStandardTags` | `Bool` | 是否接受 `!!timestamp`/`!!binary` 等 |
| `_profileKey` | `String` | profile 提取键；空表示关闭 |

不变量：深度/字节/文档 >0；别名 ≥0；version/profileKey 非 null；布尔字段无隐含组合。

---

## 4. 生命周期

可变；无 close；`copy` 返回独立快照。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `YamlOptions()` | 无 | 默认值 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `version` | 设置 YAML 版本 | `YamlVersion value` | `YamlOptions` | null → panic |
| `maxDepth` | 设置深度 | `Int value` | `YamlOptions` | ≤0 → panic |
| `maxBytes` | 设置字节上限 | `Long value` | `YamlOptions` | ≤0 → panic |
| `maxDocuments` | 设置文档上限 | `Int value` | `YamlOptions` | ≤0 → panic |
| `maxAliases` | 设置别名上限 | `Int value` | `YamlOptions` | <0 → panic |
| `allowDuplicateKeys` | 重复键策略 | `Bool value` | `YamlOptions` | 无 |
| `allowAnchors` | 锚点开关 | `Bool value` | `YamlOptions` | 无 |
| `allowMergeKeys` | 合并键开关 | `Bool value` | `YamlOptions` | 无 |
| `allowStandardTags` | 标准标签开关 | `Bool value` | `YamlOptions` | 无 |
| `profileKey` | profile 键 | `String value` | `YamlOptions` | null → panic |
| `getVersion` | 读取版本 | 无 | `YamlVersion` | 无 |
| `getMaxDepth` | 读取深度 | 无 | `Int` | 无 |
| `getMaxBytes` | 读取字节上限 | 无 | `Long` | 无 |
| `getMaxDocuments` | 读取文档上限 | 无 | `Int` | 无 |
| `getMaxAliases` | 读取别名上限 | 无 | `Int` | 无 |
| `isAllowDuplicateKeys` | 读取重复键策略 | 无 | `Bool` | 无 |
| `isAllowAnchors` | 读取锚点开关 | 无 | `Bool` | 无 |
| `isAllowMergeKeys` | 读取合并键开关 | 无 | `Bool` | 无 |
| `isAllowStandardTags` | 读取标准标签开关 | 无 | `Bool` | 无 |
| `getProfileKey` | 读取 profile 键 | 无 | `String` | 无 |
| `copy` | 独立快照 | 无 | `YamlOptions` | 无 |

说明：

- `maxDepth` 统计容器层级；根容器为 1，标量根不消耗容器深度。
- `maxBytes` 在解析时限制输入 UTF-8 字节，在生成时限制输出 UTF-8 字节。
- `maxDocuments` 对 `parseAll`/`parsePropertySources` 生效；`parse` 仍要求恰好一个。
- `maxAliases` 统计别名展开次数，防止“YAML 炸弹”；0 禁用。
- `profileKey` 为空字符串时不提取 profiles；非空时只接受字符串或字符串数组值。
- `allowMergeKeys` 为 false 时 `<<` 键返回 `Unsupported`，不静默当普通键。
- `allowStandardTags` 为 false 时除 core schema 标签外的标签均 `Unsupported`。

---

## 8. 使用的技术

- 可变 builder；
- 有界预算；
- 版本/profile/安全策略开关。

---

## 9. 需要的支撑

- 语言：class、Int、Long、Bool、String；
- 运行时：无；
- 接口：`YamlVersion`。

---

## 10. 依赖的特性/接口/类

`YamlVersion`。

---

## 11. 所有权与并发

可变；非线程安全；无资源。调用方负责在跨任务共享前完成配置；`Yaml` 入口会复制，之后不再读取原对象。

---

## 12. 示例与反例

正确：`new YamlOptions().version(YamlVersion.Yaml11).allowMergeKeys(true).profileKey("spring.config.activate.on-profile")`。  
反例：`maxDepth(0)`；`maxAliases(-1)`；设置 `allowMergeKeys(true)` 但 `allowAnchors(false)` 期望合并生效；修改已传入 `Yaml.parseAll` 的 options 并期望正在进行的解析变化。

---

## 13. 测试/场景义务

默认值；每个 setter/getter；非正预算 panic；`copy` 独立；入口复制；版本 bool 差异；别名上限 0/N；合并键开关；标准标签开关；profile 键空/非空/非法值；多字节 UTF-8 计数。

---

## 14. XNull 伪代码

```xnull
class YamlOptions {
    YamlVersion _version = YamlVersion.Yaml11
    Int _maxDepth = 128
    Long _maxBytes = 16777216
    Int _maxDocuments = 128
    Int _maxAliases = 1000
    Bool _allowDuplicateKeys = false
    Bool _allowAnchors = true
    Bool _allowMergeKeys = true
    Bool _allowStandardTags = true
    String _profileKey = ""

    YamlOptions() {
    }

    YamlOptions version(YamlVersion value) {
        if value == null { throw "YamlOptions.version: null" }
        _version = value
        return self
    }

    YamlOptions maxDepth(Int value) {
        if value <= 0 { throw "YamlOptions.maxDepth: invalid" }
        _maxDepth = value
        return self
    }

    YamlOptions maxBytes(Long value) {
        if value <= 0 { throw "YamlOptions.maxBytes: invalid" }
        _maxBytes = value
        return self
    }

    YamlOptions maxDocuments(Int value) {
        if value <= 0 { throw "YamlOptions.maxDocuments: invalid" }
        _maxDocuments = value
        return self
    }

    YamlOptions maxAliases(Int value) {
        if value < 0 { throw "YamlOptions.maxAliases: negative" }
        _maxAliases = value
        return self
    }

    YamlOptions allowDuplicateKeys(Bool value) {
        _allowDuplicateKeys = value
        return self
    }

    YamlOptions allowAnchors(Bool value) {
        _allowAnchors = value
        return self
    }

    YamlOptions allowMergeKeys(Bool value) {
        _allowMergeKeys = value
        return self
    }

    YamlOptions allowStandardTags(Bool value) {
        _allowStandardTags = value
        return self
    }

    YamlOptions profileKey(String value) {
        if value == null { throw "YamlOptions.profileKey: null" }
        _profileKey = value
        return self
    }

    YamlVersion getVersion() { return _version }
    Int getMaxDepth() { return _maxDepth }
    Long getMaxBytes() { return _maxBytes }
    Int getMaxDocuments() { return _maxDocuments }
    Int getMaxAliases() { return _maxAliases }
    Bool isAllowDuplicateKeys() { return _allowDuplicateKeys }
    Bool isAllowAnchors() { return _allowAnchors }
    Bool isAllowMergeKeys() { return _allowMergeKeys }
    Bool isAllowStandardTags() { return _allowStandardTags }
    String getProfileKey() { return _profileKey }

    YamlOptions copy() {
        YamlOptions result = new YamlOptions()
        result.version(_version)
        result.maxDepth(_maxDepth)
        result.maxBytes(_maxBytes)
        result.maxDocuments(_maxDocuments)
        result.maxAliases(_maxAliases)
        result.allowDuplicateKeys(_allowDuplicateKeys)
        result.allowAnchors(_allowAnchors)
        result.allowMergeKeys(_allowMergeKeys)
        result.allowStandardTags(_allowStandardTags)
        result.profileKey(_profileKey)
        return result
    }
}
```
