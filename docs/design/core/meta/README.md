# `xdk.meta` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.meta` |
| 层 | `xdk.core` / L1 |
| 依赖 | 无（构建期常量/目标平台由运行时提供） |
| 被依赖 | `runtime`、`log`、`cli`、`config` |
| 稳定性 | 基础字段 `stable`；依赖/能力矩阵 `preview` |
| 文档原则 | 包级说明在本 README；每个类一个 PascalCase 文件 |

---

## 1. 包定位

`xdk.meta` 提供构建/目标平台只读元数据：

- 语言版本、XDK 版本；
- 目标平台、架构、构建模式、构建 ID；
- 目标能力矩阵；
- 依赖名称/版本；
- 构建角色、能力画像、资源上限、I/O 偏好、关闭策略。

不做：构建系统、包管理、依赖解析、编译配置、许可证管理、运行时能力探测。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 只读快照 | 所有类型不可变；需要最新值重新调用 |
| 无全局状态 | 不维护全局元数据单例 |
| 可复现 | `buildId` 可复现；`builtAt` 只作诊断，可为空，不参与缓存/排序 |
| 目标 ≠ 运行时 | 能力是构建目标支持，不是当前进程保证 |
| 版本是字符串 | 不把 semver 比较塞进 meta |
| 依赖是快照 | 不解析、不加载、不联网 |
| 画像是快照 | `CoreProfile` 只读；不作为权限/运行时开关 |
| 角色给默认 | `RuntimeRole` 给默认能力/上限；`Capability` 给精确允许 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `Capability` | enum | 目标能力标记 | [`Capability.md`](Capability.md) |
| `CapabilitySet` | class | 不可变能力集合 | [`CapabilitySet.md`](CapabilitySet.md) |
| `RuntimeRole` | enum | 构建角色 | [`RuntimeRole.md`](RuntimeRole.md) |
| `IoModel` | enum | I/O 偏好 | [`IoModel.md`](IoModel.md) |
| `ShutdownPolicy` | enum | 关闭策略 | [`ShutdownPolicy.md`](ShutdownPolicy.md) |
| `ResourceLimits` | class | 资源上限快照 | [`ResourceLimits.md`](ResourceLimits.md) |
| `CoreProfile` | class | 角色能力画像 | [`CoreProfile.md`](CoreProfile.md) |
| `ProfileBuilder` | class | 画像构造器 | [`ProfileBuilder.md`](ProfileBuilder.md) |
| `DependencyInfo` | class | 依赖名/版本/可选 | [`DependencyInfo.md`](DependencyInfo.md) |
| `BuildInfo` | class | 构建元数据快照 | [`BuildInfo.md`](BuildInfo.md) |
| `TargetInfo` | class | 目标平台/能力快照 | [`TargetInfo.md`](TargetInfo.md) |

---

## 4. 顶层函数

### 4.1 方法面

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `languageVersion` | 语言版本 | 无 | `String` | 无 |
| `xdkVersion` | XDK 版本 | 无 | `String` | 无 |
| `compilerName` | 编译器名 | 无 | `String` | 无 |
| `compilerVersion` | 编译器版本 | 无 | `String` | 无 |
| `buildDate` | 构建时间文本（诊断） | 无 | `String` | 无；可为空/不可复现 |
| `targetPlatform` | 目标平台 | 无 | `String` | 无 |
| `buildInfo` | 构建快照 | 无 | `BuildInfo` | 无 |
| `targetInfo` | 目标快照 | 无 | `TargetInfo` | 无 |
| `hasCapability` | 目标能力查询 | `Capability capability` | `Bool` | 无 |
| `targetCapabilities` | 能力快照 | 无 | `List<Capability>` | 无 |
| `dependencyVersion` | 依赖版本 | `String name` | `String?` | 无 |
| `capabilityName` | 能力稳定名 | `Capability capability` | `String` | 无 |
| `capabilityFromName` | 能力名称解析 | `String name` | `Capability?` | 无 |
| `runtimeRoleName` | 角色稳定名 | `RuntimeRole role` | `String` | 无 |
| `runtimeRoleDisplayName` | 角色显示名 | `RuntimeRole role` | `String` | 无 |
| `runtimeRoleFromName` | 角色解析 | `String name` | `RuntimeRole?` | 无 |
| `ioModelName` | I/O 模型稳定名 | `IoModel model` | `String` | 无 |
| `ioModelFromName` | I/O 模型解析 | `String name` | `IoModel?` | 无 |
| `shutdownPolicyName` | 关闭策略稳定名 | `ShutdownPolicy policy` | `String` | 无 |
| `shutdownPolicyFromName` | 关闭策略解析 | `String name` | `ShutdownPolicy?` | 无 |

### 4.2 使用的技术

- 构建期常量；
- 不可变快照；
- 能力列表；
- 依赖表线性查找；
- 字符串映射；
- 角色/能力画像；
- 资源上限校验。

### 4.3 需要的支撑

- 语言：String、Bool、List；
- 运行时/构建：语言/XDK 版本、目标平台、架构、构建模式、构建 ID、依赖表、能力表；
- 接口：`BuildInfo`、`TargetInfo`、`Capability`、`DependencyInfo`、`RuntimeRole`、`CapabilitySet`、
  `ResourceLimits`、`CoreProfile`、`ProfileBuilder`。

### 4.4 依赖的特性/接口/类

`BuildInfo`、`TargetInfo`、`Capability`、`DependencyInfo`、`RuntimeRole`、`IoModel`、
`ShutdownPolicy`、`CapabilitySet`、`ResourceLimits`、`CoreProfile`、`ProfileBuilder`。

### 4.5 XNull 伪代码

```xnull
String languageVersion() {
    return buildInfo().languageVersion()
}

String xdkVersion() {
    return buildInfo().xdkVersion()
}

String targetPlatform() {
    return buildInfo().targetPlatform()
}

BuildInfo buildInfo() {
    List<DependencyInfo> dependencies = []
    dependencies.push(new DependencyInfo("xdk.errors", XDK_ERRORS_VERSION, false))
    dependencies.push(new DependencyInfo("xdk.runtime", XDK_RUNTIME_VERSION, false))
    dependencies.push(new DependencyInfo("xdk.meta", XDK_META_VERSION, false))
    return new BuildInfo(
        LANG_VERSION,
        XDK_VERSION,
        compilerName(),
        compilerVersion(),
        TARGET_PLATFORM,
        TARGET_ARCH,
        BUILD_MODE,
        BUILD_ID,
        buildDate(),
        dependencies
    )
}

TargetInfo targetInfo() {
    List<Capability> capabilities = []
    capabilities.push(Capability.Threads)
    capabilities.push(Capability.Network)
    capabilities.push(Capability.Tls)
    capabilities.push(Capability.Filesystem)
    capabilities.push(Capability.Process)
    capabilities.push(Capability.Signals)
    capabilities.push(Capability.Unicode)
    capabilities.push(Capability.Regex)
    capabilities.push(Capability.Compression)
    capabilities.push(Capability.Crypto)
    capabilities.push(Capability.Random)
    capabilities.push(Capability.NetworkClient)
    capabilities.push(Capability.NetworkServer)
    capabilities.push(Capability.TlsClient)
    capabilities.push(Capability.TlsServer)
    capabilities.push(Capability.HttpClient)
    capabilities.push(Capability.HttpServer)
    capabilities.push(Capability.WebSocketClient)
    capabilities.push(Capability.WebSocketServer)
    capabilities.push(Capability.DnsResolver)
    capabilities.push(Capability.ProxyClient)
    capabilities.push(Capability.ProxyServer)
    capabilities.push(Capability.CookieStore)
    capabilities.push(Capability.Pty)
    capabilities.push(Capability.FileWatch)
    capabilities.push(Capability.Locale)
    capabilities.push(Capability.TimeZoneDatabase)
    capabilities.push(Capability.SecureRandom)
    capabilities.push(Capability.ProcessSupervision)
    capabilities.push(Capability.Stdio)
    capabilities.push(Capability.Multicore)
    return new TargetInfo(
        TARGET_OS,
        TARGET_ARCH,
        TARGET_FAMILY,
        TARGET_POINTER_BITS,
        TARGET_ENDIAN,
        capabilities
    )
}

Bool hasCapability(Capability capability) {
    return targetInfo().hasCapability(capability)
}

List<Capability> targetCapabilities() {
    return targetInfo().capabilities()
}

String? dependencyVersion(String name) {
    return buildInfo().dependencyVersion(name)
}

String capabilityName(Capability capability) {
    if capability == Capability.Threads { return "threads" }
    if capability == Capability.Network { return "network" }
    if capability == Capability.Tls { return "tls" }
    if capability == Capability.Filesystem { return "filesystem" }
    if capability == Capability.Process { return "process" }
    if capability == Capability.Signals { return "signals" }
    if capability == Capability.Unicode { return "unicode" }
    if capability == Capability.Regex { return "regex" }
    if capability == Capability.Compression { return "compression" }
    if capability == Capability.Crypto { return "crypto" }
    if capability == Capability.Random { return "random" }
    if capability == Capability.DynamicLibrary { return "dynamic_library" }
    if capability == Capability.NetworkClient { return "network_client" }
    if capability == Capability.NetworkServer { return "network_server" }
    if capability == Capability.TlsClient { return "tls_client" }
    if capability == Capability.TlsServer { return "tls_server" }
    if capability == Capability.HttpClient { return "http_client" }
    if capability == Capability.HttpServer { return "http_server" }
    if capability == Capability.WebSocketClient { return "websocket_client" }
    if capability == Capability.WebSocketServer { return "websocket_server" }
    if capability == Capability.DnsResolver { return "dns_resolver" }
    if capability == Capability.ProxyClient { return "proxy_client" }
    if capability == Capability.ProxyServer { return "proxy_server" }
    if capability == Capability.CookieStore { return "cookie_store" }
    if capability == Capability.Pty { return "pty" }
    if capability == Capability.FileWatch { return "file_watch" }
    if capability == Capability.Locale { return "locale" }
    if capability == Capability.TimeZoneDatabase { return "timezone_database" }
    if capability == Capability.SecureRandom { return "secure_random" }
    if capability == Capability.ProcessSupervision { return "process_supervision" }
    if capability == Capability.Stdio { return "stdio" }
    if capability == Capability.Multicore { return "multicore" }
    return "unknown"
}

Capability? capabilityFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "threads" { return Capability.Threads }
    if normalized == "network" { return Capability.Network }
    if normalized == "tls" { return Capability.Tls }
    if normalized == "filesystem" { return Capability.Filesystem }
    if normalized == "process" { return Capability.Process }
    if normalized == "signals" { return Capability.Signals }
    if normalized == "unicode" { return Capability.Unicode }
    if normalized == "regex" { return Capability.Regex }
    if normalized == "compression" { return Capability.Compression }
    if normalized == "crypto" { return Capability.Crypto }
    if normalized == "random" { return Capability.Random }
    if normalized == "dynamic_library" { return Capability.DynamicLibrary }
    if normalized == "network_client" { return Capability.NetworkClient }
    if normalized == "network_server" { return Capability.NetworkServer }
    if normalized == "tls_client" { return Capability.TlsClient }
    if normalized == "tls_server" { return Capability.TlsServer }
    if normalized == "http_client" { return Capability.HttpClient }
    if normalized == "http_server" { return Capability.HttpServer }
    if normalized == "websocket_client" { return Capability.WebSocketClient }
    if normalized == "websocket_server" { return Capability.WebSocketServer }
    if normalized == "dns_resolver" { return Capability.DnsResolver }
    if normalized == "proxy_client" { return Capability.ProxyClient }
    if normalized == "proxy_server" { return Capability.ProxyServer }
    if normalized == "cookie_store" { return Capability.CookieStore }
    if normalized == "pty" { return Capability.Pty }
    if normalized == "file_watch" { return Capability.FileWatch }
    if normalized == "locale" { return Capability.Locale }
    if normalized == "timezone_database" { return Capability.TimeZoneDatabase }
    if normalized == "secure_random" { return Capability.SecureRandom }
    if normalized == "process_supervision" { return Capability.ProcessSupervision }
    if normalized == "stdio" { return Capability.Stdio }
    if normalized == "multicore" { return Capability.Multicore }
    return null
}

String runtimeRoleName(RuntimeRole role) {
    if role == RuntimeRole.Client { return "client" }
    if role == RuntimeRole.Server { return "server" }
    if role == RuntimeRole.Tool { return "tool" }
    return "library"
}

String runtimeRoleDisplayName(RuntimeRole role) {
    if role == RuntimeRole.Client { return "Client" }
    if role == RuntimeRole.Server { return "Server" }
    if role == RuntimeRole.Tool { return "Tool" }
    return "Library"
}

RuntimeRole? runtimeRoleFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "client" { return RuntimeRole.Client }
    if normalized == "server" { return RuntimeRole.Server }
    if normalized == "tool" { return RuntimeRole.Tool }
    if normalized == "library" { return RuntimeRole.Library }
    return null
}

String ioModelName(IoModel model) {
    if model == IoModel.Blocking { return "blocking" }
    if model == IoModel.ThreadPerConnection { return "thread_per_connection" }
    if model == IoModel.EventDriven { return "event_driven" }
    return "hybrid"
}

IoModel? ioModelFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "blocking" { return IoModel.Blocking }
    if normalized == "thread_per_connection" { return IoModel.ThreadPerConnection }
    if normalized == "event_driven" { return IoModel.EventDriven }
    if normalized == "hybrid" { return IoModel.Hybrid }
    return null
}

String shutdownPolicyName(ShutdownPolicy policy) {
    if policy == ShutdownPolicy.Immediate { return "immediate" }
    if policy == ShutdownPolicy.Drain { return "drain" }
    return "deadline"
}

ShutdownPolicy? shutdownPolicyFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "immediate" { return ShutdownPolicy.Immediate }
    if normalized == "drain" { return ShutdownPolicy.Drain }
    if normalized == "deadline" { return ShutdownPolicy.Deadline }
    return null
}
```

---

## 5. 场景

### M1：`--version` / bug report

`buildInfo().describe()` + `targetInfo().describe()`；输出语言/XDK/平台/架构/构建 ID/能力摘要。验收：信息可复制到 issue；不含敏感路径。

### M2：功能开关

启动时 `hasCapability(Capability.Tls)`；不支持则禁用 TLS 路径或退出；不得假装支持。验收：目标能力与运行时错误分开处理。

### M3：依赖审计

`buildInfo().dependencies()` + `dependencyVersion(name)`；列出名称/版本/可选。验收：缺失依赖返回 null，不 panic。

### M4：启动横幅

`languageVersion()`/`xdkVersion()`/`targetPlatform()` 写日志；与 `runtime.runtimeInfo()` 区分：meta 是构建目标，runtime 是进程实例。

### M5：跨平台条件

`targetInfo().os()`/`arch()` 做构建期条件；运行期行为仍用能力/错误处理。验收：不用 `os` 字符串替代能力查询。

### M6：客户端/服务器画像

`CoreProfile.client()`/`server()`；`ProfileBuilder` 派生；`isCoherent` 校验入站/出站能力与
`Deadline` 截止。验收：客户端默认不含入站能力；服务器默认含入站能力与 30s 关闭截止；
不支持的画像在启动时报配置错误。

### M7：资源规划

`CoreProfile.limits()` 读取上限；与 `Executor`/`Semaphore`/服务器 options 对齐。验收：
0 表示不限制/停用；负值 panic；客户端与服务器默认值不同且可显式覆盖。

---

## 6. 缺口与决策

| 项 | 决策/缺口 |
| --- | --- |
| 构建时间戳 | `buildDate` 保留为诊断字段；可为空/不可复现，不参与缓存/排序/业务判断 |
| 编译器内部信息 | 不进入 XDK 公共面 |
| semver 比较 | 不提供；版本是字符串 |
| 运行时能力探测 | meta 只给目标能力；运行时探测为 X |
| 依赖图/许可证 | 不提供；包管理/合规为 ecosystem |
| 动态能力 | `DynamicLibrary` 只表示目标支持，不表示已加载 |
| ABI 版本 | 未进入 meta；需要时单独设计 |
| 依赖重复 | `DependencyInfo` 列表由构建保证唯一；meta 不做去重 |

## 9. 1.x 兼容合同（C7）

| 1.x API | 2.x 合同 | 失败/边界 |
| --- | --- | --- |
| `BuildInfo`（8 字段 + `complete`） | [`BuildInfo.md`](BuildInfo.md)；保留 `compiler`/`compilerVersion`/`builtAt`，新增 `buildId`/dependencies | `builtAt` 仅诊断、可为空；`complete()` 不要求 builtAt |
| `buildInfo()` | 顶层 `buildInfo`；返回不可变快照 | 无 |
| `buildDate()` | 顶层 `buildDate`；返回构建时间文本 | 可为空/不可复现；不得用于业务/缓存 |
| `compilerName()` / `compilerVersion()` | 顶层同名函数 | 诊断字段；不是 ABI 承诺 |
| `targetPlatform()` / `targetArch()` / `buildMode()` | 顶层 `targetPlatform`/`targetArch`/`buildMode` | 未知平台空串/`"unknown"` 按实现 |
| 目标/能力清单 | `TargetInfo`/`Capability`/`CapabilitySet`/`targetInfo`/`hasCapability` | 1.x 只有构建期 TSV，没有运行时查询；2.x 为增量，不声称 1.x 已实现 |

示例：

```xnull
BuildInfo info = buildInfo()
Bool complete = info.complete()
String builtAt = buildDate()
Bool tls = hasCapability(Capability.Tls)
```

测试义务：`compiler`/`compilerVersion`/`builtAt` 读取；`complete()` 空/非空；`buildDate` 空值与诊断用途；`buildId` 可复现断言；`TargetInfo`/`Capability` 为 2.x 增量测试。
