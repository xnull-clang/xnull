# `NormalizationForm`

| 项 | 值 |
| --- | --- |
| 类型 | `enum NormalizationForm` |
| 包 | `xdk.text` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

Unicode 规范化形式：NFC/NFD/NFKC/NFKD；供 `Unicode.normalize` 使用。

不做：完整 ICU 选项、locale 规则、字素簇。

---

## 2. 设计逻辑

- 四值枚举；值语义。
- 替代字符串 `"NFC"`/`"NFD"` 等魔法值。
- 完整规范化表为 X； 保证常用字符。

---

## 3. 表示与不变量

| 成员 | 含义 |
| --- | --- |
| `NFC` | 规范组合 |
| `NFD` | 规范分解 |
| `NFKC` | 兼容组合 |
| `NFKD` | 兼容分解 |

不变量：成员固定；只允许追加。

---

## 4. 生命周期

值类型；无 close；可共享。

---

## 5. 构造契约

枚举成员直接使用。

---

## 6. 字段表

无实例字段。

---

## 7. 方法面

`NormalizationForm` 没有实例方法；`Unicode.normalize` 使用该枚举。

---

## 8. 使用的技术

- 枚举；
- 规范化表选择。

---

## 9. 需要的支撑

- 语言：enum；
- 运行时：Unicode 规范化表；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

值语义；可共享；无资源。

---

## 12. 示例与反例

正确：`Unicode.normalize(text, NormalizationForm.NFC)`。  
反例：用字符串 `"NFC"`；用规范化替代大小写折叠；期望完整 ICU。

---

## 13. 测试/场景义务

四种形式；ASCII/组合字符/兼容字符；空串；与 `Unicode` 集成。

---

## 14. XNull 伪代码

```xnull
enum NormalizationForm {
    NFC,
    NFD,
    NFKC,
    NFKD,
}
```
