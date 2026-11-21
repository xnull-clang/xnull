# `ProblemDetails`

| 项 | 值 |
| --- | --- |
| 类型 | `class ProblemDetails` |
| 包 | `xdk.api` |
| 稳定性 | `preview` |
| 依赖 | `HttpStatus`、`ValidationError`、`JsonValue`、`JsonObject`、`JsonArray`、`JsonNumber`、`Error` |

---

## 1. 定位

RFC 7807/9457 问题详情值对象：`type`、`title`、`status`、`detail`、`instance` 与扩展成员；序列化为 `application/problem+json` 的 JSON 对象。

不做：自动异常捕获、日志记录、i18n、错误码注册表、XML 问题格式、HTTP 写入。

---

## 2. 设计逻辑

- 不可变；所有 `with*`/`extension` 返回新实例。
- `type` 默认 `about:blank`；`title` 默认取 `HttpStatus.of(status).reason()`，未知状态用 `HTTP <code>`。
- `status` 100..599；建议只用于 4xx/5xx，但规范允许任意状态。
- `detail`/`instance` 允许空串，序列化时省略空值。
- 扩展名不能是 `type`/`title`/`status`/`detail`/`instance`；扩展值必须非 null。
- `fromValidation` 生成 422，扩展 `errors` 为 `{field, code, detail}` 数组；`field` 取自 `ValidationError.path`。
- 序列化顺序固定：标准字段在前，扩展按添加顺序。
- 无 close；可共享；不可变（JsonValue 扩展树按只读约定）。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_type` | `String` | URI 引用，默认 `about:blank` |
| `_title` | `String` | 短摘要，非空 |
| `_status` | `Int` | 100..599 |
| `_detail` | `String` | 本次问题说明，可为空 |
| `_instance` | `String` | 本次问题实例 URI 引用，可为空 |
| `_extensions` | `JsonObject` | 扩展成员 |

不变量：type/title 非空；status 合法；扩展不覆盖标准字段；不可变。

---

## 4. 生命周期

构造/派生后不可变；无 close；可跨任务共享；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ProblemDetails(Int status)` | status | 100..599 | 越界 → panic |

私有全字段构造供派生使用。

---

## 6. 字段表

见 §3；字段私有。`_extensions` 在构造/派生时复制。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `of` | 按状态构造 | `Int status` | `ProblemDetails` | 越界 → panic |
| `fromValidation` | 校验问题 | `List<ValidationError> errors` | `ProblemDetails` | null → panic |
| `type` | 类型 URI | 无 | `String` | 无 |
| `title` | 摘要 | 无 | `String` | 无 |
| `status` | 状态码 | 无 | `Int` | 无 |
| `detail` | 详细说明 | 无 | `String` | 无 |
| `instance` | 实例 URI | 无 | `String` | 无 |
| `extensions` | 扩展快照 | 无 | `JsonObject` | 无 |
| `withType` | 派生类型 | `String type` | `ProblemDetails` | 空/换行 → panic |
| `withTitle` | 派生摘要 | `String title` | `ProblemDetails` | 空/换行 → panic |
| `withDetail` | 派生说明 | `String detail` | `ProblemDetails` | null → panic |
| `withInstance` | 派生实例 | `String instance` | `ProblemDetails` | null → panic |
| `extension` | 添加扩展 | `String name, JsonValue value` | `ProblemDetails` | 保留名/空/换行 → panic |
| `toJson` | JSON 对象 | 无 | `JsonObject` | 无 |
| `toJsonValue` | JSON 值 | 无 | `JsonValue` | 无 |
| `isClientError` | 4xx | 无 | `Bool` | 无 |
| `isServerError` | 5xx | 无 | `Bool` | 无 |
| `copy` | 复制 | 无 | `ProblemDetails` | 无 |
| `toString` | 单行摘要 | 无 | `String` | 无 |

说明：

- `fromValidation` 不聚合状态；所有错误共用 422。
- `extension` 不修改原对象；重复扩展名覆盖旧值（保持首次顺序）。
- `toJson` 总是包含 `type`/`title`/`status`；`detail`/`instance` 非空时才包含。
- `toJsonValue` 返回 `JsonValue.object(toJson())`。
- `isClientError`/`isServerError` 按状态百位判断。

---

## 8. 使用的技术

- 不可变值对象；
- 链式派生；
- JSON 对象构建；
- 校验错误映射；
- RFC 7807/9457 字段语义。

---

## 9. 需要的支撑

- 语言：class、String、Int、Bool、List、Result；
- 运行时：无；
- 接口：`HttpStatus`、`ValidationError`、`JsonObject`、`JsonArray`、`JsonNumber`、`JsonValue`、`Error`。

---

## 10. 依赖的特性/接口/类

`HttpStatus`、`ValidationError`、`JsonObject`、`JsonArray`、`JsonNumber`、`JsonValue`。

---

## 11. 所有权与并发

不可变；扩展 JsonObject 在构造/派生时浅拷贝；嵌套 JsonValue 按只读约定共享；可共享；无资源；无取消点；相等按引用身份（需要逐字段比较）。

---

## 12. 示例与反例

正确：

```text
ProblemDetails problem = ProblemDetails.of(404)
    .withType("urn:example:problem:user-not-found")
    .withDetail("user 42 does not exist")
    .extension("request_id", JsonValue.string("abc"))
```

反例：

- `type` 为空；
- 扩展名用 `status`；
- 把 500 的堆栈写入 `detail`；
- `detail` 里包含密码/令牌；
- 修改 `extensions()` 期望原对象变化；
- 用 200 表示问题。

---

## 13. 测试/场景义务

默认值；未知状态 title；所有 `with*`；保留扩展名；重复扩展；扩展顺序；detail/instance 省略；fromValidation 多错误；toJson/toJsonValue；isClientError/isServerError；copy 独立；敏感信息不进入 toString。

---

## 14. XNull 伪代码

> 非可执行设计伪代码。

```xnull
class ProblemDetails {
    final String _type
    final String _title
    final Int _status
    final String _detail
    final String _instance
    final JsonObject _extensions

    ProblemDetails(Int status) {
        if status < 100 || status > 599 {
            throw "ProblemDetails: invalid status"
        }
        String reason = HttpStatus.of(status).reason()
        _status = status
        _type = "about:blank"
        if reason == "" {
            _title = "HTTP " + str(status)
        } else {
            _title = reason
        }
        _detail = ""
        _instance = ""
        _extensions = new JsonObject()
    }

    private ProblemDetails(String type, String title, Int status,
                           String detail, String instance,
                           JsonObject extensions) {
        _type = type
        _title = title
        _status = status
        _detail = detail
        _instance = instance
        _extensions = extensions.copy()
    }

    static ProblemDetails of(Int status) {
        return new ProblemDetails(status)
    }

    static ProblemDetails fromValidation(List<ValidationError> errors) {
        if errors == null { throw "ProblemDetails.fromValidation: null errors" }
        JsonArray items = new JsonArray()
        Int index = 0
        while index < errors.length() {
            ValidationError error = errors.get(index)
            JsonObject item = new JsonObject()
            item.set("field", JsonValue.string(error.path()))
            item.set("code", JsonValue.string(error.code()))
            item.set("detail", JsonValue.string(error.message()))
            items.add(JsonValue.object(item))
            index = index + 1
        }
        ProblemDetails problem = new ProblemDetails(422)
            .withType("urn:xdk:api:validation")
            .withTitle("Validation failed")
            .withDetail(str(errors.length()) + " validation error(s)")
        return problem.extension("errors", JsonValue.array(items))
    }

    String type() { return _type }
    String title() { return _title }
    Int status() { return _status }
    String detail() { return _detail }
    String instance() { return _instance }
    JsonObject extensions() { return _extensions.copy() }

    ProblemDetails withType(String type) {
        if type == null || type == "" {
            throw "ProblemDetails.withType: empty type"
        }
        if type.indexOf("\n") >= 0 || type.indexOf("\r") >= 0 {
            throw "ProblemDetails.withType: multiline"
        }
        return new ProblemDetails(type, _title, _status, _detail, _instance, _extensions)
    }

    ProblemDetails withTitle(String title) {
        if title == null || title == "" {
            throw "ProblemDetails.withTitle: empty title"
        }
        if title.indexOf("\n") >= 0 || title.indexOf("\r") >= 0 {
            throw "ProblemDetails.withTitle: multiline"
        }
        return new ProblemDetails(_type, title, _status, _detail, _instance, _extensions)
    }

    ProblemDetails withDetail(String detail) {
        if detail == null { throw "ProblemDetails.withDetail: null" }
        return new ProblemDetails(_type, _title, _status, detail, _instance, _extensions)
    }

    ProblemDetails withInstance(String instance) {
        if instance == null { throw "ProblemDetails.withInstance: null" }
        return new ProblemDetails(_type, _title, _status, _detail, instance, _extensions)
    }

    ProblemDetails extension(String name, JsonValue value) {
        if name == null || name == "" {
            throw "ProblemDetails.extension: empty name"
        }
        if value == null { throw "ProblemDetails.extension: null value" }
        if name == "type" || name == "title" || name == "status"
            || name == "detail" || name == "instance" {
            throw "ProblemDetails.extension: reserved name"
        }
        if name.indexOf("\n") >= 0 || name.indexOf("\r") >= 0 {
            throw "ProblemDetails.extension: multiline name"
        }
        JsonObject next = _extensions.copy()
        next.set(name, value)
        return new ProblemDetails(_type, _title, _status, _detail, _instance, next)
    }

    JsonObject toJson() {
        JsonObject result = new JsonObject()
        result.set("type", JsonValue.string(_type))
        result.set("title", JsonValue.string(_title))
        result.set("status", JsonValue.number(new JsonNumber(str(_status))))
        if _detail != "" {
            result.set("detail", JsonValue.string(_detail))
        }
        if _instance != "" {
            result.set("instance", JsonValue.string(_instance))
        }
        List<String> names = _extensions.keys()
        Int index = 0
        while index < names.length() {
            String name = names.get(index)
            result.set(name, _extensions.getOr(name, JsonValue.nullValue()))
            index = index + 1
        }
        return result
    }

    JsonValue toJsonValue() { return JsonValue.object(self.toJson()) }

    Bool isClientError() { return _status >= 400 && _status <= 499 }
    Bool isServerError() { return _status >= 500 && _status <= 599 }

    ProblemDetails copy() {
        return new ProblemDetails(_type, _title, _status, _detail, _instance, _extensions)
    }

    String toString() {
        return "problem " + str(_status) + " " + _title + " type=" + _type
    }
}
```
