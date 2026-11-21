# `SmartHealth`

| 项 | 值 |
| --- | --- |
| 类型 | `enum SmartHealth` |
| 包 | `xdk.os.storage` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

SMART 健康分类：Good、Warning、Critical、Unknown。

不做：SMART 属性解析、故障预测、保修判断、安全联锁。

---

## 2. 设计逻辑

- 只表达聚合健康；具体属性在 `SmartInfo`。
- `Unknown` 是合法值，不 panic。
- 值语义；可作 `Map`/`Set` 键；成员固定，只允许追加。

---

## 3. 表示与不变量

| 成员 | 含义 |
| --- | --- |
| `Good` | 健康 |
| `Warning` | 警告 |
| `Critical` | 临界 |
| `Unknown` | 未知/不可用 |

不变量：成员固定；只允许追加；值语义。

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
| `smartHealthName` | 稳定小写名 | `SmartHealth health` | `String` | 无 |
| `smartHealthFromName` | 名称解析 | `String name` | `SmartHealth?` | 无；未知返回 null |
| `smartHealthIsHealthy` | 是否健康 | `SmartHealth health` | `Bool` | 无 |

---

## 8. 使用的技术

- 简单枚举；
- 名称映射。

---

## 9. 需要的支撑

- 语言：enum、String、Bool；
- 运行时：无；
- 接口：`SmartInfo`。

---

## 10. 依赖的特性/接口/类

`SmartInfo`、`StorageDevice`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。
相等：按枚举底层值比较；可作 `Map` 键。

---

## 12. 示例与反例

正确：`smart.kind() == SmartHealth.Warning`。  
反例：把 Unknown 当健康；用 SMART 替代备份；应用扩展枚举。

---

## 13. 测试/场景义务

每个成员名称/解析/健康判定；未知名称；与 `SmartInfo` 组合。

---

## 14. XNull 伪代码

```xnull
enum SmartHealth {
    Good,
    Warning,
    Critical,
    Unknown,
}

String smartHealthName(SmartHealth health) {
    if health == SmartHealth.Good { return "good" }
    if health == SmartHealth.Warning { return "warning" }
    if health == SmartHealth.Critical { return "critical" }
    return "unknown"
}

SmartHealth? smartHealthFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "good" { return SmartHealth.Good }
    if normalized == "warning" { return SmartHealth.Warning }
    if normalized == "critical" { return SmartHealth.Critical }
    if normalized == "unknown" { return SmartHealth.Unknown }
    return null
}

Bool smartHealthIsHealthy(SmartHealth health) {
    return health == SmartHealth.Good
}
```
