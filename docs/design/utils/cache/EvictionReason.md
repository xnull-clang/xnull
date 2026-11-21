# `EvictionReason`

| 项 | 值 |
| --- | --- |
| 类型 | `enum EvictionReason` |
| 包 | `xdk.cache` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

缓存条目离开缓存的原因。

不做：统计、监听、策略选择。

---

## 2. 设计逻辑

- `Capacity`：容量/权重淘汰。
- `Expired`：TTL 到期。
- `Replaced`：同键写入覆盖旧值。
- `Explicit`：`invalidate`/`invalidateAll`。
- `Closed`：`close` 清空。
- 值语义；无 close。

---

## 3. 表示与不变量

| 成员 | 说明 |
| --- | --- |
| `Capacity` | 容量/权重 |
| `Expired` | TTL |
| `Replaced` | 覆盖 |
| `Explicit` | 显式删除 |
| `Closed` | 关闭 |

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

正确：listener 根据 `reason == EvictionReason.Expired` 记录过期数。  
反例：把 `Replaced` 计入容量淘汰；把 `Closed` 当显式删除。

---

## 13. 测试/场景义务

每个成员；listener 收到正确原因；统计区分 Expired/Capacity。

---

## 14. XNull 伪代码

```xnull
enum EvictionReason {
    Capacity,
    Expired,
    Replaced,
    Explicit,
    Closed,
}
```
