# 注解目录（Annotation Catalog）

| 项 | 值 |
| --- | --- |
| 范围 | 语言内建、A8 派生、领域注解、块注解；不含 `@arc`/`@gc`（非法，不属于注解系统） |
| 权威语义 | [`ANNOTATION-SYSTEM.md`](ANNOTATION-SYSTEM.md)、[`ANNOTATION-PLAN.md`](ANNOTATION-PLAN.md)、[`ARCHITECTURE.md`](ARCHITECTURE.md) §6 |
| 状态含义 | `implemented` = 编译器已识别并有测试；`reserved` = 保留词，不改变语义；`planned` = 合同已列、实现未开始 |
| 计数 | 48 条：`implemented` 9、`reserved` 4、`planned` 35（A8 5 + S5 2 + 领域 28） |

处理器阶段统一为 `Resolve → Validate → Generate → Finalize`；下表写主要阶段。未写 `@Retention` 时默认 `Binary`；未写 `@Target` 时默认允许所有声明目标，`TypeUse` 必须显式。

## 1. 语言内建

| 注解 | 做什么 | 解决什么问题 | 目标 / 保留 | 处理器阶段 | 归属包 | 状态 | 验收 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `@Target` | 限定注解可挂载目标 | 防止注解挂错位置 | Annotation / Binary | A3 Validate | `xdk.annotations` + 编译器 | implemented | B1/A3 目标矩阵 + `AN0009` |
| `@Retention` | 选择 Source/Binary/Runtime | 区分编译期、工具和运行时可见性 | Annotation / Binary | A5 Validate | `xdk.annotations` + 编译器 | implemented | B1/A5 三保留策略场景 |
| `@Repeatable` | 允许同一目标重复并保序 | 多值元数据不丢项 | Annotation / Binary | A5 Validate | `xdk.annotations` + 编译器 | implemented | 重复保序 + 未标重复 `AN0003` |
| `@ReadOnly` | 字段对外只读 | 防止外部写状态 | Field / Binary | A6 Validate | `xdk.annotations` + 编译器 | implemented | 字段读写矩阵 + `AN0012` |
| `@WriteOnly` | 标记只写字段 | 识别 API 方向 | Field / Binary | A6 Validate | `xdk.annotations` + 编译器 | implemented（识别） | 目标/保留测试；不承诺强制 |
| `@Override` | 要求方法匹配协议签名 | 防拼写漂移和伪实现 | Method / Binary | A6 Validate | `xdk.annotations` + 编译器 | implemented | 协议签名匹配/不匹配诊断 |
| `@Deprecated` | 标记弃用声明 | 使用点提示迁移 | 声明目标 / Binary | A6 Validate | `xdk.annotations` + 编译器 | implemented | 使用点 `AN0014` 警告 |
| `@SuppressWarnings` | 按诊断码抑制警告 | 局部豁免已知告警 | 声明目标 / Source | A6 Validate | `xdk.annotations` + 编译器 | implemented | 指定码抑制 + 非目标诊断 |
| `@MustUse` | 标记返回值必须使用 | 防忽略关键结果 | Type/Method / Binary | A6 Validate | `xdk.annotations` + 编译器 | implemented（识别） | 目标测试；强制规则随 A6 完善 |
| `@Immediate` | 预留执行策略标记 | 未来调度提示 | 声明目标 / Binary | 无 | 编译器（预留） | reserved | 不改变语义；非法组合诊断 |
| `@NoAlloc` | 预留无分配标记 | 未来分配约束提示 | 声明目标 / Binary | 无 | 编译器（预留） | reserved | 不改变语义；非法组合诊断 |
| `@Pure` | 预留纯函数标记 | 未来优化提示 | Method / Binary | 无 | 编译器（预留） | reserved | 不改变语义；不据此优化 |
| `@Sendable` | 预留跨任务安全标记 | 未来并发检查提示 | Type/Method / Binary | 无 | 编译器（预留） | reserved | 不改变语义；不据此放行 |
| `@tasks` | 块内任务结构化并发 | 任务作用域与取消 | Block / Source | S5 | 语言 S5 | planned (S5) | 语法 + 取消/异常场景 |
| `@arena` | 块内区域分配 | 批量释放生命周期 | Block / Source | S5 | 语言 S5 | planned (S5) | 语法 + 生命周期场景 |

## 2. 语言内建派生（A8）

| 注解 | 做什么 | 解决什么问题 | 目标 / 保留 | 处理器阶段 | 归属包 | 状态 | 验收 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `@Value` | 生成不可变值语义成员 | 消除手写 equals/toString/构造样板 | Type / Source | A8 Generate→Finalize | 编译器 A8 | planned (A8) | 生成成员 + 冲突/原子失败场景 |
| `@Data` | 生成数据类成员与访问器 | 减少字段样板且保持显式 | Type / Source | A8 Generate→Finalize | 编译器 A8 | planned (A8) | 生成成员 + 可空/默认值场景 |
| `@Builder` | 生成 builder 类型与 `build()` | 多参数构造可读且可校验 | Type / Source | A8 Generate→Finalize | 编译器 A8 | planned (A8) | 构建顺序/必填/失败原子场景 |
| `@Copy` | 生成复制与逐字段 `withX` | 不可变更新不手写全字段 | Type / Source | A8 Generate→Finalize | 编译器 A8 | planned (A8) | 复制/嵌套/引用语义场景 |
| `@Delegate` | 生成到指定字段的转发方法 | 组合代替继承样板 | Type/Field / Source | A8 Generate→Finalize | 编译器 A8 | planned (A8) | 转发冲突/可见性/缺失方法诊断 |

A8 约束：多轮固定点；只读输入 AST、沙箱生成；输出确定（同输入同字节）；任何生成/校验失败整批回滚，不落半成品；不得写任意文件、联网、反射或启动进程。

## 3. 领域注解

领域注解随所属包实现，均不允许塞进 `xdk.annotations`。下表状态均为 `planned`；验收统一为“包实现 + 处理器 + 生成代码 + 场景”。

### 3.1 codec

| 注解 | 做什么 | 解决什么问题 | 目标 / 保留 | 处理器阶段 | 归属包 | 状态 | 验收 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `@Serializable` | 标记可序列化类型 | 生成 codec 入口 | Type / Runtime | Generate | B5 `xdk.codec` | planned | 包实现 + 处理器 + 生成代码 + 场景 |
| `@JsonName` | 指定 JSON 字段名 | 兼容外部命名 | Field / Runtime | Generate | B5 `xdk.codec` | planned | 包实现 + 处理器 + 生成代码 + 场景 |
| `@YamlName` | 指定 YAML 字段名 | 兼容外部命名 | Field / Runtime | Generate | B5 `xdk.codec` | planned | 包实现 + 处理器 + 生成代码 + 场景 |
| `@TomlName` | 指定 TOML 字段名 | 兼容外部命名 | Field / Runtime | Generate | B5 `xdk.codec` | planned | 包实现 + 处理器 + 生成代码 + 场景 |
| `@XmlName` | 指定 XML 元素/属性名 | 兼容外部命名 | Field / Runtime | Generate | B5 `xdk.codec` | planned | 包实现 + 处理器 + 生成代码 + 场景 |

### 3.2 validation

| 注解 | 做什么 | 解决什么问题 | 目标 / 保留 | 处理器阶段 | 归属包 | 状态 | 验收 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `@Validate` | 标记类型/成员需校验 | 生成校验入口 | Type/Field/Parameter / Runtime | Validate→Generate | B9 `xdk.validate` | planned | 包实现 + 处理器 + 生成代码 + 场景 |
| `@Min` | 数值下界 | 统一边界校验 | Field/Parameter / Runtime | Validate→Generate | B9 `xdk.validate` | planned | 包实现 + 处理器 + 生成代码 + 场景 |
| `@Max` | 数值上界 | 统一边界校验 | Field/Parameter / Runtime | Validate→Generate | B9 `xdk.validate` | planned | 包实现 + 处理器 + 生成代码 + 场景 |
| `@Pattern` | 字符串正则约束 | 复用格式校验 | Field/Parameter / Runtime | Validate→Generate | B9 `xdk.validate` | planned | 包实现 + 处理器 + 生成代码 + 场景 |

### 3.3 net/http

| 注解 | 做什么 | 解决什么问题 | 目标 / 保留 | 处理器阶段 | 归属包 | 状态 | 验收 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `@HttpRoute` | 绑定方法与 HTTP 路径 | 消除手写路由表 | Method / Runtime | Generate | B7 `xdk.net.http` | planned | 包实现 + 处理器 + 生成代码 + 场景 |
| `@Header` | 绑定请求/响应头 | 声明式取参 | Parameter / Runtime | Generate | B7 `xdk.net.http` | planned | 包实现 + 处理器 + 生成代码 + 场景 |
| `@Query` | 绑定查询参数 | 声明式取参 | Parameter / Runtime | Generate | B7 `xdk.net.http` | planned | 包实现 + 处理器 + 生成代码 + 场景 |

### 3.4 db

| 注解 | 做什么 | 解决什么问题 | 目标 / 保留 | 处理器阶段 | 归属包 | 状态 | 验收 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `@Sql` | 绑定 SQL 语句 | 消除手写查询样板 | Method/Type / Runtime | Generate | B10 `xdk.db` | planned | 包实现 + 处理器 + 生成代码 + 场景 |
| `@Param` | 绑定命名参数 | 参数与语句显式对应 | Parameter / Runtime | Generate | B10 `xdk.db` | planned | 包实现 + 处理器 + 生成代码 + 场景 |
| `@Row` | 标记行映射类型 | 结果集到对象的显式映射 | Type / Runtime | Generate | B10 `xdk.db` | planned | 包实现 + 处理器 + 生成代码 + 场景 |

### 3.5 auth

| 注解 | 做什么 | 解决什么问题 | 目标 / 保留 | 处理器阶段 | 归属包 | 状态 | 验收 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `@JwtClaim` | 绑定 JWT claim 字段 | 消除手写 claim 映射 | Field / Runtime | Generate | B9 `xdk.auth` | planned | 包实现 + 处理器 + 生成代码 + 场景 |
| `@JwtHeader` | 绑定 JWT header 字段 | 消除手写 header 映射 | Field / Runtime | Generate | B9 `xdk.auth` | planned | 包实现 + 处理器 + 生成代码 + 场景 |

### 3.6 test / scheduler

| 注解 | 做什么 | 解决什么问题 | 目标 / 保留 | 处理器阶段 | 归属包 | 状态 | 验收 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `@Test` | 标记测试方法 | 测试发现不靠命名约定 | Method / Runtime | Generate | B9 `xdk.test` | planned | 包实现 + 处理器 + 生成代码 + 场景 |
| `@Scheduled` | 标记调度任务 | 调度声明与实现分离 | Method / Runtime | Generate | B9 `xdk.schedule` | planned | 包实现 + 处理器 + 生成代码 + 场景 |

### 3.7 ffi / platform

| 注解 | 做什么 | 解决什么问题 | 目标 / 保留 | 处理器阶段 | 归属包 | 状态 | 验收 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `@Packed` | 指定 FFI 结构紧排 | 匹配 C ABI 布局 | Type / Binary | Validate | B5/P4 编译器 | planned | 包实现 + 处理器 + 生成代码 + 场景 |
| `@Align` | 指定字段/类型对齐 | 匹配 C ABI 布局 | Type/Field / Binary | Validate | B5/P4 编译器 | planned | 包实现 + 处理器 + 生成代码 + 场景 |
| `@Device` | 标记设备绑定 | 设备能力显式归属 | Type/Method / Runtime | Generate | B8 `xdk.os.device` | planned | 包实现 + 处理器 + 生成代码 + 场景 |
| `@GpuKernel` | 标记 GPU kernel | 核函数入口显式生成 | Method / Runtime | Generate | B8 `xdk.gpu` | planned | 包实现 + 处理器 + 生成代码 + 场景 |

### 3.8 resilience / observability

| 注解 | 做什么 | 解决什么问题 | 目标 / 保留 | 处理器阶段 | 归属包 | 状态 | 验收 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `@Cacheable` | 声明可缓存方法 | 缓存键/失效集中生成 | Method / Runtime | Generate | B9 `xdk.cache` | planned | 包实现 + 处理器 + 生成代码 + 场景 |
| `@Retry` | 声明重试策略 | 重试不散落在调用点 | Method / Runtime | Generate | B9 `xdk.resilience` | planned | 包实现 + 处理器 + 生成代码 + 场景 |
| `@Metered` | 生成指标埋点 | 指标命名与标签统一 | Method / Runtime | Generate | B9 `xdk.metrics` | planned | 包实现 + 处理器 + 生成代码 + 场景 |
| `@Traced` | 生成 trace span | 调用链边界显式 | Method / Runtime | Generate | B9 `xdk.trace` | planned | 包实现 + 处理器 + 生成代码 + 场景 |
| `@Audited` | 生成审计事件 | 敏感操作可追溯 | Method / Runtime | Generate | B9 `xdk.audit` | planned | 包实现 + 处理器 + 生成代码 + 场景 |

## 4. 使用边界

- 注解是**构建期**元数据/检查/生成入口，不是运行时反射、扫描、动态代理或注解类加载。
- 处理器必须**显式启用**；未启用的处理器不运行，也不产生“已处理”承诺。
- 处理器在**沙箱**内运行：只读输入 AST，只写声明式输出；禁止任意文件、网络、进程、反射。
- **失败原子**：Resolve/Validate/Generate/Finalize 任一步失败，整批输出回滚；不得留下半生成文件或半修改 AST。
- **确定性**：同一输入、同一处理器集合、同一配置产生相同字节；排序、命名、重复项保序。
- 运行时只有 `Runtime` 注解进入编译器生成的静态 `AnnotationRegistry`；`Source`/`Binary` 不可运行时查询。
- 领域注解定义在**所属包**，不放进 `xdk.annotations`；`xdk.annotations` 只保留 14 个元模型类型、处理器合同和 Registry。
- 识别但不强制的注解（如 `@WriteOnly`、预留 `@Pure`）不是语义承诺；不得据此宣称行为已被检查。
- `@arc`/`@gc` 不是注解系统成员，使用即编译错误；块注解 `@tasks`/`@arena` 归语言 S5。
