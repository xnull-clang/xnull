# `FileLogReceiver`

| 项 | 值 |
| --- | --- |
| 类型 | `class FileLogReceiver implements Receiver` |
| 包 | `xdk.agent` |
| 稳定性 | `preview` |
| 依赖 | `Receiver`、`TelemetryKind`、`TelemetryBatch`、`TelemetryRecord`、`LogRecord`、`Field`、`Level`、`Regex`、`PathMatcher`、`File`、`fs`、`Timer`、`Context`、`Error` |

---

## 1. 定位

文件日志接收器：按 glob 监控文件，增量读取新行，按可选 multiline 规则聚合，生成 Logs 批次。

它面向节点 Agent / sidecar 的本地日志采集；不负责日志格式化、脱敏、解析 JSON、轮转管理策略
（除最小偏移处理）、持久化 checkpoint。

不做：文件删除、压缩文件、header 解析、复杂 operator 链、持久化 offset、远程日志拉取、
日志级别推断（默认级别由构造器给出）。

---

## 2. 设计逻辑

- 实现 `Receiver`；`kind()` 固定 Logs；
- 每个 poll 周期扫描 include glob、应用 exclude matcher、读取新增内容；
- 偏移与 partial/multiline 缓冲保存在内存；重启后按 `startAt` 重新定位（不承诺断点续传）；
- 读取先写入临时 offset/partial 映射，只有下游成功后才提交；下游 `Busy` 时保留旧 offset，
  下个周期重读，形成自然背压；
- 单行超过 `maximumLogBytes` 时截断并计数，避免内存爆；multiline 聚合也受该上限约束；
- 每个文件生成 `LogRecord`，附带 `log.file.name`/`log.file.path`/`log.file.offset`/
  `log.file.record_number` 等字段（可配）；
- 默认级别由 `defaultLevel` 给出；不根据文本猜测级别；
- `onTruncate` 处理 copytruncate：`ignore` 保留 offset、`read_whole_file` 从 0 重读、
  `read_new` 跳到当前文件尾；
- `stop` 停止调度；`drain` 冲刷 partial/multiline 并交付最后一批；`close` 清空状态；
- 不拥有 `Path`/`File` 之外的注入依赖；不删除文件、不改权限、不跟随未声明的 symlink 语义。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | 非空、单行 |
| `_includePatterns` | `List<String>` | 非空；glob |
| `_excludeMatchers` | `List<PathMatcher>` | 可为空；构造时编译 |
| `_startAt` | `String` | `beginning`/`end` |
| `_encoding` | `String` | `utf-8`/`ascii`/`nop` |
| `_pollIntervalMillis` | `Long` | >0 |
| `_maximumLogBytes` | `Long` | >0 |
| `_multilinePattern` | `String` | 可为空；非空时编译为正则 |
| `_multilineRegex` | `Regex?` | 非空 pattern 时非 null |
| `_includeFileName` | `Bool` | 是否加 `log.file.name` |
| `_includeFilePath` | `Bool` | 是否加 `log.file.path` |
| `_onTruncate` | `String` | `ignore`/`read_whole_file`/`read_new` |
| `_defaultLevel` | `Level` | 非 null |
| `_resource` | `Map<String,String>` | 构造时复制 |
| `_attributes` | `Map<String,String>` | 构造时复制；附加到每条记录 |
| `_overflowPolicy` | `String` | `reject`/`drop_oldest`/`drop_newest` |
| `_timer` | `Timer` | 接收器拥有 |
| `_timerHandle` | `Long` | ≥0 |
| `_offsets` | `Map<String,Long>` | path → 已提交字节偏移 |
| `_partials` | `Map<String,String>` | path → multiline/半行缓冲 |
| `_recordNumbers` | `Map<String,Long>` | path → 下一条记录号 |
| `_downstream` | `Result<Unit, Error>(TelemetryBatch)?` | start 后非 null |
| `_running` | `Bool` | start 后 true |
| `_polling` | `Bool` | 防止 poll 重叠 |
| `_closed` | `Bool` | 只从 false 变 true |
| `_healthy` | `Bool` | 最近 poll 是否无错误 |
| `_lastError` | `String` | 可为空；不含日志正文 |
| `_lastSuccessMono` | `Long` | ≥0 |
| `_collectedBatches` | `Int` | ≥0 |
| `_droppedRecords` | `Int` | ≥0 |
| `_refusedBatches` | `Int` | ≥0 |
| `_truncatedRecords` | `Int` | ≥0 |

不变量：glob 非空；exclude 已编译；startAt/onTruncate/encoding/policy 合法；maxBytes >0；
偏移非负；partial 长度不超过 maxBytes；stop 后不再 poll；close 后不再接受 start；
错误描述不包含日志正文/敏感路径（路径只放字段，不放错误消息）。

---

## 4. 生命周期

```text
构造 → start（初始 poll + 周期 poll）→ poll（多次）→ stop → drain → close
```

- `start`：非阻塞；保存 downstream；调度初始 poll 与周期 poll；重复 start 返回 `Ok(unit)`；
- `poll`：读取新增行；下游成功才提交 offset/partial；下游 Busy 保留旧状态，下周期重试；
- `stop`：取消定时器；不丢弃已提交/未提交状态；可重复；
- `drain`：把 partial/multiline 缓冲作为记录交付；可重复；取消返回 `Cancelled`；
- `close`：stop + 清空 offset/partial/record 状态；幂等；关闭后 `drain` 返回 `Unavailable`；
- 重启不恢复 offset；按 `startAt` 决定从文件头或文件尾开始。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `FileLogReceiver` | `String name, List<String> includePatterns, List<String> excludePatterns, String startAt, String encoding, Long pollIntervalMillis, Long maximumLogBytes, String multilinePattern, Bool includeFileName, Bool includeFilePath, String onTruncate, Level defaultLevel, Map<String,String> resource, Map<String,String> attributes, String overflowPolicy` | name 非空；include 非空；startAt/encoding/onTruncate/policy 合法；poll/maxBytes >0；defaultLevel 非 null | 非法 → panic |

说明：

- `includePatterns` 支持 `*`/`?`/`**`/字符类；由 `fs.glob` 解析；
- `excludePatterns` 编译为 `PathMatcher`；对 include 结果过滤；
- `multilinePattern` 为空串表示逐行；非空时用 `Regex.compile`，编译失败 panic；
- `encoding` 基线只支持 `utf-8`/`ascii`/`nop`；UTF-16/压缩为 X；
- `onTruncate` 只在检测到文件大小小于已提交 offset 时生效；
- `resource`/`attributes` 复制；attributes 会附加到每条记录字段；
- `name` 同一 Agent 内唯一，通常为 `"filelog"`。

---

## 6. 字段表

见 §3；配置字段为 `final`；offset/partial/运行状态由接收器串行化。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `kind` | 固定 Logs | 无 | `TelemetryKind` | 无 |
| `name` | 接收器名 | 无 | `String` | 无 |
| `start` | 启动轮询 | `Context context, Result<Unit, Error>(TelemetryBatch) downstream` | `Result<Unit, Error>` | `Unavailable`/`InvalidArgument`/`Cancelled` |
| `stop` | 停止轮询 | `Context context` | `Result<Unit, Error>` | `Cancelled`/`Internal` |
| `drain` | 冲刷 partial | `Context context` | `Result<Unit, Error>` | `Busy`/`Cancelled`/`Unavailable` |
| `close` | 清空状态 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isRunning` | 是否运行 | 无 | `Bool` | 无 |
| `isHealthy` | 是否健康 | 无 | `Bool` | 无 |
| `pollOnce` | 手动轮询一次 | `Context context` | `Result<Unit, Error>` | `Unavailable`/`Cancelled`/`Io`/`DataCorrupted` |
| `offsets` | 当前偏移快照 | 无 | `Map<String,Long>` | 无 |
| `lastSuccessMono` | 最近成功时间 | 无 | `Long` | 无 |
| `collectedBatches` | 成功批次数 | 无 | `Int` | 无 |
| `droppedRecords` | 丢弃记录数 | 无 | `Int` | 无 |
| `refusedBatches` | 拒绝批次数 | 无 | `Int` | 无 |
| `truncatedRecords` | 截断记录数 | 无 | `Int` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |

说明：

- `start` 对 null context/downstream → panic；已关闭 → `Unavailable`；重复 start → `Ok(unit)`；
- `start` 调度初始 poll（延迟 0）与周期 poll；`polling` 为 true 时跳过重叠轮询；
- `pollOnce` 对 null context → panic；未 start/close → `Unavailable`；不改变调度；
- `poll` 先写临时 offset/partial/recordNumber 映射；读取失败的文件回滚该 path 的临时状态；
  下游成功才整体提交；`reject` 不提交并返回错误；`drop_oldest`/`drop_newest` 提交并返回
  `Ok(unit)`，同时累加丢弃计数；读取失败前已加入的记录可能在下轮重复（at-least-once）；
  `log.file.offset` 记录该条日志读取后的下一字节偏移；
- `stop` 对 null context → panic；未启动 → `Ok(unit)`；取消 timer；
- `drain` 对 null context → panic；关闭后 → `Unavailable`；stop 后仍可冲刷 partial；把每个文件的
  partial 交付；下游 Busy → `Busy`，状态保留；
- `close` 幂等；清空 offsets/partials/recordNumbers；不删除文件；
- `isHealthy` 运行中且最近 poll 无错误为 true；
- `offsets()` 返回副本；不暴露 partial 内容（可能含敏感日志）。

---

## 8. 使用的技术

- glob + PathMatcher；
- 增量偏移；
- 行读取；
- multiline 聚合；
- 临时状态提交/回滚；
- 有界单批；
- 下游背压/显式丢弃；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、String、Long、Int、Bool、List、Map、Result；
- 运行时/FS：`fs.glob`、`fs.fileSize`、`Path.of`、`OpenOptions`、`File.open/seek/readLine/position/close`、`PathMatcher`、`Regex.compile/isMatch`；
- 调度：`Timer.after/every/cancel/shutdown`、`Context`、`nowMono`、`nowWall`；
- 接口：`LogRecord`、`Field`、`Level`、`TelemetryRecord`、`TelemetryBatch`。

---

## 10. 依赖的特性/接口/类

`Receiver`、`TelemetryKind`、`TelemetryBatch`、`TelemetryRecord`、`LogRecord`、`Field`、`Level`、
`Regex`、`PathMatcher`、`File`、`OpenOptions`、`Path`、`fs.glob`、`fs.fileSize`、`truncate`、`Timer`、
`Duration`、`Context`、`Error`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

- 接收器拥有 Timer、offset/partial/record 状态；不拥有 downstream；
- `start`/`stop`/`close` 串行化状态；`pollOnce` 与调度 poll 用 `_polling` 互斥；
- `poll` 不持有监视器调用 downstream；downstream 错误原样返回；
- `offsets`/计数/健康可并发读取；
- 同一文件不应被多个 `FileLogReceiver` 实例同时采集（重复日志）；应用负责唯一性；
- 不跨 Agent 共享同一实例。

---

## 12. 示例与反例

正确：

```xnull
FileLogReceiver receiver = new FileLogReceiver(
    "filelog",
    ["/var/log/app/*.log"],
    ["/var/log/app/*.gz"],
    "end",
    "utf-8",
    200,
    1048576,
    "",
    true,
    true,
    "ignore",
    Level.Info,
    ["service.name":"api"],
    ["log.source":"file"],
    "reject"
)
```

反例：多个实例采集同一文件导致重复；下游 Busy 仍提交 offset 导致丢日志；把日志正文写进错误
描述；默认从文件头重读生产日志；无限 multiline 缓冲；删除文件；把截断当完整记录。

---

## 13. 测试/场景义务

构造校验（glob/startAt/encoding/policy/multiline 编译）；首次从 beginning/end；追加读取；
offset 提交/回滚；下游 Busy 重读；exclude 过滤；multiline 开始/结束/未闭合；超长行截断；
onTruncate 三种；drain 冲刷 partial；stop 后不再 poll；重复 start/stop/close；pollOnce 未启动；
文件权限/不存在；并发 poll；字段包含/不包含；不泄露正文；describe。

---

## 14. XNull 伪代码

```xnull
class FileLogReceiver implements Receiver {
    final String _name
    final List<String> _includePatterns
    final List<PathMatcher> _excludeMatchers
    final String _startAt
    final String _encoding
    final Long _pollIntervalMillis
    final Long _maximumLogBytes
    final String _multilinePattern
    final Regex? _multilineRegex
    final Bool _includeFileName
    final Bool _includeFilePath
    final String _onTruncate
    final Level _defaultLevel
    final Map<String, String> _resource
    final Map<String, String> _attributes
    final String _overflowPolicy
    final Timer _timer
    Long _timerHandle = 0
    Map<String, Long> _offsets = [:]
    Map<String, String> _partials = [:]
    Map<String, Long> _recordNumbers = [:]
    Result<Unit, Error>(TelemetryBatch)? _downstream
    Bool _running = false
    Bool _polling = false
    Bool _closed = false
    Bool _healthy = false
    String _lastError = ""
    Long _lastSuccessMono = 0
    Int _collectedBatches = 0
    Int _droppedRecords = 0
    Int _truncatedRecords = 0
    Int _refusedBatches = 0
    final RuntimeMonitor _monitor

    FileLogReceiver(String name, List<String> includePatterns,
                    List<String> excludePatterns, String startAt,
                    String encoding, Long pollIntervalMillis,
                    Long maximumLogBytes, String multilinePattern,
                    Bool includeFileName, Bool includeFilePath,
                    String onTruncate, Level defaultLevel,
                    Map<String, String> resource,
                    Map<String, String> attributes,
                    String overflowPolicy) {
        if name == null || name == "" {
            throw "FileLogReceiver: empty name"
        }
        if includePatterns == null || includePatterns.length() == 0 {
            throw "FileLogReceiver: no include pattern"
        }
        if startAt != "beginning" && startAt != "end" {
            throw "FileLogReceiver: invalid startAt"
        }
        if encoding != "utf-8" && encoding != "ascii" && encoding != "nop" {
            throw "FileLogReceiver: unsupported encoding"
        }
        if pollIntervalMillis <= 0 {
            throw "FileLogReceiver: poll interval <= 0"
        }
        if maximumLogBytes <= 0 {
            throw "FileLogReceiver: max log bytes <= 0"
        }
        if onTruncate != "ignore" && onTruncate != "read_whole_file"
            && onTruncate != "read_new" {
            throw "FileLogReceiver: invalid onTruncate"
        }
        if defaultLevel == null {
            throw "FileLogReceiver: null default level"
        }
        if overflowPolicy != "reject" && overflowPolicy != "drop_oldest"
            && overflowPolicy != "drop_newest" {
            throw "FileLogReceiver: invalid overflow policy"
        }
        List<PathMatcher> matchers = []
        if excludePatterns != null {
            Int matcherIndex = 0
            while matcherIndex < excludePatterns.length() {
                matchers.push(new PathMatcher(excludePatterns.get(matcherIndex)))
                matcherIndex = matcherIndex + 1
            }
        }
        Regex? compiled = null
        if multilinePattern != null && multilinePattern != "" {
            Result<Regex, Error> result = Regex.compile(multilinePattern)
            if result.isErr() {
                throw "FileLogReceiver: invalid multiline pattern"
            }
            compiled = result.value()
        }
        _name = name
        _includePatterns = includePatterns.copy()
        _excludeMatchers = matchers
        _startAt = startAt
        _encoding = encoding
        _pollIntervalMillis = pollIntervalMillis
        _maximumLogBytes = maximumLogBytes
        _multilinePattern = multilinePattern
        _multilineRegex = compiled
        _includeFileName = includeFileName
        _includeFilePath = includeFilePath
        _onTruncate = onTruncate
        _defaultLevel = defaultLevel
        _resource = resource.copy()
        _attributes = attributes.copy()
        _overflowPolicy = overflowPolicy
        _timer = new Timer()
        _monitor = new RuntimeMonitor()
    }

    TelemetryKind kind() { return TelemetryKind.Logs }
    String name() { return _name }

    Result<Unit, Error> start(Context context,
        Result<Unit, Error>(TelemetryBatch) downstream) {
        if context == null || downstream == null {
            throw "FileLogReceiver.start: null argument"
        }
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable, "closed"))
        }
        if _running {
            _monitor.exit()
            return Ok(unit)
        }
        _downstream = downstream
        _running = true
        _monitor.exit()
        Result<Long, Error> initial = _timer.after(context, Duration.ofMillis(0),
            () -> self.pollTick(context))
        if initial.isErr() {
            _monitor.enter()
            _running = false
            _monitor.exit()
            return Err(initial.error())
        }
        _monitor.enter()
        _timerHandle = initial.value()
        Result<Long, Error> periodic = _timer.every(context,
            Duration.ofMillis(_pollIntervalMillis),
            () -> self.pollTick(context))
        if periodic.isErr() {
            _timer.cancel(_timerHandle)
            _timerHandle = 0
            _running = false
            _monitor.exit()
            return Err(periodic.error())
        }
        _timerHandle = periodic.value()
        _monitor.exit()
        return Ok(unit)
    }

    Result<Unit, Error> stop(Context context) {
        if context == null { throw "FileLogReceiver.stop: null context" }
        _monitor.enter()
        if !_running {
            _monitor.exit()
            return Ok(unit)
        }
        _running = false
        if _timerHandle != 0 { _timer.cancel(_timerHandle) }
        _timerHandle = 0
        _monitor.exit()
        return Ok(unit)
    }

    Result<Unit, Error> drain(Context context) {
        if context == null { throw "FileLogReceiver.drain: null context" }
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable, "closed"))
        }
        _monitor.exit()
        List<TelemetryRecord> records = []
        List<String> paths = self.partialPaths()
        Int index = 0
        while index < paths.length() {
            String path = paths.get(index)
            String partial = _partials.getOr(path, "")
            if partial != "" {
                records.push(self.makeRecord(path, partial,
                    _recordNumbers.getOr(path, 0),
                    _offsets.getOr(path, 0)))
            }
            index = index + 1
        }
        if records.length() == 0 { return Ok(unit) }
        Result<Unit, Error> delivered = self.deliver(records)
        if delivered.isErr() { return delivered }
        _monitor.enter()
        index = 0
        while index < paths.length() {
            String path = paths.get(index)
            _partials.put(path, "")
            _recordNumbers.put(path, _recordNumbers.getOr(path, 0) + 1)
            index = index + 1
        }
        _monitor.exit()
        return Ok(unit)
    }

    Result<Unit, Error> close() {
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return Ok(unit)
        }
        _closed = true
        _running = false
        if _timerHandle != 0 { _timer.cancel(_timerHandle) }
        _timerHandle = 0
        _offsets.clear()
        _partials.clear()
        _recordNumbers.clear()
        _monitor.exit()
        _timer.shutdown()
        return Ok(unit)
    }

    Bool isRunning() { return _running }
    Bool isHealthy() { return _running && _healthy }
    Map<String, Long> offsets() { return _offsets.copy() }
    Long lastSuccessMono() { return _lastSuccessMono }
    Int collectedBatches() { return _collectedBatches }
    Int droppedRecords() { return _droppedRecords }
    Int refusedBatches() { return _refusedBatches }
    Int truncatedRecords() { return _truncatedRecords }

    Result<Unit, Error> pollOnce(Context context) {
        if context == null { throw "FileLogReceiver.pollOnce: null context" }
        if !_running { return Err(new BasicError(ErrorKind.Unavailable,
            "not running")) }
        return self.poll(context)
    }

    void pollTick(Context context) {
        self.pollScheduled(context)
    }

    Result<Unit, Error> pollScheduled(Context context) {
        if !_running || context.isCancelled() { return Ok(unit) }
        return self.poll(context)
    }

    Result<Unit, Error> poll(Context context) {
        _monitor.enter()
        if _polling {
            _monitor.exit()
            return Ok(unit)
        }
        _polling = true
        _monitor.exit()
        List<String> paths = self.listFiles()
        Map<String, Long> nextOffsets = _offsets.copy()
        Map<String, String> nextPartials = _partials.copy()
        Map<String, Long> nextNumbers = _recordNumbers.copy()
        List<TelemetryRecord> records = []
        String firstError = ""
        Int index = 0
        while index < paths.length() {
            String path = paths.get(index)
            Result<Unit, Error> read = self.readFile(context, path,
                nextOffsets, nextPartials, nextNumbers, records)
            if read.isErr() {
                self.restore(path, nextOffsets, nextPartials, nextNumbers)
                if firstError == "" {
                    firstError = read.error().describe()
                }
            }
            index = index + 1
        }
        if records.length() == 0 {
            _monitor.enter()
            _polling = false
            if firstError == "" {
                _healthy = true
                _lastSuccessMono = nowMono()
            } else {
                _healthy = false
                _lastError = firstError
            }
            _monitor.exit()
            if firstError != "" {
                return Err(new BasicError(ErrorKind.Io, firstError))
            }
            return Ok(unit)
        }
        Result<Unit, Error> delivered = self.deliver(records)
        _monitor.enter()
        _polling = false
        if delivered.isErr() {
            _lastError = delivered.error().describe()
            if _overflowPolicy == "reject" {
                _refusedBatches = _refusedBatches + 1
                _healthy = false
                _monitor.exit()
                return delivered
            }
            _droppedRecords = _droppedRecords + records.length()
            _offsets = nextOffsets
            _partials = nextPartials
            _recordNumbers = nextNumbers
            _collectedBatches = _collectedBatches + 1
            _lastSuccessMono = nowMono()
            _healthy = false
            _monitor.exit()
            return Ok(unit)
        }
        _offsets = nextOffsets
        _partials = nextPartials
        _recordNumbers = nextNumbers
        _collectedBatches = _collectedBatches + 1
        _lastSuccessMono = nowMono()
        if firstError == "" {
            _healthy = true
        } else {
            _healthy = false
            _lastError = firstError
        }
        _monitor.exit()
        return Ok(unit)
    }

    Result<Unit, Error> deliver(List<TelemetryRecord> records) {
        if _downstream == null {
            return Err(new BasicError(ErrorKind.Unavailable,
                "no downstream"))
        }
        TelemetryBatch batch = new TelemetryBatch(TelemetryKind.Logs,
            _resource, records, 0, nowMono())
        return _downstream(batch)
    }

    Result<Unit, Error> readFile(Context context, String path,
                                 Map<String, Long> nextOffsets,
                                 Map<String, String> nextPartials,
                                 Map<String, Long> nextNumbers,
                                 List<TelemetryRecord> records) {
        Result<Long, Error> sizeResult = fs.fileSize(path)
        if sizeResult.isErr() { return Err(sizeResult.error()) }
        Long size = sizeResult.value()
        Long offset = 0
        if nextOffsets.has(path) { offset = nextOffsets.getOr(path, 0) }
        else if _startAt == "end" { offset = size }
        if size < offset {
            if _onTruncate == "ignore" {
                return Ok(unit)
            }
            if _onTruncate == "read_whole_file" { offset = 0 }
            if _onTruncate == "read_new" { offset = size }
            nextOffsets.put(path, offset)
        }
        Result<File, Error> opened = File.open(Path.of(path),
            OpenOptions.read())
        if opened.isErr() { return Err(opened.error()) }
        File file = opened.value()
        Result<Unit, Error> seeked = file.seek(offset, SeekOrigin.Begin)
        if seeked.isErr() {
            file.close()
            return Err(seeked.error())
        }
        Long number = 0
        if nextNumbers.has(path) { number = nextNumbers.getOr(path, 0) }
        while true {
            if context.isCancelled() {
                file.close()
                return Err(new BasicError(ErrorKind.Cancelled, "cancelled"))
            }
            Result<String?, Error> line = file.readLine(context)
            if line.isErr() {
                file.close()
                return Err(line.error())
            }
            if line.value() == null { break }
            String text = line.value()
            if text.length() > _maximumLogBytes {
                text = truncate(text, _maximumLogBytes as Int)
                _monitor.enter()
                _truncatedRecords = _truncatedRecords + 1
                _monitor.exit()
            }
            Long position = file.position()
            nextOffsets.put(path, position)
            if _multilineRegex != null {
                String partial = ""
                if nextPartials.has(path) { partial = nextPartials.getOr(path, "") }
                if _multilineRegex.isMatch(text) {
                    if partial != "" {
                        records.push(self.makeRecord(path, partial, number,
                            position))
                        number = number + 1
                    }
                    nextPartials.put(path, text)
                } else {
                    if partial == "" {
                        partial = text
                    } else {
                        partial = partial + "\n" + text
                    }
                    if partial.length() > _maximumLogBytes {
                        partial = truncate(partial, _maximumLogBytes as Int)
                    }
                    nextPartials.put(path, partial)
                }
            } else {
                records.push(self.makeRecord(path, text, number, position))
                number = number + 1
            }
        }
        nextNumbers.put(path, number)
        file.close()
        return Ok(unit)
    }

    void restore(String path, Map<String, Long> nextOffsets,
                 Map<String, String> nextPartials,
                 Map<String, Long> nextNumbers) {
        if _offsets.has(path) {
            nextOffsets.put(path, _offsets.getOr(path, 0))
        } else {
            nextOffsets.remove(path)
        }
        if _partials.has(path) {
            nextPartials.put(path, _partials.getOr(path, ""))
        } else {
            nextPartials.remove(path)
        }
        if _recordNumbers.has(path) {
            nextNumbers.put(path, _recordNumbers.getOr(path, 0))
        } else {
            nextNumbers.remove(path)
        }
    }

    List<String> listFiles() {
        List<String> result = []
        Int patternIndex = 0
        while patternIndex < _includePatterns.length() {
            Result<List<String>, Error> matched =
                fs.glob(_includePatterns.get(patternIndex))
            if matched.isOk() {
                List<String> paths = matched.value()
                Int index = 0
                while index < paths.length() {
                    String path = paths.get(index)
                    if !self.isExcluded(path) && !self.contains(result, path) {
                        result.push(path)
                    }
                    index = index + 1
                }
            }
            patternIndex = patternIndex + 1
        }
        return result
    }

    Bool isExcluded(String path) {
        Int index = 0
        while index < _excludeMatchers.length() {
            if _excludeMatchers.get(index).matchesText(path) { return true }
            index = index + 1
        }
        return false
    }

    List<String> partialPaths() {
        List<String> result = []
        List<String> paths = _partials.keys()
        Int index = 0
        while index < paths.length() {
            if _partials.getOr(paths.get(index), "") != "" {
                result.push(paths.get(index))
            }
            index = index + 1
        }
        return result
    }

    TelemetryRecord makeRecord(String path, String body, Long recordNumber,
                               Long byteOffset) {
        List<Field> fields = []
        if _includeFileName {
            fields.push(new Field("log.file.name", Path.of(path).name()))
        }
        if _includeFilePath {
            fields.push(new Field("log.file.path", path))
        }
        fields.push(new Field("log.file.offset", str(byteOffset)))
        fields.push(new Field("log.file.record_number", str(recordNumber)))
        List<String> keys = _attributes.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            fields.push(new Field(key, _attributes.getOr(key, "")))
            index = index + 1
        }
        LogRecord logRecord = new LogRecord(_defaultLevel, _name, body, fields,
            nowMono(), nowWall(), null)
        return TelemetryRecord.log(logRecord)
    }

    Bool contains(List<String> values, String value) {
        Int index = 0
        while index < values.length() {
            if values.get(index) == value { return true }
            index = index + 1
        }
        return false
    }

    String describe() {
        return "filelog " + _name + " include=" + str(_includePatterns.length())
            + " interval=" + str(_pollIntervalMillis) + "ms"
    }
}
```

> `Path.name()`、`File.readLine(context)`、`File.position()`、`fs.glob`/`fs.fileSize`/`truncate`
> 是 `xdk.fs`/`xdk.text` 的现有或运行时支撑；`_encoding` 在基线只用于校验，UTF-16 解码为 X。
