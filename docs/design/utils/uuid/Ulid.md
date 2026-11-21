# `Ulid`

| 项 | 值 |
| --- | --- |
| 类型 | `class Ulid` |
| 包 | `xdk.uuid` |
| 稳定性 | `preview` |
| 依赖 | `Bytes`、`Error` |

---

## 1. 定位

128 位 ULID：生成（可选单调）、解析、字节、时间戳、随机部分、比较。

不做：Snowflake、分布式 ID 服务、全局生成器。

---

## 2. 设计逻辑

- 字段 `_bytes: Bytes`（16 字节）；前 6 字节时间，后 10 字节随机。
- `generate(monotonic)` 由运行时生成；单调模式同毫秒递增。
- `parse` 接受 26 字符 Crockford Base32；失败 `InvalidArgument`。
- 不可变；可作 Map 键；无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_bytes` | `Bytes` | 16 字节 |

---

## 4. 生命周期

不可变；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Ulid.generate(Bool monotonic)` | 无 | 无 | `Unavailable` |
| `Ulid.parse(String)` | text | 26 字符 | `InvalidArgument` |
| `Ulid.fromBytes(Bytes)` | bytes | 16 字节 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `generate` | 生成 | `Bool monotonic` | `Result<Ulid, Error>` | 随机源失败 |
| `parse` | 解析 | `String` | `Result<Ulid, Error>` | `InvalidArgument` |
| `fromBytes` | 字节构造 | `Bytes` | `Ulid` | 长度非法 → panic |
| `timestamp` | 毫秒时间 | 无 | `Long` | 无 |
| `randomness` | 随机部分 | 无 | `Bytes` | 无 |
| `bytes` | 字节副本 | 无 | `Bytes` | 无 |
| `equals` | 值相等 | `Ulid other` | `Bool` | 无 |
| `compare` | 排序 | `Ulid other` | `Int` | null → panic |
| `toString` | 26 字符 | 无 | `String` | 无 |

---

## 8. 使用的技术

- Crockford Base32；
- 时间前缀；
- 单调生成。

---

## 9. 需要的支撑

- 语言：class、Bytes、Long、Bool、Result；
- 运行时：`ulidGenerateRaw`、`parseUlidRaw`、`formatUlidRaw`、`ulidTimestampRaw`、`ulidRandomnessRaw`、`UlidRaw`；
- 接口：`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Bytes`、`Error`、ULID 运行时原语。

---

## 11. 所有权与并发

不可变；无资源；可共享；可作 Map 键。

---

## 12. 示例与反例

正确：`Ulid.generate(true)`。  
反例：期望 ULID 全局单调而不传 monotonic；用 UUID 格式解析。

---

## 13. 测试/场景义务

生成/解析；时间戳；随机部分；单调；长度；非法字符；equals/compare。

---

## 14. XNull 伪代码

```xnull
class Ulid {
    final Bytes _bytes

    private Ulid(Bytes bytes) {
        if bytes == null || bytes.length() != 16 {
            throw "Ulid: invalid bytes"
        }
        _bytes = bytes.copy()
    }

    static Result<Ulid, Error> generate(Bool monotonic) {
        Result<UlidRaw, Error> raw = ulidGenerateRaw(monotonic)
        if raw.isErr() { return Err(raw.error()) }
        return Ok(new Ulid(raw.value().bytes()))
    }

    static Result<Ulid, Error> parse(String text) {
        if text == null { throw "Ulid.parse: null" }
        Result<UlidRaw, Error> raw = parseUlidRaw(text)
        if raw.isErr() { return Err(raw.error()) }
        return Ok(new Ulid(raw.value().bytes()))
    }

    static Ulid fromBytes(Bytes bytes) { return new Ulid(bytes) }

    Long timestamp() { return ulidTimestampRaw(_bytes) }
    Bytes randomness() { return ulidRandomnessRaw(_bytes) }
    Bytes bytes() { return _bytes.copy() }

    Bool equals(Ulid other) {
        if other == null { return false }
        return equals(_bytes, other.bytes())
    }

    Int compare(Ulid other) {
        if other == null { throw "Ulid.compare: null" }
        return compare(_bytes, other.bytes())
    }

    String toString() { return formatUlidRaw(_bytes) }
}
```

> `UlidRaw`、`ulid*Raw` 是运行时 ULID 原语；不是 XDK 公共类型。
