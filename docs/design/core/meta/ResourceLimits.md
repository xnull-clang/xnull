# `ResourceLimits`

| 项 | 值 |
| --- | --- |
| 类型 | `class ResourceLimits` |
| 包 | `xdk.meta` |
| 稳定性 | `preview` |
| 依赖 | `RuntimeRole` |

---

## 1. 定位

能力画像的统一资源上限快照：并发任务、连接、队列、请求/响应字节、文件、堆、重试、
默认截止和关闭截止。

不做：强制配额、cgroup、计费、内存分配器、运行时抢占。

---

## 2. 设计逻辑

- 所有字段不可变；修改通过 `with*` 返回新快照。
- `0` 表示“不限制/无默认”；负值非法，构造时 panic。
- 上限是**建议+合同**：核心/网络实现应尽量执行；无法执行时必须在文档声明。
- 默认值按 `RuntimeRole` 分组；客户端小、服务器大、工具小、库全 0。
- 上限不替代背压：队列满仍需 `Busy`/`Unavailable`/阻塞语义。
- 不提供全局上限；每个 `CoreProfile` 显式持有。

---

## 3. 表示与不变量

| 字段 | 类型 | 含义 | 0 的语义 |
| --- | --- | --- | --- |
| `_maxConcurrentTasks` | `Int` | 同时运行任务数 | 不限制 |
| `_maxConnections` | `Int` | 同时连接/会话数 | 不限制 |
| `_maxQueuedRequests` | `Int` | 等待队列长度 | 不排队 |
| `_maxRequestBytes` | `Long` | 单请求/单消息入站字节 | 不限制 |
| `_maxResponseBytes` | `Long` | 单响应/单消息出站字节 | 不限制 |
| `_maxOpenFiles` | `Int` | 同时打开文件数 | 不限制 |
| `_maxHeapBytes` | `Long` | 建议堆上限 | 不限制 |
| `_maxRetryAttempts` | `Int` | 默认重试次数 | 不重试 |
| `_defaultTimeoutMillis` | `Long` | 默认操作截止 | 无默认截止 |
| `_shutdownDeadlineMillis` | `Long` | 排空关闭最长等待 | 无限等待 |

不变量：所有字段 ≥ 0；不可变；默认值来自 `defaultsFor`；可跨任务只读共享。

---

## 4. 生命周期

构造后不可变；无 close；GC 管理；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ResourceLimits(...)` | 10 个上限 | 每个 ≥ 0 | 负值 → panic |

参数顺序固定：tasks、connections、queuedRequests、requestBytes、responseBytes、
openFiles、heapBytes、retryAttempts、defaultTimeoutMillis、shutdownDeadlineMillis。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `defaultsFor` | 角色默认值 | `RuntimeRole role` | `ResourceLimits` | null → panic |
| 读取 | 各字段 getter | 无 | `Int`/`Long` | 无 |
| `withMaxConcurrentTasks` | 派生 | `Int value` | `ResourceLimits` | 负值 → panic |
| `withMaxConnections` | 派生 | `Int value` | `ResourceLimits` | 负值 → panic |
| `withMaxQueuedRequests` | 派生 | `Int value` | `ResourceLimits` | 负值 → panic |
| `withMaxRequestBytes` | 派生 | `Long value` | `ResourceLimits` | 负值 → panic |
| `withMaxResponseBytes` | 派生 | `Long value` | `ResourceLimits` | 负值 → panic |
| `withMaxOpenFiles` | 派生 | `Int value` | `ResourceLimits` | 负值 → panic |
| `withMaxHeapBytes` | 派生 | `Long value` | `ResourceLimits` | 负值 → panic |
| `withMaxRetryAttempts` | 派生 | `Int value` | `ResourceLimits` | 负值 → panic |
| `withDefaultTimeoutMillis` | 派生 | `Long value` | `ResourceLimits` | 负值 → panic |
| `withShutdownDeadlineMillis` | 派生 | `Long value` | `ResourceLimits` | 负值 → panic |
| `isUnlimited` | 是否全 0 | 无 | `Bool` | 无 |
| `equals` | 值比较 | `ResourceLimits other` | `Bool` | null → false |
| `describe` | 稳定文本 | 无 | `String` | 无 |
| `copy` | 复制 | 无 | `ResourceLimits` | 无 |

---

## 8. 使用的技术

- 不可变值快照；
- 整数校验；
- 角色默认表；
- 字符串拼接。

---

## 9. 需要的支撑

- 语言：class、final 字段、Int、Long、Bool、String；
- 运行时：无；
- 接口：`RuntimeRole`。

---

## 10. 依赖的特性/接口/类

`RuntimeRole`。

---

## 11. 所有权与并发

不可变；可共享；无资源；无取消点。
相等：`equals` 做字段比较；`==` 仍是引用身份；不推荐作为 `Map` 键。

---

## 12. 示例与反例

正确：`CoreProfile.server().limits().withMaxConnections(4096)`。  
反例：用 0 当“禁止”；把上限当硬配额；负值表示无限；运行时修改共享快照。

---

## 13. 测试/场景义务

四个角色默认值；每个字段边界 0/1/最大值；负值 panic；派生不改原对象；equals；
isUnlimited；describe；客户端/服务器默认差异。

---

## 14. XNull 伪代码

```xnull
class ResourceLimits {
    final Int _maxConcurrentTasks
    final Int _maxConnections
    final Int _maxQueuedRequests
    final Long _maxRequestBytes
    final Long _maxResponseBytes
    final Int _maxOpenFiles
    final Long _maxHeapBytes
    final Int _maxRetryAttempts
    final Long _defaultTimeoutMillis
    final Long _shutdownDeadlineMillis

    ResourceLimits(Int maxConcurrentTasks, Int maxConnections, Int maxQueuedRequests,
                   Long maxRequestBytes, Long maxResponseBytes, Int maxOpenFiles,
                   Long maxHeapBytes, Int maxRetryAttempts,
                   Long defaultTimeoutMillis, Long shutdownDeadlineMillis) {
        if maxConcurrentTasks < 0 || maxConnections < 0 || maxQueuedRequests < 0 {
            throw "ResourceLimits: negative count"
        }
        if maxRequestBytes < 0 || maxResponseBytes < 0 || maxOpenFiles < 0 {
            throw "ResourceLimits: negative size"
        }
        if maxHeapBytes < 0 || maxRetryAttempts < 0 {
            throw "ResourceLimits: negative limit"
        }
        if defaultTimeoutMillis < 0 || shutdownDeadlineMillis < 0 {
            throw "ResourceLimits: negative deadline"
        }
        _maxConcurrentTasks = maxConcurrentTasks
        _maxConnections = maxConnections
        _maxQueuedRequests = maxQueuedRequests
        _maxRequestBytes = maxRequestBytes
        _maxResponseBytes = maxResponseBytes
        _maxOpenFiles = maxOpenFiles
        _maxHeapBytes = maxHeapBytes
        _maxRetryAttempts = maxRetryAttempts
        _defaultTimeoutMillis = defaultTimeoutMillis
        _shutdownDeadlineMillis = shutdownDeadlineMillis
    }

    static ResourceLimits defaultsFor(RuntimeRole role) {
        if role == null { throw "ResourceLimits.defaultsFor: null role" }
        if role == RuntimeRole.Client {
            return new ResourceLimits(8, 32, 8, 8388608, 33554432, 128, 0, 3, 30000, 3000)
        }
        if role == RuntimeRole.Server {
            return new ResourceLimits(1024, 4096, 1024, 16777216, 0, 8192, 0, 0, 15000, 30000)
        }
        if role == RuntimeRole.Tool {
            return new ResourceLimits(4, 1, 1, 8388608, 8388608, 64, 0, 1, 0, 1000)
        }
        return new ResourceLimits(0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    Int maxConcurrentTasks() { return _maxConcurrentTasks }
    Int maxConnections() { return _maxConnections }
    Int maxQueuedRequests() { return _maxQueuedRequests }
    Long maxRequestBytes() { return _maxRequestBytes }
    Long maxResponseBytes() { return _maxResponseBytes }
    Int maxOpenFiles() { return _maxOpenFiles }
    Long maxHeapBytes() { return _maxHeapBytes }
    Int maxRetryAttempts() { return _maxRetryAttempts }
    Long defaultTimeoutMillis() { return _defaultTimeoutMillis }
    Long shutdownDeadlineMillis() { return _shutdownDeadlineMillis }

    ResourceLimits withMaxConcurrentTasks(Int value) {
        if value < 0 { throw "ResourceLimits.withMaxConcurrentTasks: negative" }
        return new ResourceLimits(value, _maxConnections, _maxQueuedRequests,
            _maxRequestBytes, _maxResponseBytes, _maxOpenFiles, _maxHeapBytes,
            _maxRetryAttempts, _defaultTimeoutMillis, _shutdownDeadlineMillis)
    }

    ResourceLimits withMaxConnections(Int value) {
        if value < 0 { throw "ResourceLimits.withMaxConnections: negative" }
        return new ResourceLimits(_maxConcurrentTasks, value, _maxQueuedRequests,
            _maxRequestBytes, _maxResponseBytes, _maxOpenFiles, _maxHeapBytes,
            _maxRetryAttempts, _defaultTimeoutMillis, _shutdownDeadlineMillis)
    }

    ResourceLimits withMaxQueuedRequests(Int value) {
        if value < 0 { throw "ResourceLimits.withMaxQueuedRequests: negative" }
        return new ResourceLimits(_maxConcurrentTasks, _maxConnections, value,
            _maxRequestBytes, _maxResponseBytes, _maxOpenFiles, _maxHeapBytes,
            _maxRetryAttempts, _defaultTimeoutMillis, _shutdownDeadlineMillis)
    }

    ResourceLimits withMaxRequestBytes(Long value) {
        if value < 0 { throw "ResourceLimits.withMaxRequestBytes: negative" }
        return new ResourceLimits(_maxConcurrentTasks, _maxConnections, _maxQueuedRequests,
            value, _maxResponseBytes, _maxOpenFiles, _maxHeapBytes,
            _maxRetryAttempts, _defaultTimeoutMillis, _shutdownDeadlineMillis)
    }

    ResourceLimits withMaxResponseBytes(Long value) {
        if value < 0 { throw "ResourceLimits.withMaxResponseBytes: negative" }
        return new ResourceLimits(_maxConcurrentTasks, _maxConnections, _maxQueuedRequests,
            _maxRequestBytes, value, _maxOpenFiles, _maxHeapBytes,
            _maxRetryAttempts, _defaultTimeoutMillis, _shutdownDeadlineMillis)
    }

    ResourceLimits withMaxOpenFiles(Int value) {
        if value < 0 { throw "ResourceLimits.withMaxOpenFiles: negative" }
        return new ResourceLimits(_maxConcurrentTasks, _maxConnections, _maxQueuedRequests,
            _maxRequestBytes, _maxResponseBytes, value, _maxHeapBytes,
            _maxRetryAttempts, _defaultTimeoutMillis, _shutdownDeadlineMillis)
    }

    ResourceLimits withMaxHeapBytes(Long value) {
        if value < 0 { throw "ResourceLimits.withMaxHeapBytes: negative" }
        return new ResourceLimits(_maxConcurrentTasks, _maxConnections, _maxQueuedRequests,
            _maxRequestBytes, _maxResponseBytes, _maxOpenFiles, value,
            _maxRetryAttempts, _defaultTimeoutMillis, _shutdownDeadlineMillis)
    }

    ResourceLimits withMaxRetryAttempts(Int value) {
        if value < 0 { throw "ResourceLimits.withMaxRetryAttempts: negative" }
        return new ResourceLimits(_maxConcurrentTasks, _maxConnections, _maxQueuedRequests,
            _maxRequestBytes, _maxResponseBytes, _maxOpenFiles, _maxHeapBytes,
            value, _defaultTimeoutMillis, _shutdownDeadlineMillis)
    }

    ResourceLimits withDefaultTimeoutMillis(Long value) {
        if value < 0 { throw "ResourceLimits.withDefaultTimeoutMillis: negative" }
        return new ResourceLimits(_maxConcurrentTasks, _maxConnections, _maxQueuedRequests,
            _maxRequestBytes, _maxResponseBytes, _maxOpenFiles, _maxHeapBytes,
            _maxRetryAttempts, value, _shutdownDeadlineMillis)
    }

    ResourceLimits withShutdownDeadlineMillis(Long value) {
        if value < 0 { throw "ResourceLimits.withShutdownDeadlineMillis: negative" }
        return new ResourceLimits(_maxConcurrentTasks, _maxConnections, _maxQueuedRequests,
            _maxRequestBytes, _maxResponseBytes, _maxOpenFiles, _maxHeapBytes,
            _maxRetryAttempts, _defaultTimeoutMillis, value)
    }

    Bool isUnlimited() {
        return _maxConcurrentTasks == 0 && _maxConnections == 0
            && _maxQueuedRequests == 0 && _maxRequestBytes == 0
            && _maxResponseBytes == 0 && _maxOpenFiles == 0
            && _maxHeapBytes == 0 && _maxRetryAttempts == 0
            && _defaultTimeoutMillis == 0 && _shutdownDeadlineMillis == 0
    }

    Bool equals(ResourceLimits other) {
        if other == null { return false }
        return _maxConcurrentTasks == other.maxConcurrentTasks()
            && _maxConnections == other.maxConnections()
            && _maxQueuedRequests == other.maxQueuedRequests()
            && _maxRequestBytes == other.maxRequestBytes()
            && _maxResponseBytes == other.maxResponseBytes()
            && _maxOpenFiles == other.maxOpenFiles()
            && _maxHeapBytes == other.maxHeapBytes()
            && _maxRetryAttempts == other.maxRetryAttempts()
            && _defaultTimeoutMillis == other.defaultTimeoutMillis()
            && _shutdownDeadlineMillis == other.shutdownDeadlineMillis()
    }

    String describe() {
        return "tasks=" + str(_maxConcurrentTasks)
            + " connections=" + str(_maxConnections)
            + " queued=" + str(_maxQueuedRequests)
            + " requestBytes=" + str(_maxRequestBytes)
            + " responseBytes=" + str(_maxResponseBytes)
            + " openFiles=" + str(_maxOpenFiles)
            + " heapBytes=" + str(_maxHeapBytes)
            + " retries=" + str(_maxRetryAttempts)
            + " timeoutMs=" + str(_defaultTimeoutMillis)
            + " shutdownMs=" + str(_shutdownDeadlineMillis)
    }

    ResourceLimits copy() {
        return new ResourceLimits(_maxConcurrentTasks, _maxConnections, _maxQueuedRequests,
            _maxRequestBytes, _maxResponseBytes, _maxOpenFiles, _maxHeapBytes,
            _maxRetryAttempts, _defaultTimeoutMillis, _shutdownDeadlineMillis)
    }
}
```
