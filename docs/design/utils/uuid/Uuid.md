# `Uuid`

| 项 | 值 |
| --- | --- |
| 类型 | `class Uuid` |
| 包 | `xdk.uuid` |
| 稳定性 | `preview` |
| 依赖 | `UuidVersion`、`Bytes`、`Error` |

---

## 1. 定位

128 位 UUID 值：v4/v7 生成、解析、字节、版本/变体、时间戳、比较。

不做：v1/v3/v5、Snowflake、全局生成器。

---

## 2. 设计逻辑

- 字段 `_bytes: Bytes`（16 字节），构造复制。
- `v4` 随机；`v7` 时间有序；由运行时生成。
- `parse` 接受标准 36 字符/32 hex；失败 `InvalidArgument`。
- `timestamp` 仅 v7 非 null；v4 null。
- 不可变；可作 Map 键；无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_bytes` | `Bytes` | 16 字节 |

不变量：长度 16；不可变。

---

## 4. 生命周期

不可变；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Uuid.v4()` | 无 | 无 | `Unavailable`（随机源） |
| `Uuid.v7()` | 无 | 无 | 同上 |
| `Uuid.parse(String)` | text | 合法 UUID | `InvalidArgument` |
| `Uuid.fromBytes(Bytes)` | bytes | 16 字节 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `v4` | 随机 UUID | 无 | `Result<Uuid, Error>` | 随机源失败 |
| `v7` | 时间 UUID | 无 | `Result<Uuid, Error>` | 随机源失败 |
| `parse` | 解析 | `String` | `Result<Uuid, Error>` | `InvalidArgument` |
| `fromBytes` | 字节构造 | `Bytes` | `Uuid` | 长度非法 → panic |
| `bytes` | 字节副本 | 无 | `Bytes` | 无 |
| `version` | 版本 | 无 | `UuidVersion` | 无 |
| `variant` | 变体 | 无 | `Int` | 无 |
| `timestamp` | v7 时间/无 | 无 | `Long?` | 无 |
| `isNil` | 全零 | 无 | `Bool` | 无 |
| `equals` | 值相等 | `Uuid other` | `Bool` | 无 |
| `compare` | 排序 | `Uuid other` | `Int` | null → panic |
| `toString` | 标准文本 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 128 位值；
- 版本/变体位；
- 时间戳；
- 值相等。

---

## 9. 需要的支撑

- 语言：class、Bytes、Int、Long、Bool、Result；
- 运行时：`uuidV4Raw`、`uuidV7Raw`、`parseUuidRaw`、`formatUuidRaw`、`uuidVersionRaw`、`uuidVariantRaw`、`uuidTimestampRaw`、`UuidRaw`；
- 接口：`UuidVersion`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`UuidVersion`、`Bytes`、`Error`、UUID 运行时原语。

---

## 11. 所有权与并发

不可变；无资源；可共享；可作 Map 键。

---

## 12. 示例与反例

正确：`Uuid.v7()`；`Uuid.parse(text)`。  
反例：v4 调 timestamp 期望时间；长度 15；用字符串比较代替 compare。

---

## 13. 测试/场景义务

v4/v7；parse 两种格式；版本/变体；v7 timestamp；nil；bytes；equals/compare；非法。

---

## 14. XNull 伪代码

```xnull
class Uuid {
    final Bytes _bytes

    private Uuid(Bytes bytes) {
        if bytes == null || bytes.length() != 16 {
            throw "Uuid: invalid bytes"
        }
        _bytes = bytes.copy()
    }

    static Result<Uuid, Error> v4() {
        Result<UuidRaw, Error> raw = uuidV4Raw()
        if raw.isErr() { return Err(raw.error()) }
        return Ok(new Uuid(raw.value().bytes()))
    }

    static Result<Uuid, Error> v7() {
        Result<UuidRaw, Error> raw = uuidV7Raw()
        if raw.isErr() { return Err(raw.error()) }
        return Ok(new Uuid(raw.value().bytes()))
    }

    static Result<Uuid, Error> parse(String text) {
        if text == null { throw "Uuid.parse: null" }
        Result<UuidRaw, Error> raw = parseUuidRaw(text)
        if raw.isErr() { return Err(raw.error()) }
        return Ok(new Uuid(raw.value().bytes()))
    }

    static Uuid fromBytes(Bytes bytes) { return new Uuid(bytes) }

    Bytes bytes() { return _bytes.copy() }
    UuidVersion version() { return uuidVersionRaw(_bytes) }
    Int variant() { return uuidVariantRaw(_bytes) }
    Long? timestamp() { return uuidTimestampRaw(_bytes) }

    Bool isNil() {
        Int index = 0
        while index < _bytes.length() {
            if _bytes.get(index) != 0 { return false }
            index = index + 1
        }
        return true
    }

    Bool equals(Uuid other) {
        if other == null { return false }
        return equals(_bytes, other.bytes())
    }

    Int compare(Uuid other) {
        if other == null { throw "Uuid.compare: null" }
        return compare(_bytes, other.bytes())
    }

    String toString() { return formatUuidRaw(_bytes) }
}
```

> `UuidRaw`、`uuid*Raw` 是运行时 UUID 原语；不是 XDK 公共类型。
