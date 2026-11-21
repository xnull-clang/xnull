# `Config`

| 项 | 值 |
| --- | --- |
| 类型 | `class Config` |
| 包 | `xdk.config` |
| 稳定性 | `stable` |
| 依赖 | `ConfigEntry`、`ConfigSchema`、`text`、`errors` |

---

## 1. 定位

有序键值配置快照：读取/覆盖/类型化/合并/冻结/渲染。

不做：来源加载（Loader）、文件解析（FileSource）、热更新、全局配置。

---

## 2. 设计逻辑

- 字段 `_profile`、`_entries: Map<String,String>`、`_order: List<String>`、`_frozen: Bool`。
- 键大小写敏感；键非空、不含 `=`/换行。
- `set` 已存在原位替换，新键追加 order。
- 类型化 getter 用 `text` 解析；失败返回 fallback 或 `Result`。
- `freeze` 后 `set/remove/clear` 失败（panic）。
- 非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_profile` | `String` | profile |
| `_entries` | `Map<String,String>` | 键值 |
| `_order` | `List<String>` | 插入序 |
| `_frozen` | `Bool` | 冻结 |

不变量：order 无重复且覆盖全部 key；entries 与 order 一致。

---

## 4. 生命周期

可变构建期；可 freeze；无 close；非线程安全。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Config(String profile)` | profile | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 组 | 方法 |
| --- | --- |
| 读取 | `profile`、`length`、`isEmpty`、`has`、`get`、`getOr`、`tryGet`、`keys`、`values`、`entries`、`toMap` |
| 类型化 | `getIntOr`、`getLongOr`、`getBoolOr`、`getDoubleOr`、`getDuration`、`tryGetInt`、`tryGetBool`、`tryGetLong` |
| 修改 | `set`、`setAll`、`remove`、`merge`、`overlay`、`clear`、`copy`、`freeze` |
| 校验/渲染 | `validate`、`render` |

详细契约：

- `get` 缺失 panic；`getOr` fallback；`tryGet` `NotFound`。
- `getIntOr` 等解析失败返回 fallback；`tryGetInt` 返回 `InvalidArgument`。
- `merge` 叠加但不覆盖已有键；`overlay` 后者覆盖前者。
- `validate(schema)` 返回 `Result<Unit, ErrorGroup>`。
- `render` 仅诊断，不是稳定序列化。

---

## 8. 使用的技术

- 有序映射；
- 键校验；
- 类型解析；
- Schema 校验；
- 覆盖/合并。

---

## 9. 需要的支撑

- 语言：class、Map、List、String、Bool、Int、Long、Result；
- 运行时：无；
- 接口：`ConfigEntry`、`ConfigSchema`、`parseInt/parseLong/parseBool/parseFloat`、`BasicError`、`ErrorGroup`。

---

## 10. 依赖的特性/接口/类

`ConfigEntry`、`ConfigSchema`、`text` 解析函数、`BasicError`、`ErrorGroup`。

---

## 11. 所有权与并发

可变；非线程安全；`copy` 独立；freeze 后只读。

---

## 12. 示例与反例

正确：`config.getIntOr("port", 8080)`。  
反例：用 `get` 读外部配置；key 含 `=`；freeze 后 set；依赖 render 做持久化。

---

## 13. 测试/场景义务

set/覆盖/顺序；get/getOr/tryGet；类型化/失败；merge/overlay；freeze；validate；render。

---

## 14. XNull 伪代码

```xnull
class Config {
    String _profile
    Map<String, String> _entries
    List<String> _order
    Bool _frozen

    Config(String profile) {
        if profile == null { throw "Config: null profile" }
        _profile = profile
        _entries = [:]
        _order = []
        _frozen = false
    }

    String profile() { return _profile }
    Int length() { return _order.length() }
    Bool isEmpty() { return _order.length() == 0 }
    Bool has(String key) { return _entries.has(key) }

    String get(String key) {
        if !_entries.has(key) { throw "Config.get: missing " + key }
        return _entries.getOr(key, "")
    }

    String getOr(String key, String fallback) {
        if !_entries.has(key) { return fallback }
        return _entries.getOr(key, fallback)
    }

    Result<String, Error> tryGet(String key) {
        if !_entries.has(key) {
            return Err(new BasicError(ErrorKind.NotFound, "config missing: " + key))
        }
        return Ok(_entries.getOr(key, ""))
    }

    void set(String key, String value) {
        if _frozen { throw "Config.set: frozen" }
        if key == "" || key.indexOf("=") >= 0 || key.indexOf("\n") >= 0 {
            throw "Config.set: invalid key"
        }
        if value == null { value = "" }
        if !_entries.has(key) {
            _order.push(key)
        }
        _entries.put(key, value)
    }

    void setAll(List<ConfigEntry> entries) {
        Int index = 0
        while index < entries.length() {
            self.set(entries.get(index).key(), entries.get(index).value())
            index = index + 1
        }
    }

    Bool remove(String key) {
        if _frozen { throw "Config.remove: frozen" }
        if !_entries.has(key) { return false }
        _entries.remove(key)
        _order.remove(_order.indexOf(key))
        return true
    }

    void merge(Config other) {
        Int index = 0
        List<String> keys = other.keys()
        while index < keys.length() {
            String key = keys.get(index)
            if !self.has(key) { self.set(key, other.get(key)) }
            index = index + 1
        }
    }

    void overlay(Config other) {
        Int index = 0
        List<String> keys = other.keys()
        while index < keys.length() {
            self.set(keys.get(index), other.get(keys.get(index)))
            index = index + 1
        }
    }

    Int getIntOr(String key, Int fallback) {
        Result<Int, Error> parsed = parseInt(self.getOr(key, str(fallback)))
        if parsed.isErr() { return fallback }
        return parsed.value()
    }

    Bool getBoolOr(String key, Bool fallback) {
        String value = self.getOr(key, "")
        if value == "true" { return true }
        if value == "false" { return false }
        return fallback
    }

    Long getLongOr(String key, Long fallback) {
        Result<Long, Error> parsed = parseLong(self.getOr(key, str(fallback)))
        if parsed.isErr() { return fallback }
        return parsed.value()
    }

    Double getDoubleOr(String key, Double fallback) {
        Result<Double, Error> parsed = parseFloat(self.getOr(key, str(fallback)))
        if parsed.isErr() { return fallback }
        return parsed.value()
    }

    List<String> keys() { return _order.copy() }

    List<String> values() {
        List<String> result = []
        Int index = 0
        while index < _order.length() {
            result.push(_entries.getOr(_order.get(index), ""))
            index = index + 1
        }
        return result
    }

    List<ConfigEntry> entries() {
        List<ConfigEntry> result = []
        Int index = 0
        while index < _order.length() {
            String key = _order.get(index)
            result.push(new ConfigEntry(key, _entries.getOr(key, "")))
            index = index + 1
        }
        return result
    }

    Map<String, String> toMap() { return _entries.copy() }
    void clear() { _entries.clear(); _order.clear() }
    void freeze() { _frozen = true }

    Config copy() {
        Config result = new Config(_profile)
        result._entries = _entries.copy()
        result._order = _order.copy()
        result._frozen = _frozen
        return result
    }

    String render() {
        String result = _profile + ":"
        Int index = 0
        while index < _order.length() {
            if index > 0 { result = result + "," }
            String key = _order.get(index)
            result = result + key + "=" + _entries.getOr(key, "")
            index = index + 1
        }
        return result
    }
}
```
