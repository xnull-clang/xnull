# `ConfigProfileSource`

| 项 | 值 |
| --- | --- |
| 类型 | `class ConfigProfileSource implements ProfileSource` |
| 包 | `xdk.config` |
| 稳定性 | `preview` |
| 依赖 | `Config`、`CoreProfile`、`RuntimeRole`、`Capability`、`ResourceLimits`、`IoModel`、`ShutdownPolicy`、`Context`、`Error` |

---

## 1. 定位

从 `Config` 快照读取一个完整 `CoreProfile`：角色、能力、资源上限、I/O 模型和关闭策略。

不做：文件/环境读取（由 `ConfigLoader` 完成）、热更新、网络拉取、权限校验。

---

## 2. 设计逻辑

- 构造时持有 `Config` 引用；`load` 每次读取当前快照，不缓存。
- 键前缀默认 `"profile"`；允许调用方自定义，便于多画像。
- `role` 必填；缺失/未知 → `InvalidArgument`。
- `name` 缺省用角色标准名；`capabilities` 缺省用角色标准能力；提供时**替换**标准能力。
- 上限逐项覆盖；缺省用角色默认值；数字解析失败 → `InvalidArgument`。
- `shutdown=deadline` 但截止为 0 → `InvalidArgument`（不自洽）。
- 构造 `CoreProfile` 后必须 `isCoherent()`；不自洽 → `InvalidArgument`。
- 取消检查在解析前后各一次；不执行阻塞 I/O。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_config` | `Config` | final | 非 null |
| `_prefix` | `String` | final | 非空；默认 `"profile"` |

不变量：config/prefix 非 null；prefix 不含空白/换行；不修改 config；非线程安全取决于 Config。

---

## 4. 生命周期

构造后使用；无 close；不拥有 Config；Config 由调用方管理。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ConfigProfileSource(Config config)` | config | 非 null | null → panic |
| `ConfigProfileSource(Config config, String prefix)` | config/prefix | 非 null；prefix 非空 | null/空 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `load` | 解析画像 | `Context context` | `Result<CoreProfile, Error>` | `InvalidArgument`/`Cancelled` |
| `name` | 来源名 | 无 | `String` | 无 |
| `prefix` | 键前缀 | 无 | `String` | 无 |

### 7.1 配置键

| 键（相对 prefix） | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `.role` | String | 是 | `client/server/tool/library` |
| `.name` | String | 否 | 画像名 |
| `.io` | String | 否 | `blocking/thread_per_connection/event_driven/hybrid` |
| `.shutdown` | String | 否 | `immediate/drain/deadline` |
| `.capabilities` | String | 否 | 逗号分隔能力名；空串表示空集合 |
| `.maxConcurrentTasks` | Int | 否 | 0 = 不限制 |
| `.maxConnections` | Int | 否 | 0 = 不限制 |
| `.maxQueuedRequests` | Int | 否 | 0 = 不排队 |
| `.maxRequestBytes` | Long | 否 | 0 = 不限制 |
| `.maxResponseBytes` | Long | 否 | 0 = 不限制 |
| `.maxOpenFiles` | Int | 否 | 0 = 不限制 |
| `.maxHeapBytes` | Long | 否 | 0 = 不限制 |
| `.maxRetryAttempts` | Int | 否 | 0 = 不重试 |
| `.defaultTimeoutMillis` | Long | 否 | 0 = 无默认截止 |
| `.shutdownDeadlineMillis` | Long | 否 | 0 = 无限等待 |

---

## 8. 使用的技术

- 配置快照读取；
- 枚举名称解析；
- 数字解析；
- 能力集合构造；
- 画像一致性校验。

---

## 9. 需要的支撑

- 语言：class、protocol 实现、List、String、Int、Long、Bool、Result；
- 运行时：无；
- 接口：`Config`、`CoreProfile`、`Capability`、`capabilityFromName`、`RuntimeRole`、
  `runtimeRoleFromName`、`IoModel`、`ioModelFromName`、`ShutdownPolicy`、
  `shutdownPolicyFromName`、`ResourceLimits`、`Context`、`BasicError`、`text.split`、`text.trim`。

---

## 10. 依赖的特性/接口/类

`Config`、`CoreProfile`、`Capability`、`CapabilitySet`、`ResourceLimits`、`RuntimeRole`、
`IoModel`、`ShutdownPolicy`、`Context`、`BasicError`。

---

## 11. 所有权与并发

引用 Config；不修改；`load` 只读；Config 若被并发修改由调用方同步；无资源；可取消。
相等：引用身份；不推荐作为 `Map` 键。

---

## 12. 示例与反例

正确：

```xnull
Config config = new Config("prod")
config.set("profile.role", "server")
config.set("profile.maxConnections", "4096")
ProfileSource source = new ConfigProfileSource(config, "profile")
Result<CoreProfile, Error> profile = source.load(context)
```

反例：缺 `role`；`capabilities` 含未知名；`deadline` 但截止 0；把 Config 当热更新源；
在 `load` 中读文件/环境。

---

## 13. 测试/场景义务

四类角色；缺省值；每个上限覆盖；非法枚举/数字；未知能力；空能力串；deadline 截止 0；
取消；自定义 prefix；多次 load 一致；不自洽画像拒绝。

---

## 14. XNull 伪代码

```xnull
class ConfigProfileSource implements ProfileSource {
    final Config _config
    final String _prefix

    ConfigProfileSource(Config config) {
        if config == null { throw "ConfigProfileSource: null config" }
        _config = config
        _prefix = "profile"
    }

    ConfigProfileSource(Config config, String prefix) {
        if config == null { throw "ConfigProfileSource: null config" }
        if prefix == null || prefix == "" {
            throw "ConfigProfileSource: empty prefix"
        }
        _config = config
        _prefix = prefix
    }

    Result<CoreProfile, Error> load(Context context) {
        if context == null { throw "ConfigProfileSource.load: null context" }
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "profile load cancelled"))
        }
        String roleText = _config.getOr(_prefix + ".role", "")
        if roleText == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "profile.role is required"))
        }
        RuntimeRole? role = runtimeRoleFromName(roleText)
        if role == null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "unknown profile role: " + roleText))
        }
        CoreProfile base = CoreProfile.standard(role as RuntimeRole)

        Result<ResourceLimits, Error> limitsResult = self.readLimits(role as RuntimeRole)
        if limitsResult.isErr() { return Err(limitsResult.error()) }
        ResourceLimits limits = limitsResult.value()

        Result<IoModel, Error> ioResult = self.readIoModel(base.ioModel())
        if ioResult.isErr() { return Err(ioResult.error()) }
        IoModel ioModel = ioResult.value()

        Result<ShutdownPolicy, Error> shutdownResult = self.readShutdownPolicy(base.shutdownPolicy())
        if shutdownResult.isErr() { return Err(shutdownResult.error()) }
        ShutdownPolicy shutdownPolicy = shutdownResult.value()

        Result<CapabilitySet, Error> capsResult = self.readCapabilities(base.capabilities())
        if capsResult.isErr() { return Err(capsResult.error()) }
        CapabilitySet capabilities = capsResult.value()

        String name = _config.getOr(_prefix + ".name", base.name())
        if name == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "profile.name must not be empty"))
        }
        CoreProfile profile = new CoreProfile(name, role as RuntimeRole, capabilities,
            limits, ioModel, shutdownPolicy)
        if !profile.isCoherent() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "profile is incoherent: " + profile.describe()))
        }
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "profile load cancelled"))
        }
        return Ok(profile)
    }

    String name() {
        return "config:" + _prefix
    }

    String prefix() { return _prefix }

    private Result<ResourceLimits, Error> readLimits(RuntimeRole role) {
        ResourceLimits limits = ResourceLimits.defaultsFor(role)
        Result<Int, Error> tasks = self.overrideInt("maxConcurrentTasks",
            limits.maxConcurrentTasks())
        if tasks.isErr() { return Err(tasks.error()) }
        limits = limits.withMaxConcurrentTasks(tasks.value())

        Result<Int, Error> connections = self.overrideInt("maxConnections",
            limits.maxConnections())
        if connections.isErr() { return Err(connections.error()) }
        limits = limits.withMaxConnections(connections.value())

        Result<Int, Error> queued = self.overrideInt("maxQueuedRequests",
            limits.maxQueuedRequests())
        if queued.isErr() { return Err(queued.error()) }
        limits = limits.withMaxQueuedRequests(queued.value())

        Result<Long, Error> requestBytes = self.overrideLong("maxRequestBytes",
            limits.maxRequestBytes())
        if requestBytes.isErr() { return Err(requestBytes.error()) }
        limits = limits.withMaxRequestBytes(requestBytes.value())

        Result<Long, Error> responseBytes = self.overrideLong("maxResponseBytes",
            limits.maxResponseBytes())
        if responseBytes.isErr() { return Err(responseBytes.error()) }
        limits = limits.withMaxResponseBytes(responseBytes.value())

        Result<Int, Error> openFiles = self.overrideInt("maxOpenFiles",
            limits.maxOpenFiles())
        if openFiles.isErr() { return Err(openFiles.error()) }
        limits = limits.withMaxOpenFiles(openFiles.value())

        Result<Long, Error> heapBytes = self.overrideLong("maxHeapBytes",
            limits.maxHeapBytes())
        if heapBytes.isErr() { return Err(heapBytes.error()) }
        limits = limits.withMaxHeapBytes(heapBytes.value())

        Result<Int, Error> retries = self.overrideInt("maxRetryAttempts",
            limits.maxRetryAttempts())
        if retries.isErr() { return Err(retries.error()) }
        limits = limits.withMaxRetryAttempts(retries.value())

        Result<Long, Error> timeout = self.overrideLong("defaultTimeoutMillis",
            limits.defaultTimeoutMillis())
        if timeout.isErr() { return Err(timeout.error()) }
        limits = limits.withDefaultTimeoutMillis(timeout.value())

        Result<Long, Error> shutdown = self.overrideLong("shutdownDeadlineMillis",
            limits.shutdownDeadlineMillis())
        if shutdown.isErr() { return Err(shutdown.error()) }
        limits = limits.withShutdownDeadlineMillis(shutdown.value())
        return Ok(limits)
    }

    private Result<Int, Error> overrideInt(String suffix, Int fallback) {
        String key = _prefix + "." + suffix
        if !_config.has(key) { return Ok(fallback) }
        return _config.tryGetInt(key)
    }

    private Result<Long, Error> overrideLong(String suffix, Long fallback) {
        String key = _prefix + "." + suffix
        if !_config.has(key) { return Ok(fallback) }
        return _config.tryGetLong(key)
    }

    private Result<IoModel, Error> readIoModel(IoModel fallback) {
        String key = _prefix + ".io"
        if !_config.has(key) { return Ok(fallback) }
        String text = _config.getOr(key, "")
        IoModel? value = ioModelFromName(text)
        if value == null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "unknown io model: " + text))
        }
        return Ok(value as IoModel)
    }

    private Result<ShutdownPolicy, Error> readShutdownPolicy(ShutdownPolicy fallback) {
        String key = _prefix + ".shutdown"
        if !_config.has(key) { return Ok(fallback) }
        String text = _config.getOr(key, "")
        ShutdownPolicy? value = shutdownPolicyFromName(text)
        if value == null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "unknown shutdown policy: " + text))
        }
        return Ok(value as ShutdownPolicy)
    }

    private Result<CapabilitySet, Error> readCapabilities(CapabilitySet fallback) {
        String key = _prefix + ".capabilities"
        if !_config.has(key) { return Ok(fallback) }
        String text = _config.getOr(key, "")
        if trim(text) == "" { return Ok(CapabilitySet.empty()) }
        List<String> parts = split(text, ",")
        List<Capability> values = []
        Int index = 0
        while index < parts.length() {
            String part = trim(parts.get(index))
            if part == "" { return Err(new BasicError(ErrorKind.InvalidArgument,
                "empty capability name")) }
            Capability? capability = capabilityFromName(part)
            if capability == null {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "unknown capability: " + part))
            }
            values.push(capability as Capability)
            index = index + 1
        }
        return Ok(CapabilitySet.of(values))
    }
}
```
