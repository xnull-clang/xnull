# `JwtToken`

| 项 | 值 |
| --- | --- |
| 类型 | `class JwtToken` |
| 包 | `xdk.jwt` |
| 稳定性 | `preview` |
| 依赖 | `JwtHeader`、`JwtClaims`、`Bytes` |

---

## 1. 定位

解析后的 JWT：header、claims、签名、原始 token。

不做：签名验证（`Jwt.verify`）、JWE、密钥管理。

---

## 2. 设计逻辑

- 不可变字段；claims 副本。
- `signature` 原始字节；`raw` 原始字符串。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_header` | `JwtHeader` | header |
| `_claims` | `JwtClaims` | claims |
| `_signature` | `Bytes` | 签名 |
| `_raw` | `String` | 原始 token |

---

## 4. 生命周期

不可变；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `JwtToken(JwtHeader, JwtClaims, Bytes, String)` | 非 null | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `header` | header | 无 | `JwtHeader` | 无 |
| `claims` | claims 副本 | 无 | `JwtClaims` | 无 |
| `signature` | 签名副本 | 无 | `Bytes` | 无 |
| `raw` | 原始 token | 无 | `String` | 无 |

---

## 8. 使用的技术

- 不可变快照。

---

## 9. 需要的支撑

- 语言：class、Bytes、String；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

`JwtHeader`、`JwtClaims`、`Bytes`。

---

## 11. 所有权与并发

不可变；无资源。

---

## 12. 示例与反例

正确：`token.header().algorithm()`。  
反例：修改 claims 期望 token 变化；把 raw 当已验证。

---

## 13. 测试/场景义务

header/claims/signature/raw；副本；不可变。

---

## 14. XNull 伪代码

```xnull
class JwtToken {
    final JwtHeader _header
    final JwtClaims _claims
    final Bytes _signature
    final String _raw

    JwtToken(JwtHeader header, JwtClaims claims, Bytes signature, String raw) {
        if header == null || claims == null || signature == null || raw == null {
            throw "JwtToken: null argument"
        }
        _header = header
        _claims = claims.copy()
        _signature = signature.copy()
        _raw = raw
    }

    JwtHeader header() { return _header }
    JwtClaims claims() { return _claims.copy() }
    Bytes signature() { return _signature.copy() }
    String raw() { return _raw }
}
```
