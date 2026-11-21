# `FormEntry`

| 项 | 值 |
| --- | --- |
| 类型 | `class FormEntry` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

`application/x-www-form-urlencoded` 的单条键值条目。

不做：解码、编码、多值集合；由 `Form` 负责。

---

## 2. 设计逻辑

- 不可变字段 `_name`、`_value`；名称非空。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | 非空 |
| `_value` | `String` | 可为空 |

---

## 4. 生命周期

不可变；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `FormEntry(String name, String value)` | name/value | name 非空 | 空 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | 名称 | 无 | `String` | 无 |
| `value` | 值 | 无 | `String` | 无 |
| `toString` | `name=value` | 无 | `String` | 无 |

---

## 8. 使用的技术

- 不可变值对象；
- 文本拼接。

---

## 9. 需要的支撑

- 语言：class、String；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

不可变；无资源；可共享。

---

## 12. 示例与反例

正确：`new FormEntry("q","xdk")`。  
反例：空名称；在 entry 层做 URL 编码。

---

## 13. 测试/场景义务

名称/值；空值；toString；不可变。

---

## 14. XNull 伪代码

```xnull
class FormEntry {
    final String _name
    final String _value

    FormEntry(String name, String value) {
        if name == null || name == "" { throw "FormEntry: empty name" }
        if value == null { throw "FormEntry: null value" }
        _name = name
        _value = value
    }

    String name() { return _name }
    String value() { return _value }
    String toString() { return _name + "=" + _value }
}
```
