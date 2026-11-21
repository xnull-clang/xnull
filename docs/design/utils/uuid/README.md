# `xdk.uuid` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.uuid` |
| 层 | L4 数据/编码（文档分组 `utils/`） |
| 依赖 | `xdk.errors`、`xdk.bytes`、`xdk.text` |
| 被依赖 | 应用、日志、追踪 |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

UUID v4/v7 与 ULID：生成、解析、字节、版本/变体、时间戳、比较。

不做：UUID v1/v3/v5、Snowflake（X）、分布式 ID 服务、全局生成器。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 无全局状态 | 生成器由运行时提供，无全局计数器可写 |
| 值语义 | UUID/ULID 不可变，可作 Map 键 |
| 严格解析 | 非法文本/长度 → `InvalidArgument` |
| 时间语义 | v7/ULID 时间戳为 epoch 毫秒 |
| 无 close | 无资源 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `UuidVersion` | enum | v4/v7 | [`UuidVersion.md`](UuidVersion.md) |
| `Uuid` | class | UUID 值/生成/解析 | [`Uuid.md`](Uuid.md) |
| `Ulid` | class | ULID 值/生成/解析 | [`Ulid.md`](Ulid.md) |

X：`Snowflake`、v1/v3/v5、UUID 到 ULID 转换。

---

## 4. 顶层函数

无。

---

## 5. 技术/支撑/依赖

- 技术：128 位值、Base32/hex、时间戳、随机字节。
- 支撑：`uuid*Raw`、`ulid*Raw`、`secureRandomBytes`。
- 依赖：`xdk.errors`、`xdk.bytes`、`xdk.text`。

---

## 6. 场景

### U1：请求 ID

`Uuid.v7()`；`toString()`；作为日志/trace ID。

### U2：解析

`Uuid.parse(text)`；`Ulid.parse(text)`；非法返回 `InvalidArgument`。

### U3：排序

v7/ULID 按时间前缀自然排序；`compare`。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| v1/v3/v5 | X |
| Snowflake | X |
| 全局生成器 | 禁止 |
| 时间精度 | 毫秒 |
| ULID 单调 | `generate(monotonic)` 显式 |
