# `HealthCheck`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol HealthCheck` |
| 包 | `xdk.runtime` |
| 稳定性 | `preview` |
| 依赖 | `HealthReport` |

---

实现状态：implemented（protocol；实现由调用方提供）。

## 1. 定位

单项健康检查合同：稳定名称 + 非阻塞检查快照。

不做：注册/聚合（`HealthRegistry`）、HTTP 端点、超时控制、重试、依赖注入。

---

## 2. 设计逻辑

- 非泛型协议；只有两个实例方法。
- `check()` 必须**非阻塞**；需要 I/O/网络的检查由实现缓存最近快照，后台更新。
- `name()` 在同一 `HealthRegistry` 内唯一；空名/重复由注册表拒绝。
- 失败不是异常：返回 `HealthReport.unhealthy(...)`，不 panic。
- 实现可跨任务只读共享；可变状态必须自行同步。
- 协议不持有字段；检查所需依赖由实现构造器注入。

---

## 3. 表示与不变量

协议无字段。实现必须保证：

- `name()` 非空、单行、稳定；
- `check()` 不阻塞、不抛可恢复错误；
- `check()` 返回的 `HealthReport` 非 null；
- `check()` 不修改全局状态。

---

## 4. 生命周期

实现决定；无协议级 close；持有资源的实现必须自行 `close()` 并与注册表解绑。

---

## 5. 构造契约

协议无构造；实现定义依赖注入。

---

## 6. 字段表

无协议字段。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | 检查名称 | 无 | `String` | 无 |
| `check` | 当前健康快照 | 无 | `HealthReport` | 无 |

---

## 8. 使用的技术

- 非泛型协议；
- 快照；
- 缓存；
- 非阻塞检查。

---

## 9. 需要的支撑

- 语言：protocol、String；
- 运行时：无；
- 接口：`HealthReport`、`HealthState`。

---

## 10. 依赖的特性/接口/类

`HealthReport`、`HealthState`、`HealthRegistry`。

---

## 11. 所有权与并发

实现可并发调用；不得共享可变状态而不加同步；`check` 不保留调用方状态。
相等：协议无值语义；实现身份由具体类决定。

---

## 12. 示例与反例

正确：`class DbCheck implements HealthCheck` 缓存最近 ping 结果，`check()` 返回快照。  
反例：`check()` 内做阻塞数据库查询；返回 null；`name()` 随请求变化；抛 panic 表达不健康。

---

## 13. 测试/场景义务

名称唯一/非空；健康/降级/不健康快照；非阻塞；并发 check；缓存更新；注册表聚合。

---

## 14. XNull 伪代码

```xnull
protocol HealthCheck {
    String name();
    HealthReport check();
}
```
