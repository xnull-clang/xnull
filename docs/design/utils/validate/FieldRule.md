# `FieldRule`

| 项 | 值 |
| --- | --- |
| 类型 | `class FieldRule` |
| 包 | `xdk.validate` |
| 稳定性 | `preview` |
| 依赖 | `Validator` |

---

## 1. 定位

Schema 字段规则：字段名、校验器、是否必填。

不做：校验逻辑、路径生成、错误收集。

---

## 2. 设计逻辑

- 不可变值对象；`withRequired` 返回新对象。
- 字段名非空；validator 非 null。
- required 表示字段缺失/null 时产生 `required` 错误。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | 字段名 |
| `_validator` | `Validator` | 校验器 |
| `_required` | `Bool` | 是否必填 |

不变量：name 非空、validator 非 null。

---

## 4. 生命周期

不可变；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `FieldRule(String name, Validator validator, Bool required)` | 全部 | 见不变量 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | 字段名 | 无 | `String` | 无 |
| `validator` | 校验器 | 无 | `Validator` | 无 |
| `isRequired` | 是否必填 | 无 | `Bool` | 无 |
| `withRequired` | 派生 | `Bool required` | `FieldRule` | 无 |
| `describe` | 描述 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 不可变值对象；
- 规则组合；
- 派生。

---

## 9. 需要的支撑

- 语言：class、String、Bool；
- 运行时：无；
- 接口：`Validator`。

---

## 10. 依赖的特性/接口/类

`Validator`。

---

## 11. 所有权与并发

不可变；可共享；validator 线程安全由实现决定；无资源。

---

## 12. 示例与反例

正确：`new FieldRule("email", Rules.email(), true)`。  
反例：空字段名；null validator；修改 required 期望原对象变化。

---

## 13. 测试/场景义务

必填/可选；withRequired；describe；null 参数；Schema 集成。

---

## 14. XNull 伪代码

```xnull
class FieldRule {
    final String _name
    final Validator _validator
    final Bool _required

    FieldRule(String name, Validator validator, Bool required) {
        if name == null || name == "" { throw "FieldRule: empty name" }
        if validator == null { throw "FieldRule: null validator" }
        _name = name
        _validator = validator
        _required = required
    }

    String name() { return _name }
    Validator validator() { return _validator }
    Bool isRequired() { return _required }

    FieldRule withRequired(Bool required) {
        return new FieldRule(_name, _validator, required)
    }

    String describe() {
        if _required { return _name + " (required)" }
        return _name
    }
}
```
