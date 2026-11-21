# `JwtOptions`

| 项 | 值 |
| --- | --- |
| 类型 | `class JwtOptions` |
| 包 | `xdk.jwt` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

JWT 验证策略：leeway、issuer、audience、required claims、exp/nbf 开关。

不做：算法白名单、JWKS、OAuth。

---

## 2. 设计逻辑

- 可变 builder；验证时复制。
- 默认 leeway 0、验证 exp/nbf、无 issuer/audience/required。
- 值非负；非法 panic。
- 无 close；非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_leewaySeconds` | `Long` | 时钟偏移 |
| `_issuer` | `String?` | iss |
| `_audience` | `String?` | aud |
| `_requiredClaims` | `List<String>` | 必填 |
| `_verifyExpiration` | `Bool` | 验 exp |
| `_verifyNotBefore` | `Bool` | 验 nbf |

---

## 4. 生命周期

可变；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `JwtOptions()` | 无 | 默认 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `leewaySeconds` | 设置 | `Long` | `JwtOptions` | <0 → panic |
| `issuer` | 设置 | `String` | `JwtOptions` | 空 → panic |
| `audience` | 设置 | `String` | `JwtOptions` | 空 → panic |
| `require` | 追加必填 | `String` | `JwtOptions` | 空 → panic |
| `verifyExpiration` | 开关 | `Bool` | `JwtOptions` | 无 |
| `verifyNotBefore` | 开关 | `Bool` | `JwtOptions` | 无 |
| `getLeewaySeconds`/`getIssuer`/`getAudience`/`getRequiredClaims`/`isVerifyExpiration`/`isVerifyNotBefore` | 读取 | 无 | 对应 | 无 |
| `copy` | 快照 | 无 | `JwtOptions` | 无 |

---

## 8. 使用的技术

- builder；
- 验证策略。

---

## 9. 需要的支撑

- 语言：class、Long、String、Bool、List；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

可变；非线程安全；无资源。

---

## 12. 示例与反例

正确：`new JwtOptions().leewaySeconds(30).issuer("auth")`。  
反例：leeway 负；required 空；关闭 exp 验证处理不可信 token。

---

## 13. 测试/场景义务

默认；leeway；iss/aud；required；exp/nbf；copy。

---

## 14. XNull 伪代码

```xnull
class JwtOptions {
    Long _leewaySeconds = 0
    String? _issuer = null
    String? _audience = null
    List<String> _requiredClaims = []
    Bool _verifyExpiration = true
    Bool _verifyNotBefore = true

    JwtOptions() {
    }

    JwtOptions leewaySeconds(Long value) {
        if value < 0 { throw "JwtOptions.leewaySeconds: negative" }
        _leewaySeconds = value
        return self
    }

    JwtOptions issuer(String value) {
        if value == null || value == "" { throw "JwtOptions.issuer: empty" }
        _issuer = value
        return self
    }

    JwtOptions audience(String value) {
        if value == null || value == "" { throw "JwtOptions.audience: empty" }
        _audience = value
        return self
    }

    JwtOptions require(String claim) {
        if claim == null || claim == "" { throw "JwtOptions.require: empty" }
        _requiredClaims.push(claim)
        return self
    }

    JwtOptions verifyExpiration(Bool value) { _verifyExpiration = value; return self }
    JwtOptions verifyNotBefore(Bool value) { _verifyNotBefore = value; return self }

    Long getLeewaySeconds() { return _leewaySeconds }
    String? getIssuer() { return _issuer }
    String? getAudience() { return _audience }
    List<String> getRequiredClaims() { return _requiredClaims.copy() }
    Bool isVerifyExpiration() { return _verifyExpiration }
    Bool isVerifyNotBefore() { return _verifyNotBefore }

    JwtOptions copy() {
        JwtOptions result = new JwtOptions()
        result.leewaySeconds(_leewaySeconds)
        if _issuer != null { result.issuer(_issuer as String) }
        if _audience != null { result.audience(_audience as String) }
        Int index = 0
        while index < _requiredClaims.length() {
            result.require(_requiredClaims.get(index))
            index = index + 1
        }
        result.verifyExpiration(_verifyExpiration)
        result.verifyNotBefore(_verifyNotBefore)
        return result
    }
}
```
