# `YamlDocument`

| 项 | 值 |
| --- | --- |
| 类型 | `class YamlDocument` |
| 包 | `xdk.yaml` |
| 稳定性 | `preview` |
| 依赖 | `JsonValue` |

---

## 1. 定位

多文档 YAML 中的单个文档：索引、值树、profile 激活表达式。

不做：属性扁平化（`YamlPropertySource`）、合并、解析、生成、Spring 绑定。

---

## 2. 设计逻辑

- 不可变；值树引用共享，按只读树使用。
- `profiles` 来自 `YamlOptions.profileKey` 指向的值；无键为空列表。
- `profiles` 为空表示始终激活；否则简单 `name` 或 `!name` 表达式，任一匹配即激活。
- 无 active profiles 时，只有无 profile 的文档激活。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_index` | `Int` | 文档序号，从 0 开始 |
| `_value` | `JsonValue` | 值树 |
| `_profiles` | `List<String>` | profile 表达式 |

不变量：index ≥0；value 非 null；profiles 非 null、元素非空、无重复。

---

## 4. 生命周期

不可变；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `YamlDocument(Int documentIndex, JsonValue value, List<String> profiles)` | 全部 | 见不变量 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `index` | 文档序号 | 无 | `Int` | 无 |
| `value` | 值树 | 无 | `JsonValue` | 无 |
| `profiles` | profile 表达式 | 无 | `List<String>` | 无 |
| `isActive` | 是否激活 | `List<String> activeProfiles` | `Bool` | null → panic |
| `describe` | 摘要 | 无 | `String` | 无 |

说明：

- `isActive` 对 `!name` 取反；`&`/`|` 表达式为 X。
- `value` 不深拷贝；调用方不得修改共享的可变 JsonObject/JsonArray。
- `profiles` 返回副本。

---

## 8. 使用的技术

- 不可变文档元数据；
- 简单 profile 表达式；
- 共享值树。

---

## 9. 需要的支撑

- 语言：class、Int、Bool、String、List；
- 运行时：无；
- 接口：`JsonValue`。

---

## 10. 依赖的特性/接口/类

`JsonValue`。

---

## 11. 所有权与并发

不可变；可共享；值树只读；无资源。

---

## 12. 示例与反例

正确：`doc.isActive(["prod"])`；无 profile 文档恒 true。  
反例：修改 `value()` 返回的对象期望文档隔离；把 `!prod` 当字符串 profile 名；期望 `prod & !dev` 生效。

---

## 13. 测试/场景义务

索引；值树；profiles 空/单/多；`!name`；active 空/匹配/不匹配；重复 profile；describe；null active → panic。

---

## 14. XNull 伪代码

```xnull
class YamlDocument {
    final Int _index
    final JsonValue _value
    final List<String> _profiles

    YamlDocument(Int documentIndex, JsonValue value, List<String> profiles) {
        if documentIndex < 0 { throw "YamlDocument: negative index" }
        if value == null || profiles == null { throw "YamlDocument: null argument" }
        List<String> copied = []
        Int index = 0
        while index < profiles.length() {
            String profile = profiles.get(index)
            if profile == null || profile == "" {
                throw "YamlDocument: empty profile"
            }
            if copied.contains(profile) { throw "YamlDocument: duplicate profile" }
            copied.push(profile)
            index = index + 1
        }
        _index = documentIndex
        _value = value
        _profiles = copied
    }

    Int index() { return _index }
    JsonValue value() { return _value }
    List<String> profiles() { return _profiles.copy() }

    Bool isActive(List<String> activeProfiles) {
        if activeProfiles == null { throw "YamlDocument.isActive: null" }
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
        return "document[" + str(_index) + "] profiles=" + str(_profiles.length())
    }
}
```
