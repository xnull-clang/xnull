# `ConfigEntry`

| 项 | 值 |
| --- | --- |
| 类型 | `class ConfigEntry` |
| 包 | `xdk.config` |
| 稳定性 | `stable` |
| 依赖 | 无 |

---

## 1. 定位

配置键值条目值对象。

不做：来源、校验、类型转换。

---

## 2. 设计逻辑

- 不可变；key/value 字符串。
- key 非空；value 可为空。
- 值语义；无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_key` | `String` | 非空 |
| `_value` | `String` | 可为空 |

不变量：key 非空；不可变。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ConfigEntry(String key, String value)` | key/value | key 非空 | 空 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `key` | 键 | 无 | `String` | 无 |
| `value` | 值 | 无 | `String` | 无 |
| `toString` | `key=value` | 无 | `String` | 无 |
| `equals` | 值相等 | `ConfigEntry` | `Bool` | 无 |

---

## 8. 使用的技术

- 不可变值对象；
- 文本拼接。

---

## 9. 需要的支撑

- 语言：class、String、Bool；
- 运行时：无；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`new ConfigEntry("port","8080")`。  
反例：空 key；修改 entry；把 value 当类型。

---

## 13. 测试/场景义务

key/value；空 value；toString；equals；来源加载。

---

## 14. XNull 伪代码

```xnull
class ConfigEntry {
    final String _key
    final String _value

    ConfigEntry(String key, String value) {
        if key == "" { throw "ConfigEntry: empty key" }
        _key = key
        _value = value
    }

    String key() { return _key }
    String value() { return _value }
    String toString() { return _key + "=" + _value }

    Bool equals(ConfigEntry other) {
        if other == null { return false }
        return _key == other._key && _value == other._value
    }
}
```
