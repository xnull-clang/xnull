# `Hmac`

| 项 | 值 |
| --- | --- |
| 类型 | `class Hmac` |
| 包 | `xdk.crypto` |
| 稳定性 | `preview` |
| 依赖 | `HashAlgorithm`、`Bytes`、`ConstantTime`、`Error` |

---

## 1. 定位

HMAC 签名/验证：SHA 系列、SM3。

不做：签名算法、KDF、口令哈希。

---

## 2. 设计逻辑

- 无状态；构造器私有。
- 签名返回原始 MAC；`hex/base64` 编码。
- `verify` 使用常量时间比较。
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
| `Hmac()` | 无 | 私有 | 外部构造 → 编译错误 |

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `sign` | 生成 MAC | `HashAlgorithm, Bytes key, Bytes data` | `Bytes` | 算法不可用 |
| `verify` | 验证 MAC | `HashAlgorithm, Bytes key, Bytes data, Bytes mac` | `Bool` | 无 |
| `hex` | hex MAC | `HashAlgorithm, Bytes key, Bytes data` | `String` | 同上 |
| `base64` | base64 MAC | 同上 | `String` | 同上 |

---

## 8. 使用的技术

- HMAC；
- 常量时间比较。

---

## 9. 需要的支撑

- 语言：class、Bytes、Bool；
- 运行时：`hmacRaw`、`toHex`、`base64Encode`；
- 接口：`HashAlgorithm`、`Bytes`、`ConstantTime`。

---

## 10. 依赖的特性/接口/类

`HashAlgorithm`、`Bytes`、`ConstantTime`、HMAC 运行时原语。

---

## 11. 所有权与并发

无状态；无资源；可并发。

---

## 12. 示例与反例

正确：`Hmac.verify(Sha256,key,data,mac)`。  
反例：用 `==` 比较 MAC；密钥当密码；SM3 算法名错。

---

## 13. 测试/场景义务

已知向量；空 key/data；篡改；SM3；hex/base64。

---

## 14. XNull 伪代码

```xnull
class Hmac {
    private Hmac() {
    }

    static Bytes sign(HashAlgorithm algorithm, Bytes key, Bytes data) {
        if key == null || data == null { throw "Hmac.sign: null argument" }
        return hmacRaw(algorithm, key, data)
    }

    static Bool verify(HashAlgorithm algorithm, Bytes key, Bytes data, Bytes mac) {
        if mac == null { return false }
        Bytes expected = Hmac.sign(algorithm, key, data)
        return ConstantTime.equals(expected, mac)
    }

    static String hex(HashAlgorithm algorithm, Bytes key, Bytes data) {
        return toHex(Hmac.sign(algorithm, key, data))
    }

    static String base64(HashAlgorithm algorithm, Bytes key, Bytes data) {
        return base64Encode(Hmac.sign(algorithm, key, data))
    }
}
```

> `hmacRaw` 是运行时 HMAC 原语；不是 XDK 公共类型。
