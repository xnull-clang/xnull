# `Match`

| 项 | 值 |
| --- | --- |
| 类型 | `class Match` |
| 包 | `xdk.text` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

单个正则匹配结果：起止字节索引、捕获组、命名捕获组。

不做：替换/切分（Regex）、继续匹配、流式匹配。

---

## 2. 设计逻辑

- 不可变；字节索引；`0 ≤ start ≤ end ≤ text.length`。
- `group(0)` 是整匹配；`group(i≥1)` 是捕获组；未捕获为空串。
- `namedGroups` 是快照；缺失名返回 null/空串按方法定。
- `isMatch` 判断 start/end 是否有效。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_start` | `Int` | 起始字节 |
| `_end` | `Int` | 结束字节（不含） |
| `_groups` | `List<String>` | 捕获组 |
| `_namedGroups` | `Map<String,String>` | 命名组 |

不变量：0 ≤ start ≤ end；groups 快照；不可变。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

构造器内部；由 `Regex` 创建。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `start` | 起始 | 无 | `Int` | 无 |
| `end` | 结束 | 无 | `Int` | 无 |
| `length` | 长度 | 无 | `Int` | 无 |
| `group` | 捕获组 | `Int index` | `String` | 越界 → panic |
| `groups` | 组快照 | 无 | `List<String>` | 无 |
| `groupCount` | 组数 | 无 | `Int` | 无 |
| `namedGroup` | 命名组 | `String name` | `String?` | 无 |
| `namedGroups` | 命名组快照 | 无 | `Map<String,String>` | 无 |
| `text` | 匹配文本 | `String source` | `String` | 越界 → panic |
| `isMatch` | 是否有效 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 字节索引；
- 捕获组列表；
- 命名组映射；
- 快照。

---

## 9. 需要的支撑

- 语言：class、Int、String、List、Map、Bool；
- 运行时：无；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

不可变；快照；可共享；无资源。

---

## 12. 示例与反例

正确：`match.group(0)` 整匹配；`namedGroup("id")`。  
反例：用匹配索引切非 UTF-8 边界；修改 groups 快照期望匹配变化；越界 group。

---

## 13. 测试/场景义务

整匹配/捕获组/未捕获/命名组；空匹配；边界；groups 快照；isMatch。

---

## 14. XNull 伪代码

```xnull
class Match {
    Int _start
    Int _end
    List<String> _groups
    Map<String, String> _namedGroups

    Match(Int start, Int end, List<String> groups, Map<String, String> namedGroups) {
        _start = start
        _end = end
        _groups = []
        Int index = 0
        while index < groups.length() {
            _groups.push(groups.get(index))
            index = index + 1
        }
        _namedGroups = [:]
        List<String> names = namedGroups.keys()
        index = 0
        while index < names.length() {
            _namedGroups.put(names.get(index), namedGroups.getOr(names.get(index), ""))
            index = index + 1
        }
    }

    Int start() { return _start }
    Int end() { return _end }
    Int length() { return _end - _start }
    Bool isMatch() { return _start <= _end }

    String group(Int index) {
        if index < 0 || index > _groups.length() {
            throw "Match.group: out of range"
        }
        if index == 0 {
            return _groups.get(0)
        }
        return _groups.get(index - 1)
    }

    List<String> groups() {
        List<String> result = []
        Int index = 0
        while index < _groups.length() {
            result.push(_groups.get(index))
            index = index + 1
        }
        return result
    }

    Int groupCount() { return _groups.length() }

    String? namedGroup(String name) {
        if !_namedGroups.has(name) {
            return null
        }
        return _namedGroups.getOr(name, null)
    }

    Map<String, String> namedGroups() {
        Map<String, String> result = [:]
        List<String> names = _namedGroups.keys()
        Int index = 0
        while index < names.length() {
            result.put(names.get(index), _namedGroups.getOr(names.get(index), ""))
            index = index + 1
        }
        return result
    }

    String text(String source) {
        if _start < 0 || _end > source.length() || _start > _end {
            throw "Match.text: out of range"
        }
        return source.substring(_start, _end - _start)
    }
}
```
