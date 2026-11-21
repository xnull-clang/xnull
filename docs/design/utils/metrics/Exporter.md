# `Exporter`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol Exporter` |
| 包 | `xdk.metrics` |
| 稳定性 | `preview` |
| 依赖 | `Registry`、`MetricsFormat`、`Writer`、`xdk.io`、`Error` |

---

## 1. 定位

指标导出协议：声明输出格式，把注册表快照写入 `Writer`，并提供 flush/close 生命周期。

不做：抓取 HTTP 服务、定时推送、认证、重试、压缩、具体编码实现、注册表变更。

---

## 2. 设计逻辑

- 非泛型协议；`format()` 返回固定 `MetricsFormat`，`export` 负责编码并写字节。
- `export(context, registry, writer)` 先调用 `registry.snapshot()` 一次，再按格式编码；导出期间不持有注册表锁。
- `export` 首参 `Context`，写入可取消；取消返回 `Cancelled`，可能留下部分已写字节，调用方负责丢弃/重试。
- 不关闭、不 flush 调用方的 `Writer`；Writer 所有权归调用方。
- `flush()` 只刷新导出器内部缓冲；无缓冲实现返回 `Ok(unit)`。
- `close()` 幂等；关闭后 `export`/`flush` 返回 `Unavailable`；不关闭 Writer。
- 同一导出器实例不保证并发 `export`；调用方应串行化，或每个任务使用独立实例。
- 无注册表修改；导出是只读操作。

---

## 3. 表示与不变量

协议无字段。实现保证：

- `format()` 在生命周期内稳定；
- `export` 只读取注册表快照；
- 写入失败原样传播为 `Io`/`Unavailable`；
- `close` 后 `isOpen()` 为 false；
- `close` 不关闭调用方 Writer；
- 编码器对 help/标签做格式转义，对非有限值按格式约定编码。

---

## 4. 生命周期

构造后打开；`export` 可多次；`flush` 可多次；`close` 一次或多次；无 OS 资源时 close 仍幂等。

---

## 5. 构造契约

协议无构造；由具体导出器定义。实现必须初始化为打开状态。

---

## 6. 字段表

无协议字段。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `format` | 输出格式 | 无 | `MetricsFormat` | 无 |
| `export` | 导出快照 | `Context context, Registry registry, Writer writer` | `Result<Unit, Error>` | `Io`/`Cancelled`/`Unavailable`/`Internal` |
| `flush` | 刷新内部缓冲 | 无 | `Result<Unit, Error>` | `Io`/`Unavailable` |
| `close` | 关闭导出器 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isOpen` | 是否可导出 | 无 | `Bool` | 无 |

说明：

- `export` 对 null context/registry/writer 是合同错误 → panic；已关闭 → `Unavailable`。
- `export` 调用 `registry.snapshot()` 后释放注册表锁；编码失败属于实现缺陷 → `Internal`。
- `export` 在写入前/写入中检查 Context；取消后不再继续写，但已写字节不自动回滚。
- `export` 不调用 `writer.close()`，也不假设 Writer 可寻址。
- `flush` 对无缓冲实现是 no-op；关闭后调用 → `Unavailable`。
- `close` 幂等；已关闭时返回 `Ok(unit)`（不重复报错）。

格式义务：

| 格式 | 约定 |
| --- | --- |
| `Text` | 每行一个样本：`name{labels} value timestampMono`；标签键排序；族之间空行；供人读/测试 |
| `Json` | 族数组；族字段 `name`/`kind`/`help`/`unit`/`samples`；样本字段 `name`/`labels`/`value`/`timestampMono`；NaN/±Inf 编码为字符串 |
| `Prometheus` | `# HELP`/`# TYPE` + 样本行；counter/gauge 单行；histogram `_bucket`（含 `le`）/`_sum`/`_count`；timer 按 summary 输出 `_sum`/`_count`/`_max`；转义 help/标签 |

具体编码器不在本包定义；应用或 X 扩展实现本协议。

---

## 8. 使用的技术

- 非泛型协议；
- 快照后编码；
- 流式写入；
- 格式分派；
- 幂等关闭；
- 所有权分离（Writer 由调用方持有）。

---

## 9. 需要的支撑

- 语言：protocol、class、String、Bool、Result、Unit；
- 运行时：`Context`、`toUtf8`；
- 接口：`Registry`、`MetricsFormat`、`Writer`、`Error`、`BasicError`。

---

## 10. 依赖的特性/接口/类

`Registry`、`MetricFamily`、`MetricSample`、`MetricsFormat`、`Writer`、`Context`、`Error`、`BasicError`、`ErrorKind`、`toUtf8`。

---

## 11. 所有权与并发

- 导出器引用语义；内部缓冲由实现持有。
- 调用方持有 Writer；导出器不关闭/不 flush 它。
- 同一实例的 `export` 不保证并发安全；调用方串行化。
- `format`/`isOpen` 可并发读取；`close` 与 `export` 的竞态由实现决定，推荐关闭后快速失败 `Unavailable`。
- 无全局导出器；无后台任务。

---

## 12. 示例与反例

正确：`Exporter exporter = createPrometheusExporter()`；`Result<Unit, Error> result = exporter.export(context, registry, writer)`；检查 `result` 后由调用方 `writer.flush()`/`writer.close()`。  
反例：导出器关闭调用方 Writer；导出时修改注册表；两个任务并发使用同一导出器；忽略 `Io`；忽略 Context 取消；把 `format()` 当 HTTP Content-Type 自动探测。

---

## 13. 测试/场景义务

`format` 稳定；`export` 空/多族/多标签；Writer 失败传播；Context 取消；关闭后 `Unavailable`；`flush` no-op/关闭后；`close` 幂等；不关闭 Writer；Text/Json/Prometheus 关键字段；非有限值编码；并发导出约束；null 参数。

---

## 14. XNull 伪代码

```xnull
protocol Exporter {
    MetricsFormat format();
    Result<Unit, Error> export(Context context, Registry registry, Writer writer);
    Result<Unit, Error> flush();
    Result<Unit, Error> close();
    Bool isOpen();
}
```
