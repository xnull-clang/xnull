# network 领域（net/jwt/sql）

| 项 | 值 |
| --- | --- |
| 范围 | 网络、安全与数据访问层：`xdk.net.*`（含 `xdk.net.service`）+ `xdk.jwt` + `xdk.sql` |
| 依赖 | `xdk.core` |
| 稳定性 | `preview` |
| 文档原则 | 每包 README + 每类型一个 PascalCase 文件 |

> 全量能力覆盖审计见 [`COVERAGE.md`](../COVERAGE.md)。
> net 的 API 广度与方法面见 [`API-SURFACE.md`](API-SURFACE.md)；跨域场景与能力分析见 [`SCENARIOS.md`](../SCENARIOS.md)、[`CAPABILITY.md`](../CAPABILITY.md)。


---

## 1. 层定位

网络层（L5）分两段。第一段是传输底座，不提供应用协议：

- `net.uri`：URI/查询串/百分号编码；
- `net`：IP/前缀、地址、DNS/resolver、ByteStream、TCP、UDP、socket 选项、连接池、网卡；
- `net.tls`：证书、信任库、TLS 配置与流。

第二段在同一 L5 内提供 `net.http`、`net.websocket`、`net.mime` 与面向连接服务的 `net.service`。

客户端/服务器的核心能力画像、资源上限与关闭策略见
[`../core/CORE-PROFILES.md`](../core/CORE-PROFILES.md)；网络层只实现传输/协议角色，不复制核心画像。

> 当前状态：L5 网络包与 `xdk.jwt`/`xdk.sql` 设计已完成；实现未开始。QUIC/HTTP3、SOCKS、Unix domain、raw socket 等为 X/不做。

---

## 2. 包状态

| 包 | 状态 | 文档 |
| --- | --- | --- |
| `net.uri` | 设计完成（待评审） | `net/uri/` |
| `net` | 设计完成（传输面完整） | `net/` |
| `net.tls` | 设计完成（待评审） | `net/tls/` |
| `net.http` | HTTP/1.1 + HTTP/2 + Form/Multipart/Auth/Proxy 设计完成（待评审） | `net/http/` |
| `net.websocket` | 设计完成（待评审） | `net/websocket/` |
| `net.mime` | 设计完成（待评审） | `net/mime/` |
| `net.service` | 设计完成（待评审） | `../solutions/net-service/` |
| `xdk.jwt` | 设计完成（待评审） | `jwt/` |
| `xdk.sql` | 通用 SQL 接口设计完成（待评审） | `sql/` |

---

## 3. 协议覆盖矩阵

| 协议/能力 | 归属 | 状态 |
| --- | --- | --- |
| IPv4 / IPv6 / CIDR | `net` | 已设计 |
| DNS（静态 + 显式 resolver/缓存） | `net` | 已设计 |
| TCP（监听/连接/半关闭/选项） | `net` | 已设计 |
| UDP（数据报/connected/组播/广播） | `net` | 已设计 |
| Socket 选项/状态/网卡 | `net` | 已设计 |
| 连接池 | `net` | 已设计 |
| URI / Query / 百分号编码 | `net.uri` | 已设计 |
| TLS 1.2/1.3 / 证书 / mTLS 配置 | `net.tls` | 已设计 |
| HTTP/1.1 + HTTP/2 + 扩展 | `net.http` | 已设计；HTTP3 不做 |
| WebSocket | `net.websocket` | 已设计 |
| MIME/MediaType | `net.mime` | 已设计 |
| 面向连接的服务器/会话编排 | `net.service` | 已设计 |
| QUIC/HTTP3、SCTP、ICMP/ARP、raw socket、Unix domain、TUN/TAP | — | 不做/后续层 |

原则：不做一个万能 `Socket` 类。流、数据报、监听器、TLS、应用协议分别建模；共享 `ByteStream` 与地址类型。

## 4. 跨包规则

- 所有可恢复失败用 `Result<T, Error>`；无值用 `Result<Unit, Error>`。
- 所有阻塞操作首参 `Context`；取消 `Cancelled`，超时 `Timeout`。
- 资源类有 `isOpen()` + 幂等 `close()`。
- HTTP 状态码不是 `Err`；WebSocket 正常关闭不是 `Err`。
- 不提供全局连接池/DNS 缓存/信任库修改。
- TCP/TLS/HTTP/WS 统一依赖 `net.ByteStream`。

---

## 注解对接（P1）

 的领域注解定义在所属包，由构建期处理器生成路由表/绑定器/映射器；运行时只读生成的静态元数据，**不做反射/类路径扫描/动态代理**。

| 包 | 注解 | 编译期检查 / 生成 |
| --- | --- | --- |
| `net.http` | `@HttpRoute`、`@HttpMethod`、`@Header`、`@Query`、`@Body`、`@StatusCode` | 路由表、参数绑定、状态码映射 |
| `net.websocket` | `@WebSocketHandler` | 处理器注册/分发 |
| `sql` | `@Sql`、`@Param`、`@Row`、`@Column` | DAO、参数绑定、行映射 |
| `jwt` | `@JwtClaim`、`@JwtHeader` | claims/header 映射 |

完整矩阵与处理器规则见 [`ANNOTATION-SYSTEM.md`](../ANNOTATION-SYSTEM.md) §5。注解参数只在编译期求值；生成代码带 `generated` 标记，处理器必须由包/项目显式启用。

## 5. 检查

- `net.uri`：README 2 类型 = 2 文件。
- `net`：README 28 类型 = 28 文件。
- `net.http`：README 40 类型 = 40 文件（HTTP/1.1 + HTTP/2 + 扩展）。
- `net.mime`：README 2 类型 = 2 文件。
- `net.service`：README 13 类型 = 13 文件（归 L5，文档在 `solutions/net-service/`）。
- `net.websocket`：README 12 类型 = 12 文件。
- `net.tls`：README 10 类型 = 10 文件。
- `jwt`：README 6 类型 = 6 文件。
- `sql`：README 12 类型 = 12 文件。
- 协议/枚举均为独立文件；没有 class 内嵌。
- L5/L6 已设计文档通过返回类型、Unit 成功值、私有字段、括号/花括号扫描。
- 未改 `src/xdk`。

---

## 6. 下一批

 设计完成（HTTP/1.1/2 + 扩展、WebSocket、MIME、JWT、SQL 接口）；实现另排；`utils` 已整理为 `docs/design/utils`。
