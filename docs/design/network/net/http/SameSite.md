# `SameSite`

| 项 | 值 |
| --- | --- |
| 类型 | `enum SameSite` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | `Error` |

---

## 1. 定位

Cookie SameSite 策略：Strict、Lax、None。

不做：跨站策略执行、浏览器行为模拟、CSRF 防护。

---

## 2. 设计逻辑

- 简单枚举；只保存值，不自动决定请求/响应行为。
- 文本大小写不敏感；顶层解析/格式化。
- 值语义；无 close。

---

## 3. 表示与不变量

| 成员 | 文本 |
| --- | --- |
| `Strict` | Strict |
| `Lax` | Lax |
| `None` | None |

---

## 4. 生命周期

值类型；无 close。

---

## 5. 构造契约

枚举成员直接使用。

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `sameSiteName` | 文本 | `SameSite value` | `String` | 无 |
| `parseSameSite` | 解析 | `String text` | `Result<SameSite, Error>` | `InvalidArgument` |

---

## 8. 使用的技术

- 简单枚举；
- 文本映射。

---

## 9. 需要的支撑

- 语言：enum、String、Result；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

`Error`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

值语义；无资源；可共享。

---

## 12. 示例与反例

正确：`Cookie` 的 `sameSite` 保存 `SameSite.Lax`。  
反例：把 SameSite 当强制 CSRF 防护；未知值静默变 None。

---

## 13. 测试/场景义务

三个成员；大小写；非法值；名称往返。

---

## 14. XNull 伪代码

```xnull
enum SameSite {
    Strict,
    Lax,
    None,
}

String sameSiteName(SameSite value) {
    if value == SameSite.Strict { return "Strict" }
    if value == SameSite.Lax { return "Lax" }
    return "None"
}

Result<SameSite, Error> parseSameSite(String text) {
    if text == null { throw "parseSameSite: null" }
    String value = text.toLower()
    if value == "strict" { return Ok(SameSite.Strict) }
    if value == "lax" { return Ok(SameSite.Lax) }
    if value == "none" { return Ok(SameSite.None) }
    return Err(new BasicError(ErrorKind.InvalidArgument, "invalid SameSite: " + text))
}
```
