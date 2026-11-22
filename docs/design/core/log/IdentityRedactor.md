# `IdentityRedactor`

| 项 | 值 |
| --- | --- |
| 类型 | `class IdentityRedactor implements Redactor` |
| 包 | `xdk.log` |
| 稳定性 | `stable` |
| 依赖 | `Redactor` |

---

## 1. 定位

默认脱敏器：原样返回文本，不做任何改写。

不做：替换、正则、过滤、采样。

---

## 2. 设计逻辑

- 无字段；`redact(value)` 返回 `value`。
- `value == null` → 返回空串，保证管道不把 null 传给 formatter/sink。
- 是 `Logger` 的默认 redactor；`withRedactor` 可替换。

---

## 3. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `IdentityRedactor()` | 无 | 无 | 无 |

---

## 4. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `redact` | 原样返回 | `String value` | `String` | null → 空串 |

---

## 5. 示例与反例

正确：`new IdentityRedactor()` 作为默认值。

反例：期望它脱敏；把 null 传给 sink；把它当过滤/采样器。

---

## 6. 测试/场景义务

原样返回；null → 空串；默认 Logger 使用；替换后原 Logger 不变；无状态/可共享。

---

## 7. XNull 伪代码

```xnull
class IdentityRedactor implements Redactor {
    IdentityRedactor() {
    }

    String redact(String value) {
        if value == null { return "" }
        return value
    }
}
```
