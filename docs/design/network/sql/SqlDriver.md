# `SqlDriver`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol SqlDriver` |
| 包 | `xdk.sql` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`SqlConnection`、`Map`、`Error` |

> 包索引见 [`README.md`](README.md)。

---

## 1. 定位

SQL 驱动注入协议：稳定名称，以及从 URI + 选项打开一个连接。

不做：连接池、驱动注册表、服务发现、SQL 解析/构建、方言实现、连接复用/重连、裸句柄导出。

---

## 2. 设计逻辑

- 驱动是生态实现；`xdk.sql` 只定义协议，不内置任何具体驱动类型。
- 调用方显式持有 `SqlDriver` 并调用 `open`；核心不提供服务加载器/全局注册表。
- `name()` 是稳定标识，用于日志/调用方自己的注册表；不是方言，也不带版本。
- `open` 的 URI 对核心不透明；scheme 与格式由驱动定义并文档化。核心不解析、不改写。
- `openOptions` 是驱动专有字符串键值；未知键返回 `InvalidArgument`，不得静默忽略。
- `open` 必须建立/验证可用会话后返回；不返回懒连接，避免第一次 `execute` 才发现认证/网络失败。
- 驱动对象可共享；`open` 可并发；每个返回的连接独立。
- 驱动不得把口令/令牌写入错误消息或日志；URI 可能含敏感信息，诊断时只输出 scheme/主机或驱动定义的脱敏形式。
- 不暴露裸句柄；实现内部可用不透明 `Long`，协议不声明。
- 协议无 `close`；驱动应保持轻量，进程级资源由生态实现自行管理。

---

## 3. 表示与不变量

协议无字段。实现必须保证：

- `name()` 非 null、非空、小写 ASCII，以字母开头，只含字母/数字/`_`/`-`；生命周期内稳定。
- `open` 成功返回 `isOpen=true` 的 `SqlConnection`，且 `dialect()` 可用。
- `open` 失败返回 `Err`，不得泄漏半打开连接/句柄。
- `openOptions` 非 null（可为空 Map）；驱动在返回前复制所需值，不保留调用方可变 Map 的别名。
- URI 非 null 且非空；scheme 必须由该驱动支持。
- 驱动不修改调用方的 URI/options；不把敏感值写入错误文本。
- 驱动可并发 `open`；实现内部共享状态必须同步。

---

## 4. 生命周期

驱动对象由调用方创建/持有；协议无 close；生命周期通常与进程/应用组件一致。连接由 `open` 创建，生命周期独立，由调用方关闭。

- `open` 可调用多次；每次返回独立连接。
- `open` 失败不留下后台连接。
- 驱动不缓存连接；连接池由调用方/生态构建。
- 驱动被丢弃不影响已返回连接（实现必须保证连接不依赖驱动对象的可变状态）。

---

## 5. 构造契约

协议无构造。生态实现提供自己的公开构造/工厂；`xdk.sql` 不定义具体驱动类。

- 调用方负责选择并实例化驱动。
- 驱动构造参数（配置、证书、凭据提供者）由生态定义，不进入 `xdk.sql` 协议。
- 不得通过全局单例获取驱动；注入是唯一路径。

---

## 6. 字段表

无协议字段。实现内部配置/句柄私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `name` | 驱动稳定名 | 无 | `String` | 无 | 小写 ASCII；用于日志/调用方注册表 |
| `open` | 打开连接 | `String connectionUri, Map<String, String> openOptions` | `Result<SqlConnection, Error>` | 同上 | `Context` 暂未进入协议；保留兼容入口 |
| `openWithOptions` | 池打开入口 | `String connectionUri, SqlOpenOptions options` | `Result<SqlConnection, Error>` | 同上 | `xdk.db` 使用；规避协议泛型 Map arity 编译器缺陷 |

详细契约：

- 当前签名不带 `Context`（核心 Context 未进入 SQL 协议）；`openWithOptions` 为 M6.4b 增补的非泛型入口。
- `name()` 只做元数据读取；不执行 I/O；名称不随连接/环境变化。
- `open` 要求非 null `context`/`connectionUri`/`openOptions`；null 是合同错误（panic）。
- 空 URI 或 scheme 不匹配：`InvalidArgument`。数据库不存在/URI 格式错误：`InvalidArgument`。
- 未知 option key、非法 option value：`InvalidArgument`；驱动不支持某能力（例如 TLS 模式）：`Unsupported`。
- 认证/授权失败：`PermissionDenied`；网络失败：`Network`；本地 I/O：`Io`；截止：`Timeout`；显式取消：`Cancelled`。
- `open` 必须在返回前完成认证与基本会话校验；连接可用性不以“第一次 execute 成功”为条件。
- `context` 截止/取消在连接建立后到达：关闭已建立连接并返回 `Cancelled`/`Timeout`，不得泄漏。
- `openOptions` 在调用开始时读取；驱动可保留自己复制后的不可变配置，不得保留调用方可变 Map。
- 错误文本不得包含口令、令牌、完整连接串；需要诊断时用脱敏主机/数据库名。
- 连接返回后归调用方所有；驱动不再持有其生命周期。
- 驱动不支持事务不影响 `open`；事务能力由 `SqlConnection.begin` 返回 `Unsupported`。

---

## 8. 使用的技术

- 依赖注入；
- 不透明 URI；
- 驱动专有字符串选项；
- 建立即验证；
- 凭据脱敏；
- 截止时间/取消；
- 不可变配置快照；
- 不透明句柄封装。

---

## 9. 需要的支撑

- 语言：protocol、Result、String、Map；
- 运行时/驱动：数据库连接建立、认证、TLS/网络、驱动句柄；实现内部可用不透明 `Long`；
- 接口：`Context`、`SqlConnection`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

[`SqlConnection`](SqlConnection.md)、[`Context`](../../core/execution/Context.md)、[`Error`](../../core/errors/Error.md)、[`ErrorKind`](../../core/errors/ErrorKind.md)。

---

## 11. 所有权与并发

- 驱动可共享、可并发 `open`；实现内部共享状态必须同步。
- `connectionUri`/`openOptions` 借用；驱动在 `open` 返回前复制所需值，不保留可变别名。
- 成功返回的 `SqlConnection` 所有权转移给调用方；失败不转移任何资源。
- 驱动不缓存连接、不持有全局注册表；连接池由调用方/生态实现。
- 相等：协议引用身份；不提供 `equals`；不同驱动实例按引用区分。
- 无裸句柄；句柄只在实现内部。

---

## 12. 示例与反例

正确：调用方持有 `SqlDriver driver`，执行 `driver.open(context, connectionUri, openOptions)`；用 `driver.name()` 做日志/自有注册表键；每次 `open` 得到独立连接并负责关闭。  
反例：全局注册表/服务发现查找驱动；把口令拼进 URI 并打印错误；忽略 `open` 返回的 `Err` 继续使用 null 连接；驱动缓存连接并偷偷复用；保留调用方 `openOptions` 的引用后异步读取；在 `open` 中只做懒连接；把驱动名当方言。

---

## 13. 测试/场景义务

`name` 稳定性/格式；合法 URI 打开；空 URI/scheme 不匹配；未知 option/非法 value；认证失败；网络失败；本地 I/O；超时/取消；取消后无泄漏；返回连接 `isOpen=true` 且 `dialect` 可用；多次 `open` 独立；并发 `open`；options 复制独立；错误文本不含口令；驱动不缓存连接；无裸句柄。

---

## 14. XNull 伪代码

```xnull
protocol SqlDriver {
    String name();
    Result<SqlConnection, Error> open(Context context, String connectionUri,
        Map<String, String> openOptions);
}
```
