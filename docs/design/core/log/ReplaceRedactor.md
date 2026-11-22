# `ReplaceRedactor`

| 项 | 值 |
| --- | --- |
| 类型 | `class ReplaceRedactor implements Redactor` |
| 包 | `xdk.log` |
| 稳定性 | `stable` |
| 依赖 | `Redactor` |

---

## 1. 定位

固定子串替换脱敏：把 message/字段值中的 `searchText` 全部替换为 `replacement`。

不做：正则、结构化字段删除、过滤、采样。

---

## 2. 设计逻辑

- 字段 `_searchText`、`_replacement`；构造后不可变。
- `searchText == ""` 时 no-op；`searchText`/`replacement` 非 null。
- 替换所有出现位置，区分大小写；不递归替换 replacement 自身。
- `Logger` 对 message 与每个 `Field.value` 调用同一实例。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_searchText` | `String` | 待替换文本 |
| `_replacement` | `String` | 替换文本 |

不变量：字段非 null；空 searchText 合法且 no-op；不可变。

---

## 4. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ReplaceRedactor(String searchText, String replacement)` | searchText/replacement | 非 null | null → panic |

---

## 5. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `redact` | 替换全部 | `String value` | `String` | null value → 空串 |

---

## 6. 示例与反例

正确：`new ReplaceRedactor("secret", "***")`；message 与字段值都替换。

反例：空 searchText 期望插入 replacement；期望正则/大小写不敏感；只替换第一次出现。

---

## 7. 测试/场景义务

单次/多次出现；空 searchText no-op；null value；message 与字段值；replacement 不再被二次替换；构造 null panic。

---

## 8. XNull 伪代码

```xnull
class ReplaceRedactor implements Redactor {
    final String _searchText
    final String _replacement

    ReplaceRedactor(String searchText, String replacement) {
        if searchText == null || replacement == null {
            throw "ReplaceRedactor: null argument"
        }
        _searchText = searchText
        _replacement = replacement
    }

    String redact(String value) {
        if value == null { return "" }
        if _searchText == "" { return value }
        return value.replace(_searchText, _replacement)
    }
}
```
