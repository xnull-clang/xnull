# `TelemetryKind`

| 项 | 值 |
| --- | --- |
| 类型 | `enum TelemetryKind` |
| 包 | `xdk.agent` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

遥测种类：Metrics、Traces、Logs。它是 Agent 管线的信号分类，也是批次与组件兼容性的唯一依据。

不做：数据模型、编码格式、传输协议、采样策略、后端能力探测。

---

## 2. 设计逻辑

- 固定三个成员，对应 OpenTelemetry Collector 的 metrics/traces/logs 管线；
- 一个管线只处理一种 kind；接收器、处理器、导出器必须与管线同 kind；
- 连接器可以输入一种 kind、输出另一种 kind，因此单独声明 `inputKind`/`outputKind`；
- 枚举只表达分类，不携带数据；具体记录由 `TelemetryRecord` 承载；
- 值语义；无 close；可作 `Map` 键、可比较；
- 不提供整数序号转换；跨进程/配置只使用稳定小写名 `metrics`、`traces`、`logs`。

---

## 3. 表示与不变量

| 成员 | 语义 | 稳定名 |
| --- | --- | --- |
| `Metrics` | 可聚合数值样本 | `metrics` |
| `Traces` | span 树/追踪记录 | `traces` |
| `Logs` | 离散日志记录 | `logs` |

不变量：成员固定；不存在 `Profiles`/`Events`/`Summaries` 等隐式成员；枚举名与
`telemetryKindName` 映射一一对应。

---

## 4. 生命周期

值类型；无构造器；无 close；无资源；可跨任务共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| 枚举成员 | 无 | 固定三项 | 无 |

说明：

- 直接使用成员，不提供整数转换；
- 配置/协议层必须显式映射文本；未知文本由调用方返回 `InvalidArgument`，不在枚举内解析。

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

无实例方法。

包级函数：

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `telemetryKindName` | 稳定小写名 | `TelemetryKind kind` | `String` | 无 |

说明：

- `kind` 为 null 时 panic；枚举不会出现未知成员；
- 名称用于诊断、配置键、导出路径（`/v1/metrics` 等）映射；
- 不承担解析；需要文本到枚举时由配置构造器显式 `if` 映射并拒绝未知值。

---

## 8. 使用的技术

- 简单枚举；
- 稳定名称映射；
- 三值闭合集合。

---

## 9. 需要的支撑

- 语言：enum、String、if；
- 运行时：无；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

值语义；不可变；可共享；可并发比较；无资源；无取消点。
相等：按枚举成员比较；可作 `Map`/`Set` 键。

---

## 12. 示例与反例

正确：`pipeline.kind() == TelemetryKind.Metrics`；`telemetryKindName(TelemetryKind.Logs)` 返回 `"logs"`。  
反例：把 metrics 批次送进 traces 导出器；用整数序号持久化 kind；假设存在 `TelemetryKind.Profiles`；
根据后端 URL 猜测 kind。

---

## 13. 测试/场景义务

三个成员；`telemetryKindName` 映射；作为 `Map` 键；管线/组件 kind 一致性校验；未知配置文本拒绝；
跨管线连接器输入/输出 kind 校验。

---

## 14. XNull 伪代码

```xnull
enum TelemetryKind {
    Metrics,
    Traces,
    Logs,
}

String telemetryKindName(TelemetryKind kind) {
    if kind == null {
        throw "telemetryKindName: null kind"
    }
    if kind == TelemetryKind.Metrics {
        return "metrics"
    }
    if kind == TelemetryKind.Traces {
        return "traces"
    }
    return "logs"
}
```
