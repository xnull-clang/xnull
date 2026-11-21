# `Hash`

| 项 | 值 |
| --- | --- |
| 类型 | `class Hash` |
| 包 | `xdk.crypto` |
| 稳定性 | `preview` |
| 依赖 | `HashAlgorithm`、`Bytes`、`Reader`、`Error` |

---

## 1. 定位

摘要静态入口：digest/hex/base64/长度/Reader 流式摘要。

不做：HMAC、签名、KDF。

---

## 2. 设计逻辑

- 无状态；构造器私有。
- `digest` 返回原始字节；`hex/base64` 编码。
- `hashReader` 可取消、流式；不一次性读全。
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
| `Hash()` | 无 | 私有 | 外部构造 → 编译错误 |

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `digest` | 摘要 | `HashAlgorithm, Bytes` | `Bytes` | 算法不可用 → panic |
| `hex` | hex 摘要 | `HashAlgorithm, Bytes` | `String` | 同上 |
| `base64` | base64 摘要 | `HashAlgorithm, Bytes` | `String` | 同上 |
| `length` | 摘要长度 | `HashAlgorithm` | `Int` | 无 |
| `hashReader` | Reader 摘要 | `Context, HashAlgorithm, Reader` | `Result<Bytes, Error>` | `Io`/`Cancelled` |

---

## 8. 使用的技术

- 摘要原语；
- 流式读取；
- 编码。

---

## 9. 需要的支撑

- 语言：class、Bytes、Reader、Result；
- 运行时：`hashRaw`、`hashReaderRaw`、`hashLengthRaw`、`toHex`、`base64Encode`；
- 接口：`HashAlgorithm`、`Context`、`Error`。

---

## 10. 依赖的特性/接口/类

`HashAlgorithm`、`Bytes`、`Reader`、`Context`、`Error`、摘要运行时原语。

---

## 11. 所有权与并发

无状态；无资源；可并发。

---

## 12. 示例与反例

正确：`Hash.hex(HashAlgorithm.Sha256, data)`。  
反例：用 MD5 做安全摘要；hashReader 不处理取消。

---

## 13. 测试/场景义务

已知向量；空数据；hex/base64；流式 vs 一次性；取消；SM3。

---

## 14. XNull 伪代码

```xnull
class Hash {
    private Hash() {
    }

    static Bytes digest(HashAlgorithm algorithm, Bytes data) {
        if data == null { throw "Hash.digest: null" }
        return hashRaw(algorithm, data)
    }

    static String hex(HashAlgorithm algorithm, Bytes data) {
        return toHex(Hash.digest(algorithm, data))
    }

    static String base64(HashAlgorithm algorithm, Bytes data) {
        return base64Encode(Hash.digest(algorithm, data))
    }

    static Int length(HashAlgorithm algorithm) { return hashLengthRaw(algorithm) }

    static Result<Bytes, Error> hashReader(Context context, HashAlgorithm algorithm, Reader reader) {
        if context == null || reader == null { throw "Hash.hashReader: null argument" }
        return hashReaderRaw(context, algorithm, reader)
    }
}
```

> `hash*Raw` 是运行时摘要原语；不是 XDK 公共类型。
