# `SpanEvent`

| 项 | 值 |
| --- | --- |
| 类型 | `class SpanEvent` |
| 包 | `xdk.trace` |
| 稳定性 | `preview` |
| 依赖 | `Map`、`nowMono` |

---

## 1. 定位

span 内的一次不可变事件快照：名称、单调时间戳、属性表。

不做：事件排序、去重、持久化、导出编码、日志行格式化。

---

## 2. 设计逻辑

- `name` 非空，最长 256 字符；空名/超长在构造时 panic。
- `timestampMono` 是创建时刻的单调毫秒；只用于同一进程内的相对顺序，不用于跨进程比较。
- `attributes` 在构造时复制；读取时返回副本，调用方不能反向修改事件。
- 事件是值对象，不持有 span 引用；`Span` 负责数量上限和写入时机。
- `SpanEvent` 自身不强制属性数量/长度；`Span`/`TraceHandle` 按 `TraceOptions` 执行上限。
- 不可变；线程安全；无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | 1..256 字符 |
| `_timestampMono` | `Long` | ≥0 的单调毫秒 |
| `_attributes` | `Map<String,String>` | 构造时复制 |

不变量：name 非空且不超过 256；timestampMono ≥0；attributes 非 null；对象构造后字段不变。

---

## 4. 生命周期

值对象；由 `Span.addEvent` 或测试创建；无 close；GC 管理。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `SpanEvent(String name, Long timestampMono, Map<String,String> attributes)` | 全部 | name 1..256；timestampMono ≥0；attributes 非 null | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有且 `final`。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | 事件名 | 无 | `String` | 无 |
| `timestampMono` | 单调时间戳 | 无 | `Long` | 无 |
| `attributes` | 属性副本 | 无 | `Map<String,String>` | 无 |
| `copy` | 独立副本 | 无 | `SpanEvent` | 无 |

说明：

- `attributes()` 返回新 Map；修改返回值不影响事件。
- `copy()` 复制属性；用于跨边界传递时避免共享可变 Map。
- 不提供 `set*`；事件创建后不可变。

---

## 8. 使用的技术

- 不可变值对象；
- 防御性复制；
- 单调时间戳；
- 有界名称。

---

## 9. 需要的支撑

- 语言：class、String、Long、Int、Map；
- 运行时：`nowMono`（由调用方取时间）；
- 接口：无。

---

## 10. 依赖的特性/接口/类

`Map`、`nowMono`。

---

## 11. 所有权与并发

不可变；线程安全；可跨任务共享；属性 Map 在构造和读取时复制；无资源。

---

## 12. 示例与反例

正确：`SpanEvent event = new SpanEvent("cache.miss", nowMono(), attributes)`。  
反例：用墙钟时间做 `timestampMono`；构造后修改传入 attributes 期望事件变化；空事件名；负时间戳。

---

## 13. 测试/场景义务

字段读取；属性复制；`copy` 独立性；空名；超长名；负时间戳；null 属性；相同内容不同实例；Map 键顺序不承诺。

---

## 14. XNull 伪代码

```xnull
class SpanEvent {
    final String _name
    final Long _timestampMono
    final Map<String, String> _attributes

    SpanEvent(String name, Long timestampMono, Map<String, String> attributes) {
        if name == null || attributes == null {
            throw "SpanEvent: null argument"
        }
        if name.length() == 0 || name.length() > 256 {
            throw "SpanEvent: invalid name"
        }
        if timestampMono < 0 {
            throw "SpanEvent: negative timestamp"
        }
        _name = name
        _timestampMono = timestampMono
        _attributes = attributes.copy()
    }

    String name() { return _name }
    Long timestampMono() { return _timestampMono }
    Map<String, String> attributes() { return _attributes.copy() }

    SpanEvent copy() {
        return new SpanEvent(_name, _timestampMono, _attributes)
    }
}
```
