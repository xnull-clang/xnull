# `MisfirePolicy`

| 项 | 值 |
| --- | --- |
| 类型 | `enum MisfirePolicy` |
| 包 | `xdk.schedule` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

错过触发时间后的处理策略：跳过、补一次、追赶到上限。

不做：执行、调度、持久化、告警。

---

## 2. 设计逻辑

- `Skip`：直接按新时间继续，不补。
- `FireOnce`：立即补一次，然后恢复。
- `CatchUp`：最多补 `SchedulerOptions.catchUpLimit` 次，避免风暴。
- 值语义；无 close。

---

## 3. 表示与不变量

| 成员 | 说明 |
| --- | --- |
| `Skip` | 跳过 |
| `FireOnce` | 补一次 |
| `CatchUp` | 有限追赶 |

---

## 4. 生命周期

值类型；无 close。

---

## 5. 构造契约

枚举成员直接使用。

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

无实例方法。

---

## 8. 使用的技术

- 简单枚举。

---

## 9. 需要的支撑

- 语言：enum。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

值语义；可共享。

---

## 12. 示例与反例

正确：停机 1 小时、每分钟作业，CatchUp limit=5 → 最多补 5 次。  
反例：CatchUp 无上限导致恢复风暴；Skip 后仍补跑；FireOnce 补多次。

---

## 13. 测试/场景义务

每个策略；多错过周期；catchUpLimit 0/1/N；恢复后下一次时间。

---

## 14. XNull 伪代码

```xnull
enum MisfirePolicy {
    Skip,
    FireOnce,
    CatchUp,
}
```
