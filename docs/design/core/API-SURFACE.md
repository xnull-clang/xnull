# `xdk.core` API 面

> **2.x 状态**：本文件是旧版 core API 广度稿，不是实现依据。包名/类型以 [`../PACKAGE-MAP.md`](../PACKAGE-MAP.md) 与逐类型合同为准；`tasks/sync` 在 2.x 归并为 `xdk.execution`。

> 当前领域设计见 [`OVERVIEW.md`](OVERVIEW.md)；本文件列出 core 的 API 广度与方法面，不声明当前目录/顺序。


| 项 | 值 |
| --- | --- |
| 范围 | `errors`、`runtime`、`meta`、`bytes`、`text`、`collections`、`math`、`time`、`io`、`fs`、`sys`、`log`、`config`、`cli`、执行层内建 `tasks/sync` |
| 目标 | 对齐业界标准库的常规方法面；从 C1 提升到 C3 |
| 规则 | 只写方案；不写代码；不讨论编译器/FFI |
| 记号 | `K` = 基础面；`X` = 扩展面；`—` = 不属于 core |

---

## 0. 通用规则

- 可恢复失败：`Result<T, Error>`；无值：`Result<Unit, Error>`。
- 可阻塞方法首参 `Context`；取消 `Cancelled`，超时 `Timeout`。
- 资源类：`isOpen()` + 幂等 `close()`。
- 参数全名；布尔参数 `is/has/can/should`。
- 容器方法：查询不修改；修改方法返回 `Bool`/旧值/`Result`，按语义定。
- 本节方法清单是 **API 面**，不是实现承诺；未标 `K` 的为 `X` 或 ``。

---

## 1. `xdk.errors`

**职责**：错误分类、构造、包装、报告、聚合、重试、Result 组合。  
**依赖**：无（仅运行时诊断）。  
**业界对齐**：Go `errors`、Rust `Result`、Java exceptions、.NET exceptions。

### 1.1 类型

| 类型 | 种类 | 能力 |
| --- | --- | --- |
| `ErrorKind` | enum | 14 类稳定失败分类 |
| `Error` | protocol | `kind()` + `describe()` |
| `DetailedError` | protocol | `kind/describe/message/code` |
| `ErrorDetail` | class | 不可变 key/value |
| `BasicError` | class | 基础错误 + code/details/causes |
| `ErrorReport` | class | 步骤链 |
| `ErrorGroup` | class | 多错误聚合 |
| `RetryPolicy` | class | 重试策略 |
| `ErrorMatcher` | class | 错误匹配 |
| `ErrorCollector` | class | 错误收集器 |
| `ErrorSink` | protocol | 错误观测出口 |
| `ErrorCode` | class | 稳定错误码 + 分类 |

### 1.2 `BasicError`

| 能力组 | 方法 |
| --- | --- |
| 构造 | `BasicError(ErrorKind kind, String message)`、`BasicError.of(ErrorKind kind)`、`BasicError.fromCode(ErrorCode code)` |
| 读取 | `kind()`、`message()`、`code()`、`describe()`、`details()`、`causes()`、`hasCode()`、`hasDetails()`、`hasCauses()`、`detailCount()`、`causeCount()` |
| 派生 | `withCode(code)`、`withDetail(key,value)`、`withDetails(list)`、`withCause(error)`、`withCauses(list)`、`withMessage(message)`、`copy()` |
| 判定 | `isKind(kind)`、`hasCode(code)`、`matches(matcher)`、`rootCause()`、`chain()` |

### 1.3 `ErrorReport`

`root()`、`steps()`、`stepCount()`、`withStep(step)`、`withSteps(list)`、`tryWithStep(step)`、`tryWithSteps(list)`、`withoutStep(index)`、`clearSteps()`、`kind()`、`message()`、`code()`、`describe()`、`details()`、`causes()`、`toBasicError()`。

### 1.4 `ErrorGroup`

`add(error)`、`addAll(errors)`、`addResult(result)`、`length()`、`isEmpty()`、`first()`、`last()`、`kind()`、`message()`、`code()`、`describe()`、`details()`、`causes()`、`toList()`、`toErrorReport()`、`clear()`、`remove(index)`、`contains(error)`。

### 1.5 `RetryPolicy`

`RetryPolicy()`、`maxAttempts(count)`、`initialDelay(Duration)`、`maxDelay(Duration)`、`multiplier(Double)`、`jitter(Double)`、`retryOn(List<ErrorKind>)`、`shouldRetry(Error error, Int attempt)`、`delayFor(Int attempt)`、`reset()`、`describe()`。

### 1.6 `ErrorMatcher` / `ErrorCollector` / `ErrorSink` / `ErrorCode`

`ErrorMatcher`：`ErrorMatcher()`、`kind(kind)`、`code(code)`、`messageContains(text)`、`matches(Error)`、`describe()`。  
`ErrorCollector`：`add(error)`、`addResult(result)`、`addAll(list)`、`hasErrors()`、`length()`、`first()`、`toGroup()`、`clear()`。  
`ErrorSink`：`void report(Error error)`；实现不得改变控制流。  
`ErrorCode`：`ErrorCode(ErrorKind kind, String code, String message)`、`kind()`、`code()`、`message()`、`describe()`。

### 1.7 顶层函数

| 组 | 函数 |
| --- | --- |
| 构造/校验 | `tryErrorDetail`、`isValidDetailKey`、`isValidDetailValue`、`isValidErrorCode` |
| 包装/观测 | `wrap`、`report`、`reportTo(sink, result)`、`annotate`、`toErrorReport` |
| 分类 | `isRetryable`、`isRetryableError`、`errorKindName`、`errorKindDisplayName`、`errorKindFromName`、`errorKindCode`、`errorKindFromCode` |
| Result 组合 | `mapOk`、`mapErr`、`andThen`、`orElse`、`unwrapOr`、`expect`、`inspect`、`inspectErr`、`filterOk`、`zip`、`zipWith`、`collectOk`、`collectAll`、`flattenResult`、`check`、`retry`、`recover`、`tap`、`tapErr`、`mapBoth` |
| 批量 | `collectOk`、`collectAll`、`partitionResults`、`firstOk`、`firstErr` |

---

## 2. `xdk.runtime`

**职责**：诊断、退出、时钟、运行时信息、任务/内存统计。  
**业界对齐**：Go runtime、Java Runtime、.NET Environment。

### 2.1 类型

| 类型 | 方法 |
| --- | --- |
| `RuntimeInfo` | `languageVersion()`、`xdkVersion()`、`targetPlatform()`、`architecture()`、`buildMode()`、`pid()`、`hostname()`、`cwd()`、`startTimeMono()`、`uptimeMillis()`、`describe()` |
| `MemoryStats` | `heapUsed()`、`heapTotal()`、`external()`、`peak()`、`gcCount()`、`describe()` |
| `TaskStats` | `active()`、`queued()`、`completed()`、`failed()`、`cancelled()`、`describe()` |

### 2.2 顶层函数

`diagnose(message)`、`diagnoseFormat(...)`、`exit(code)`、`abort(message)`、`nowMono()`、`nowWall()`、`nowMicros()`、`runtimeInfo()`、`memoryStats()`、`taskStats()`、`dumpTasks()`、`stackTrace()`。

> `sleep` 归 `time`；`env`/`pid` 归 `sys`；`runtime` 只保留运行时观测。

---

## 3. `xdk.meta`

**职责**：版本、目标平台、构建信息、能力矩阵。  
**业界对齐**：Go build info、Java manifest、.NET assembly info。

### 3.1 类型

| 类型 | 方法 |
| --- | --- |
| `BuildInfo` | `languageVersion()`、`xdkVersion()`、`targetPlatform()`、`architecture()`、`buildMode()`、`buildId()`、`dependencyVersion(packageName)`、`dependencies()`、`describe()` |
| `TargetInfo` | `os()`、`arch()`、`family()`、`pointerBits()`、`endian()`、`hasThreads()`、`hasNetwork()`、`hasTls()`、`hasFilesystem()`、`hasProcess()`、`hasSignals()` |
| `Capability` | enum：`Threads`、`Network`、`Tls`、`Filesystem`、`Process`、`Signals`、`Unicode`、`Regex`、`Compression`、`Crypto`、`Random`、`DynamicLibrary` |

### 3.2 顶层函数

`languageVersion()`、`xdkVersion()`、`targetPlatform()`、`buildInfo()`、`targetInfo()`、`hasCapability(capability)`、`targetCapabilities()`、`dependencyVersion(packageName)`。

---

## 4. `xdk.bytes`

**职责**：字节序列、构建器、缓冲、读写、端序、位集。  
**业界对齐**：Go `bytes`、Java `ByteBuffer`、.NET `Span<byte>`、Python `bytes/bytearray`。

### 4.1 类型

| 类型 | 能力 |
| --- | --- |
| `Bytes` | 可变字节序列 |
| `BytesBuilder` | 可增长构建器 |
| `ByteBuffer` | position/limit/capacity 缓冲 |
| `ByteReader` | 顺序/随机读 |
| `ByteWriter` | 顺序写 |
| `BitSet` | 位集合 |
| `ByteOrder` | BigEndian/LittleEndian |
| `BytesView` | 零拷贝切片（X） |

### 4.2 `Bytes`

| 能力组 | 方法 |
| --- | --- |
| 构造 | `Bytes.alloc(length)`、`Bytes.fromUtf8(text)`、`Bytes.fromHex(text)`、`Bytes.fromString(text)`、`Bytes.wrap(array)`（X） |
| 查询 | `length()`、`isEmpty()`、`get(index)`、`tryGet(index)`、`indexOf(value)`、`lastIndexOf(value)`、`contains(value)`、`startsWith(prefix)`、`endsWith(suffix)`、`compare(other)`、`equals(other)`、`toHex()`、`toUtf8()`、`toArray()` |
| 修改 | `set(index,value)`、`trySet(index,value)`、`push(value)`、`append(bytes)`、`insert(index,value)`、`remove(index)`、`removeRange(start,end)`、`fill(value)`、`reverse()`、`clear()` |
| 切片/复制 | `slice(start,end)`、`sliceChecked(start,end)`、`copy()`、`view(start,end)`（X） |

### 4.3 `BytesBuilder`

`BytesBuilder()`、`BytesBuilder(initialCapacity)`、`appendByte(value)`、`append(bytes)`、`appendUtf8(text)`、`appendHex(text)`、`appendInt(value)`、`appendLong(value)`、`appendDouble(value)`、`appendBool(value)`、`insert(index,bytes)`、`length()`、`capacity()`、`reserve(minimumCapacity)`、`clear()`、`build()`、`take()`。

### 4.4 `ByteBuffer`

| 能力组 | 方法 |
| --- | --- |
| 状态 | `capacity()`、`position()`、`position(newPosition)`、`limit()`、`limit(newLimit)`、`remaining()`、`hasRemaining()`、`mark()`、`reset()`、`clear()`、`flip()`、`rewind()`、`compact()` |
| 读 | `get()`、`get(index)`、`getU8()`、`getI8()`、`getU16(order)`、`getI16(order)`、`getU32(order)`、`getI32(order)`、`getU64(order)`、`getI64(order)`、`getF32(order)`、`getF64(order)`、`getBytes(count)`、`getSlice(count)` |
| 写 | `put(value)`、`put(index,value)`、`putU8/I8/U16/I16/U32/I32/U64/I64/F32/F64`、`putBytes(bytes)`、`putSlice(source)` |
| 视图 | `order()`、`order(newOrder)`、`slice()`、`duplicate()`、`asReadOnly()`、`array()`、`hasArray()` |

### 4.5 `ByteReader`

`ByteReader(bytes)`、`position()`、`limit()`、`remaining()`、`hasRemaining()`、`seek(offset)`、`skip(count)`、`mark()`、`reset()`、`peek()`、`readU8()`、`readI8()`、`readU16BE/LE()`、`readI16BE/LE()`、`readU32BE/LE()`、`readI32BE/LE()`、`readU64BE/LE()`、`readI64BE/LE()`、`readF32BE/LE()`、`readF64BE/LE()`、`readBytes(count)`、`readExact(count)`、`readAll()`、`readLine()`、`readUntil(delimiter)`、`readInto(target)`、`readUtf8(count)`、`readHex(count)`、`tryReadU8()` 等 checked 版本。

### 4.6 `ByteWriter`

`ByteWriter()`、`length()`、`capacity()`、`writeU8/I8/U16/I16/U32/I32/U64/I64/F32/F64`、`writeBytes(bytes)`、`writeUtf8(text)`、`writeHex(text)`、`writeLine(text)`、`writeZeros(count)`、`toBytes()`、`takeBytes()`、`clear()`、`reserve(minimumCapacity)`、`flush()`（无资源时 no-op）。

### 4.7 `BitSet`

`BitSet()`、`BitSet(size)`、`set(index)`、`set(index,value)`、`clear(index)`、`clearAll()`、`get(index)`、`flip(index)`、`cardinality()`、`length()`、`size()`、`isEmpty()`、`nextSetBit(from)`、`previousSetBit(from)`、`and(other)`、`or(other)`、`xor(other)`、`andNot(other)`、`intersects(other)`、`toBytes()`、`fromBytes(bytes)`。

### 4.8 顶层函数

| 组 | 函数 |
| --- | --- |
| 转换 | `fromUtf8`、`toUtf8`、`fromHex`、`tryFromHex`、`toHex`、`byteLength`、`isEmptyBytes`、`concatBytes`、`copy`、`equals`、`compare`、`slice`、`sliceChecked`、`tryGetByte`、`trySetByte` |
| 端序 | `u16BE/LE`、`i16BE/LE`、`u32BE/LE`、`i32BE/LE`、`u64BE/LE`、`i64BE/LE`、`readShort/Int/Long`、checked 版本 |
| 位 | `bitAnd/Or/Xor/Not`、`shiftLeft/Right`、`popCount`、`leadingZeros`、`trailingZeros`、`rotateLeft/Right`、`reverseBits`、`byteSwap`、`isPowerOfTwo`、`nextPowerOfTwo`、`mask`、`extract`、`insert`、`Long` 版本 |

---

## 5. `xdk.text`

**职责**：文本变换、构建、格式化、解析、Unicode、正则。  
**业界对齐**：Go `strings`、Java `String/StringBuilder`、Python `str`、.NET `string`。

### 5.1 类型

`StringBuilder`、`StringJoiner`、`Format`、`Regex`、`Match`、`Utf16`、`Unicode`、`Escape`、`FormatSpec`。

### 5.2 `StringBuilder`

`StringBuilder()`、`StringBuilder(capacity)`、`append(text)`、`appendChar(c)`、`appendInt(v)`、`appendLong(v)`、`appendDouble(v)`、`appendBool(v)`、`appendLine(text)`、`appendFormat(format, values...)`、`insert(index,text)`、`delete(start,end)`、`replace(start,end,text)`、`reverse()`、`length()`、`capacity()`、`charAt(index)`、`setCharAt(index,c)`、`substring(start,end)`、`ensureCapacity(minimum)`、`clear()`、`build()`。

### 5.3 `StringJoiner`

`StringJoiner(separator)`、`StringJoiner(separator,prefix,suffix)`、`add(text)`、`addAll(list)`、`length()`、`build()`、`clear()`、`isEmpty()`。

### 5.4 `Format`

| 能力组 | 方法 |
| --- | --- |
| 工厂 | `Format.int(value)`、`Format.long(value)`、`Format.float(value)`、`Format.double(value)`、`Format.bool(value)`、`Format.char(value)`、`Format.string(value)`、`Format.bytes(value)`、`Format.hex(value)`、`Format.binary(value)` |
| 选项 | `width(n)`、`precision(n)`、`pad(c)`、`alignLeft()`、`alignRight()`、`alignCenter()`、`sign(mode)`、`group(bool)`、`upper()`、`lower()`、`zeroPad()`、`build()` |

### 5.5 `Regex` / `Match`

`Regex.compile(pattern)`、`Regex.compile(pattern, options)`、`isMatch(text)`、`find(text)`、`findFirst(text)`、`findAll(text)`、`matchAll(text)`、`replaceAll(text,replacement)`、`replaceFirst(text,replacement)`、`replaceAllWith(text,callback)`（X）、`split(text)`、`splitLimit(text,limit)`、`groups()`、`namedGroups()`、`pattern()`、`options()`、`escape(text)`。  
`Match`：`start()`、`end()`、`length()`、`group(index)`、`groups()`、`groupCount()`、`namedGroup(name)`、`namedGroups()`、`text()`、`isMatch()`。

### 5.6 `Utf16` / `Unicode` / `Escape`

`Utf16`：`length()`、`get(index)`、`units()`、`toList()`、`fromString(text)`、`toString()`。  
`Unicode`：`isLetter(c)`、`isDigit(c)`、`isWhitespace(c)`、`isUpper(c)`、`isLower(c)`、`isTitle(c)`、`toUpper(c)`、`toLower(c)`、`caseFold(text)`、`normalize(text,form)`、`codePointAt(text,index)`、`charCount(codePoint)`、`isSurrogate(c)`、`decode(bytes)`、`encode(text)`。  
`Escape`：`json(text)`、`unescapeJson(text)`、`html(text)`、`xml(text)`、`csv(text)`、`shell(text)`、`quoted(text)`、`unquote(text)`。

### 5.7 顶层函数

| 组 | 函数 |
| --- | --- |
| 判断 | `contains`、`startsWith`、`endsWith`、`indexOf`、`lastIndexOf`、`containsAny`、`countText`、`isEmpty`、`isBlank`、`isAscii`、`isNumeric`、`isAlpha`、`isAlnum`、`isLower`、`isUpper`、`equalsIgnoreCase`、`compareIgnoreCase` |
| 变换 | `trim`、`trimStart`、`trimEnd`、`stripIndent`、`normalizeWhitespace`、`split`、`splitLines`、`splitWhitespace`、`replace`、`replaceFirst`、`replaceAll`、`removePrefix`、`removeSuffix`、`reverse`、`capitalize`、`decapitalize`、`truncate`、`wrap`、`indent`、`padLeft`、`padRight`、`repeatText`、`repeatJoined` |
| 解析 | `parseInt`、`parseLong`、`parseFloat`、`parseDouble`、`parseBool`、`parseHexInt`、`parseBinaryInt` |
| 格式化 | `formatInt`、`formatLong`、`formatFloat`、`formatDouble`、`formatBool`、`formatHex`、`formatBinary`、`formatBytes` |
| Unicode | `utf8ToUtf16`、`utf16ToUtf8`、`codePoints`、`codePointAt`、`codePointLen`、`fromCodePoint`、`decodeCodePoint` |
| 正则 | `regexCompile`、`regexIsMatch`、`regexFind`、`regexFindAll`、`regexReplaceAll` |

---

## 6. `xdk.collections`

**职责**：容器、算法、专用容器。  
**业界对齐**：Java Collections、Go slices/maps、Python list/dict/set、.NET Collections。

### 6.1 类型

| 类型 | 能力 |
| --- | --- |
| `List<T>` | 有序、可重复、索引 |
| `Map<K,V>` | 键唯一、查找/替换/删除 |
| `Set<T>` | 元素唯一 |
| `Deque<T>` | 双端队列 |
| `Stack<T>` | 栈 |
| `Queue<T>` | 队列 |
| `PriorityQueue<T>` | 最小堆 |
| `RingBuffer<T>` | 固定容量环形缓冲 |
| `OrderedMap<V>` | Int 键插入序 |
| `BTreeMap<V>` | Int 键有序 |
| `MultiMap<K,V>` | 一键多值 |
| `BiMap<K,V>` | 双向映射 |
| `LRUCache<K,V>` | 容量淘汰 |
| `Pair` / `Triple` | 值对象 |
| `Iterator<T>` / `Iterable<T>` | 迭代（X） |
| `IntRange` | 整数区间 |

### 6.2 `List<T>`

| 能力组 | 方法 |
| --- | --- |
| 查询 | `length()`、`isEmpty()`、`get(index)`、`tryGet(index)`、`first()`、`last()`、`indexOf(value)`、`lastIndexOf(value)`、`contains(value)`、`containsAll(values)`、`toArray()` |
| 修改 | `set(index,value)`、`trySet(...)`、`push(value)`、`addAll(values)`、`insert(index,value)`、`insertAll(index,values)`、`remove(index)`、`removeValue(value)`、`removeIf(predicate)`、`retainIf(predicate)`、`clear()`、`fill(value)`、`swap(i,j)` |
| 变换 | `reverse()`、`sort(comparator)`、`sortBy(lessThan)`、`shuffle()`、`copy()`、`slice(start,end)`、`sublist(start,end)`、`join(separator)`、`min()`、`max()` |

### 6.3 `Map<K,V>`

| 能力组 | 方法 |
| --- | --- |
| 查询 | `length()`、`isEmpty()`、`has(key)`、`get(key)`、`getOr(key,fallback)`、`tryGet(key)`、`containsValue(value)`、`count(predicate)`、`any(predicate)`、`all(predicate)`、`keys()`、`values()`、`entries()` |
| 修改 | `put(key,value)`、`putIfAbsent(key,value)`、`putAll(other)`、`replace(key,value)`、`replaceIf(key,expected,value)`、`replaceAll(transform)`、`compute(key,remap)`、`computeIfAbsent(key,mapping)`、`merge(key,value,combine)`、`remove(key)`、`removeIf(predicate)`、`removeOr(key,fallback)`、`clear()`、`copy()` |

### 6.4 `Set<T>`

`length()`、`isEmpty()`、`has(value)`、`add(value)`、`addAll(values)`、`remove(value)`、`removeAll(values)`、`retainAll(values)`、`clear()`、`union(other)`、`intersection(other)`、`difference(other)`、`isSubset(other)`、`isSuperset(other)`、`toList()`、`copy()`。

### 6.5 专用容器

| 类型 | 方法 |
| --- | --- |
| `Deque<T>` | `pushFront`、`pushBack`、`popFront`、`popBack`、`peekFront`、`peekBack`、`length`、`isEmpty`、`clear` |
| `Stack<T>` | `push`、`pop`、`peek`、`length`、`isEmpty`、`clear` |
| `Queue<T>` | `enqueue`、`dequeue`、`peek`、`length`、`isEmpty`、`clear` |
| `PriorityQueue<T>` | `PriorityQueue(lessThan)`、`push`、`pop`、`peek`、`remove(value)`、`contains(value)`、`length`、`isEmpty`、`clear`、`toList` |
| `RingBuffer<T>` | `RingBuffer(capacity)`、`push`、`pop`、`peek`、`length`、`capacity`、`isEmpty`、`isFull`、`clear`、`toList`、`drain` |
| `OrderedMap<V>` | `length`、`has`、`get`、`getOr`、`put`、`remove`、`keys`、`values`、`entries`、`clear`、`firstKey`、`lastKey` |
| `BTreeMap<V>` | 同 `OrderedMap` + `floorKey`、`ceilingKey`、`lowerKey`、`higherKey`、`range(from,to)`、`descendingKeys` |
| `MultiMap<K,V>` | `put`、`get`、`getAll`、`remove`、`removeAll`、`keys`、`entries`、`size`、`clear` |
| `BiMap<K,V>` | `put`、`get`、`getKey`、`inverse`、`remove`、`keys`、`values`、`clear` |
| `LRUCache<K,V>` | `LRUCache(capacity)`、`get`、`put`、`getOrLoad`、`remove`、`containsKey`、`size`、`capacity`、`clear`、`stats` |

### 6.6 算法

| 组 | 函数 |
| --- | --- |
| 排序/查找 | `sort`、`stableSort`、`sortBy`、`sortedBy`、`isSortedBy`、`reverse`、`shuffle`、`binarySearch`、`binarySearchBy`、`lowerBound`、`upperBound` |
| 查询 | `find`、`findIndex`、`findAll`、`any`、`all`、`none`、`countIf`、`min`、`max`、`minBy`、`maxBy` |
| 变换 | `map`、`flatMap`、`filter`、`reject`、`reduce`、`fold`、`scan`、`dedup`、`distinct`、`partition`、`chunk`、`window`、`zip`、`unzip`、`flattenList`、`join` |
| 集合 | `union`、`intersection`、`difference`、`frequency`、`topK`、`groupBy`、`groupByInt` |
| 组合 | `permutations`、`combinations`、`cartesianProduct` |

### 6.7 迭代（X / ）

`Iterator<T>`：`hasNext()`、`next()`、`remove()`、`close()`。  
`Iterable<T>`：`iterator()`。  
`IntRange`：`start()`、`end()`、`step()`、`contains(value)`、`length()`、`toList()`。

---

## 7. `xdk.math`

**职责**：数学、整数、Decimal、统计。  
**业界对齐**：Go `math`、Java `Math/BigDecimal`、Python `math/statistics`、.NET `Math/decimal`。

### 7.1 类型

| 类型 | 能力 |
| --- | --- |
| `RoundingMode` | 取整模式 |
| `Decimal` | 十进制定点/浮点（金额/精确计算） |
| `Int128` | 语言标量 |
| `Complex`（X） | 复数 |
| `Stats` | 统计函数组 |

### 7.2 `Decimal`

`Decimal.parse(text)`、`Decimal.fromInt(value)`、`Decimal.fromLong(value)`、`Decimal.fromDouble(value)`、`add(other)`、`sub(other)`、`mul(other)`、`div(other,scale,mode)`、`mod(other)`、`negate()`、`abs()`、`compare(other)`、`equals(other)`、`scale()`、`setScale(scale,mode)`、`round(scale,mode)`、`floor()`、`ceil()`、`truncate()`、`toInt()`、`toLong()`、`toDouble()`、`isZero()`、`isNegative()`、`toString()`。

### 7.3 `RoundingMode`

`Up`、`Down`、`Ceiling`、`Floor`、`HalfUp`、`HalfDown`、`HalfEven`、`Unnecessary`。

### 7.4 顶层函数

| 组 | 函数 |
| --- | --- |
| 常量/判定 | `PI`、`E`、`TAU`、`Inf`、`NaN`、`isNaN`、`isInf`、`isFinite`、`sign` |
| 取整/比较 | `abs`、`absI`、`min`、`max`、`minI`、`maxI`、`clamp`、`clampI`、`floor`、`ceil`、`round`、`trunc`、`floorToInt`、`ceilToInt`、`roundToInt`、`truncToInt` |
| 算术 | `mod`、`rem`、`pow`、`sqrt`、`cbrt`、`hypot`、`exp`、`log`、`log2`、`log10` |
| 三角 | `sin`、`cos`、`tan`、`asin`、`acos`、`atan`、`atan2`、`sinh`、`cosh`、`tanh`、`deg2rad`、`rad2deg` |
| 插值 | `lerp`、`smoothstep`、`mapRange` |
| 数论 | `gcd`、`lcm`、`isPrime`、`nextPrime`、`primeFactors`、`factorial`、`binomial`、`permutations`、`combinations` |
| 整数 | `maxIntValue`、`minIntValue`、`maxLongValue`、`minLongValue`、`addIntChecked`、`subIntChecked`、`mulIntChecked`、`divIntChecked`、`modIntChecked`、`negIntChecked`、`absIntChecked`、Long 版本、saturating 版本 |
| Int128 | `int128Min`、`int128Max`、`addI128Checked`、`subI128Checked`、`mulI128Checked`、`divI128Checked`、`modI128Checked`、`negI128Checked`、`absI128Checked` |
| 统计 | `sum`、`product`、`mean`、`median`、`mode`、`variance`、`stddev`、`quantile`、`percentile`、`range`、`min`、`max`、`covariance`、`correlation`、`linearRegression`、`histogram`、`movingAverage`、`ema`、`zscore` |

---

## 8. `xdk.time`

**职责**：时长、时间点、日期、时间、时区、格式化、计时。  
**业界对齐**：Go `time`、Java `java.time`、Python `datetime`、.NET `DateTime`。

### 8.1 类型

`Month`、`Weekday`、`TimeUnit`、`Duration`、`Instant`、`DateTime`、`Date`、`Time`、`TimeZone`、`Clock`、`Stopwatch`、`Timer`、`DateTimeFormatter`、`DateTimeParser`。

### 8.2 `Duration`

`Duration.ofMillis`、`Duration.ofSeconds`、`Duration.ofMinutes`、`Duration.ofHours`、`Duration.ofDays`、`Duration.parse`、`millis`、`seconds`、`minutes`、`hours`、`days`、`nanos`、`plus`、`minus`、`multipliedBy`、`dividedBy`、`negated`、`abs`、`compare`、`isZero`、`isNegative`、`toMillis`、`toSeconds`、`toString`。

### 8.3 `Instant`

`Instant.ofEpochMillis`、`Instant.ofEpochSeconds`、`Instant.now`、`epochMillis`、`epochSeconds`、`plus`、`minus`、`isBefore`、`isAfter`、`compare`、`toDateTime`、`toString`。

### 8.4 `DateTime`

| 能力组 | 方法 |
| --- | --- |
| 构造 | `DateTime.of(year,month,day,hour,minute,second)`、`DateTime.ofMs(...)`、`DateTime.fromTimestamp(millis)`、`DateTime.parse(text)`、`DateTime.now()` |
| 读取 | `timestamp`、`instant`、`date`、`time`、`civil`、`year`、`month`、`day`、`hour`、`minute`、`second`、`millisecond`、`weekday`、`dayOfYear`、`weekOfYear`、`isLeapYear` |
| 修改 | `withYear`、`withMonth`、`withDay`、`withHour`、`withMinute`、`withSecond`、`withMillisecond`、`add(Duration)`、`addYears`、`addMonths`、`addDays`、`addHours`、`addMinutes`、`addSeconds`、`addMillis`、`subtract(...)` |
| 比较/转换 | `before`、`after`、`compare`、`equals`、`toInstant`、`toZone`、`toUTC`、`toLocal`、`startOfDay`、`endOfDay`、`startOfMonth`、`endOfMonth` |
| 格式化 | `format(formatter)`、`format(layout)`、`iso8601`、`rfc3339`、`toString` |

### 8.5 `Date` / `Time` / `TimeZone` / `Clock`

`Date`：`year/month/day`、`plusDays`、`plusMonths`、`plusYears`、`weekday`、`dayOfYear`、`isLeapYear`、`compare`、`toString`。  
`Time`：`hour/minute/second/millisecond`、`plus`、`minus`、`compare`、`toString`。  
`TimeZone`：`utc()`、`fixed(offsetMillis)`、`of(id)`（X）、`id()`、`offsetMillis()`、`offsetAt(instant)`、`abbreviation()`。  
`Clock`：`system()`、`monotonic()`、`fixed(instant)`、`now()`、`nowMillis()`。

### 8.6 `Stopwatch` / `Timer` / 格式化

`Stopwatch`：`start`、`stop`、`reset`、`elapsed`、`elapsedMillis`、`isRunning`。  
`Timer`（X）：`after(delay, callback)`、`every(period, callback)`、`cancel(handle)`。  
`DateTimeFormatter`：`ofPattern(pattern)`、`format(dateTime)`、`withLocale`、`withZone`。  
`DateTimeParser`：`ofPattern`、`parse(text)`、`tryParse(text)`。  
`TimeUnit`：`Millis`、`Seconds`、`Minutes`、`Hours`、`Days`、`convert`。

---

## 9. `xdk.io`

**职责**：流、缓冲、行、组合、Stdio。  
**业界对齐**：Go `io/bufio`、Java `java.io/nio`、Python `io`、.NET `Stream`。

### 9.1 协议与类型

`Reader`（protocol）、`Writer`（protocol）、`Seekable`（protocol）、`Closer`（protocol）、`ByteArrayReader/Writer`、`StringReader/Writer`、`BufferedReader/Writer`、`LineReader/Writer`、`ChainReader`、`TeeReader/Writer`、`LimitReader/Writer`、`CountingReader/Writer`、`PeekReader`、`Stdio`。

### 9.2 协议

`Reader`：`read(Context, buffer) -> Result<Int, Error>`、`readExact`、`readAll`、`skip`、`close`、`isOpen`。  
`Writer`：`write(Context, data) -> Result<Int, Error>`、`writeAll`、`flush`、`close`、`isOpen`。  
`Seekable`：`seek(offset, origin)`、`position()`、`size()`。  
`Closer`：`close()`、`isOpen()`。

### 9.3 实现类

| 类型 | 方法 |
| --- | --- |
| `ByteArrayReader` | `ByteArrayReader(bytes)`、`read`、`readExact`、`readAll`、`position`、`seek`、`remaining`、`close` |
| `ByteArrayWriter` | `ByteArrayWriter()`、`write`、`writeAll`、`toBytes`、`takeBytes`、`length`、`clear`、`close` |
| `StringReader` | `StringReader(text)`、`read`、`readLine`、`readAll`、`position`、`seek`、`close` |
| `StringWriter` | `StringWriter()`、`write`、`writeLine`、`toString`、`length`、`clear`、`close` |
| `BufferedReader` | `BufferedReader(source, capacity)`、`read`、`readExact`、`readLine`、`peek`、`skip`、`close` |
| `BufferedWriter` | `BufferedWriter(target, capacity)`、`write`、`writeAll`、`flush`、`close` |
| `LineReader` | `LineReader(source)`、`readLine()`、`readLineOrNull()`、`lines()`、`close` |
| `LineWriter` | `LineWriter(target)`、`writeLine`、`writeLines`、`flush`、`close` |
| `ChainReader` | `ChainReader(sources)`、`read`、`readExact`、`close` |
| `TeeReader` | `TeeReader(source, copy)`、`read`、`close` |
| `TeeWriter` | `TeeWriter(first, second)`、`write`、`flush`、`close` |
| `LimitReader` | `LimitReader(source, limit)`、`read`、`remaining`、`close` |
| `LimitWriter` | `LimitWriter(target, limit)`、`write`、`remaining`、`close` |
| `CountingReader` | `CountingReader(source)`、`read`、`count`、`close` |
| `CountingWriter` | `CountingWriter(target)`、`write`、`count`、`close` |
| `PeekReader` | `PeekReader(source, capacity)`、`peek(count)`、`read`、`close` |
| `Stdio` | `stdin()`、`stdout()`、`stderr()`、`isTerminal` |

### 9.4 顶层函数

`copy(Context, source, target)`、`copyN(Context, source, target, count)`、`copyBuffer(Context, source, target, buffer)`、`readAll(Context, source)`、`readAllText(Context, source)`、`readFully(Context, source, buffer)`、`readLine(Context, source)`、`skip(Context, source, count)`、`skipFully(Context, source, count)`、`pump(Context, source, target, callback)`。

---

## 10. `xdk.fs`

**职责**：路径、文件、目录、元数据、临时、原子、遍历、权限。  
**业界对齐**：Go `os/path/filepath`、Java `java.nio.file`、Python `pathlib`、.NET `File/Directory`。

### 10.1 类型

`Path`、`OpenOptions`、`File`、`Dir`、`Metadata`、`DirEntry`、`Permissions`、`FileMode`、`TempFile`、`TempDir`、`FileSystem`、`PathMatcher`、`FileLock`（X）、`WatchService`（X）。

### 10.2 `Path`

`Path(text)`、`parse(text)`、`text()`、`toString()`、`isAbsolute()`、`isRelative()`、`name()`、`stem()`、`extension()`、`parent()`、`join(child)`、`resolve(other)`、`normalize()`、`relativize(other)`、`components()`、`startsWith(prefix)`、`endsWith(suffix)`、`equals(other)`、`compare(other)`、`toUri()`。

### 10.3 `OpenOptions`

`OpenOptions()`、`read(bool)`、`write(bool)`、`append(bool)`、`create(bool)`、`createNew(bool)`、`truncate(bool)`、`sync(bool)`、`permissions(mode)`、`build()`。

### 10.4 `File`

| 能力组 | 方法 |
| --- | --- |
| 打开 | `File.open(path, options)`、`openRead`、`openWrite`、`openAppend`、`isOpen`、`isReadable`、`isWritable`、`isSeekable` |
| 读 | `read(Context, buffer)`、`readAll(Context)`、`readText(Context)`、`readLine(Context)`、`readFully(Context, buffer)`、`position()`、`size()` |
| 写 | `write(Context, data)`、`writeAll(Context, data)`、`writeText(Context, text)`、`writeLine(Context, text)`、`append(Context, data)`、`truncate(size)`、`flush()`、`sync()` |
| 定位 | `seek(offset, origin)`、`rewind()`、`skip(count)` |
| 元数据 | `metadata()`、`setPermissions(mode)`、`permissions()`、`path()` |
| 关闭 | `close()`、`isOpen()` |

### 10.5 `Dir` / `Metadata` / `DirEntry` / `Permissions`

`Dir`：`Dir.open(path)`、`next()`、`nextOrNull()`、`entries()`、`list()`、`walk()`、`glob(pattern)`、`create()`、`remove()`、`close()`、`isOpen()`。  
`Metadata`：`size()`、`isFile()`、`isDirectory()`、`isSymlink()`、`createdMillis()`、`modifiedMillis()`、`accessedMillis()`、`permissions()`、`owner()`（X）、`group()`（X）。  
`DirEntry`：`name()`、`path()`、`isFile()`、`isDirectory()`、`isSymlink()`、`size()`、`metadata()`。  
`Permissions`：`fromOctal(text)`、`toOctal()`、`ownerRead/Write/Execute`、`groupRead/Write/Execute`、`otherRead/Write/Execute`、`isReadable/isWritable/isExecutable`。

### 10.6 `TempFile` / `TempDir` / `FileSystem`

`TempFile`：`create(prefix,suffix)`、`path()`、`file()`、`close()`、`persist(path)`、`isOpen()`。  
`TempDir`：`create(prefix)`、`path()`、`close()`、`persist(path)`。  
`FileSystem`：`exists`、`isFile`、`isDir`、`isSymlink`、`readAllBytes`、`readAllText`、`writeAllBytes`、`writeAllText`、`appendText`、`copy`、`copyTree`、`move`、`remove`、`removeTree`、`createDir`、`createDirs`、`createTempFile`、`createTempDir`、`walk`、`glob`、`metadata`、`canonicalize`、`symlink`、`readLink`、`setPermissions`。

### 10.7 顶层函数

`exists`、`isFile`、`isDir`、`isSymlink`、`readText`、`readBytes`、`writeText`、`writeBytes`、`appendText`、`appendBytes`、`copyFile`、`copyTree`、`rename`、`move`、`removeFile`、`removeTree`、`makeDir`、`makeDirs`、`removeDir`、`mkdirAll`、`walk`、`glob`、`fileSize`、`fileMtime`、`canonicalize`、`symlink`、`readLink`、`setPermissions`、`writeTextAtomic`、`writeBytesAtomic`、`withTempFile`、`withTempDir`。

---

## 11. `xdk.sys`

**职责**：进程、环境、平台、信号、资源、系统信息。  
**业界对齐**：Go `os/exec`、Java `ProcessBuilder`、Python `subprocess`、.NET `Process`。

### 11.1 类型

`ProcessBuilder`、`Process`、`ProcessResult`、`Env`、`Platform`、`Signal`、`SignalHandler`、`Resource`、`SystemInfo`、`CpuInfo`、`MemoryInfo`、`DiskInfo`、`UserInfo`。

### 11.2 `ProcessBuilder`

`ProcessBuilder(command)`、`args(list)`、`arg(value)`、`cwd(path)`、`env(name,value)`、`envAll(map)`、`stdin(stream)`、`stdout(stream)`、`stderr(stream)`、`redirectErrorStream(bool)`、`inheritEnv(bool)`、`spawn(Context)`、`run(Context)`、`build()`。

### 11.3 `Process`

`id()`、`isAlive()`、`wait()`、`waitTimeout(Context, duration)`、`exitCode()`、`kill()`、`signal(signal)`、`stdin()`、`stdout()`、`stderr()`、`close()`、`isOpen()`。

### 11.4 `ProcessResult`

`status()`、`exitCode()`、`stdout()`、`stderr()`、`output()`、`duration()`、`isSuccess()`、`signal()`。

### 11.5 `Env` / `Platform` / `Signal` / 系统信息

`Env`：`snapshot()`、`get(name)`、`getOr`、`tryGet`、`has`、`keys`、`values`、`all`、`length`。  
`Platform`：`os`、`arch`、`family`、`version`、`hostname`、`pid`、`cwd`、`home`、`tempDir`、`separator`、`pathSeparator`、`lineSeparator`、`user`、`isWindows`、`isLinux`、`isMacOS`。  
`Signal`：`Hangup`、`Interrupt`、`Kill`、`Terminate`、`User1`、`User2`、`number()`。  
`SignalHandler`：`register(signal, callback)`、`unregister(handle)`、`ignore(signal)`、`default(signal)`。  
`SystemInfo`：`cpu()`、`memory()`、`disks()`、`user()`、`hostname()`、`uptime()`。  
`CpuInfo`：`cores`、`model`、`frequencyMhz`、`usagePercent`。  
`MemoryInfo`：`total`、`free`、`available`、`used`、`swapTotal`、`swapFree`。  
`DiskInfo`：`mount`、`total`、`free`、`available`。  
`UserInfo`：`name`、`uid`、`gid`、`home`、`shell`。

### 11.6 `Resource`

`resourceExists(path)`、`resourceSize(path)`、`readResource(Context, path)`、`readResourceText(Context, path)`、`listResources(Context, prefix)`、`resourcePath(path)`。

### 11.7 顶层函数

`runProcess`、`runProcessResult`、`spawnProcess`、`envOrNull`、`envOr`、`envHas`、`envAll`、`platform`、`arch`、`hostname`、`pid`、`cwd`、`chdir`、`homeDir`、`tempDir`、`which`、`commandExists`、`signal`、`kill`。

---

## 12. `xdk.log`

**职责**：日志级别、字段、Sink、过滤、格式化、脱敏、轮转。  
**业界对齐**：Go `log/slog`、SLF4J/Logback、Python `logging`、.NET `ILogger`。

### 12.1 类型

`Level`、`Logger`、`LoggerFactory`、`Field`、`Fields`、`LogRecord`、`Sink`、`ConsoleSink`、`MemorySink`、`FileSink`、`RotatingFileSink`、`AsyncSink`、`MultiSink`、`Filter`、`LevelFilter`、`FieldFilter`、`Redactor`、`Formatter`、`TextFormatter`、`JsonFormatter`、`Sampler`。

### 12.2 `Logger`

`Logger(name, minimum)`、`name()`、`level()`、`isEnabled(level)`、`log(level,message)`、`logRecord(record)`、`debug/info/warn/error/fatal(message)`、`withName(name)`、`withLevel(level)`、`withField(key,value)`、`withFields(fields)`、`withSink(sink)`、`withFilter(filter)`、`child(name)`、`flush()`。

### 12.3 `LoggerFactory`

`root()`、`getLogger(name)`、`configure(config)`、`setDefaultLevel(level)`、`setDefaultSink(sink)`、`shutdown()`。

### 12.4 字段/记录/Sink

`Field`：`Field(key,value)`、`key()`、`value()`、`toString()`。  
`Fields`：`add`、`addAll`、`get`、`getOr`、`has`、`remove`、`length`、`entries`、`copy`。  
`LogRecord`：`level`、`loggerName`、`message`、`fields`、`timestampMono`、`timestampWall`、`threadName`（X）、`error`、`context`（X）。  
`Sink`：`write(record)`、`flush()`、`close()`、`isOpen()`。  
`ConsoleSink`、`MemorySink`、`FileSink`、`RotatingFileSink`、`AsyncSink`、`MultiSink`：各自实现 `write/flush/close`；`MemorySink.records()`、`RotatingFileSink.maxBytes/maxFiles`、`AsyncSink.capacity/queueSize`。

### 12.5 过滤/格式化

`Filter`：`accept(record) -> Bool`。  
`LevelFilter`：`LevelFilter(minimum)`、`accept`。  
`FieldFilter`：`FieldFilter(key,value)`、`accept`。  
`Redactor`：`addPattern(pattern,replacement)`、`redact(text)`、`redactRecord(record)`。  
`Formatter`：`format(record) -> String`。  
`TextFormatter`：`TextFormatter(pattern)`、`format`。  
`JsonFormatter`：`JsonFormatter()`、`format`（依赖 codec）。  
`Sampler`：`Sampler(rate)`、`accept(record)`。

---

## 13. `xdk.config`

**职责**：配置快照、来源、覆盖、类型化、校验、重载。  
**业界对齐**：Viper、Spring Config、Python dynaconf、.NET Configuration。

### 13.1 类型

`Config`、`ConfigEntry`、`ConfigPath`、`ConfigSource`、`MapSource`、`FileSource`、`EnvSource`、`ArgsSource`、`OverlaySource`、`ConfigLoader`、`ConfigSchema`、`ConfigField`、`ConfigSnapshot`、`ConfigWatcher`（X）。

### 13.2 `Config`

| 能力组 | 方法 |
| --- | --- |
| 读取 | `length`、`isEmpty`、`has(key)`、`get(key)`、`getOr(key,fallback)`、`tryGet(key)`、`getInt`、`getLong`、`getBool`、`getDouble`、`getDuration`、`getPath`、`keys`、`values`、`entries`、`profile` |
| 修改 | `set(key,value)`、`setAll(entries)`、`remove(key)`、`merge(other)`、`overlay(other)`、`clear`、`copy`、`freeze` |
| 校验 | `validate(schema)`、`require(keys)`、`ensure(key, predicate, message)` |
| 渲染 | `render()`、`toMap()` |
| 重载 | `reload()`（X）、`watch()`（X） |

### 13.3 来源

`ConfigSource`：`load(Context) -> Result<List<ConfigEntry>, Error>`、`name()`、`priority()`。  
`MapSource`、`FileSource`、`EnvSource`、`ArgsSource`：各自构造 + `load`。  
`OverlaySource`：`OverlaySource(sources)`、`add(source)`、`load`。  
`ConfigLoader`：`ConfigLoader()`、`addSource(source)`、`profile(profile)`、`load(Context)`、`reload(Context)`、`precedence(list)`。

### 13.4 Schema

`ConfigSchema`：`ConfigSchema()`、`field(name)`、`require(name)`、`defaultValue(value)`、`validator(validator)`、`validate(config)`、`fields()`。  
`ConfigField`：`name`、`type`、`isRequired`、`defaultValue`、`validator`、`description`。  
`ConfigSnapshot`：不可变快照；`get`/`getOr`/`keys`/`entries`/`profile`。

---

## 14. `xdk.cli`

**职责**：参数、选项、命令、子命令、帮助、补全、退出码。  
**业界对齐**：Cobra、picocli、argparse、System.CommandLine。

### 14.1 类型

`Args`、`OptionSpec`、`Flag`、`Command`、`CommandGroup`、`Parser`、`HelpFormatter`、`Completion`、`ExitCode`、`UsageError`、`ValueParser`、`ArgSource`。

### 14.2 `Args`

`length()`、`get(index)`、`has(flag)`、`hasFlag(flag)`、`value(flag)`、`valueOr(flag,fallback)`、`valueOrNull(flag)`、`tryValue(flag)`、`values(flag)`、`positionals()`、`subcommand()`、`optionNames()`、`raw()`、`isPresent(flag)`。

### 14.3 `OptionSpec`

`OptionSpec(name)`、`shortName(name)`、`longName(name)`、`hasValue(bool)`、`isRequired(bool)`、`isRepeatable(bool)`、`defaultValue(value)`、`description(text)`、`valueName(name)`、`parser(parser)`、`validator(validator)`、`env(name)`、`hidden(bool)`、`build()`。

### 14.4 `Command`

`Command(name)`、`description(text)`、`addOption(spec)`、`addFlag(spec)`、`addSubcommand(command)`、`alias(name)`、`handler(handler)`、`parse(arguments)`、`run(Context, args)`、`help()`、`usage()`、`name()`、`subcommands()`、`options()`。

### 14.5 `Parser` / `HelpFormatter` / `Completion`

`Parser`：`Parser(command)`、`parse(arguments)`、`parseOrExit(arguments)`、`usage()`、`help()`。  
`HelpFormatter`：`format(command)`、`usage(command)`、`options(command)`、`subcommands(command)`。  
`Completion`：`complete(prefix)`、`completeCommand(command, prefix)`、`script(shell)`。

### 14.6 `ExitCode` / `UsageError` / `ValueParser`

`ExitCode`：`Ok=0`、`Usage=2`、`Error=1`、`NotFound=127`、`SignalBase=128`。  
`UsageError`：`UsageError(message)`、`message()`、`describe()`、`exitCode()`。  
`ValueParser`：`parse(text)`、`typeName()`（X，可用具体 parser 实现）。

---

## 15. 执行层内建：`tasks` / `sync`

> 按 P9=B：语言/运行时内建；`xdk.tasks`/`xdk.sync` 只作为 deprecated 兼容命名空间。  
> API 面设计仍把它们列为 core 的能力面，因为真实程序离不开。

### 15.1 `tasks`

| 类型 | 方法 |
| --- | --- |
| `Context` | `background()`、`withCancel(parent)`、`withDeadline(parent, deadline)`、`withTimeout(parent, timeout)`、`isCancelled()`、`cancel()`、`done()`、`err()`、`value(key)`、`withValue(key,value)` |
| `CancellationScope` | `create(parent)`、`cancel()`、`close()`、`isCancelled()` |
| `Task<T>` | `join()`、`joinDeadline(deadline)`、`cancel()`、`isDone()`、`result()` |
| `TaskGroup` | `create(parent)`、`spawn(body)`、`spawnAll(bodies)`、`cancel()`、`close()`、`wait()`、`results()` |
| `Executor` | `fixed(count)`、`cached()`、`single()`、`submit(task)`、`schedule(task,delay)`、`shutdown()`、`isShutdown()` |
| `Timer` | `after(delay)`、`every(period)`、`cancel(handle)` |
| `Future<T>` / `Promise<T>` | `get`、`getDeadline`、`complete`、`fail`、`cancel`、`isDone` |
| `Select` | `select(channels)`、`selectTimeout(timeout)` |

### 15.2 `sync`

| 类型 | 方法 |
| --- | --- |
| `Mutex<T>` | `Mutex(value)`、`withLock(body)`、`withLockResult(body)`、`tryLock()`、`isLocked()` |
| `RwLock<T>` | `RwLock(value)`、`withRead(body)`、`withWrite(body)`、`tryRead()`、`tryWrite()` |
| `Semaphore` | `Semaphore(permits)`、`acquire()`、`tryAcquire()`、`release()`、`available()` |
| `WaitGroup` | `add(count)`、`done()`、`wait()`、`waitDeadline(deadline)` |
| `Once` | `do(body)`、`isDone()` |
| `Barrier` | `Barrier(count)`、`wait()` |
| `Channel<T>` | `Channel(capacity)`、`send`、`trySend`、`receive`、`tryReceive`、`sendDeadline`、`receiveDeadline`、`close`、`isClosed`、`length`、`capacity` |
| `AtomicInt` | `load`、`store`、`compareExchange`、`addAndGet`、`getAndAdd`、`increment`、`decrement`、`exchange` |
| `AtomicLong` | 同 `AtomicInt`，Long 宽度 |
| `AtomicBool` | `load`、`store`、`compareExchange`、`exchange` |
| `AtomicRef<T>` | `load`、`store`、`compareExchange`、`exchange` |
| `Lazy<T>` | `Lazy(initializer)`、`get()`、`isInitialized()` |
| `Broadcast<T>` | `Broadcast(capacity)`、`send`、`subscribe`、`unsubscribe` |
| `PubSub<T>` | `publish`、`subscribe`、`unsubscribe` |

---

## 16. 注解面（Annotation Surface）

完整模板见 [`../../solution-03-annotation.md`](../../solution-03-annotation.md) §8 与 [`../API-SURFACE.md`](../API-SURFACE.md) §7。本节只给 core/B4 包的注解面现状；A8/编译器状态是全局能力，不代表每个类型都已采用。

### 16.1 core/B4 注解面

| 包 | 可用注解 | 状态 |
| --- | --- | --- |
| `xdk.errors` | `@Value`、`@Copy`、`@Override`、`@Deprecated` | A8/compiler implemented；包内采用 partial |
| `xdk.runtime` | `@Value`、`@Copy`、`@Override` | A8/compiler implemented；partial |
| `xdk.meta` | `@Value`、`@Data`、`@Builder`、`@Copy` | A8 implemented；partial |
| `xdk.bytes` | `@Data`、`@Value`、`@Builder`、`@Copy` | A8 implemented；partial |
| `xdk.text` | `@Value`、`@Builder`、`@Copy`、`@Override` | A8/compiler implemented；partial |
| `xdk.collections` | `@Data`、`@Value`、`@Builder`、`@Copy` | A8 implemented；partial |
| `xdk.math` | `@Value`、`@Builder`、`@Copy` | A8 implemented；已落地范围见类型合同 |
| `xdk.time` | `struct` 原生值语义；`@Data`/`@Builder` | A8 implemented；struct 类型已落地 |
| `xdk.io` | `@Override`、`@Deprecated` | compiler implemented；流是资源，不套 `@Value`/`@Data` |
| `xdk.fs` | `@Value`、`@Override` | A8/compiler implemented；partial |
| `xdk.sys` | `@Value`、`@Copy`、`@Override` | A8/compiler implemented；partial |
| `xdk.log` | `@Value`、`@Builder`、`@Override` | A8/compiler implemented；partial |
| `xdk.config` | `@Value`、`@Data`、`@Builder`、`@Override` | A8/compiler implemented；partial |
| `xdk.cli` | `@CliCommand`、`@CliSubcommand`、`@Option`、`@Arg`；`@Value`/`@Copy` | 领域注解 planned；A8 implemented |
| `xdk.execution` | `@Value`、`@Override` | A8/compiler implemented；partial |

### 16.2 强制模板

每个 core 公共类型/成员必须写：

```markdown
| 项 | 内容 |
| --- | --- |
| 类型/成员 | `Type.member(...)` |
| 可用注解 | `@Value` / 无 |
| 目标 / 保留 | `Type` / `Source` |
| 所属包/处理器 | `xdk.core` / 编译器 A8 |
| 生成物 | `equals`、`toString`、`copy`；不生成 `hash()` |
| 诊断码 | `AN0021`–`AN0023` |
| 状态 | implemented（含限制） |
| 反例 | `@Value` 用于 struct |
```

### 16.3 规则

- `planned` 的 `@CliCommand` 等不得写成已生效；A8 implemented 不等于领域处理器 implemented。
- 每个公共类型必须显式写“无注解”或注解面；缺失视为文档不完整。
- 删除/收紧注解、目标、保留、默认值或生成物是破坏性变更。

---

## 17. `xdk.core` 覆盖结论

| 包 | 旧版方法面 | API 面目标 |
| --- | --- | --- |
| errors | 构造/报告/聚合 | + RetryPolicy/Matcher/Collector/Sink/Code + 更多 ResultOps |
| runtime | 4 函数 | + RuntimeInfo/MemoryStats/TaskStats/stackTrace |
| meta | 3 函数 | + BuildInfo/TargetInfo/Capability |
| bytes | 基础读写 | + Builder/ByteBuffer/BitSet/BytesView/更多 checked |
| text | 基础字符串 | + StringBuilder/Joiner/Format/Unicode/Escape/完整 Regex |
| collections | List/Map/Set 基础 | + Deque/Stack/Queue/MultiMap/BiMap/LRUCache/Range + 算法 |
| math | 函数组 | + Decimal/RoundingMode/更多统计/数论 |
| time | Duration/DateTime | + Instant/Date/Time/TimeZone/Clock/Formatter/Parser/Stopwatch/Timer |
| io | Reader/Writer | + Buffered/Line/Chain/Tee/Limit/Counting/Peek/Stdio |
| fs | 3 函数 | + Path/OpenOptions/File/Dir/Metadata/Permissions/Temp/FileSystem/Atomic |
| sys | Process/Env | + ProcessBuilder/ProcessResult/Signal/SystemInfo/Cpu/Memory/Disk/User |
| log | Level/Logger | + Field/Record/Sink/Filter/Formatter/Redactor/Rotation/Async |
| config | 快照 | + Sources/Loader/Schema/Typed/Snapshot/Watcher |
| cli | Args/usage | + OptionSpec/Flag/Command/CommandGroup/Parser/Help/Completion/ExitCode |
| tasks/sync | 最小面 | + Executor/Timer/Future/Promise/Select/RwLock/Semaphore/WaitGroup/Once/Barrier |
