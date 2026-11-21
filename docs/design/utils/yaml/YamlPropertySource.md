# `YamlPropertySource`

| 项 | 值 |
| --- | --- |
| 类型 | `class YamlPropertySource` |
| 包 | `xdk.yaml` |
| 稳定性 | `preview` |
| 依赖 | `YamlDocument` |

---

## 1. 定位

扁平 YAML 属性源：`Map<String,String>` + 文档序号/profile 元数据。

不做：属性合并/优先级、占位符解析、类型转换、Spring Environment/PropertySource 实现。

---

## 2. 设计逻辑

- 不可变；properties 构造时复制，读取返回副本。
- 名称非空；文档序号 ≥0；profile 列表同 `YamlDocument` 规则。
- 值均为 String：null → 空串，bool → `true`/`false`，number → 原始文本，string 原样。
- `isActiveFor` 与 `YamlDocument.isActive` 同语义。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | 属性源名 |
| `_documentIndex` | `Int` | 文档序号 |
| `_profiles` | `List<String>` | profile 表达式 |
| `_properties` | `Map<String,String>` | 扁平属性 |

不变量：name 非空；index ≥0；profiles/properties 非 null；properties 值非 null。

---

## 4. 生命周期

不可变；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `YamlPropertySource(String name, Int documentIndex, List<String> profiles, Map<String,String> properties)` | 全部 | 见不变量 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | 属性源名 | 无 | `String` | 无 |
| `documentIndex` | 文档序号 | 无 | `Int` | 无 |
| `profiles` | profile 表达式 | 无 | `List<String>` | 无 |
| `properties` | 属性快照 | 无 | `Map<String,String>` | 无 |
| `getOrNull` | 取值/无 | `String key` | `String?` | null → panic |
| `getOr` | 取值/兜底 | `String key, String fallback` | `String` | null → panic |
| `contains` | 是否存在 | `String key` | `Bool` | null → panic |
| `keys` | 键快照 | 无 | `List<String>` | 无 |
| `isActiveFor` | 是否激活 | `List<String> activeProfiles` | `Bool` | null → panic |
| `describe` | 摘要 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 不可变属性快照；
- 扁平键约定；
- profile 匹配。

---

## 9. 需要的支撑

- 语言：class、String、Int、Bool、List、Map；
- 运行时：无；
- 接口：`YamlDocument`（语义参考）。

---

## 10. 依赖的特性/接口/类

`YamlDocument`（profile 语义）。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`source.getOrNull("server.port")`；`source.isActiveFor(["prod"])`。  
反例：期望属性源自动合并多文档；修改 `properties()` 期望影响 source；把 null 值当缺失（实际是空串）。

---

## 13. 测试/场景义务

名称/序号；properties 复制；getOrNull/getOr/contains/keys；null 值；profiles 空/匹配/取反；describe；非法构造。

---

## 14. XNull 伪代码

```xnull
class YamlPropertySource {
    final String _name
    final Int _documentIndex
    final List<String> _profiles
    final Map<String, String> _properties

    YamlPropertySource(String name, Int documentIndex, List<String> profiles,
                       Map<String, String> properties) {
        if name == null || name == "" { throw "YamlPropertySource: empty name" }
        if documentIndex < 0 { throw "YamlPropertySource: negative index" }
        if profiles == null || properties == null {
            throw "YamlPropertySource: null argument"
        }
        _name = name
        _documentIndex = documentIndex
        _profiles = profiles.copy()
        _properties = properties.copy()
    }

    String name() { return _name }
    Int documentIndex() { return _documentIndex }
    List<String> profiles() { return _profiles.copy() }
    Map<String, String> properties() { return _properties.copy() }

    String? getOrNull(String key) {
        if key == null { throw "YamlPropertySource.getOrNull: null key" }
        if !_properties.has(key) { return null }
        return _properties.get(key)
    }

    String getOr(String key, String fallback) {
        if key == null || fallback == null {
            throw "YamlPropertySource.getOr: null argument"
        }
        if !_properties.has(key) { return fallback }
        return _properties.get(key)
    }

    Bool contains(String key) {
        if key == null { throw "YamlPropertySource.contains: null key" }
        return _properties.has(key)
    }

    List<String> keys() { return _properties.keys() }

    Bool isActiveFor(List<String> activeProfiles) {
        if activeProfiles == null {
            throw "YamlPropertySource.isActiveFor: null"
        }
        if _profiles.isEmpty() { return true }
        Int index = 0
        while index < _profiles.length() {
            String expression = _profiles.get(index)
            if expression.startsWith("!") {
                String name = expression.substring(1, expression.length() - 1)
                if !activeProfiles.contains(name) { return true }
            } else {
                if activeProfiles.contains(expression) { return true }
            }
            index = index + 1
        }
        return false
    }

    String describe() {
        return _name + "#" + str(_documentIndex) + " (" + str(_properties.length()) + ")"
    }
}
```
