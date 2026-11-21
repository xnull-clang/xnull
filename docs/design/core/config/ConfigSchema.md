# `ConfigSchema`

| 项 | 值 |
| --- | --- |
| 类型 | `class ConfigSchema` |
| 包 | `xdk.config` |
| 稳定性 | `preview` |
| 依赖 | `ConfigField`、`Config`、`ErrorGroup` |

---

## 1. 定位

配置字段集合校验：必填/自定义规则；一次返回全部错误。

不做：类型系统、自动填充默认值、UI。

---

## 2. 设计逻辑

- 字段 `_fields: List<ConfigField>`。
- `add` 追加；`validate(config)` 遍历字段：
  - 缺失且必填 → `InvalidArgument`；
  - 缺失且有默认 → 跳过（默认值由调用方读取）；
  - 有值 → 调 field.validate；错误聚合。
- 返回 `Result<Unit, ErrorGroup>`；无错误 Ok。
- 非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_fields` | `List<ConfigField>` | 字段 |

不变量：字段名唯一；非线程安全。

---

## 4. 生命周期

可变构建期；无 close；非线程安全。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ConfigSchema()` | 无 | 空 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `add` | 添加字段 | `ConfigField` | `ConfigSchema` | null/重复 → panic |
| `field` | 按名取 | `String` | `ConfigField?` | 无 |
| `fields` | 快照 | 无 | `List<ConfigField>` | 无 |
| `validate` | 校验 | `Config` | `Result<Unit, ErrorGroup>` | 字段错误 |

---

## 8. 使用的技术

- 字段列表；
- 必填/校验；
- 错误聚合。

---

## 9. 需要的支撑

- 语言：class、List、String、Result；
- 运行时：无；
- 接口：`ConfigField`、`Config`、`ErrorGroup`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`ConfigField`、`Config`、`ErrorGroup`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

可变；非线程安全；无资源。

---

## 12. 示例与反例

正确：required 缺失 → ErrorGroup。  
反例：只返回第一个错误；自动修改 Config；重复字段名。

---

## 13. 测试/场景义务

必填/可选/默认；validator；多错误聚合；空 schema；重复字段。

---

## 14. XNull 伪代码

```xnull
class ConfigSchema {
    List<ConfigField> _fields

    ConfigSchema() {
        _fields = []
    }

    ConfigSchema add(ConfigField field) {
        if field == null { throw "ConfigSchema.add: null" }
        Int index = 0
        while index < _fields.length() {
            if _fields.get(index).name() == field.name() {
                throw "ConfigSchema.add: duplicate field"
            }
            index = index + 1
        }
        _fields.push(field)
        return self
    }

    ConfigField? field(String name) {
        Int index = 0
        while index < _fields.length() {
            if _fields.get(index).name() == name {
                return _fields.get(index)
            }
            index = index + 1
        }
        return null
    }

    List<ConfigField> fields() { return _fields.copy() }

    Result<Unit, ErrorGroup> validate(Config config) {
        if config == null { throw "ConfigSchema.validate: null" }
        ErrorGroup errors = new ErrorGroup()
        Int index = 0
        while index < _fields.length() {
            ConfigField field = _fields.get(index)
            if !config.has(field.name()) {
                if field.isRequired() {
                    errors.add(new BasicError(ErrorKind.InvalidArgument, "missing " + field.name()))
                }
            } else {
                Result<Unit, Error> valid = field.validate(config.get(field.name()))
                if valid.isErr() {
                    Error error = valid.error()
                    errors.add(new BasicError(error.kind(), error.describe()))
                }
            }
            index = index + 1
        }
        if errors.isEmpty() { return Ok(unit) }
        return Err(errors)
    }
}
```
