# `MetricsFormat`

| 项 | 值 |
| --- | --- |
| 类型 | `enum MetricsFormat` |
| 包 | `xdk.metrics` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

指标导出格式分类：Text、Json、Prometheus。

不做：编码实现、Content-Type 协商、自动探测、解析/导入、压缩、传输。

---

## 2. 设计逻辑

- `Text`：面向人/测试的逐行文本；标签键排序；便于断言。
- `Json`：面向机器交换；族数组 + 样本对象；非有限值用字符串。
- `Prometheus`：Prometheus 文本暴露格式；`# HELP`/`# TYPE` + 样本行；直方图桶累计。
- 枚举只表达格式；具体编码由 `Exporter` 实现。
- 格式不隐含传输方式；文件、stdout、HTTP 响应都由调用方决定。
- 不提供 `parse`/自动探测；配置必须显式选择。
- 值语义；无 close；可作 `Map` 键。

---

## 3. 表示与不变量

| 成员 | 语义 | 稳定名称 |
| --- | --- | --- |
| `Text` | 人读文本 | `text` |
| `Json` | JSON 文档 | `json` |
| `Prometheus` | Prometheus 文本 | `prometheus` |

不变量：成员固定；不存在 `OpenMetrics`/`Csv` 等隐式成员；格式与导出器 `format()` 一致。

---

## 4. 生命周期

值类型；无 close；无资源；可跨任务共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| 枚举成员 | 无 | 固定三项 | 无 |

说明：

- 直接使用成员；不提供整数转换。
- 不从文件扩展名/Content-Type 推断；由配置/调用方显式传入。

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

无实例方法。

包级函数：

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `metricsFormatName` | 稳定小写名 | `MetricsFormat format` | `String` | 无 |

说明：

- `metricsFormatName` 用于诊断/文件名后缀；不承担解析。
- 名称固定为 `text`、`json`、`prometheus`。

---

## 8. 使用的技术

- 简单枚举；
- 稳定名称映射；
- 导出器按格式分派编码器。

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

值语义；不可变；可共享；可并发比较；无资源。

---

## 12. 示例与反例

正确：`exporter.format() == MetricsFormat.Prometheus`。  
反例：根据文件名猜格式；把枚举当 Content-Type；持久化序号；假设存在 `MetricsFormat.OpenMetrics`；在格式枚举里实现编码。

---

## 13. 测试/场景义务

三个成员；`metricsFormatName` 映射；导出器 `format()` 与编码一致；作为 `Map` 键；配置显式选择；未知文本拒绝。

---

## 14. XNull 伪代码

```xnull
enum MetricsFormat {
    Text,
    Json,
    Prometheus,
}

String metricsFormatName(MetricsFormat format) {
    if format == MetricsFormat.Text { return "text" }
    if format == MetricsFormat.Json { return "json" }
    return "prometheus"
}
```
