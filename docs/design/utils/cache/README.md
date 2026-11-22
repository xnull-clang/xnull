# `xdk.cache` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.cache` |
| 层 | L7 应用服务（文档分组 `utils/`） |
| 依赖 | `xdk.errors`、`xdk.execution`、`xdk.runtime` |
| 被依赖 | 应用、HTTP 客户端、存储层 |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

并发缓存门面：LRU + TTL + 权重上限、加载、统计、淘汰监听、关闭。

不重复 `xdk.collections.LRUCache`：后者是单线程 LRU 原语；本包提供并发、TTL、权重、加载和统计。

不做：分布式缓存、持久化、弱引用、单飞加载（X）、异步加载。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 线程安全 | 内部监视器保护全部状态；跨任务共享 |
| 显式上限 | `maxEntries` + `maxWeight`；条目权重可显式设置 |
| TTL | 相对写入的单调毫秒；0 = 不过期 |
| 无泛型协议 | loader/listener 用函数类型，避免 XNull 泛型协议限制 |
| 监听谨慎 | listener 在锁内调用；不得重入 cache |
| 单飞 X | `getOrLoad` 并发缺失可能重复加载 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `EvictionReason` | enum | 淘汰原因 | [`EvictionReason.md`](EvictionReason.md) |
| `CacheStats` | class | 命中/加载/淘汰/容量快照 | [`CacheStats.md`](CacheStats.md) |
| `CacheOptions` | class | 上限/TTL/统计开关 | [`CacheOptions.md`](CacheOptions.md) |
| `Cache` | class | 并发 LRU+TTL+权重缓存 | [`Cache.md`](Cache.md) |

X：single-flight 加载、异步 loader、分布式缓存、持久化、弱引用、按权重函数自动计算、淘汰监听异步化。

---

## 4. 顶层函数

无。

---

## 5. 技术/支撑/依赖

- 技术：LRU 顺序表、TTL 截止、权重核算、加载器、统计、监听。
- 支撑：`RuntimeMonitor`、`nowMono`、`BasicError`。
- 依赖：`errors`、`execution`、`runtime`。

---

## 6. 场景

### C1：请求缓存

`CacheOptions().maxEntries(1024).defaultTtlMillis(60000)`；`getOrLoad(key, loader)`。

### C2：权重缓存

`putWeighted(key, bytes, bytes.length(), 30000)`；超过 `maxWeight` 淘汰最旧。

### C3：观测

`stats().hitRate()`；`resetStats()`；`EvictionReason` 监听。

### C4：关闭

`close()` 清空并通知 `Closed`；之后 `getOrLoad` 返回 `Unavailable`。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 单飞 | X；并发缺失可能重复加载 |
| 异步 loader | 不做 |
| 弱引用 | 不做 |
| 持久化/分布式 | 不做 |
| 监听线程 | 锁内同步；不得重入 |
| 权重 | `put` 默认 1；`putWeighted` 显式 |
| TTL 时钟 | 单调毫秒；墙钟回拨不影响 |

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | `@Cacheable`、`@CacheEvict` |
| 本包消费 | `@Value`、`@Builder` |
| 处理器 | CacheAnnotationProcessor（Validate/Generate） |
| 生成物 | 缓存键/包装器、淘汰元数据 |
| 状态 | 领域注解 planned；A8 派生 planned；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 服务方法 | `@Cacheable`/`@CacheEvict` | 缓存/淘汰包装 |
| `CacheOptions`/`CacheStats` | `@Value`/`@Builder` | 值语义/选项 |

### 声明

```x
@Target(Method)
@Retention(Source)
@annotation Cacheable {
    final String value
    final String key = ""
}

@Target(Method)
@Retention(Source)
@annotation CacheEvict {
    final String value
    final String key = ""
}
```

声明文件：每个注解单独一个 PascalCase 文件；处理器为构建期类型；生成代码在 `<package>/generated/`。

### 使用

```x
class UserService {
    @Cacheable("users", "id")
    User find(Long id) {
        // ...
    }

    @CacheEvict("users", "id")
    void update(Long id, User user) {
        // ...
    }
}
```

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
