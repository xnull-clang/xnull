# `xdk.utils` 工作分配与执行分析

| 项 | 值 |
| --- | --- |
| 目的 |  剩余包一次并行完成，不再逐批停留（已完成） |
| 方法 | 盘点 → 依赖/冲突分析 → 不相交工作流 → 并行执行 → 统一集成校验 |
| 范围 | metrics、trace、audit、terminal、i18n、test（ 设计） |
| 约束 | 只写设计文档；不改 `src/xdk`；共享 README 只由集成者修改 |

---

## 1. 盘点

| 包 | 类型数 | 类型 |
| --- | ---: | --- |
| `xdk.metrics` | 11 | `MetricKind`、`MetricSample`、`MetricFamily`、`Metric`、`Counter`、`Gauge`、`Histogram`、`Timer`、`Registry`、`Exporter`、`MetricsFormat` |
| `xdk.trace` | 9 | `SpanKind`、`SpanStatus`、`SpanContext`、`SpanEvent`、`TraceOptions`、`Sampler`、`Propagator`、`Span`、`Tracer` |
| `xdk.audit` | 5 | `AuditLevel`、`AuditEvent`、`AuditSink`、`AuditLogger`、`Redactor` |
| `xdk.terminal` | 8 | `Terminal`、`Ansi`、`Color`、`Style`、`ProgressBar`、`Spinner`、`Prompt`、`Table` |
| `xdk.i18n` | 7 | `Locale`、`MessageCatalog`、`MessageFormatter`、`PluralRules`、`NumberFormat`、`DateFormat`、`Translator` |
| `xdk.test` | 7 | `Assert`、`Test`、`TestSuite`、`TestRunner`、`TestResult`、`TestStatus`、`TestContext` |

合计 47 个类型文件 + 6 个包 README。

health 不单独建包：`xdk.runtime` 已有 `HealthState`/`HealthReport`/`HealthCheck`/`HealthRegistry`，重复会违反去重规则。

`xdk.event`/`reflect`/`graph` 仍为 X，不在本次设计收口范围。

---

## 2. 依赖与冲突分析

- 六个包目录互不相交，每个工作流只写自己的目录。
- 共享文件：
  - `docs/design/README.md`
  - `docs/design/WORK-ALLOCATION.md`
  - `docs/design/platform/os/WORK-ALLOCATION.md`（参考，不修改）
  由集成者最后统一修改，工作流不得改。
- `metrics.Histogram` 组合 `xdk.stats.BucketHistogram`，不复制桶算法；仅增加标签/注册表快照。
- `trace` 不依赖 metrics；`audit` 不依赖 log 包（只依赖 errors/regex）。
- `terminal` 不依赖 log；`i18n` 不复用 `xdk.time.DateTimeFormatter` 的通用格式化，只做 locale 资源。
- `test` 不依赖 terminal/i18n，保持纯断言/运行器。
- 同一包 README 与类型文件由同一工作流负责，避免并行写同一文件。

---

## 3. 工作流

| 流 | 范围 | 产物 | 状态 |
| --- | --- | --- | --- |
| W1 | Metrics | 11 类型 + `metrics/README.md` | 已完成 |
| W2 | Trace | 9 类型 + `trace/README.md` | 已完成 |
| W3 | Audit | 5 类型 + `audit/README.md` | 已完成 |
| W4 | Terminal | 8 类型 + `terminal/README.md` | 已完成 |
| W5 | I18n | 7 类型 + `i18n/README.md` | 已完成 |
| W6 | Test | 7 类型 + `test/README.md` | 已完成 |

并行规则：

- 每个流只写自己的目录；
- 不新建共享类型；
- 不修改 `utils/README.md`、本文件、其他包目录、`src/xdk`；
- 类型名/字段/方法与盘点表一致；
- 每个类型 14 段；README 只留索引/规则/场景/缺口；
- 伪代码必须 XNull 形态。

---

## 4. 每类型 14 段

1. 定位
2. 设计逻辑
3. 表示与不变量
4. 生命周期
5. 构造契约
6. 字段表
7. 方法总表 / 详表
8. 使用的技术
9. 需要的支撑
10. 依赖的特性/接口/类
11. 所有权与并发
12. 示例与反例
13. 测试/场景义务
14. XNull 伪代码

禁止：`Void`、空参数 `Ok()`、`Result<void>`、`self._`、`self(...)`、`new T()`、`// ...`、小写辅助文件。

---

## 5. 集成校验

1. 统计 47 个类型文件是否齐全；
2. README 索引与文件一一对应；
3. 每个类型 14 段；
4. 相对链接 0 broken；
5. 扫描非 XNull 写法；
6. 更新 `README.md` 包状态与依赖树；
7. 确认 `src/xdk` 无改动；
8. 不提交代码。

---

## 6. 验收谓词

- 6 个包 README + 47 个类型文件全部存在；
- 每个类型 14 段齐全；
- README 索引 = 文件数；
- 链接全部可达；
- 无禁用伪代码写法；
- health 明确标注复用 `xdk.runtime`；
- `src/xdk` 未改动。

---

## 7. 执行结果

```text
W1 Metrics   11/11
W2 Trace      9/9
W3 Audit      5/5
W4 Terminal   8/8
W5 I18n       7/7
W6 Test       7/7
合计         47/47 类型文件
14 段检查：全部通过
命名检查：PASS
相对链接：0 broken
代码/脚本改动：无
```

“已完成”指设计文档完成；`src/xdk` 尚未实现这些包。
