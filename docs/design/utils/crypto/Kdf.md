# `Kdf`

| 项 | 值 |
| --- | --- |
| 类型 | `class Kdf` |
| 包 | `xdk.crypto` |
| 稳定性 | `preview` |
| 依赖 | `KdfAlgorithm`、`HashAlgorithm`、`Bytes`、`Error` |

---

## 1. 定位

密钥派生静态入口：PBKDF2、scrypt、Argon2id、HKDF、SM3-KDF。

不做：口令策略、盐生成、密钥存储。

---

## 2. 设计逻辑

- 无状态；构造器私有。
- 每个算法显式参数；长度 >0；盐/密码非 null。
- 失败 `InvalidArgument`/`Unsupported`。
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
| `Kdf()` | 无 | 私有 | 外部构造 → 编译错误 |

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `pbkdf2` | PBKDF2 | `HashAlgorithm, Bytes password, Bytes salt, Int iterations, Int length` | `Result<Bytes, Error>` | 参数/算法 |
| `scrypt` | scrypt | `Bytes password, Bytes salt, Int costN, Int blockSize, Int parallelism, Int length` | `Result<Bytes, Error>` | 参数 |
| `argon2id` | Argon2id | `Bytes password, Bytes salt, Int memory, Int iterations, Int parallelism, Int length` | `Result<Bytes, Error>` | 参数 |
| `hkdf` | HKDF | `HashAlgorithm, Bytes ikm, Bytes salt, Bytes info, Int length` | `Result<Bytes, Error>` | 参数 |
| `sm3Kdf` | SM3 KDF | `Bytes secret, Bytes salt, Int length` | `Result<Bytes, Error>` | 参数 |

---

## 8. 使用的技术

- PBKDF2/scrypt/Argon2/HKDF/SM3-KDF。

---

## 9. 需要的支撑

- 语言：class、Bytes、Int、Result；
- 运行时：`kdfPbkdf2Raw`、`kdfScryptRaw`、`kdfArgon2idRaw`、`kdfHkdfRaw`、`kdfSm3Raw`；
- 接口：`KdfAlgorithm`、`HashAlgorithm`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`KdfAlgorithm`、`HashAlgorithm`、`Bytes`、`Error`、KDF 运行时原语。

---

## 11. 所有权与并发

无状态；无资源；可并发。

---

## 12. 示例与反例

正确：`Kdf.argon2id(password,salt,65536,3,1,32)`。  
反例：固定盐；长度 0；scrypt 参数过大无上限。

---

## 13. 测试/场景义务

已知向量；参数边界；Argon2 内存；HKDF info；SM3；错误。

---

## 14. XNull 伪代码

```xnull
class Kdf {
    private Kdf() {
    }

    static Result<Bytes, Error> pbkdf2(HashAlgorithm hash, Bytes password,
                                       Bytes salt, Int iterations, Int length) {
        if password == null || salt == null { throw "Kdf.pbkdf2: null" }
        if iterations <= 0 || length <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid KDF parameter"))
        }
        return kdfPbkdf2Raw(hash, password, salt, iterations, length)
    }

    static Result<Bytes, Error> scrypt(Bytes password, Bytes salt, Int costN, Int blockSize, Int parallelism, Int length) {
        if password == null || salt == null { throw "Kdf.scrypt: null" }
        if costN <= 1 || blockSize <= 0 || parallelism <= 0 || length <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid scrypt parameter"))
        }
        return kdfScryptRaw(password, salt, costN, blockSize, parallelism, length)
    }

    static Result<Bytes, Error> argon2id(Bytes password, Bytes salt, Int memory,
                                         Int iterations, Int parallelism, Int length) {
        if password == null || salt == null { throw "Kdf.argon2id: null" }
        if memory <= 0 || iterations <= 0 || parallelism <= 0 || length <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid argon2 parameter"))
        }
        return kdfArgon2idRaw(password, salt, memory, iterations, parallelism, length)
    }

    static Result<Bytes, Error> hkdf(HashAlgorithm hash, Bytes ikm, Bytes salt,
                                     Bytes info, Int length) {
        if ikm == null || salt == null || info == null { throw "Kdf.hkdf: null" }
        if length <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid length"))
        }
        return kdfHkdfRaw(hash, ikm, salt, info, length)
    }

    static Result<Bytes, Error> sm3Kdf(Bytes secret, Bytes salt, Int length) {
        if secret == null || salt == null { throw "Kdf.sm3Kdf: null" }
        if length <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid length"))
        }
        return kdfSm3Raw(secret, salt, length)
    }
}
```

> `kdf*Raw` 是运行时 KDF 原语；不是 XDK 公共类型。
