# `Registry`

| 项 | 值 |
| --- | --- |
| 类型 | `class Registry` |
| 包 | `xdk.metrics` |
| 稳定性 | `preview` |
| 依赖 | `Metric`、`Counter`、`Gauge`、`Histogram`、`Timer`、`MetricFamily`、`MetricKind`、`RuntimeMonitor`、`xdk.collections` |

---

## 1. 定位

进程内指标注册表：按族名创建/登记指标、按名称/标签查询、移除、清空、快照；无全局单例。

不做：全局注册表、抓取服务器、推送网关、持久化、分布式聚合、指标导出编码。

---

## 2. 设计逻辑

- 字段 `_families: Map<String,List<Metric>>`：族名 → 标签序列列表；同一列表内 kind/help/unit 必须一致。
- 所有结构访问由 `RuntimeMonitor` 保护；注册表可跨任务共享。
- 四个便捷方法 `counter(name)`/`gauge(name)`/`histogram(name,boundaries)`/`timer(name)` 创建或返回空标签序列。
- 冲突返回 `Result`：同名不同 kind、help/unit 不同、直方图边界不同 → `AlreadyExists`。
- 同族同标签重复登记是幂等操作，保留已有对象，不替换。
- `register` 接受带 help/unit/标签的具体指标；四个便捷方法委托它完成登记。
- 便捷方法使用空 help/unit 创建序列；同族已有非空 help/unit 时，改用构造器 + `register` 并保持全部序列元数据一致。
- `get(name)` 只查空标签序列；`get(name,labels)` 查精确标签序列。
- `remove(name)` 移除整族；`remove(name,labels)` 移除单序列；移除不清空指标值。
- `snapshot` 先在锁内复制族/序列引用，释放锁后逐个 `snapshot()`；弱一致但无嵌套锁。
- 族名排序按字典序；族内序列保持登记顺序；不承诺跨调用稳定（并发登记时可能变化）。
- 无 close；无 OS 资源；无全局注册表。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_families` | `Map<String,List<Metric>>` | 族名 → 序列列表 |
| `_monitor` | `RuntimeMonitor` | 结构保护 |

不变量：族名非空；列表非空；同列表内所有指标 kind/help/unit 一致；直方图同族边界一致；同族内标签集合唯一；不持有 null。

---

## 4. 生命周期

构造为空；`register`/便捷方法/`remove`/`clear` 改变结构；`get`/`names`/`snapshot` 读取；无 close；被移除的指标引用仍由调用方持有。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Registry()` | 无 | 空注册表 | 无 |

说明：

- 不提供全局实例、静态访问器或默认注册表。
- 每个应用/测试自建 Registry，避免隐式共享。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `counter` | 创建/取 Counter | `String name` | `Result<Counter, Error>` | 名称冲突 → `AlreadyExists` |
| `gauge` | 创建/取 Gauge | `String name` | `Result<Gauge, Error>` | 名称冲突 → `AlreadyExists` |
| `histogram` | 创建/取 Histogram | `String name, List<Double> boundaries` | `Result<Histogram, Error>` | 名称/边界冲突 → `AlreadyExists` |
| `timer` | 创建/取 Timer | `String name` | `Result<Timer, Error>` | 名称冲突 → `AlreadyExists` |
| `register` | 登记已有指标 | `Metric metric` | `Result<Unit, Error>` | 冲突 → `AlreadyExists`；非内建直方图 → `Unsupported` |
| `get` | 查空标签序列 | `String name` | `Metric?` | 无 |
| `get` | 查精确标签序列 | `String name, Map<String,String> labels` | `Metric?` | 无 |
| `remove` | 移除整族 | `String name` | `Bool` | 无 |
| `remove` | 移除单序列 | `String name, Map<String,String> labels` | `Bool` | 无 |
| `names` | 族名快照 | 无 | `List<String>` | 无 |
| `snapshot` | 全量族快照 | 无 | `List<MetricFamily>` | 无 |
| `clear` | 清空结构 | 无 | `void` | 无 |

说明：

- `counter(name)` 先查空标签序列；存在且是 Counter 则返回；存在但类型不同 → `AlreadyExists`；不存在则创建并登记。
- `histogram(name,boundaries)` 对已存在序列比较边界；不同 → `AlreadyExists`，不替换。
- `register` 幂等：同族同标签且元数据一致时返回 `Ok(unit)`，保留已有对象；不更新其值。
- 便捷方法创建的序列 help/unit 为空；若同族需要非空 help/unit，用构造器 + `register` 创建全部序列，避免元数据冲突。
- `get` 返回接口引用；需要强类型时调用方显式 `as`，或直接使用便捷方法的返回值。
- `remove` 返回是否移除；移除/清空不调用 `reset`，不影响已持有引用。
- `snapshot` 的族名排序；族内样本顺序为序列登记顺序，序列内顺序由各指标 `snapshot` 决定。
- `snapshot` 不持有注册表锁调用指标；并发登记/移除可能使快照漏掉或包含刚移除的序列（弱一致）。

---

## 8. 使用的技术

- 名称映射 + 序列列表；
- 运行时监视器；
- 冲突检测；
- 幂等登记；
- 复制后快照；
- 字典序排序。

---

## 9. 需要的支撑

- 语言：class、Map、List、String、Int、Bool、Result、Unit；
- 运行时：`RuntimeMonitor.enter/exit`；
- 接口：`Metric`、`Counter`、`Gauge`、`Histogram`、`Timer`、`MetricFamily`、`MetricKind`、`Error`、`BasicError`。

---

## 10. 依赖的特性/接口/类

`Metric`、`Counter`、`Gauge`、`Histogram`、`Timer`、`MetricFamily`、`MetricKind`、`RuntimeMonitor`、`Error`、`BasicError`、`ErrorKind`、`xdk.collections.sortedBy`。

---

## 11. 所有权与并发

引用语义；线程安全；注册表持有指标引用但不独占；`remove`/`clear` 不销毁指标；`snapshot` 弱一致；无 close；无资源。

锁顺序：Registry 持有 `_monitor` 时只调用指标的元数据/`labels()`，不调用 `snapshot()`/`reset()`/更新方法；指标实现不反向调用 Registry；因此无嵌套死锁。`snapshot()` 在释放 Registry 锁后调用指标锁。

---

## 12. 示例与反例

正确：`Registry registry = new Registry()`；`Result<Counter,Error> c = registry.counter("http_requests")`；`registry.register(new Histogram("latency", "Latency", "ms", ["route":"/"], [5.0,10.0]))`；`List<MetricFamily> families = registry.snapshot()`。  
反例：使用全局 Registry；同名先注册 Counter 再注册 Gauge；同一直方图名用不同边界；期望 `remove` 清空指标值；在持有 Registry 锁时导出；并发 `clear` 后假设旧快照仍包含全部序列。

---

## 13. 测试/场景义务

空注册表；四个便捷方法；重复取同一指标；同标签幂等；kind 冲突；help/unit 冲突；直方图边界冲突；带标签登记；`get` 空/标签/缺失；`remove` 整族/单序列/缺失；`names` 排序；`snapshot` 分组/排序/弱一致；`clear`；并发登记/快照/移除；null 参数；非内建 Histogram 实现。

---

## 14. XNull 伪代码

```xnull
class Registry {
    final Map<String, List<Metric>> _families
    final RuntimeMonitor _monitor

    Registry() {
        _families = [:]
        _monitor = new RuntimeMonitor()
    }

    Result<Counter, Error> counter(String name) {
        if name == null || name == "" { throw "Registry.counter: empty name" }
        Metric? existing = self.get(name)
        if existing != null {
            if !(existing is Counter) {
                return Err(new BasicError(ErrorKind.AlreadyExists,
                    "Registry.counter: name conflict for " + name))
            }
            return Ok(existing as Counter)
        }
        Counter created = new Counter(name)
        Result<Unit, Error> added = self.register(created)
        if added.isErr() { return Err(added.error()) }
        Metric? stored = self.get(name)
        if stored == null {
            return Err(new BasicError(ErrorKind.Internal,
                "Registry.counter: registration lost for " + name))
        }
        if !(stored is Counter) {
            return Err(new BasicError(ErrorKind.AlreadyExists,
                "Registry.counter: name conflict for " + name))
        }
        return Ok(stored as Counter)
    }

    Result<Gauge, Error> gauge(String name) {
        if name == null || name == "" { throw "Registry.gauge: empty name" }
        Metric? existing = self.get(name)
        if existing != null {
            if !(existing is Gauge) {
                return Err(new BasicError(ErrorKind.AlreadyExists,
                    "Registry.gauge: name conflict for " + name))
            }
            return Ok(existing as Gauge)
        }
        Gauge created = new Gauge(name)
        Result<Unit, Error> added = self.register(created)
        if added.isErr() { return Err(added.error()) }
        Metric? stored = self.get(name)
        if stored == null {
            return Err(new BasicError(ErrorKind.Internal,
                "Registry.gauge: registration lost for " + name))
        }
        if !(stored is Gauge) {
            return Err(new BasicError(ErrorKind.AlreadyExists,
                "Registry.gauge: name conflict for " + name))
        }
        return Ok(stored as Gauge)
    }

    Result<Histogram, Error> histogram(String name, List<Double> boundaries) {
        if name == null || name == "" { throw "Registry.histogram: empty name" }
        if boundaries == null { throw "Registry.histogram: null boundaries" }
        Metric? existing = self.get(name)
        if existing != null {
            if !(existing is Histogram) {
                return Err(new BasicError(ErrorKind.AlreadyExists,
                    "Registry.histogram: name conflict for " + name))
            }
            Histogram current = existing as Histogram
            if !self.boundariesEqual(current.boundaries(), boundaries) {
                return Err(new BasicError(ErrorKind.AlreadyExists,
                    "Registry.histogram: boundaries conflict for " + name))
            }
            return Ok(current)
        }
        Histogram created = new Histogram(name, boundaries)
        Result<Unit, Error> added = self.register(created)
        if added.isErr() { return Err(added.error()) }
        Metric? stored = self.get(name)
        if stored == null {
            return Err(new BasicError(ErrorKind.Internal,
                "Registry.histogram: registration lost for " + name))
        }
        if !(stored is Histogram) {
            return Err(new BasicError(ErrorKind.AlreadyExists,
                "Registry.histogram: name conflict for " + name))
        }
        Histogram result = stored as Histogram
        if !self.boundariesEqual(result.boundaries(), boundaries) {
            return Err(new BasicError(ErrorKind.AlreadyExists,
                "Registry.histogram: boundaries conflict for " + name))
        }
        return Ok(result)
    }

    Result<Timer, Error> timer(String name) {
        if name == null || name == "" { throw "Registry.timer: empty name" }
        Metric? existing = self.get(name)
        if existing != null {
            if !(existing is Timer) {
                return Err(new BasicError(ErrorKind.AlreadyExists,
                    "Registry.timer: name conflict for " + name))
            }
            return Ok(existing as Timer)
        }
        Timer created = new Timer(name)
        Result<Unit, Error> added = self.register(created)
        if added.isErr() { return Err(added.error()) }
        Metric? stored = self.get(name)
        if stored == null {
            return Err(new BasicError(ErrorKind.Internal,
                "Registry.timer: registration lost for " + name))
        }
        if !(stored is Timer) {
            return Err(new BasicError(ErrorKind.AlreadyExists,
                "Registry.timer: name conflict for " + name))
        }
        return Ok(stored as Timer)
    }

    Result<Unit, Error> register(Metric metric) {
        if metric == null { throw "Registry.register: null metric" }
        String name = metric.name()
        if name == null || name == "" { throw "Registry.register: empty name" }
        _monitor.enter()
        if !_families.has(name) {
            List<Metric> series = []
            series.push(metric)
            _families.put(name, series)
            _monitor.exit()
            return Ok(unit)
        }
        List<Metric> series = _families.get(name)
        Metric first = series.get(0)
        if first.kind() != metric.kind() {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.AlreadyExists,
                "Registry.register: kind conflict for " + name))
        }
        if first.help() != metric.help() || first.unit() != metric.unit() {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.AlreadyExists,
                "Registry.register: metadata conflict for " + name))
        }
        if first is Histogram {
            if !(metric is Histogram) {
                _monitor.exit()
                return Err(new BasicError(ErrorKind.Unsupported,
                    "Registry.register: unsupported histogram implementation"))
            }
            Histogram existing = first as Histogram
            Histogram candidate = metric as Histogram
            if !self.boundariesEqual(existing.boundaries(), candidate.boundaries()) {
                _monitor.exit()
                return Err(new BasicError(ErrorKind.AlreadyExists,
                    "Registry.register: boundaries conflict for " + name))
            }
        }
        Map<String, String> incomingLabels = metric.labels()
        Int index = 0
        while index < series.length() {
            Metric current = series.get(index)
            if self.labelsEqual(current.labels(), incomingLabels) {
                _monitor.exit()
                return Ok(unit)
            }
            index = index + 1
        }
        series.push(metric)
        _monitor.exit()
        return Ok(unit)
    }

    Metric? get(String name) {
        if name == null { throw "Registry.get: null name" }
        _monitor.enter()
        Metric? result = null
        if _families.has(name) {
            List<Metric> series = _families.get(name)
            Int index = 0
            while index < series.length() {
                Metric current = series.get(index)
                if current.labels().isEmpty() {
                    result = current
                    break
                }
                index = index + 1
            }
        }
        _monitor.exit()
        return result
    }

    Metric? get(String name, Map<String, String> labels) {
        if name == null { throw "Registry.get: null name" }
        if labels == null { throw "Registry.get: null labels" }
        _monitor.enter()
        Metric? result = null
        if _families.has(name) {
            List<Metric> series = _families.get(name)
            Int index = 0
            while index < series.length() {
                Metric current = series.get(index)
                if self.labelsEqual(current.labels(), labels) {
                    result = current
                    break
                }
                index = index + 1
            }
        }
        _monitor.exit()
        return result
    }

    Bool remove(String name) {
        if name == null { throw "Registry.remove: null name" }
        _monitor.enter()
        Bool removed = _families.remove(name)
        _monitor.exit()
        return removed
    }

    Bool remove(String name, Map<String, String> labels) {
        if name == null { throw "Registry.remove: null name" }
        if labels == null { throw "Registry.remove: null labels" }
        _monitor.enter()
        Bool removed = false
        if _families.has(name) {
            List<Metric> series = _families.get(name)
            Int index = 0
            while index < series.length() {
                Metric current = series.get(index)
                if self.labelsEqual(current.labels(), labels) {
                    series.remove(index)
                    removed = true
                    break
                }
                index = index + 1
            }
            if series.isEmpty() { _families.remove(name) }
        }
        _monitor.exit()
        return removed
    }

    List<String> names() {
        _monitor.enter()
        List<String> result = _families.keys()
        _monitor.exit()
        return sortedBy(result, (String a, String b) -> a < b)
    }

    List<MetricFamily> snapshot() {
        _monitor.enter()
        List<String> familyNames = _families.keys()
        Map<String, List<Metric>> copied = [:]
        Int index = 0
        while index < familyNames.length() {
            String name = familyNames.get(index)
            copied.put(name, _families.get(name).copy())
            index = index + 1
        }
        _monitor.exit()
        List<String> ordered = sortedBy(familyNames, (String a, String b) -> a < b)
        List<MetricFamily> result = []
        index = 0
        while index < ordered.length() {
            String name = ordered.get(index)
            List<Metric> series = copied.get(name)
            List<MetricSample> samples = []
            MetricKind kind = MetricKind.Counter
            String help = ""
            String unit = ""
            Bool first = true
            Int seriesIndex = 0
            while seriesIndex < series.length() {
                MetricFamily family = series.get(seriesIndex).snapshot()
                if first {
                    kind = family.kind()
                    help = family.help()
                    unit = family.unit()
                    first = false
                }
                List<MetricSample> familySamples = family.samples()
                Int sampleIndex = 0
                while sampleIndex < familySamples.length() {
                    samples.push(familySamples.get(sampleIndex))
                    sampleIndex = sampleIndex + 1
                }
                seriesIndex = seriesIndex + 1
            }
            if !first {
                result.push(new MetricFamily(name, kind, help, unit, samples))
            }
            index = index + 1
        }
        return result
    }

    void clear() {
        _monitor.enter()
        _families.clear()
        _monitor.exit()
    }

    private Bool labelsEqual(Map<String, String> left, Map<String, String> right) {
        if left.length() != right.length() { return false }
        List<String> keys = left.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            if !right.has(key) { return false }
            if left.get(key) != right.get(key) { return false }
            index = index + 1
        }
        return true
    }

    private Bool boundariesEqual(List<Double> left, List<Double> right) {
        if left.length() != right.length() { return false }
        Int index = 0
        while index < left.length() {
            if left.get(index) != right.get(index) { return false }
            index = index + 1
        }
        return true
    }
}
```
