# `ConfigLoader`

| 项 | 值 |
| --- | --- |
| 类型 | `class ConfigLoader` |
| 包 | `xdk.config` |
| 稳定性 | `preview` |
| 依赖 | `ConfigSource`、`Config` |

---

## 1. 定位

配置加载器：按来源优先级加载成 `Config`；支持 reload。

不做：文件监听、远程配置、缓存/合并策略定制。

---

## 2. 设计逻辑

- 字段 `_sources: List<ConfigSource>`、`_profile`。
- `addSource` 追加；`load` 按 priority 升序应用 `config.set`（后者覆盖）。
- `reload` 重新加载为新的 Config。
- 不做全局缓存；无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_sources` | `List<ConfigSource>` | 来源 |
| `_profile` | `String` | profile |

不变量：profile 非空；来源非 null。

---

## 4. 生命周期

可变构建期；无 close；非线程安全。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ConfigLoader(String profile)` | profile | 非空 | 空 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `addSource` | 追加来源 | `ConfigSource` | `ConfigLoader` | null → panic |
| `load` | 加载 | `Context` | `Result<Config, Error>` | 来源错误 |
| `reload` | 重载 | `Context` | `Result<Config, Error>` | 同上 |
| `profile` | profile | 无 | `String` | 无 |
| `sources` | 来源快照 | 无 | `List<ConfigSource>` | 无 |

---

## 8. 使用的技术

- 来源排序；
- 覆盖；
- Config 构造。

---

## 9. 需要的支撑

- 语言：class、List、String、Result、Context；
- 运行时：无；
- 接口：`ConfigSource`、`Config`。

---

## 10. 依赖的特性/接口/类

`ConfigSource`、`Config`。

---

## 11. 所有权与并发

可变；非线程安全；load 返回新 Config。

---

## 12. 示例与反例

正确：add default/file/env → load。  
反例：期望自动 watcher；load 修改 sources；忽略来源错误。

---

## 13. 测试/场景义务

空/单/多来源；优先级覆盖；profile；错误传播；reload；取消。

---

## 14. XNull 伪代码

```xnull
class ConfigLoader {
    List<ConfigSource> _sources
    final String _profile

    ConfigLoader(String profile) {
        if profile == "" { throw "ConfigLoader: empty profile" }
        _sources = []
        _profile = profile
    }

    ConfigLoader addSource(ConfigSource source) {
        if source == null { throw "ConfigLoader.addSource: null" }
        _sources.push(source)
        return self
    }

    Result<Config, Error> load(Context context) {
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
        Config config = new Config(_profile)
        index = 0
        while index < ordered.length() {
            Result<List<ConfigEntry>, Error> loaded = ordered.get(index).load(context)
            if loaded.isErr() { return Err(loaded.error()) }
            config.setAll(loaded.value())
            index = index + 1
        }
        return Ok(config)
    }

    Result<Config, Error> reload(Context context) {
        return self.load(context)
    }

    String profile() { return _profile }
    List<ConfigSource> sources() { return _sources.copy() }
}
```
