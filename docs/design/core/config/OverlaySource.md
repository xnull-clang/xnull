# `OverlaySource`

| 项 | 值 |
| --- | --- |
| 类型 | `class OverlaySource implements ConfigSource` |
| 包 | `xdk.config` |
| 稳定性 | `preview` |
| 依赖 | `ConfigSource`、`ConfigEntry` |

---

## 1. 定位

多来源覆盖：按优先级加载，后加载覆盖前者。

不做：去重/合并策略、条件启用、热更新。

---

## 2. 设计逻辑

- 字段 `_sources: List<ConfigSource>`、`_name`。
- `add` 追加；`load` 按 priority 升序稳定排序后拼接条目。
- 不在这里合并键；ConfigLoader/Config 负责覆盖。
- 无 close；不可变？sources 可变构建期；load 只读。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_sources` | `List<ConfigSource>` | 来源 |
| `_name` | `String` | 名称 |

不变量：source 非 null；排序稳定。

---

## 4. 生命周期

可变构建期；无 close；非线程安全。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `OverlaySource()` | 无 | 空 | 无 |
| `OverlaySource(List<ConfigSource> sources)` | sources | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `add` | 追加来源 | `ConfigSource` | `OverlaySource` | null → panic |
| `load` | 加载全部 | `Context` | `Result<List<ConfigEntry>, Error>` | 来源错误传播 |
| `name` | 名称 | 无 | `String` | 无 |
| `priority` | 优先级 | 无 | `Int` | 无 |

---

## 8. 使用的技术

- 来源排序；
- 条目拼接；
- 错误传播。

---

## 9. 需要的支撑

- 语言：class、List、String、Int、Result；
- 运行时：无；
- 接口：`ConfigSource`、`ConfigEntry`。

---

## 10. 依赖的特性/接口/类

`ConfigSource`、`ConfigEntry`。

---

## 11. 所有权与并发

可变构建期；非线程安全；load 只读。

---

## 12. 示例与反例

正确：default < profile < env < cli。  
反例：期望 Overlay 直接去重；同优先级顺序不稳定；load 后修改 sources。

---

## 13. 测试/场景义务

空/单/多；优先级排序；同优先级稳定；错误传播；取消。

---

## 14. XNull 伪代码

```xnull
class OverlaySource implements ConfigSource {
    List<ConfigSource> _sources
    final String _name

    OverlaySource() {
        _sources = []
        _name = "overlay"
    }

    OverlaySource(List<ConfigSource> sources) {
        _sources = []
        Int index = 0
        while index < sources.length() {
            self.add(sources.get(index))
            index = index + 1
        }
        _name = "overlay"
    }

    OverlaySource add(ConfigSource source) {
        if source == null { throw "OverlaySource.add: null" }
        _sources.push(source)
        return self
    }

    Result<List<ConfigEntry>, Error> load(Context context) {
        List<ConfigSource> ordered = _sources.copy()
        Int index = 1
        while index < ordered.length() {
            ConfigSource current = ordered.get(index)
            Int position = index - 1
            while position >= 0 && ordered.get(position).priority() > current.priority() {
                ordered.set(position + 1, ordered.get(position))
                position = position - 1
            }
            ordered.set(position + 1, current)
            index = index + 1
        }
        List<ConfigEntry> result = []
        index = 0
        while index < ordered.length() {
            Result<List<ConfigEntry>, Error> loaded = ordered.get(index).load(context)
            if loaded.isErr() { return Err(loaded.error()) }
            result.pushAll(loaded.value())
            index = index + 1
        }
        return Ok(result)
    }

    String name() { return _name }
    Int priority() { return 0 }
}
```
