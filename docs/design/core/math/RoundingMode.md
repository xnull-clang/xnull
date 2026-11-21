# `RoundingMode`

| 项 | 值 |
| --- | --- |
| 类型 | `enum RoundingMode` |
| 包 | `xdk.math` |
| 稳定性 | `stable` |
| 依赖 | 无 |

---

## 1. 定位

十进制/定点舍入模式；供 `Decimal.setScale/round` 等方法使用。

不做：浮点 FPU 舍入控制、全局舍入模式、locale 规则。

---

## 2. 设计逻辑

- 八种模式：远离零、向零、向正无穷、向负无穷、半上、半下、半偶、禁止舍入。
- 值语义；可作 Map 键。
- 不使用魔法整数。
- 每次舍入显式传模式；无全局默认。

---

## 3. 表示与不变量

| 成员 | 含义 |
| --- | --- |
| `Up` | 远离零 |
| `Down` | 向零 |
| `Ceiling` | 向 +∞ |
| `Floor` | 向 -∞ |
| `HalfUp` | 半值远离零 |
| `HalfDown` | 半值向零 |
| `HalfEven` | 半值取偶（银行家舍入） |
| `Unnecessary` | 不需要舍入；有丢失则失败 |

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

`RoundingMode` 没有实例方法；`Decimal` 的舍入方法使用该枚举。

---

## 8. 使用的技术

- 枚举；
- 舍入分支；
- 半值/奇偶判断。

---

## 9. 需要的支撑

- 语言：enum、Bool、Int；
- 运行时：无；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

值语义；可共享；无资源。

---

## 12. 示例与反例

正确：`Decimal.parse("1.25").round(1, RoundingMode.HalfEven)` → `1.2`。  
反例：用整数 0..7 传模式；期望全局设置默认舍入；`Unnecessary` 丢精度却返回成功。

---

## 13. 测试/场景义务

每个模式的正/负/半值；零；`Unnecessary` 失败；与 Decimal 集成。

---

## 14. XNull 伪代码

```xnull
enum RoundingMode {
    Up,
    Down,
    Ceiling,
    Floor,
    HalfUp,
    HalfDown,
    HalfEven,
    Unnecessary,
}
```
