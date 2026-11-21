# `TelemetryBatch`

| 项 | 值 |
| --- | --- |
| 类型 | `class TelemetryBatch` |
| 包 | `xdk.agent` |
| 稳定性 | `preview` |
| 依赖 | `TelemetryKind`、`TelemetryRecord`、`MetricFamily`、`SpanContext`、`LogRecord` |

---

## 1. 定位

不可变的同 kind 遥测批次：共享资源属性 + 记录列表 + 丢弃计数 + 代表时间戳 + 大小估算。

批次是 Receiver/Processor/Exporter/Connector 之间唯一的数据单位；它不携带管线、组件或目标信息。

不做：跨 kind 混装、可变追加、持久化、编码、资源属性派生、记录排序。

---

## 2. 设计逻辑

- 一个批次只含一种 `TelemetryKind`；记录本身的 kind 必须与批次一致；
- 资源属性是批次级 `Map<String,String>`；同一批次的记录共享同一资源视图；
- 记录列表在构造时复制；读取返回副本；记录本身不可变，可安全共享；
- `droppedRecords` 记录上游因队列/限制丢弃的条数，便于端到端丢弃可见；
- `timestampMono` 是批次代表时间（通常为最早记录或采集时刻），用于排序/超时；
- `estimatedBytes` 是记录估算之和加资源属性估算，用于内存限制与队列预算；
- `merge` 只允许 kind 与资源属性完全相同的批次；
- `split` 保持记录顺序；丢弃计数只放在第一个分片，避免重复计数；
- 无 close；无资源；可跨任务共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_kind` | `TelemetryKind` | 非 null |
| `_resource` | `Map<String,String>` | 非 null；键非空；值非 null |
| `_records` | `List<TelemetryRecord>` | 非 null；元素非 null 且 kind 一致 |
| `_droppedRecords` | `Int` | ≥0 |
| `_timestampMono` | `Long` | ≥0 |
| `_estimatedBytes` | `Long` | ≥0；构造时计算 |

不变量：所有记录 kind 等于批次 kind；资源 Map 为私有快照；记录列表为私有快照；
`estimatedBytes` ≥ 记录估算之和；不可变；空批次合法（`isEmpty()` 为 true）。

---

## 4. 生命周期

构造后不可变；无 close；无资源；可跨任务只读共享；GC 管理。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `TelemetryBatch(TelemetryKind kind, Map<String,String> resource, List<TelemetryRecord> records, Int droppedRecords, Long timestampMono)` | 全部 | kind 非 null；resource/records 非 null；记录 kind 一致；dropped ≥0；timestamp ≥0 | 非法 → panic |
| `of` | `TelemetryKind kind, Map<String,String> resource, List<TelemetryRecord> records` | 同上；时间戳取 `nowMono()`，dropped 为 0 | 非法 → panic |

说明：

- `resource` 复制后存储；调用方后续修改不影响批次；
- `records` 复制后存储；记录不可变，不深拷贝；
- 允许空记录列表：表示过滤器丢弃全部数据或空采集；
- 资源键规则：非空、无换行/制表/`=`；值非 null、无换行/制表；
- `timestampMono` 不从记录推导，由接收器/处理器显式给出。

---

## 6. 字段表

见 §3；字段私有且 `final`。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `of` | 便捷构造 | `TelemetryKind kind, Map<String,String> resource, List<TelemetryRecord> records` | `TelemetryBatch` | 非法 → panic |
| `kind` | 批次种类 | 无 | `TelemetryKind` | 无 |
| `resource` | 资源属性快照 | 无 | `Map<String,String>` | 无 |
| `records` | 记录快照 | 无 | `List<TelemetryRecord>` | 无 |
| `recordCount` | 记录条数 | 无 | `Int` | 无 |
| `isEmpty` | 是否空批次 | 无 | `Bool` | 无 |
| `droppedRecords` | 上游丢弃条数 | 无 | `Int` | 无 |
| `timestampMono` | 代表时间戳 | 无 | `Long` | 无 |
| `estimatedBytes` | 估算大小 | 无 | `Long` | 无 |
| `withRecords` | 派生记录列表 | `List<TelemetryRecord> records` | `TelemetryBatch` | 非法 → panic |
| `withAdditionalDropped` | 增加丢弃计数 | `Int count` | `TelemetryBatch` | 负值 → panic |
| `merge` | 合并同资源批次 | `TelemetryBatch other` | `Result<TelemetryBatch, Error>` | null → panic；kind/资源不同 → `InvalidArgument` |
| `split` | 按最大条数分片 | `Int maximumRecords` | `List<TelemetryBatch>` | ≤0 → panic |
| `describe` | 单行摘要 | 无 | `String` | 无 |

说明：

- `records()` 返回新列表；元素不可变，可共享；
- `withRecords` 保留 kind/resource/dropped/timestamp，只替换记录并重算估算大小；
- `withAdditionalDropped` 返回新批次；负数 panic；计数可能溢出，按 `Int` 边界 panic；
- `merge` 要求 kind 相同且资源 Map 逐键相等；时间戳取两者较小值；丢弃数相加；
- `split` 对空批次返回空列表；记录数不超过上限时返回一个副本；丢弃计数只进入第一个分片；
- `describe` 只用于诊断，不是导出格式。

---

## 8. 使用的技术

- 不可变容器；
- 防御性复制；
- kind/资源合并校验；
- 记录分片；
- 字节估算；
- 丢弃计数。

---

## 9. 需要的支撑

- 语言：class、List、Map、Int、Long、Bool、Result；
- 运行时：`nowMono`、`str`；
- 接口：`TelemetryKind`、`TelemetryRecord`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`TelemetryKind`、`TelemetryRecord`、`MetricFamily`、`SpanContext`、`LogRecord`、`nowMono`、
`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

不可变；可跨任务共享；`resource()`/`records()`/`split()` 返回新容器；无资源；无取消点；
`merge` 不修改任一输入。
相等：引用身份；值比较需比较 kind/resource/records/dropped/timestamp；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：

```xnull
TelemetryRecord record = TelemetryRecord.log(logRecord)
TelemetryBatch batch = TelemetryBatch.of(
    TelemetryKind.Logs,
    ["service.name":"api"],
    [record]
)
```

反例：把 metrics 与 logs 记录放进同一批次；修改 `records()` 返回值期望改批次；合并不同
`service.name` 的批次；把 `droppedRecords` 当本批次实际条数；用空批次表示“删除资源”。

---

## 13. 测试/场景义务

空批次/单条/多条；kind 混装拒绝；资源复制；记录复制；`withRecords` 重算大小；
`withAdditionalDropped`；`merge` 同资源/不同 kind/不同资源；`split` 1 条/边界/空/丢弃计数归首片；
`estimatedBytes` 非负；并发读取；`describe`。

---

## 14. XNull 伪代码

```xnull
class TelemetryBatch {
    final TelemetryKind _kind
    final Map<String, String> _resource
    final List<TelemetryRecord> _records
    final Int _droppedRecords
    final Long _timestampMono
    final Long _estimatedBytes

    TelemetryBatch(TelemetryKind kind, Map<String, String> resource,
                   List<TelemetryRecord> records, Int droppedRecords,
                   Long timestampMono) {
        if kind == null { throw "TelemetryBatch: null kind" }
        if resource == null || records == null {
            throw "TelemetryBatch: null container"
        }
        if droppedRecords < 0 { throw "TelemetryBatch: negative dropped" }
        if timestampMono < 0 { throw "TelemetryBatch: negative timestamp" }
        Map<String, String> resourceCopy = [:]
        List<String> resourceKeys = resource.keys()
        Int resourceIndex = 0
        while resourceIndex < resourceKeys.length() {
            String key = resourceKeys.get(resourceIndex)
            String value = resource.get(key)
            if key == "" || key.indexOf("\n") >= 0 || key.indexOf("\t") >= 0
                || key.indexOf("=") >= 0 {
                throw "TelemetryBatch: invalid resource key"
            }
            if value == null || value.indexOf("\n") >= 0
                || value.indexOf("\t") >= 0 {
                throw "TelemetryBatch: invalid resource value"
            }
            resourceCopy.put(key, value)
            resourceIndex = resourceIndex + 1
        }
        List<TelemetryRecord> recordCopy = []
        Long totalBytes = 0
        Int recordIndex = 0
        while recordIndex < records.length() {
            TelemetryRecord record = records.get(recordIndex)
            if record == null { throw "TelemetryBatch: null record" }
            if record.kind() != kind {
                throw "TelemetryBatch: record kind mismatch"
            }
            recordCopy.push(record)
            totalBytes = totalBytes + record.estimatedBytes()
            recordIndex = recordIndex + 1
        }
        _kind = kind
        _resource = resourceCopy
        _records = recordCopy
        _droppedRecords = droppedRecords
        _timestampMono = timestampMono
        _estimatedBytes = totalBytes
    }

    static TelemetryBatch of(TelemetryKind kind, Map<String, String> resource,
                             List<TelemetryRecord> records) {
        return new TelemetryBatch(kind, resource, records, 0, nowMono())
    }

    TelemetryKind kind() { return _kind }
    Map<String, String> resource() { return _resource.copy() }
    List<TelemetryRecord> records() { return _records.copy() }
    Int recordCount() { return _records.length() }
    Bool isEmpty() { return _records.length() == 0 }
    Int droppedRecords() { return _droppedRecords }
    Long timestampMono() { return _timestampMono }
    Long estimatedBytes() { return _estimatedBytes }

    TelemetryBatch withRecords(List<TelemetryRecord> records) {
        return new TelemetryBatch(_kind, _resource, records, _droppedRecords,
            _timestampMono)
    }

    TelemetryBatch withAdditionalDropped(Int count) {
        if count < 0 { throw "TelemetryBatch.withAdditionalDropped: negative" }
        return new TelemetryBatch(_kind, _resource, _records,
            _droppedRecords + count, _timestampMono)
    }

    Result<TelemetryBatch, Error> merge(TelemetryBatch other) {
        if other == null { throw "TelemetryBatch.merge: null batch" }
        if other._kind != _kind {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "TelemetryBatch.merge: kind mismatch"))
        }
        if !self.resourceEquals(_resource, other._resource) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "TelemetryBatch.merge: resource mismatch"))
        }
        List<TelemetryRecord> merged = _records.copy()
        merged.pushAll(other._records)
        Long earlier = _timestampMono
        if other._timestampMono < earlier { earlier = other._timestampMono }
        return Ok(new TelemetryBatch(_kind, _resource, merged,
            _droppedRecords + other._droppedRecords, earlier))
    }

    List<TelemetryBatch> split(Int maximumRecords) {
        if maximumRecords <= 0 {
            throw "TelemetryBatch.split: maximumRecords <= 0"
        }
        List<TelemetryBatch> result = []
        if _records.length() == 0 { return result }
        Int offset = 0
        while offset < _records.length() {
            Int end = offset + maximumRecords
            if end > _records.length() { end = _records.length() }
            List<TelemetryRecord> slice = []
            Int index = offset
            while index < end {
                slice.push(_records.get(index))
                index = index + 1
            }
            Int dropped = 0
            if offset == 0 { dropped = _droppedRecords }
            result.push(new TelemetryBatch(_kind, _resource, slice, dropped,
                _timestampMono))
            offset = end
        }
        return result
    }

    Bool resourceEquals(Map<String, String> left, Map<String, String> right) {
        if left.length() != right.length() { return false }
        List<String> keys = left.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            if !right.has(key) { return false }
            if left.getOr(key, "") != right.getOr(key, "") { return false }
            index = index + 1
        }
        return true
    }

    String describe() {
        return telemetryKindName(_kind) + " records=" + str(_records.length())
            + " dropped=" + str(_droppedRecords)
            + " bytes=" + str(_estimatedBytes)
    }
}
```
