# `xdk.utils` API 面（旧版广度稿）

> **2.x 状态**：本文件是旧版 API 广度稿，不是实现依据。包名以 [`PACKAGE-MAP.md`](../PACKAGE-MAP.md) 为准；类型签名以逐类型合同为准；已知冲突见 [`DESIGN-CONSISTENCY.md`](../DESIGN-CONSISTENCY.md)。`xdk.utils.*` 是旧写法，2.x 包名是 `xdk.codec`、`xdk.crypto` 等；本文件将按合同重新生成，不再手写。

> 当前领域设计见 [`OVERVIEW.md`](OVERVIEW.md)；本文件列出 utils 的 API 广度与方法面，不声明当前目录/顺序。


> **包边界**：`regex` 归 `xdk.text`，`health` 归 `xdk.runtime`，`resource` 归 `xdk.sys`，不再作为独立 utils 包；当前 utils 共 24 包。

| 项 | 值 |
| --- | --- |
| 范围 | `xdk.codec`、`crypto`、`compress`、`random`、`uuid`、`stats`、`functional`、`resilience`、`validate`、`cache`、`queue`、`schedule`、`metrics`、`trace`、`audit`、`terminal`、`i18n`、`test`、`event`、`reflect`、`graph`、`yaml`、`toml`、`xml` |
| 目标 | 对齐 Guava/Apache Commons、Go 标准库、Python 标准库、.NET、OpenTelemetry 的常规能力 |
| 规则 | 只写方案；不写代码；不展开编译器/FFI 实现 |
| 记号 | `K` = 基础面；`X` = 扩展面 |

---

## 0. 定位

`xdk.utils` 不是单一 `util` 大杂烩，而是“可复用工具包组”。每组单一职责：

```text
数据工具：codec / crypto / compress / random / uuid / regex / stats / validate
运行时工具：cache / queue / schedule / metrics / trace / health / audit
工具与集成：terminal / i18n / test / resource
```

依赖规则：

- 数据工具依赖 `core`（bytes/text/collections/math/time/errors）。
- 运行时工具依赖 `core` + 执行层 `xdk.execution`。
- `codec` 可被 `net.http` 使用（JSON/Multipart）。
- `crypto` 可被 `net.tls` 使用。
- `compress` 可被 `net.http` 使用（gzip）。
- utils 文档组不得依赖应用层。

---

## 1. `xdk.codec`

**职责**：JSON、CSV、Base64、Hex、URL 编码。  
**业界对齐**：`encoding/json`、Jackson、Python `json/csv`、.NET `System.Text.Json`。

### 1.1 类型

`JsonValue`、`JsonObject`、`JsonArray`、`JsonNumber`、`JsonString`、`JsonBool`、`JsonNull`、`Json`、`JsonOptions`、`JsonPointer`（X）、`Csv`、`CsvOptions`、`CsvReader`、`CsvWriter`、`Base64`、`Hex`、`UrlCodec`、`CodecError`。

### 1.2 `Json`

| 能力组 | 方法 |
| --- | --- |
| 解析 | `Json.parse(text)`、`Json.parseBytes(bytes)`、`Json.parseObject(text)`、`Json.parseArray(text)`、`Json.parseReader(Context, reader)` |
| 生成 | `Json.stringify(value)`、`Json.stringifyPretty(value)`、`Json.write(value, writer)`、`Json.toBytes(value)` |
| 类型 | `Json.object()`、`Json.array()`、`Json.string(text)`、`Json.number(value)`、`Json.bool(value)`、`Json.nullValue()` |
| 便捷 | `Json.get(value,path)`、`Json.getString`、`Json.getInt`、`Json.getBool`、`Json.getArray`、`Json.getObject` |
| 选项 | `JsonOptions.maxDepth`、`maxBytes`、`allowComments`、`allowTrailingComma`、`pretty` |

### 1.3 `JsonValue` 及子类

`JsonValue`：`kind()`、`isNull/isBool/isNumber/isString/isArray/isObject`、`asBool/asNumber/asString/asArray/asObject`、`toJson()`。  
`JsonObject`：`get(name)`、`getOr`、`has`、`set`、`remove`、`keys`、`values`、`entries`、`length`、`copy`。  
`JsonArray`：`get(index)`、`add`、`remove`、`length`、`toList`、`copy`。  
`JsonNumber`：`asInt`、`asLong`、`asDouble`、`isInteger`。  
`JsonString`：`value`、`length`。

### 1.4 `Csv`

`Csv.parse(text,options)`、`Csv.parseReader(Context,reader,options)`、`Csv.write(rows,options)`、`Csv.writeTo(writer,rows,options)`、`Csv.readRecord(reader)`、`Csv.writeRecord(writer,record)`。  
`CsvOptions`：`delimiter`、`quote`、`escape`、`hasHeader`、`skipEmptyLines`、`trim`。  
`CsvReader`：`readRecord()`、`readAll()`、`headers()`、`close()`。  
`CsvWriter`：`writeRecord(record)`、`writeAll(records)`、`flush()`、`close()`。

### 1.5 `Base64` / `Hex` / `UrlCodec`

`Base64`：`encode(bytes)`、`decode(text)`、`encodeUrl(bytes)`、`decodeUrl(text)`、`encodeNoPadding`、`decodeNoPadding`、`encodedLength`、`decodedLength`。  
`Hex`：`encode(bytes)`、`encodeUpper(bytes)`、`decode(text)`、`isValid(text)`。  
`UrlCodec`：`encode`、`decode`、`queryEncode`、`queryDecode`、`formEncode`、`formDecode`。

---

## 2. `xdk.crypto`

**职责**：哈希、HMAC、对称加密、KDF、常量时间比较、CRC。  
**业界对齐**：Go `crypto`、Java JCA、Python `hashlib/cryptography`、.NET Cryptography。

### 2.1 类型

`HashAlgorithm`、`Hash`、`Hmac`、`AesMode`、`Aes`、`ChaCha20Poly1305`、`Kdf`、`KdfAlgorithm`、`SecureRandom`、`ConstantTime`、`Crc32`、`Adler32`、`Fnv`。

### 2.2 `Hash` / `Hmac`

`Hash`：`sha1(bytes)`、`sha256(bytes)`、`sha512(bytes)`、`md5(bytes)`（标 deprecated）、`hash(algorithm,bytes)`、`hashReader(Context,algorithm,reader)`、`hex(algorithm,bytes)`、`base64(algorithm,bytes)`、`length(algorithm)`。  
`Hmac`：`sha1(key,data)`、`sha256(key,data)`、`sha512(key,data)`、`hmac(algorithm,key,data)`、`verify(algorithm,key,data,mac)`、`hex`、`base64`。

### 2.3 `Aes` / `ChaCha20Poly1305`

`Aes`：`Aes(key)`、`encryptCbc(iv,plaintext)`、`decryptCbc(iv,ciphertext)`、`encryptGcm(nonce,plaintext,aad)`、`decryptGcm(nonce,ciphertext,tag,aad)`、`keySize()`、`blockSize()`。  
`ChaCha20Poly1305`：`ChaCha20Poly1305(key)`、`encrypt(nonce,plaintext,aad)`、`decrypt(nonce,ciphertext,tag,aad)`、`nonceSize()`、`tagSize()`。

### 2.4 `Kdf` / `SecureRandom` / `ConstantTime` / 校验和

`Kdf`：`pbkdf2(algorithm,password,salt,iterations,length)`、`scrypt(password,salt,n,r,p,length)`、`argon2id(password,salt,memory,iterations,parallelism,length)`（X）。  
`SecureRandom`：`bytes(count)`、`int()`、`long()`、`uniform(max)`、`shuffle(list)`、`reseed()`。  
`ConstantTime`：`equals(left,right)`、`compare(left,right)`、`isZero(bytes)`。  
`Crc32`、`Adler32`、`Fnv`：`compute(bytes)`、`update(current,bytes)`、`hex`。

---

## 3. `xdk.compress`

**职责**：gzip、zlib、zip。  
**业界对齐**：Go `compress`、Java `zip`、Python `gzip/zipfile`、.NET Compression。

### 3.1 类型

`CompressionLevel`、`Gzip`、`Zlib`、`ZipArchive`、`ZipWriter`、`ZipEntry`、`ZipOptions`。

### 3.2 `Gzip` / `Zlib`

`Gzip.compress(bytes,level)`、`Gzip.decompress(bytes)`、`Gzip.reader(reader)`、`Gzip.writer(writer,level)`、`Gzip.isGzip(bytes)`。  
`Zlib.compress(bytes,level)`、`Zlib.decompress(bytes)`、`Zlib.reader(reader)`、`Zlib.writer(writer,level)`。

### 3.3 `ZipArchive` / `ZipWriter` / `ZipEntry`

`ZipArchive.open(path)`、`openReader(reader)`、`entries()`、`getEntry(name)`、`readEntry(name)`、`extractTo(path)`、`close()`、`isOpen()`。  
`ZipWriter.create(path)`、`createWriter(writer)`、`addFile(name,bytes)`、`addDirectory(name)`、`finish()`、`close()`。  
`ZipEntry`：`name()`、`size()`、`compressedSize()`、`isDirectory()`、`crc()`、`modifiedMillis()`、`comment()`。

---

## 4. `xdk.random`

**职责**：可种子 PRNG、安全随机、采样/洗牌。  
**业界对齐**：Go `math/rand`、Java `Random`、Python `random`、.NET `Random`。

### 4.1 类型

`Random`、`SecureRandom`、`RandomSource`（protocol）、`WeightedChoice`。

### 4.2 `Random`

`Random()`、`Random(seed)`、`seed(value)`、`nextBool()`、`nextInt()`、`nextInt(max)`、`nextInt(min,max)`、`nextLong()`、`nextLong(min,max)`、`nextDouble()`、`nextDouble(min,max)`、`nextGaussian()`、`nextBytes(count)`、`shuffle(list)`、`choice(list)`、`sample(list,count)`、`weightedChoice(choices)`、`fork()`、`state()`。

### 4.3 `SecureRandom` / `WeightedChoice`

`SecureRandom.bytes(count)`、`int(max)`、`long(max)`、`double()`、`shuffle(list)`、`reseed()`。  
`WeightedChoice`：`add(value,weight)`、`pick(random)`、`totalWeight()`、`clear()`。

---

## 5. `xdk.uuid`

**职责**：UUID v4/v7、ULID。  
**业界对齐**：Go `google/uuid`、Java `UUID`、Python `uuid`、.NET `Guid`。

### 5.1 类型

`Uuid`、`UuidVersion`、`Ulid`、`Snowflake`（X）。

### 5.2 `Uuid`

`Uuid.v4()`、`Uuid.v7()`、`Uuid.parse(text)`、`Uuid.fromBytes(bytes)`、`bytes()`、`toString()`、`version()`、`variant()`、`timestamp()`（v7）、`isNil()`、`equals(other)`、`compare(other)`、`toUlid()`（X）。

### 5.3 `Ulid` / `Snowflake`

`Ulid.generate()`、`Ulid.generate(monotonic)`、`Ulid.parse(text)`、`Ulid.fromBytes(bytes)`、`timestamp()`、`randomness()`、`bytes()`、`toString()`、`equals`、`compare`。  
`Snowflake`：`Snowflake(nodeId)`、`next()`、`parse(value)`、`timestamp()`、`nodeId()`、`sequence()`。

---

## 6. `xdk.utils.regex`（已归并到 `xdk.text.Regex`；不是独立包）

**职责**：完整正则引擎，支持命名组、选项、替换。  
**业界对齐**：Go `regexp`、Java `Pattern`、Python `re`、.NET `Regex`。

### 6.1 类型

`RegexOptions`、`Regex`、`Match`、`RegexSet`、`RegexBuilder`。

### 6.2 `Regex`

`Regex.compile(pattern)`、`compile(pattern,options)`、`isMatch(text)`、`find(text)`、`findFirst(text)`、`findAll(text)`、`matchAll(text)`、`replaceAll(text,replacement)`、`replaceFirst(text,replacement)`、`replaceAllWith(text,callback)`、`split(text)`、`splitLimit(text,limit)`、`groups()`、`namedGroups()`、`pattern()`、`options()`、`escape(text)`。

### 6.3 `Match` / `RegexSet` / `RegexBuilder`

`Match`：`start`、`end`、`length`、`group(index)`、`groups`、`groupCount`、`namedGroup(name)`、`namedGroups`、`text`、`isMatch`。  
`RegexSet`：`RegexSet(patterns)`、`isMatch(text)`、`matches(text)`、`which(text)`、`length`。  
`RegexBuilder`：`RegexBuilder()`、`pattern(pattern)`、`caseInsensitive(bool)`、`multiline(bool)`、`dotAll(bool)`、`unicode(bool)`、`build()`。

---

## 7. `xdk.stats`

**职责**：统计、直方图、回归、移动平均。  
**业界对齐**：Python `statistics`、Apache Commons Math、.NET MathNet。

### 7.1 类型

`Stats`、`Histogram`、`HistogramBucket`、`Summary`、`Regression`、`MovingAverage`、`Ema`。

### 7.2 `Stats`

`sum(values)`、`product(values)`、`mean(values)`、`median(values)`、`mode(values)`、`variance(values)`、`sampleVariance(values)`、`stddev(values)`、`sampleStddev(values)`、`min(values)`、`max(values)`、`range(values)`、`quantile(values,q)`、`percentile(values,p)`、`covariance(left,right)`、`correlation(left,right)`、`zscore(values,value)`、`histogram(values,buckets)`。

### 7.3 `Histogram` / `Summary` / `Regression` / 移动平均

`Histogram`：`Histogram(boundaries)`、`observe(value)`、`count()`、`sum()`、`min()`、`max()`、`mean()`、`stddev()`、`percentile(p)`、`buckets()`、`reset()`、`snapshot()`。  
`Summary`：`observe(value)`、`count()`、`sum()`、`min()`、`max()`、`mean()`、`variance()`、`stddev()`、`quantiles()`、`reset()`。  
`Regression`：`Regression(xs,ys)`、`slope()`、`intercept()`、`predict(x)`、`r2()`、`residuals()`。  
`MovingAverage`：`MovingAverage(window)`、`add(value)`、`average()`、`reset()`。  
`Ema`：`Ema(alpha)`、`add(value)`、`value()`、`reset()`。

---

## 8. `xdk.validate`

**职责**：字段/模式/规则校验、错误聚合。  
**业界对齐**：Jakarta Validation、FluentValidation、pydantic。

### 8.1 类型

`ValidationError`、`ValidationResult`、`Validator`（protocol）、`Rules`、`Schema`、`FieldRule`、`ValidationContext`、`Validators`。

### 8.2 `ValidationError` / `ValidationResult`

`ValidationError`：`ValidationError(field,code,message)`、`field`、`code`、`message`、`describe`。  
`ValidationResult`：`isValid()`、`errors()`、`firstError()`、`errorCount()`、`add(error)`、`addAll(errors)`、`merge(other)`、`toResult()`、`throwIfInvalid()`（X）。

### 8.3 `Validator` / `Rules` / `Schema`

`Validator`：`validate(value,context)`、`describe()`。  
`Rules`：`required()`、`notEmpty()`、`minLength(n)`、`maxLength(n)`、`pattern(regex)`、`email()`、`url()`、`range(min,max)`、`oneOf(values)`、`custom(predicate,message)`、`all(validators)`、`any(validators)`。  
`Schema`：`Schema()`、`field(name,validator)`、`required(name)`、`validate(object)`、`validateField(name,value)`、`fields()`。  
`ValidationContext`：`path()`、`locale()`、`failFast()`、`withPath(path)`、`addError(error)`。

### 8.4 `Validators`

`Validators.string()`、`number()`、`integer()`、`bool()`、`list()`、`map()`、`duration()`、`dateTime()`、`path()`、`email()`、`url()`、`uuid()`。

---

## 9. `xdk.cache`

**职责**：LRU、TTL、Loading Cache、统计。  
**业界对齐**：Guava Cache、Caffeine、.NET MemoryCache。

### 9.1 类型

`CacheStats`、`CacheLoader`（protocol）、`LruCache`、`TtlCache`、`LoadingCache`。

### 9.2 `LruCache`

`LruCache(capacity)`、`get(key)`、`getOrLoad(key,loader)`、`put(key,value)`、`putIfAbsent`、`remove(key)`、`contains(key)`、`size()`、`capacity()`、`resize(capacity)`、`clear()`、`keys()`、`values()`、`entries()`、`stats()`。

### 9.3 `TtlCache` / `LoadingCache` / `CacheStats`

`TtlCache`：`TtlCache(ttl)`、`get`、`put`、`remove`、`contains`、`size`、`clear`、`cleanup()`、`stats`。  
`LoadingCache`：`LoadingCache(loader,capacity)`、`get(key)`、`getOrLoad`、`refresh(key)`、`invalidate(key)`、`invalidateAll`、`stats`。  
`CacheStats`：`hits`、`misses`、`evictions`、`loads`、`loadFailures`、`size`、`capacity`、`hitRate()`、`missRate()`、`reset()`。

---

## 10. `xdk.queue`

**职责**：有界队列、阻塞队列、批处理队列。  
**业界对齐**：Java `BlockingQueue`、.NET Channels、Go channels。

### 10.1 类型

`QueueStats`、`DropPolicy`、`BoundedQueue`、`BlockingQueue`、`BatchQueue`、`QueueItem`（X）。

### 10.2 `BoundedQueue`

`BoundedQueue(capacity,policy)`、`push(value)`、`tryPush(value)`、`pop()`、`tryPop()`、`peek()`、`size()`、`capacity()`、`isEmpty()`、`isFull()`、`clear()`、`close()`、`isClosed()`、`stats()`。

### 10.3 `BlockingQueue`

`BlockingQueue(capacity)`、`put(Context,value)`、`tryPut(value)`、`take(Context)`、`tryTake()`、`peek()`、`size()`、`capacity()`、`close()`、`isClosed()`、`stats()`。

### 10.4 `BatchQueue` / `DropPolicy` / `QueueStats`

`BatchQueue`：`BatchQueue(batchSize)`、`add(value)`、`flush()`、`drain()`、`size()`、`close()`。  
`DropPolicy`：`Block`、`DropNewest`、`DropOldest`、`Error`。  
`QueueStats`：`size`、`capacity`、`pushed`、`popped`、`dropped`、`closed`、`reset()`。

---

## 11. `xdk.schedule`

**职责**：cron、周期任务、一次性任务。  
**业界对齐**：Quartz、Go `time.Ticker`、.NET `Timer`、cron 库。

### 11.1 类型

`Scheduler`、`SchedulerOptions`、`Job`（protocol）、`JobHandle`、`CronExpression`、`Schedule`、`MisfirePolicy`。

### 11.2 `Scheduler`

`Scheduler.create(options)`、`schedule(job,delay)`、`scheduleAtFixedRate(job,initialDelay,period)`、`scheduleWithFixedDelay(job,initialDelay,delay)`、`scheduleCron(job,cron)`、`cancel(handle)`、`shutdown()`、`isShutdown()`、`jobs()`。

### 11.3 `Job` / `JobHandle` / `CronExpression` / `Schedule`

`Job`：`name()`、`run(Context)`。  
`JobHandle`：`cancel()`、`isCancelled()`、`isDone()`、`nextRun()`、`lastRun()`。  
`CronExpression.parse(text)`、`next(from)`、`nextN(from,count)`、`matches(time)`、`describe()`。  
`Schedule`：`once(delay)`、`every(period)`、`cron(text)`、`at(time)`。  
`MisfirePolicy`：`Skip`、`FireOnce`、`CatchUp`。

---

## 12. `xdk.metrics`

**职责**：Counter/Gauge/Histogram/Timer/Registry/Exporter。  
**业界对齐**：Micrometer、Prometheus、.NET Meter。

### 12.1 类型

`MetricKind`、`MetricSample`、`MetricFamily`、`Counter`、`Gauge`、`Histogram`、`Timer`、`Registry`、`Exporter`（protocol）、`MetricsFormat`。

### 12.2 指标类型

`Counter`：`inc()`、`add(delta)`、`get()`、`reset()`。  
`Gauge`：`set(value)`、`get()`、`add(delta)`、`sub(delta)`、`reset()`。  
`Histogram`：`observe(value)`、`count()`、`sum()`、`min()`、`max()`、`mean()`、`percentile(p)`、`buckets()`、`snapshot()`、`reset()`。  
`Timer`：`start()`、`stop()`、`observe(Duration)`、`count()`、`total()`、`mean()`、`max()`、`snapshot()`、`reset()`。

### 12.3 `Registry` / `Exporter`

`Registry`：`Registry()`、`counter(name)`、`gauge(name)`、`histogram(name)`、`timer(name)`、`get(name)`、`remove(name)`、`names()`、`snapshot()`、`clear()`。  
`MetricFamily`：`name`、`kind`、`samples`、`help`、`unit`。  
`MetricSample`：`name`、`labels`、`value`、`timestamp`。  
`Exporter`：`export(registry,writer)`、`format()`。  
`MetricsFormat`：`Text`、`Json`、`Prometheus`。

---

## 13. `xdk.trace`

**职责**：Tracer/Span/Context/Propagator。  
**业界对齐**：OpenTelemetry。

### 13.1 类型

`Tracer`、`TraceOptions`、`Span`、`SpanContext`、`SpanKind`、`SpanStatus`、`SpanEvent`、`Propagator`（protocol）、`Sampler`。

### 13.2 `Tracer` / `Span`

`Tracer.create(options)`、`startSpan(name)`、`startSpan(name,parent)`、`startSpan(name,kind)`、`currentSpan()`、`spanFromContext(context)`、`inject(context,carrier)`、`extract(carrier)`、`close()`。  
`Span`：`name`、`context`、`setAttribute(key,value)`、`addEvent(name,attributes)`、`setStatus(status,message)`、`recordError(error)`、`end()`、`isRecording()`、`duration()`。

### 13.3 `SpanContext` / `Propagator` / `Sampler`

`SpanContext`：`traceId`、`spanId`、`parentSpanId`、`isSampled`、`baggage`、`isValid()`、`copy()`。  
`Propagator`：`inject(context,carrier)`、`extract(carrier)`。  
`Sampler`：`alwaysOn()`、`alwaysOff()`、`ratio(value)`、`shouldSample(context)`。

---

## 14. `xdk.utils.health`（已归并到 `xdk.runtime.Health*`；不是独立包）

**职责**：readiness/liveness/健康聚合。  
**业界对齐**：Spring Actuator、.NET HealthChecks。

### 14.1 类型

`HealthStatus`、`HealthResult`、`HealthReport`、`HealthCheck`（protocol）、`HealthRegistry`。

### 14.2 API

`HealthStatus`：`Up`、`Down`、`Degraded`、`Unknown`。  
`HealthResult`：`HealthResult(name,status,message)`、`name`、`status`、`message`、`details`、`duration`。  
`HealthReport`：`status()`、`results()`、`isHealthy()`、`add(result)`、`merge(other)`、`describe()`。  
`HealthCheck`：`name()`、`check(Context)`。  
`HealthRegistry`：`register(check)`、`unregister(name)`、`check(name)`、`checkAll(Context)`、`report()`、`isHealthy()`。

---

## 15. `xdk.audit`

**职责**：审计事件、Sink、脱敏。  
**业界对齐**：审计日志/合规日志。

### 15.1 类型

`AuditLevel`、`AuditEvent`、`AuditSink`（protocol）、`AuditLogger`、`Redactor`。

### 15.2 API

`AuditLevel`：`Info`、`Warning`、`Critical`。  
`AuditEvent`：`AuditEvent(actor,action,resource,outcome)`、`timestamp`、`actor`、`action`、`resource`、`outcome`、`level`、`fields`、`withField`、`withLevel`、`describe`。  
`AuditSink`：`write(event)`、`flush()`、`close()`。  
`AuditLogger`：`AuditLogger(sink)`、`log(event)`、`logAction(actor,action,resource,outcome)`、`withField`、`withRedactor`、`flush()`、`close()`。  
`Redactor`：`addPattern(pattern,replacement)`、`redact(text)`、`redactEvent(event)`、`clear()`。

---

## 16. `xdk.terminal`

**职责**：TTY、ANSI、进度、表格、提示。  
**业界对齐**：ANSI 库、progress、prompt 库。

### 16.1 类型

`Terminal`、`Ansi`、`Color`、`Style`、`ProgressBar`、`Spinner`、`Prompt`、`Table`。

### 16.2 API

`Terminal`：`isTerminal()`、`width()`、`height()`、`write(text)`、`writeLine(text)`、`clear()`、`flush()`。  
`Ansi`：`reset()`、`bold(text)`、`dim(text)`、`italic(text)`、`underline(text)`、`fg(color,text)`、`bg(color,text)`、`color256(index,text)`、`rgb(r,g,b,text)`、`cursorUp(n)`、`cursorDown(n)`、`clearScreen()`、`hideCursor()`、`showCursor()`。  
`Style`：`Style()`、`fg`、`bg`、`bold`、`italic`、`underline`、`apply(text)`。  
`ProgressBar`：`ProgressBar(total)`、`set(value)`、`increment()`、`finish()`、`clear()`、`message(text)`。  
`Spinner`：`Spinner()`、`start()`、`stop()`、`setMessage(text)`。  
`Prompt`：`text(message)`、`password(message)`、`confirm(message)`、`select(message,options)`。  
`Table`：`Table(columns)`、`addRow(row)`、`render()`、`clear()`。

---

## 17. `xdk.i18n`

**职责**：Locale、消息目录、复数、数字/日期格式。  
**业界对齐**：ICU、Java ResourceBundle、.NET Resources。

### 17.1 类型

`Locale`、`MessageCatalog`、`MessageFormatter`、`PluralRules`、`NumberFormat`、`DateFormat`、`Translator`。

### 17.2 API

`Locale.parse(text)`、`language()`、`country()`、`variant()`、`toString()`。  
`MessageCatalog`：`MessageCatalog(locale)`、`load(path)`、`get(key)`、`getOr`、`has`、`add(key,value)`、`merge(other)`、`locales()`。  
`MessageFormatter`：`format(template,args)`、`plural(count,forms)`、`select(value,cases)`。  
`PluralRules`：`category(number)`、`select(number,forms)`。  
`NumberFormat`：`NumberFormat(locale)`、`format(value)`、`parse(text)`、`withPattern(pattern)`。  
`DateFormat`：`DateFormat(locale)`、`format(dateTime)`、`parse(text)`、`withPattern(pattern)`、`withTimeZone(zone)`。  
`Translator`：`Translator(catalog)`、`translate(key)`、`translateWithArgs(key,args)`、`withLocale(locale)`、`withCatalog(catalog)`。

---

## 18. `xdk.test`

**职责**：断言、测试注册、运行器。  
**业界对齐**：JUnit、pytest、.NET xUnit。

### 18.1 类型

`Assert`、`Test`、`TestSuite`、`TestRunner`、`TestResult`、`TestStatus`、`TestContext`。

### 18.2 API

`Assert`：`isTrue`、`isFalse`、`equals`、`notEquals`、`isNull`、`isNotNull`、`lessThan`、`greaterThan`、`contains`、`startsWith`、`endsWith`、`throwsError`、`fail`。  
`Test`：`Test(name,body)`、`name`、`tags`、`timeout`、`body`。  
`TestSuite`：`TestSuite(name)`、`add(test)`、`addAll(tests)`、`run()`、`results()`、`filter(tag)`。  
`TestRunner`：`run(suite)`、`runAll(suites)`、`runFiltered(predicate)`。  
`TestResult`：`name`、`status`、`duration`、`error`、`describe`。  
`TestStatus`：`Passed`、`Failed`、`Skipped`。  
`TestContext`：`name`、`log(text)`、`skip(reason)`、`fail(message)`。

---

## 19. `xdk.utils.resource`（已归并到 `xdk.sys.Resource`；不是独立包）

**职责**：内嵌资源读取。  
**业界对齐**：Go `embed`、Java resources、.NET embedded resources。

### 19.1 类型

`Resource`、`ResourceSet`、`Resources`、`ResourceOptions`。

### 19.2 API

`Resource`：`path()`、`size()`、`exists()`、`bytes()`、`text()`、`open()`、`close()`。  
`ResourceSet`：`ResourceSet(options)`、`get(path)`、`list(prefix)`、`exists(path)`、`size(path)`、`close()`。  
`Resources`：`exists(path)`、`size(path)`、`readBytes(Context,path)`、`readText(Context,path)`、`list(Context,prefix)`、`open(Context,path)`。  
`ResourceOptions`：`root`、`allowEmpty`、`maxBytes`。

---

## 20. `xdk.utils` 覆盖结论

| 包 | 业界基线 | API 面目标 |
| --- | --- | --- |
| codec | JSON/CSV/Base64/Hex | 完整 JSON 树/流式 CSV/编码工具 |
| crypto | Hash/HMAC/AES/KDF | 常用算法 + 常量时间 + 校验和 |
| compress | gzip/zlib/zip | 完整读写/归档 |
| random | PRNG/SecureRandom | 采样/洗牌/高斯/可种子 |
| uuid | UUID/ULID | v4/v7/ULID/Snowflake |
| regex | 完整正则 | 命名组/选项/集合/替换回调 |
| stats | 统计/回归/直方图 | 完整描述统计 + 直方图 + 回归 |
| validate | 字段/模式 | 规则组合/Schema/错误聚合 |
| cache | LRU/TTL/Loading | 完整缓存 + 统计 |
| queue | 有界/阻塞/批处理 | 完整队列/丢弃策略 |
| schedule | cron/周期 | 完整调度/JobHandle/Misfire |
| metrics | Counter/Gauge/Histogram/Timer | Registry/Exporter |
| trace | Span/Context | Tracer/Propagator/Sampler |
| health | readiness/liveness | 聚合/报告 |
| audit | 审计事件 | Sink/脱敏 |
| terminal | ANSI/进度/表格 | TTY/样式/交互 |
| i18n | 消息/复数/格式 | 目录/翻译/数字日期 |
| test | 断言/运行器 | Suite/Runner/Result |
| resource | 内嵌资源 | 读取/列出/流 |

---

## 21. 注解对接（P1）

注解是**编译期契约/生成入口**，不是运行时反射：`@Serializable` 等由构建期处理器生成编解码器，`@Validate` 生成校验器，`@Cacheable`/`@Retryable` 等生成包装器，`@TestCase`/`@Scheduled` 生成测试清单/作业注册。运行时只读生成的静态元数据。

| 包 | 注解 | 编译期检查 / 生成 |
| --- | --- | --- |
| `xdk.codec` | `@Serializable`、`@JsonName`、`@YamlName`、`@TomlName`、`@XmlName` | 编解码器、字段名映射 |
| `xdk.validate` | `@Validate`、`@Min`、`@Max`、`@Pattern`、`@Email` | 校验器生成 |
| `xdk.cache` / `xdk.resilience` | `@Cacheable`、`@CacheEvict`、`@Retryable`、`@CircuitBreakerPolicy`、`@RateLimit`、`@TimeoutPolicy` | 缓存/重试/熔断包装器 |
| `xdk.metrics` / `xdk.trace` / `xdk.audit` | `@Metered`、`@Traced`、`@Audited` | 指标/追踪/审计包装 |
| `xdk.test` / `xdk.schedule` | `@TestCase`、`@Before`、`@After`、`@Benchmark`、`@Scheduled` | 测试清单、作业注册 |

完整矩阵与处理器规则见 [`../ANNOTATION-SYSTEM.md`](../ANNOTATION-SYSTEM.md) §5；包计数按当前 24 包口径，不因注解维度重算。
