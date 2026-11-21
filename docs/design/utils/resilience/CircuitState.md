# `CircuitState`

| 项 | 值 |
| --- | --- |
| 类型 | `enum CircuitState` |
| 包 | `xdk.resilience` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

熔断器状态：Closed、Open、HalfOpen。

不做：策略配置、计数、计时、分布式状态同步。

---

## 2. 设计逻辑

- `Closed`：正常放行，累计失败。
- `Open`：快速失败，直到打开时长耗尽。
- `HalfOpen`：放行有限探测请求；成功回 Closed，失败回 Open。
- 状态迁移只由 `CircuitBreaker` 执行；枚举本身无行为。
- 值语义；无 close。

---

## 3. 表示与不变量

| 成员 | 说明 |
| --- | --- |
| `Closed` | 正常 |
| `Open` | 熔断 |
| `HalfOpen` | 半开探测 |

不变量：成员固定；不存在 `Disabled`/`ForcedOpen` 等隐式状态。

---

## 4. 生命周期

值类型；无 close；无资源。

---

## 5. 构造契约

枚举成员直接使用；不提供整数转换。

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

无实例方法；状态名由 `str`/日志层格式化。

---

## 8. 使用的技术

- 简单枚举；
- 显式状态机。

---

## 9. 需要的支撑

- 语言：enum。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

值语义；无资源；可跨任务共享。

---

## 12. 示例与反例

正确：`breaker.state() == CircuitState.Open`。  
反例：把 HalfOpen 当完全关闭；在枚举上实现计数；期望 Open 自动计时切换。

---

## 13. 测试/场景义务

每个成员；状态迁移；日志/字符串；比较；Map 键。

---

## 14. XNull 伪代码

```xnull
enum CircuitState {
    Closed,
    Open,
    HalfOpen,
}
```
