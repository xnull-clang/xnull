# `HttpHeader`

| 项 | 值 |
| --- | --- |
| 类型 | `class HttpHeader` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

> 注解合同（A8，planned）：`@Value` 生成 `equals`/`hash`/`toString`/`copy`；字段保持 `final`；引用字段按值语义比较。实现由处理器生成，不手写；实现时删除同名手写成员，避免生成冲突；伪代码中的 `equals`/`hash`/`toString`/`copy` 只描述生成物行为，不是手写实现。

## 1. 定位

单条 HTTP 头：名称 + 值；不可变。

不做：多值集合、大小写归一、头解析。

---

## 2. 设计逻辑

- 字段 `_name`、`_value`；构造时校验。
- 名称：非空 token，不含冒号/空白/CR/LF；保留原大小写。
- 值：不含 CR/LF；允许空串。
- 不可变；无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | 头名 |
| `_value` | `String` | 头值 |

不变量：name 合法；value 单行；不可变。

---

## 4. 生命周期

不可变；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `HttpHeader(String name, String value)` | name/value | 名称 token；单行 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | 名称 | 无 | `String` | 无 |
| `value` | 值 | 无 | `String` | 无 |
| `equals` | 值相等 | `HttpHeader other` | `Bool` | 无 |
| `toString` | `name: value` | 无 | `String` | 无 |

---

## 8. 使用的技术

- 不可变值对象；
- token/单行校验。

---

## 9. 需要的支撑

- 语言：class、String、Bool；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

不可变；无资源；可共享。

---

## 12. 示例与反例

正确：`new HttpHeader("Content-Type","application/json")`。  
反例：名称含空格；值含换行；把头名大小写当语义。

---

## 13. 测试/场景义务

合法名称/值；空值；非法 token；CRLF；equals/toString；大小写保留。

---

## 14. XNull 伪代码

```xnull
@Value
class HttpHeader {
    final String _name
    final String _value

    HttpHeader(String name, String value) {
        if name == null || name == "" { throw "HttpHeader: empty name" }
        if value == null { throw "HttpHeader: null value" }
        if name.indexOf(":") >= 0 || name.indexOf(" ") >= 0 || name.indexOf("\t") >= 0 {
            throw "HttpHeader: invalid name"
        }
        if name.indexOf("\n") >= 0 || value.indexOf("\n") >= 0 || value.indexOf("\r") >= 0 {
            throw "HttpHeader: multiline"
        }
        _name = name
        _value = value
    }

    String name() { return _name }
    String value() { return _value }

    Bool equals(HttpHeader other) {
        if other == null { return false }
        return _name == other.name() && _value == other.value()
    }

    String toString() { return _name + ": " + _value }
}
```
