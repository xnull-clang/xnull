# `CoreProfile`

| 项 | 值 |
| --- | --- |
| 类型 | `class CoreProfile` |
| 包 | `xdk.meta` |
| 稳定性 | `preview` |
| 依赖 | `RuntimeRole`、`CapabilitySet`、`ResourceLimits`、`IoModel`、`ShutdownPolicy` |

---

## 1. 定位

不可变的程序能力画像：角色、能力集合、资源上限、I/O 偏好、关闭策略。用于启动校验、
功能开关、资源规划、客户端/服务器默认装配。

不做：权限系统、运行时探测、全局单例、配置解析、网络实现。

---

## 2. 设计逻辑

- 画像由构建常量、配置或测试构造；进程启动后只读。
- `standard(role)` 给四类角色默认值；`client/server/tool/library` 是便捷入口。
- 角色给默认值，能力给精确允许项；能力可以比角色默认更多或更少。
- 不依赖 `Error/Context`；失败通过 `Bool`/`List<Capability>` 表达，配置加载才用 `Result`。
- `isCoherent` 检查能力依赖关系，不强制角色能力；例如服务器可以额外有出站能力。
- 不持有资源；无 close；可跨任务共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_name` | `String` | final | 非空；画像名 |
| `_role` | `RuntimeRole` | final | 非 null |
| `_capabilities` | `CapabilitySet` | final | 非 null；不可变 |
| `_limits` | `ResourceLimits` | final | 非 null；不可变 |
| `_ioModel` | `IoModel` | final | 非 null |
| `_shutdownPolicy` | `ShutdownPolicy` | final | 非 null |

不变量：name 非空；所有字段非 null；`Deadline` 策略要求 `limits.shutdownDeadlineMillis >= 0`
（0 表示无限等待，`isCoherent` 返回 false）；不可变。

---

## 4. 生命周期

构造后不可变；无 close；GC 管理；可跨任务共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `CoreProfile(...)` | name/role/capabilities/limits/io/shutdown | 全部非 null；name 非空 | null/空名 → panic |

业务代码优先使用 `client/server/tool/library/standard` 或 `ProfileBuilder`。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `standard` | 角色默认画像 | `RuntimeRole role` | `CoreProfile` | null → panic |
| `client` | 客户端画像 | 无 | `CoreProfile` | 无 |
| `server` | 服务器画像 | 无 | `CoreProfile` | 无 |
| `tool` | 工具画像 | 无 | `CoreProfile` | 无 |
| `library` | 库画像 | 无 | `CoreProfile` | 无 |
| `name` | 画像名 | 无 | `String` | 无 |
| `role` | 角色 | 无 | `RuntimeRole` | 无 |
| `capabilities` | 能力集合 | 无 | `CapabilitySet` | 无 |
| `limits` | 资源上限 | 无 | `ResourceLimits` | 无 |
| `ioModel` | I/O 偏好 | 无 | `IoModel` | 无 |
| `shutdownPolicy` | 关闭策略 | 无 | `ShutdownPolicy` | 无 |
| `supports` | 是否支持能力 | `Capability capability` | `Bool` | null → panic |
| `missingCapabilities` | 缺少的能力 | `List<Capability> required` | `List<Capability>` | null → panic |
| `unsupportedBy` | 目标不支持的能力 | `TargetInfo target` | `List<Capability>` | null → panic |
| `isCoherent` | 能力依赖是否自洽 | 无 | `Bool` | 无 |
| `withName` | 派生名称 | `String value` | `CoreProfile` | 空名 → panic |
| `withCapability` | 派生添加能力 | `Capability capability` | `CoreProfile` | null → panic |
| `withoutCapability` | 派生移除能力 | `Capability capability` | `CoreProfile` | null → panic |
| `withCapabilities` | 派生替换能力 | `CapabilitySet value` | `CoreProfile` | null → panic |
| `withLimits` | 派生上限 | `ResourceLimits value` | `CoreProfile` | null → panic |
| `withIoModel` | 派生 I/O | `IoModel value` | `CoreProfile` | null → panic |
| `withShutdownPolicy` | 派生关闭 | `ShutdownPolicy value` | `CoreProfile` | null → panic |
| `describe` | 稳定文本 | 无 | `String` | 无 |
| `copy` | 复制 | 无 | `CoreProfile` | 无 |

说明：

- `supports` 只查声明，不查运行时是否成功。
- `missingCapabilities` 保序返回缺少项；不修改入参。
- `unsupportedBy` 把画像能力与 `TargetInfo` 目标能力对比；返回目标不支持项；不修改入参。
- `isCoherent` 规则见 §8。
- `with*` 返回新对象；原对象不变。

---

## 8. 使用的技术

- 不可变快照；
- 角色默认表；
- 能力依赖校验；
- 字符串描述。

### 8.1 `isCoherent` 规则

| 条件 | 结论 |
| --- | --- |
| `NetworkClient` 但无 `Network` | false |
| `NetworkServer` 但无 `Network` | false |
| `TlsClient`/`TlsServer` 但无 `Tls` | false |
| `HttpClient`/`WebSocketClient`/`ProxyClient` 但无 `NetworkClient` | false |
| `HttpServer`/`WebSocketServer`/`ProxyServer` 但无 `NetworkServer` | false |
| `Client` 角色含任一入站能力 | false |
| `Deadline` 策略且 `shutdownDeadlineMillis == 0` | false |
| 其他 | true |

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Bool、List；
- 运行时：无；
- 接口：`RuntimeRole`、`Capability`、`CapabilitySet`、`ResourceLimits`、`IoModel`、`ShutdownPolicy`、`TargetInfo`。

---

## 10. 依赖的特性/接口/类

`RuntimeRole`、`Capability`、`CapabilitySet`、`ResourceLimits`、`IoModel`、`ShutdownPolicy`、`TargetInfo`。

---

## 11. 所有权与并发

不可变；可跨任务共享；`capabilities`/`limits` 返回不可变快照；无资源；无取消点。
相等：引用身份；需要比较字段时显式比较 role/capabilities/limits；不推荐作为 `Map` 键。

---

## 12. 示例与反例

正确：

```xnull
CoreProfile profile = CoreProfile.server()
CoreProfile tight = profile.withLimits(profile.limits().withMaxConnections(512))
if !tight.isCoherent() { throw "incoherent profile" }
```

反例：客户端画像含 `NetworkServer`；`Deadline` 但截止为 0；运行时修改共享画像；
用画像替代权限校验。

---

## 13. 测试/场景义务

四个角色默认值；`standard` 分支；能力添加/移除；缺少能力；`unsupportedBy` 目标能力；
`isCoherent` 每条规则；客户端不含入站；服务器含入站；Deadline 截止；describe；复制独立性。

---

## 14. XNull 伪代码

```xnull
class CoreProfile {
    final String _name
    final RuntimeRole _role
    final CapabilitySet _capabilities
    final ResourceLimits _limits
    final IoModel _ioModel
    final ShutdownPolicy _shutdownPolicy

    CoreProfile(String name, RuntimeRole role, CapabilitySet capabilities,
                ResourceLimits limits, IoModel ioModel, ShutdownPolicy shutdownPolicy) {
        if name == null || name == "" { throw "CoreProfile: empty name" }
        if role == null || capabilities == null || limits == null {
            throw "CoreProfile: null field"
        }
        if ioModel == null || shutdownPolicy == null {
            throw "CoreProfile: null enum"
        }
        _name = name
        _role = role
        _capabilities = capabilities
        _limits = limits
        _ioModel = ioModel
        _shutdownPolicy = shutdownPolicy
    }

    static CoreProfile standard(RuntimeRole role) {
        if role == null { throw "CoreProfile.standard: null role" }
        if role == RuntimeRole.Client { return CoreProfile.client() }
        if role == RuntimeRole.Server { return CoreProfile.server() }
        if role == RuntimeRole.Tool { return CoreProfile.tool() }
        return CoreProfile.library()
    }

    static CoreProfile client() {
        List<Capability> capabilities = [
            Capability.Threads,
            Capability.Network,
            Capability.NetworkClient,
            Capability.Tls,
            Capability.TlsClient,
            Capability.HttpClient,
            Capability.WebSocketClient,
            Capability.DnsResolver,
            Capability.ProxyClient,
            Capability.CookieStore,
            Capability.Filesystem,
            Capability.Process,
            Capability.Signals,
            Capability.Unicode,
            Capability.Regex,
            Capability.Compression,
            Capability.Crypto,
            Capability.Random,
            Capability.SecureRandom,
            Capability.Stdio,
        ]
        return new CoreProfile(
            "client",
            RuntimeRole.Client,
            CapabilitySet.of(capabilities),
            ResourceLimits.defaultsFor(RuntimeRole.Client),
            IoModel.Blocking,
            ShutdownPolicy.Immediate
        )
    }

    static CoreProfile server() {
        List<Capability> capabilities = [
            Capability.Threads,
            Capability.Multicore,
            Capability.Network,
            Capability.NetworkServer,
            Capability.Tls,
            Capability.TlsServer,
            Capability.HttpServer,
            Capability.WebSocketServer,
            Capability.ProxyServer,
            Capability.DnsResolver,
            Capability.Signals,
            Capability.Filesystem,
            Capability.Process,
            Capability.ProcessSupervision,
            Capability.Unicode,
            Capability.Regex,
            Capability.Compression,
            Capability.Crypto,
            Capability.Random,
            Capability.SecureRandom,
            Capability.Stdio,
            Capability.FileWatch,
        ]
        return new CoreProfile(
            "server",
            RuntimeRole.Server,
            CapabilitySet.of(capabilities),
            ResourceLimits.defaultsFor(RuntimeRole.Server),
            IoModel.EventDriven,
            ShutdownPolicy.Deadline
        )
    }

    static CoreProfile tool() {
        List<Capability> capabilities = [
            Capability.Threads,
            Capability.Filesystem,
            Capability.Process,
            Capability.Signals,
            Capability.Stdio,
            Capability.Unicode,
            Capability.Regex,
            Capability.Compression,
            Capability.Crypto,
            Capability.Random,
        ]
        return new CoreProfile(
            "tool",
            RuntimeRole.Tool,
            CapabilitySet.of(capabilities),
            ResourceLimits.defaultsFor(RuntimeRole.Tool),
            IoModel.Blocking,
            ShutdownPolicy.Immediate
        )
    }

    static CoreProfile library() {
        return new CoreProfile(
            "library",
            RuntimeRole.Library,
            CapabilitySet.empty(),
            ResourceLimits.defaultsFor(RuntimeRole.Library),
            IoModel.Blocking,
            ShutdownPolicy.Immediate
        )
    }

    String name() { return _name }
    RuntimeRole role() { return _role }
    CapabilitySet capabilities() { return _capabilities }
    ResourceLimits limits() { return _limits }
    IoModel ioModel() { return _ioModel }
    ShutdownPolicy shutdownPolicy() { return _shutdownPolicy }

    Bool supports(Capability capability) {
        if capability == null { throw "CoreProfile.supports: null capability" }
        return _capabilities.has(capability)
    }

    List<Capability> missingCapabilities(List<Capability> required) {
        if required == null { throw "CoreProfile.missingCapabilities: null list" }
        List<Capability> result = []
        Int index = 0
        while index < required.length() {
            Capability capability = required.get(index)
            if !_capabilities.has(capability) {
                result.push(capability)
            }
            index = index + 1
        }
        return result
    }

    List<Capability> unsupportedBy(TargetInfo target) {
        if target == null { throw "CoreProfile.unsupportedBy: null target" }
        List<Capability> result = []
        List<Capability> values = _capabilities.toList()
        Int index = 0
        while index < values.length() {
            if !target.hasCapability(values.get(index)) {
                result.push(values.get(index))
            }
            index = index + 1
        }
        return result
    }

    Bool isCoherent() {
        if _capabilities.has(Capability.NetworkClient)
            && !_capabilities.has(Capability.Network) { return false }
        if _capabilities.has(Capability.NetworkServer)
            && !_capabilities.has(Capability.Network) { return false }
        if _capabilities.has(Capability.TlsClient)
            && !_capabilities.has(Capability.Tls) { return false }
        if _capabilities.has(Capability.TlsServer)
            && !_capabilities.has(Capability.Tls) { return false }
        if _capabilities.has(Capability.HttpClient)
            && !_capabilities.has(Capability.NetworkClient) { return false }
        if _capabilities.has(Capability.WebSocketClient)
            && !_capabilities.has(Capability.NetworkClient) { return false }
        if _capabilities.has(Capability.ProxyClient)
            && !_capabilities.has(Capability.NetworkClient) { return false }
        if _capabilities.has(Capability.HttpServer)
            && !_capabilities.has(Capability.NetworkServer) { return false }
        if _capabilities.has(Capability.WebSocketServer)
            && !_capabilities.has(Capability.NetworkServer) { return false }
        if _capabilities.has(Capability.ProxyServer)
            && !_capabilities.has(Capability.NetworkServer) { return false }
        if _role == RuntimeRole.Client {
            if _capabilities.has(Capability.NetworkServer) { return false }
            if _capabilities.has(Capability.TlsServer) { return false }
            if _capabilities.has(Capability.HttpServer) { return false }
            if _capabilities.has(Capability.WebSocketServer) { return false }
            if _capabilities.has(Capability.ProxyServer) { return false }
        }
        if _shutdownPolicy == ShutdownPolicy.Deadline
            && _limits.shutdownDeadlineMillis() == 0 { return false }
        return true
    }

    CoreProfile withName(String value) {
        if value == null || value == "" { throw "CoreProfile.withName: empty" }
        return new CoreProfile(value, _role, _capabilities, _limits,
            _ioModel, _shutdownPolicy)
    }

    CoreProfile withCapability(Capability capability) {
        if capability == null { throw "CoreProfile.withCapability: null" }
        return new CoreProfile(_name, _role, _capabilities.with(capability),
            _limits, _ioModel, _shutdownPolicy)
    }

    CoreProfile withoutCapability(Capability capability) {
        if capability == null { throw "CoreProfile.withoutCapability: null" }
        return new CoreProfile(_name, _role, _capabilities.without(capability),
            _limits, _ioModel, _shutdownPolicy)
    }

    CoreProfile withCapabilities(CapabilitySet value) {
        if value == null { throw "CoreProfile.withCapabilities: null" }
        return new CoreProfile(_name, _role, value, _limits, _ioModel, _shutdownPolicy)
    }

    CoreProfile withLimits(ResourceLimits value) {
        if value == null { throw "CoreProfile.withLimits: null" }
        return new CoreProfile(_name, _role, _capabilities, value, _ioModel, _shutdownPolicy)
    }

    CoreProfile withIoModel(IoModel value) {
        if value == null { throw "CoreProfile.withIoModel: null" }
        return new CoreProfile(_name, _role, _capabilities, _limits, value, _shutdownPolicy)
    }

    CoreProfile withShutdownPolicy(ShutdownPolicy value) {
        if value == null { throw "CoreProfile.withShutdownPolicy: null" }
        return new CoreProfile(_name, _role, _capabilities, _limits, _ioModel, value)
    }

    String describe() {
        return "profile " + _name
            + " role=" + runtimeRoleName(_role)
            + " io=" + ioModelName(_ioModel)
            + " shutdown=" + shutdownPolicyName(_shutdownPolicy)
            + " caps=[" + _capabilities.describe() + "]"
            + " limits={" + _limits.describe() + "}"
    }

    CoreProfile copy() {
        return new CoreProfile(_name, _role, _capabilities.copy(), _limits.copy(),
            _ioModel, _shutdownPolicy)
    }
}
```
