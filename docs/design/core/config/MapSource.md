# `MapSource`

| 项 | 值 |
| --- | --- |
| 类型 | `class MapSource implements ConfigSource` |
| 包 | `xdk.config` |
| 稳定性 | `preview` |
| 依赖 | `ConfigEntry`、`Map` |

---

## 1. 定位

内存配置来源：从 Map 生成条目列表。

不做：文件/env、校验、热更新。

---

## 2. 设计逻辑

- 字段 `_name`、`_priority`、`_entries: Map<String,String>`。
- 构造复制 Map；`load` 返回条目快照。
- name 默认 `"map"`；priority 默认 0。
- 无 close；不可变。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | 来源名 |
| `_priority` | `Int` | 优先级 |
| `_entries` | `Map<String,String>` | 条目 |

不变量：name 非空；不可变。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `MapSource(Map<String,String> entries)` | entries | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `load` | 加载 | `Context` | `Result<List<ConfigEntry>, Error>` | 无 |
| `name` | 名称 | 无 | `String` | 无 |
| `priority` | 优先级 | 无 | `Int` | 无 |
| `withName` | 派生 | `String` | `MapSource` | 空 → panic |
| `withPriority` | 派生 | `Int` | `MapSource` | 无 |

---

## 8. 使用的技术

- Map 复制；
- 条目快照。

---

## 9. 需要的支撑

- 语言：class、Map、List、String、Int、Result；
- 运行时：无；
- 接口：`ConfigSource`、`ConfigEntry`。

---

## 10. 依赖的特性/接口/类

`ConfigSource`、`ConfigEntry`。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：测试用 MapSource。  
反例：修改入参 Map 期望 source 变化；name 空；priority 语义混用。

---

## 13. 测试/场景义务

load 条目；顺序；withName/priority；空 Map。

---

## 14. XNull 伪代码

```xnull
class MapSource implements ConfigSource {
    final String _name
    final Int _priority
    final Map<String, String> _entries

    MapSource(Map<String, String> entries) {
        if entries == null { throw "MapSource: null entries" }
        _name = "map"
        _priority = 0
        _entries = entries.copy()
    }

    MapSource withName(String name) {
        if name == "" { throw "MapSource.withName: empty" }
        MapSource result = new MapSource(_entries)
        result._name = name
        return result
    }

    MapSource withPriority(Int priority) {
        MapSource result = new MapSource(_entries)
        result._priority = priority
        return result
    }

    Result<List<ConfigEntry>, Error> load(Context context) {
        List<ConfigEntry> result = []
        List<String> keys = _entries.keys()
        Int index = 0
        while index < keys.length() {
            result.push(new ConfigEntry(keys.get(index), _entries.getOr(keys.get(index), "")))
            index = index + 1
        }
        return Ok(result)
    }

    String name() { return _name }
    Int priority() { return _priority }
}
```
