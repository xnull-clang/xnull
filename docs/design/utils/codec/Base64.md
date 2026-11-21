# `Base64`

| 项 | 值 |
| --- | --- |
| 类型 | `class Base64` |
| 包 | `xdk.codec` |
| 稳定性 | `preview` |
| 依赖 | `Bytes`、`Error` |

---

## 1. 定位

Base64 编解码：标准、URL-safe、无 padding、长度估算。

不做：Base64url 流式、MIME 换行、加密。

---

## 2. 设计逻辑

- 无状态；构造器私有；全部静态方法。
- 标准字母表；`url` 变体 `-`/`_`。
- `decode` 严格校验 padding/字符；失败 `DataCorrupted`。
- 无 close；可并发。

---

## 3. 表示与不变量

无实例字段。

---

## 4. 生命周期

静态命名空间；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Base64()` | 无 | 私有 | 外部构造 → 编译错误 |

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `encode` | 标准编码 | `Bytes` | `String` | 无 |
| `decode` | 标准解码 | `String` | `Result<Bytes, Error>` | `DataCorrupted` |
| `encodeUrl` | URL-safe | `Bytes` | `String` | 无 |
| `decodeUrl` | URL-safe 解码 | `String` | `Result<Bytes, Error>` | 同上 |
| `encodeNoPadding` | 无 padding | `Bytes` | `String` | 无 |
| `decodeNoPadding` | 无 padding 解码 | `String` | `Result<Bytes, Error>` | 同上 |
| `encodedLength` | 编码长度 | `Int` | `Int` | 负值 → panic |
| `decodedLength` | 解码长度 | `Int` | `Int` | 负值 → panic |

---

## 8. 使用的技术

- Base64 字母表；
- 严格解码。

---

## 9. 需要的支撑

- 语言：class、Bytes、String、Int、Result；
- 运行时：`base64EncodeRaw`、`base64DecodeRaw`；
- 接口：`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Bytes`、`Error`、`BasicError`、`ErrorKind`、Base64 运行时原语。

---

## 11. 所有权与并发

无状态；无资源；可并发。

---

## 12. 示例与反例

正确：`Base64.decode(Base64.encode(data))`。  
反例：忽略非法字符；URL-safe 混用标准表；期望自动换行。

---

## 13. 测试/场景义务

空/1/2/3 字节；padding；URL-safe；无 padding；非法；长度估算。

---

## 14. XNull 伪代码

```xnull
class Base64 {
    private Base64() {
    }

    static String encode(Bytes data) {
        if data == null { throw "Base64.encode: null" }
        return base64EncodeRaw(data, false, true)
    }

    static Result<Bytes, Error> decode(String text) {
        if text == null { throw "Base64.decode: null" }
        return base64DecodeRaw(text, false, true)
    }

    static String encodeUrl(Bytes data) {
        if data == null { throw "Base64.encodeUrl: null" }
        return base64EncodeRaw(data, true, true)
    }

    static Result<Bytes, Error> decodeUrl(String text) {
        if text == null { throw "Base64.decodeUrl: null" }
        return base64DecodeRaw(text, true, true)
    }

    static String encodeNoPadding(Bytes data) {
        if data == null { throw "Base64.encodeNoPadding: null" }
        return base64EncodeRaw(data, false, false)
    }

    static Result<Bytes, Error> decodeNoPadding(String text) {
        if text == null { throw "Base64.decodeNoPadding: null" }
        return base64DecodeRaw(text, false, false)
    }

    static Int encodedLength(Int byteCount) {
        if byteCount < 0 { throw "Base64.encodedLength: negative" }
        return ((byteCount + 2) / 3) * 4
    }

    static Int decodedLength(Int characterCount) {
        if characterCount < 0 { throw "Base64.decodedLength: negative" }
        return (characterCount / 4) * 3
    }
}
```

> `base64*Raw` 是运行时 Base64 原语；不是 XDK 公共类型。
