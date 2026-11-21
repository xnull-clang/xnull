# `DropPolicy`

| 项 | 值 |
| --- | --- |
| 类型 | `enum DropPolicy` |
| 包 | `xdk.queue` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

有界队列满时的处理策略：报错、丢新、丢旧。

不做：阻塞、优先级、批量刷新。

---

## 2. 设计逻辑

- `Error`：拒绝新值，返回 false，rejected++。
- `DropNewest`：拒绝新值，dropped++。
- `DropOldest`：删除最旧值，插入新值，dropped++。
- 值语义；无 close。

---

## 3. 表示与不变量

| 成员 | 说明 |
| --- | --- |
| `Error` | 拒绝新值 |
| `DropNewest` | 丢新值 |
| `DropOldest` | 丢最旧值 |

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

正确：容量 2、DropOldest，push 1/2/3 → 队列 [2,3]。  
反例：把 Error 当阻塞；把 DropNewest 计数到 popped；期望 DropOldest 保留旧值。

---

## 13. 测试/场景义务

每个成员；满队列 push 返回值；计数；关闭状态。

---

## 14. XNull 伪代码

```xnull
enum DropPolicy {
    Error,
    DropNewest,
    DropOldest,
}
```
