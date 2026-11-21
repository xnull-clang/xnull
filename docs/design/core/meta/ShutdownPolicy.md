# `ShutdownPolicy`

| 项 | 值 |
| --- | --- |
| 类型 | `enum ShutdownPolicy` |
| 包 | `xdk.meta` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

能力画像的关闭策略：立即取消、无限排空或带截止排空。

不做：信号处理、进程终止、连接关闭实现、具体截止值。

---

## 2. 设计逻辑

- 策略作用于“应用拥有的工作”：任务、会话、队列、连接。
- 截止值来自 `ResourceLimits.shutdownDeadlineMillis`，不放在枚举里；枚举保持值语义。
- 客户端默认 `Immediate`；服务器默认 `Deadline`。
- `Drain` 没有截止，文档必须要求调用方提供外部监督，避免永久挂起。
- 关闭顺序由应用/服务器文档固定，不由枚举隐式执行。

---

## 3. 表示与不变量

| 成员 | 含义 | 截止 | 典型场景 |
| --- | --- | --- | --- |
| `Immediate` | 立即取消所有工作 | 无 | 客户端退出、工具 |
| `Drain` | 停止接受，等待自然结束 | 无 | 已知短任务、测试 |
| `Deadline` | 停止接受，等待到截止后取消 | `shutdownDeadlineMillis` | 生产服务器 |

不变量：成员固定；只允许追加；值语义；可作 `Map`/`Set` 键。

---

## 4. 生命周期

值类型；无构造器、无 close；可共享。

---

## 5. 构造契约

枚举项直接使用，无构造器。

---

## 6. 字段表

无实例字段。

---

## 7. 方法面

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `shutdownPolicyName` | 稳定小写名 | `ShutdownPolicy policy` | `String` | 无 |
| `shutdownPolicyFromName` | 名称解析（大小写不敏感） | `String name` | `ShutdownPolicy?` | 无；未知返回 null |
| `shutdownPolicyUsesDeadline` | 是否需要截止值 | `ShutdownPolicy policy` | `Bool` | 无 |

---

## 8. 使用的技术

- 简单枚举；
- 名称映射；
- 与 `ResourceLimits.shutdownDeadlineMillis` 组合。

---

## 9. 需要的支撑

- 语言：enum、String、Bool；
- 运行时：无；
- 接口：`CoreProfile`、`ResourceLimits`。

---

## 10. 依赖的特性/接口/类

`CoreProfile`、`ResourceLimits`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。

---

## 12. 示例与反例

正确：服务器 `Deadline` + 30000ms；超时后取消剩余会话。  
反例：生产使用 `Drain` 且无监督；`Immediate` 后继续写响应；把截止值写进枚举成员。

---

## 13. 测试/场景义务

每个成员名称/解析；截止判定；客户端/服务器默认值；无截止排空；超时后资源关闭。

---

## 14. XNull 伪代码

```xnull
enum ShutdownPolicy {
    Immediate,
    Drain,
    Deadline,
}

String shutdownPolicyName(ShutdownPolicy policy) {
    if policy == ShutdownPolicy.Immediate { return "immediate" }
    if policy == ShutdownPolicy.Drain { return "drain" }
    return "deadline"
}

ShutdownPolicy? shutdownPolicyFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "immediate" { return ShutdownPolicy.Immediate }
    if normalized == "drain" { return ShutdownPolicy.Drain }
    if normalized == "deadline" { return ShutdownPolicy.Deadline }
    return null
}

Bool shutdownPolicyUsesDeadline(ShutdownPolicy policy) {
    return policy == ShutdownPolicy.Deadline
}
```
