# `JwtClaims`

| 项 | 值 |
| --- | --- |
| 类型 | `class JwtClaims` |
| 包 | `xdk.jwt` |
| 稳定性 | `preview` |
| 依赖 | `JsonObject`、`JsonValue`、`Context` |

---

> 注解合同（A8，implemented；限制见 S3 §5.7）：`@Data` 生成 `equals`/`toString`/`copy`（不生成 `hash`）；字段可保持可变，不生成访问器。实现由处理器生成，不手写；实现时删除同名手写成员，避免生成冲突；伪代码中的 `equals`/`toString`/`copy` 只描述生成物行为，不是手写实现。

## 1. 定位

JWT claims 集合：标准字段、任意 JSON claims、过期/受众检查。

不做：业务 schema、JWE、OAuth 流程。

---

## 2. 设计逻辑

- 字段 `_claims: JsonObject`；可变构建。
- 标准字段 iss/sub/aud/exp/nbf/iat/jti；时间秒级 epoch（JWT 规范）。
- `audience` 支持字符串或数组由 Json 读取；这里提供首个/全部。
- 无 close；非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_claims` | `JsonObject` | claims |

---

## 4. 生命周期

可变；无 close；`copy` 独立。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `JwtClaims()` | 无 | 空 | 无 |
| `JwtClaims(JsonObject claims)` | claims | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `set` | 设置 claim | `String, JsonValue` | `void` | 非法 |
| `getOrNull` | claim/无 | `String` | `JsonValue?` | 无 |
| `string`/`longValue` | 类型读取 | `String` | `Result<...>` | `NotFound`/类型 |
| `subject`/`issuer`/`jwtId` | 标准字段 | 无 | `String?` | 无 |
| `audiences` | 受众 | 无 | `List<String>` | 无 |
| `expiresAtSeconds`/`notBeforeSeconds`/`issuedAtSeconds` | 时间 | 无 | `Long?` | 无 |
| `isExpired` | 过期 | `Long nowSeconds, Long leewaySeconds` | `Bool` | 无 |
| `toJson` | 快照 | 无 | `JsonObject` | 无 |
| `copy` | 副本 | 无 | `JwtClaims` | 无 |

---

## 8. 使用的技术

- JSON 对象；
- 标准 claim 读取；
- 时间窗口。

---

## 9. 需要的支撑

- 语言：class、String、Long、List、Result；
- 运行时：无；
- 接口：`JsonObject`、`JsonValue`、`Json`。

---

## 10. 依赖的特性/接口/类

`JsonObject`、`JsonValue`、`Json`。

---

## 11. 所有权与并发

可变；非线程安全；无资源。

---

## 12. 示例与反例

正确：`claims.set("sub", JsonValue.string("u1"))`。  
反例：exp 用毫秒；aud 当单值；忽略 nbf。

---

## 13. 测试/场景义务

标准字段；aud 字符串/数组；exp/nbf/iat；leeway；copy；toJson。

---

## 14. XNull 伪代码

```xnull
@Data
class JwtClaims {
    final JsonObject _claims

    JwtClaims() {
        _claims = new JsonObject()
    }

    JwtClaims(JsonObject claims) {
        if claims == null { throw "JwtClaims: null" }
        _claims = claims.copy()
    }

    void set(String name, JsonValue value) { _claims.set(name, value) }
    JsonValue? getOrNull(String name) { return _claims.getOrNull(name) }

    Result<String, Error> string(String name) {
        JsonValue? value = _claims.getOrNull(name)
        if value == null { return Err(new BasicError(ErrorKind.NotFound, "claim missing")) }
        if !value.isString() { return Err(new BasicError(ErrorKind.InvalidArgument, "not string")) }
        return Ok(value.asString() as String)
    }

    Result<Long, Error> longValue(String name) {
        JsonValue? value = _claims.getOrNull(name)
        if value == null { return Err(new BasicError(ErrorKind.NotFound, "claim missing")) }
        if !value.isNumber() { return Err(new BasicError(ErrorKind.InvalidArgument, "not number")) }
        return (value.asNumber() as JsonNumber).asLong()
    }

    String? subject() { return _claims.getOrNull("sub")?.asString() }
    String? issuer() { return _claims.getOrNull("iss")?.asString() }
    String? jwtId() { return _claims.getOrNull("jti")?.asString() }
    Long? expiresAtSeconds() {
        Result<Long, Error> value = self.longValue("exp")
        if value.isErr() { return null }
        return value.value()
    }

    Long? notBeforeSeconds() {
        Result<Long, Error> value = self.longValue("nbf")
        if value.isErr() { return null }
        return value.value()
    }

    Long? issuedAtSeconds() {
        Result<Long, Error> value = self.longValue("iat")
        if value.isErr() { return null }
        return value.value()
    }

    List<String> audiences() {
        JsonValue? value = _claims.getOrNull("aud")
        if value == null { return [] }
        if value.isString() { return [value.asString() as String] }
        List<String> result = []
        if value.isArray() {
            JsonArray array = value.asArray() as JsonArray
            Int index = 0
            while index < array.length() {
                if array.get(index).isString() {
                    result.push(array.get(index).asString() as String)
                }
                index = index + 1
            }
        }
        return result
    }

    Bool isExpired(Long nowSeconds, Long leewaySeconds) {
        Long? exp = self.expiresAtSeconds()
        if exp == null { return false }
        return nowSeconds > (exp as Long) + leewaySeconds
    }

    JsonObject toJson() { return _claims.copy() }
    JwtClaims copy() { return new JwtClaims(_claims) }
}
```

> `?.as...` 链式可空访问是 XNull 语法；实现按 Json 值 kind 检查。
