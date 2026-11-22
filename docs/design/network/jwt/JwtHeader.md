# `JwtHeader`

| 项 | 值 |
| --- | --- |
| 类型 | `class JwtHeader` |
| 包 | `xdk.jwt` |
| 稳定性 | `preview` |
| 依赖 | `JwtAlgorithm` |

---

> 注解合同（A8，implemented；限制见 S3 §5.7）：`@Value` 生成 `equals`/`toString`/`copy`（不生成 `hash`）；字段保持 `final`；引用字段按值语义比较。实现由处理器生成，不手写；实现时删除同名手写成员，避免生成冲突；伪代码中的 `equals`/`toString`/`copy` 只描述生成物行为，不是手写实现。

## 1. 定位

JWT JOSE header：alg、typ、kid。

不做：任意 header 参数、JWE、JWK。

---

## 2. 设计逻辑

- 不可变字段 `_algorithm`、`_type`、`_keyId`。
- typ 默认 `"JWT"`；kid 可空。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_algorithm` | `JwtAlgorithm` | alg |
| `_type` | `String` | typ |
| `_keyId` | `String?` | kid |

---

## 4. 生命周期

不可变；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `JwtHeader(JwtAlgorithm algorithm)` | algorithm | 非 null | null → panic |
| `JwtHeader(JwtAlgorithm algorithm, String type, String? keyId)` | 全部 | type 非空 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `algorithm` | alg | 无 | `JwtAlgorithm` | 无 |
| `type` | typ | 无 | `String` | 无 |
| `keyId` | kid/无 | 无 | `String?` | 无 |

---

## 8. 使用的技术

- 值对象。

---

## 9. 需要的支撑

- 语言：class、String；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

`JwtAlgorithm`。

---

## 11. 所有权与并发

不可变；无资源。

---

## 12. 示例与反例

正确：`new JwtHeader(JwtAlgorithm.Rs256)`。  
反例：alg none；typ 空；kid 含换行。

---

## 13. 测试/场景义务

默认 typ；kid 可空；非法；alg。

---

## 14. XNull 伪代码

```xnull
@Value
class JwtHeader {
    final JwtAlgorithm _algorithm
    final String _type
    final String? _keyId

    JwtHeader(JwtAlgorithm algorithm) {
        if algorithm == null { throw "JwtHeader: null algorithm" }
        _algorithm = algorithm
        _type = "JWT"
        _keyId = null
    }

    JwtHeader(JwtAlgorithm algorithm, String type, String? keyId) {
        if algorithm == null { throw "JwtHeader: null algorithm" }
        if type == null || type == "" { throw "JwtHeader: empty type" }
        _algorithm = algorithm
        _type = type
        _keyId = keyId
    }

    JwtAlgorithm algorithm() { return _algorithm }
    String type() { return _type }
    String? keyId() { return _keyId }
}
```
