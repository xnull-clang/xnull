# `ProfileBuilder`

| 项 | 值 |
| --- | --- |
| 类型 | `class ProfileBuilder` |
| 包 | `xdk.meta` |
| 稳定性 | `preview` |
| 依赖 | `CoreProfile`、`RuntimeRole`、`CapabilitySet`、`ResourceLimits`、`IoModel`、`ShutdownPolicy` |

---

## 1. 定位

`CoreProfile` 的可变构造器：逐步设置角色、名称、能力、上限、I/O 与关闭策略，最后
生成不可变画像。

不做：配置解析、全局注册、运行时热更新、权限校验。

---

## 2. 设计逻辑

- 构造器只在装配期使用；`build()` 返回不可变 `CoreProfile`。
- `build()` 不冻结 builder；之后继续修改只影响下一次 `build()`，不影响已生成画像。
- `from(profile)` 复制已有画像，便于派生。
- `role` 只改角色，不自动套用角色默认能力/上限；需要默认值用 `from(CoreProfile.standard(role))`。
- 默认值：`Library` 角色、名称 `custom`、能力空、`ResourceLimits.defaultsFor(Library)`、
  `Blocking`、`Immediate`。
- 所有 setter 返回 `this`，支持链式；null/非法值 panic。
- 不提供 `addCapability` 与 `withCapability` 两个同义名；统一 `capability`/`withoutCapability`。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | 非空 |
| `_role` | `RuntimeRole` | 非 null |
| `_capabilities` | `CapabilitySet` | 非 null；不可变 |
| `_limits` | `ResourceLimits` | 非 null |
| `_ioModel` | `IoModel` | 非 null |
| `_shutdownPolicy` | `ShutdownPolicy` | 非 null |

不变量：所有字段非 null；name 非空；builder 非线程安全。

---

## 4. 生命周期

构造后使用；`build` 可多次；无 close；GC 管理；不跨任务共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ProfileBuilder()` | 无 | 空 builder | 无 |
| `from(CoreProfile profile)` | profile | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `from` | 复制画像 | `CoreProfile profile` | `ProfileBuilder` | null → panic |
| `name` | 设置名称 | `String value` | `ProfileBuilder` | 空名 → panic |
| `role` | 设置角色 | `RuntimeRole value` | `ProfileBuilder` | null → panic |
| `capability` | 添加能力 | `Capability value` | `ProfileBuilder` | null → panic |
| `withoutCapability` | 移除能力 | `Capability value` | `ProfileBuilder` | null → panic |
| `capabilities` | 替换能力集合 | `CapabilitySet value` | `ProfileBuilder` | null → panic |
| `limits` | 设置上限 | `ResourceLimits value` | `ProfileBuilder` | null → panic |
| `ioModel` | 设置 I/O | `IoModel value` | `ProfileBuilder` | null → panic |
| `shutdownPolicy` | 设置关闭 | `ShutdownPolicy value` | `ProfileBuilder` | null → panic |
| `build` | 生成画像 | 无 | `CoreProfile` | 无 |
| `reset` | 恢复默认 | 无 | `ProfileBuilder` | 无 |

---

## 8. 使用的技术

- 可变构造器；
- 不可变快照；
- 能力集合派生；
- 链式调用。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Int；
- 运行时：无；
- 接口：`CoreProfile`、`RuntimeRole`、`Capability`、`CapabilitySet`、`ResourceLimits`、
  `IoModel`、`ShutdownPolicy`。

---

## 10. 依赖的特性/接口/类

`CoreProfile`、`RuntimeRole`、`Capability`、`CapabilitySet`、`ResourceLimits`、
`IoModel`、`ShutdownPolicy`。

---

## 11. 所有权与并发

可变；非线程安全；不跨任务共享；`build` 返回独立不可变画像；无资源。
相等：引用身份；builder 是可变构造器，不推荐作为 `Map` 键。

---

## 12. 示例与反例

正确：

```xnull
CoreProfile profile = new ProfileBuilder()
    .name("edge-client")
    .role(RuntimeRole.Client)
    .capability(Capability.HttpClient)
    .limits(ResourceLimits.defaultsFor(RuntimeRole.Client).withMaxConnections(16))
    .ioModel(IoModel.Blocking)
    .shutdownPolicy(ShutdownPolicy.Drain)
    .build()
```

反例：多任务同时修改 builder；`build` 后修改并期望旧画像变化；用 builder 替代配置解析；
添加与角色冲突的入站能力后不做 `isCoherent` 校验。

---

## 13. 测试/场景义务

默认值；链式 setter；能力添加/移除/替换；`from` 复制；多次 build 独立性；reset；
空名/null；与 `CoreProfile` 默认工厂一致；客户端/服务器派生。

---

## 14. XNull 伪代码

```xnull
class ProfileBuilder {
    String _name
    RuntimeRole _role
    CapabilitySet _capabilities
    ResourceLimits _limits
    IoModel _ioModel
    ShutdownPolicy _shutdownPolicy

    ProfileBuilder() {
        _name = "custom"
        _role = RuntimeRole.Library
        _capabilities = CapabilitySet.empty()
        _limits = ResourceLimits.defaultsFor(RuntimeRole.Library)
        _ioModel = IoModel.Blocking
        _shutdownPolicy = ShutdownPolicy.Immediate
    }

    static ProfileBuilder from(CoreProfile profile) {
        if profile == null { throw "ProfileBuilder.from: null profile" }
        ProfileBuilder builder = new ProfileBuilder()
        builder.name(profile.name())
        builder.role(profile.role())
        builder.capabilities(profile.capabilities())
        builder.limits(profile.limits())
        builder.ioModel(profile.ioModel())
        builder.shutdownPolicy(profile.shutdownPolicy())
        return builder
    }

    ProfileBuilder name(String value) {
        if value == null || value == "" { throw "ProfileBuilder.name: empty" }
        _name = value
        return self
    }

    ProfileBuilder role(RuntimeRole value) {
        if value == null { throw "ProfileBuilder.role: null" }
        _role = value
        return self
    }

    ProfileBuilder capability(Capability value) {
        if value == null { throw "ProfileBuilder.capability: null" }
        _capabilities = _capabilities.with(value)
        return self
    }

    ProfileBuilder withoutCapability(Capability value) {
        if value == null { throw "ProfileBuilder.withoutCapability: null" }
        _capabilities = _capabilities.without(value)
        return self
    }

    ProfileBuilder capabilities(CapabilitySet value) {
        if value == null { throw "ProfileBuilder.capabilities: null" }
        _capabilities = value
        return self
    }

    ProfileBuilder limits(ResourceLimits value) {
        if value == null { throw "ProfileBuilder.limits: null" }
        _limits = value
        return self
    }

    ProfileBuilder ioModel(IoModel value) {
        if value == null { throw "ProfileBuilder.ioModel: null" }
        _ioModel = value
        return self
    }

    ProfileBuilder shutdownPolicy(ShutdownPolicy value) {
        if value == null { throw "ProfileBuilder.shutdownPolicy: null" }
        _shutdownPolicy = value
        return self
    }

    CoreProfile build() {
        return new CoreProfile(_name, _role, _capabilities, _limits,
            _ioModel, _shutdownPolicy)
    }

    ProfileBuilder reset() {
        _name = "custom"
        _role = RuntimeRole.Library
        _capabilities = CapabilitySet.empty()
        _limits = ResourceLimits.defaultsFor(RuntimeRole.Library)
        _ioModel = IoModel.Blocking
        _shutdownPolicy = ShutdownPolicy.Immediate
        return self
    }
}
```
