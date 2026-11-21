# `Hex`

| 项 | 值 |
| --- | --- |
| 类型 | `class Hex` |
| 包 | `xdk.codec` |
| 稳定性 | `preview` |
| 依赖 | `Bytes`、`Error` |

---

## 1. 定位

Hex 编解码：小写/大写、严格校验。

不做：base32、流式、格式化分组。

---

## 2. 设计逻辑

- 无状态；构造器私有；静态方法。
- `decode` 忽略大小写；非法字符/奇数长度 `DataCorrupted`。
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
| `Hex()` | 无 | 私有 | 外部构造 → 编译错误 |

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `encode` | 小写 | `Bytes` | `String` | 无 |
| `encodeUpper` | 大写 | `Bytes` | `String` | 无 |
| `decode` | 解码 | `String` | `Result<Bytes, Error>` | `DataCorrupted` |
| `isValid` | 是否合法 | `String` | `Bool` | 无 |

---

## 8. 使用的技术

- 半字节映射；
- 严格解码。

---

## 9. 需要的支撑

- 语言：class、Bytes、String、Bool、Result；
- 运行时：`hexEncodeRaw`、`hexDecodeRaw`；
- 接口：`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Bytes`、`Error`、`BasicError`、`ErrorKind`、Hex 运行时原语。

---

## 11. 所有权与并发

无状态；无资源；可并发。

---

## 12. 示例与反例

正确：`Hex.decode("0aFF")`。  
反例：奇数长度；非法字符；期望保留大小写。

---

## 13. 测试/场景义务

空；大小写；奇数；非法；encode/decode 往返；isValid。

---

## 14. XNull 伪代码

```xnull
class Hex {
    private Hex() {
    }

    static String encode(Bytes data) {
        if data == null { throw "Hex.encode: null" }
        return hexEncodeRaw(data, false)
    }

    static String encodeUpper(Bytes data) {
        if data == null { throw "Hex.encodeUpper: null" }
        return hexEncodeRaw(data, true)
    }

    static Result<Bytes, Error> decode(String text) {
        if text == null { throw "Hex.decode: null" }
        return hexDecodeRaw(text)
    }

    static Bool isValid(String text) {
        if text == null { return false }
        Result<Bytes, Error> decoded = hexDecodeRaw(text)
        return decoded.isOk()
    }
}
```

> `hexEncodeRaw`、`hexDecodeRaw` 是运行时 Hex 原语；不是 XDK 公共类型。
