# `Field`

| 项 | 值 |
| --- | --- |
| 类型 | `class Field` |
| 包 | `xdk.log` |
| 稳定性 | `stable` |
| 依赖 | 无 |

---

> 注解合同（A8，planned）：`@Value` 生成 `equals`/`hash`/`toString`/`copy`；字段保持 `final`；引用字段按值语义比较。实现由处理器生成，不手写；实现时删除同名手写成员，避免生成冲突；伪代码中的 `equals`/`hash`/`toString`/`copy` 只描述生成物行为，不是手写实现。

## 1. 定位

结构化日志键值字段；用于 request id、user id、path 等。

不做：嵌套对象、敏感值自动脱敏、国际化。

---

## 2. 设计逻辑

- 不可变；字段 `_key: String`、`_value: String`。
- key 非空；不含 `=`/换行；value 单行。
- 值统一字符串；复杂对象由调用方格式化。
- 值语义。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_key` | `String` | 非空 |
| `_value` | `String` | 单行 |

不变量：key 非空；无控制字符；不可变。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Field(String key, String value)` | key/value | key 非空；单行 | 非法 → panic |

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
| `equals` | 值相等 | `Field other` | `Bool` | 无 |

---

## 8. 使用的技术

- 不可变值对象；
- 单行校验；
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

正确：`new Field("request.id","abc")`。  
反例：空 key；value 含换行；把敏感 token 直接写入字段。

---

## 13. 测试/场景义务

key 合法/非法；value 单行；toString；equals；空值。

---

## 14. XNull 伪代码

```xnull
@Value
class Field {
    final String _key
    final String _value

    Field(String key, String value) {
        if key == "" { throw "Field: empty key" }
        if key.indexOf("=") >= 0 { throw "Field: key contains =" }
        if key.indexOf("\n") >= 0 || value.indexOf("\n") >= 0 {
            throw "Field: multiline"
        }
        _key = key
        _value = value
    }

    String key() { return _key }
    String value() { return _value }
    String toString() { return _key + "=" + _value }

    Bool equals(Field other) {
        if other == null { return false }
        return _key == other._key && _value == other._value
    }
}
```
