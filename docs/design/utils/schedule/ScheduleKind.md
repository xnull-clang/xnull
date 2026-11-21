# `ScheduleKind`

| 项 | 值 |
| --- | --- |
| 类型 | `enum ScheduleKind` |
| 包 | `xdk.schedule` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

调度规格类型：一次性、固定频率、固定延迟、cron。

不做：执行、misfire、时区、句柄。

---

## 2. 设计逻辑

- `Once`：绝对时间或相对延迟一次。
- `FixedRate`：按开始时间固定周期。
- `FixedDelay`：上次结束后延迟。
- `Cron`：cron 表达式。
- 值语义；无 close。

---

## 3. 表示与不变量

| 成员 | 说明 |
| --- | --- |
| `Once` | 一次 |
| `FixedRate` | 固定频率 |
| `FixedDelay` | 固定延迟 |
| `Cron` | cron |

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

正确：`Schedule.cron(...).kind() == ScheduleKind.Cron`。  
反例：把 FixedRate 当 FixedDelay；期望 Once 可重复。

---

## 13. 测试/场景义务

四个成员；Schedule 工厂映射；日志/描述。

---

## 14. XNull 伪代码

```xnull
enum ScheduleKind {
    Once,
    FixedRate,
    FixedDelay,
    Cron,
}
```
