# `TlsPrivateKey`

| 项 | 值 |
| --- | --- |
| 类型 | `class TlsPrivateKey` |
| 包 | `xdk.net.tls` |
| 稳定性 | `preview` |
| 依赖 | `Error` |

---

## 1. 定位

TLS 私钥句柄：PEM 解析、算法/位数只读属性；不导出私钥字节。

不做：密钥生成、DER 导出、签名/解密 API、日志展示、持久化。

---

## 2. 设计逻辑

- 字段 `_handle`（运行时私钥句柄）、`_algorithm`、`_bits`。
- `parsePem` 调用运行时私钥解析；失败 `DataCorrupted`/`Unsupported`。
- 不提供 `bytes()`/`der()`/`pem()`；私钥不得进入日志/错误/诊断。
- `toString` 只显示算法/位数。
- 无 close；运行时管理句柄；不可变。
- 私钥对象可跨任务共享，但只用于 TLS 配置。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_handle` | `TlsKeyHandle` | 运行时私钥句柄 |
| `_algorithm` | `String` | 算法名 |
| `_bits` | `Int` | 位数 |

不变量：handle 非 null；algorithm 非空；bits >0；不可变；不暴露密钥材料。

---

## 4. 生命周期

解析后不可变；无 close；句柄由运行时管理；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `TlsPrivateKey.parsePem(String pem)` | pem | 非 null | `DataCorrupted`/`Unsupported` |

构造器私有。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `parsePem` | 解析私钥 | `String pem` | `Result<TlsPrivateKey, Error>` | `DataCorrupted`/`Unsupported` |
| `algorithm` | 算法名 | 无 | `String` | 无 |
| `bits` | 位数 | 无 | `Int` | 无 |
| `toString` | 安全摘要 | 无 | `String` | 无 |

---

## 8. 使用的技术

- PEM 解析；
- 运行时私钥句柄；
- 安全摘要。

---

## 9. 需要的支撑

- 语言：class、String、Int、Result；
- 运行时：`parsePrivateKeyPemRaw`、`PrivateKeyRaw`、`TlsKeyHandle`；
- 接口：`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Error`、`BasicError`、`ErrorKind`、`parsePrivateKeyPemRaw`、`TlsKeyHandle`。

---

## 11. 所有权与并发

不可变；不暴露密钥材料；可共享给 TLS 配置；无公开 close。

---

## 12. 示例与反例

正确：`TlsPrivateKey.parsePem(pem)`；`key.algorithm()`。  
反例：打印私钥 PEM；提供 `bytes()`；把私钥写入错误 describe；跨进程持久化明文。

---

## 13. 测试/场景义务

PEM 成功/失败；算法/位数；toString 不含密钥；错误消息不含私钥；不可导出。

---

## 14. XNull 伪代码

```xnull
class TlsPrivateKey {
    final TlsKeyHandle _handle
    final String _algorithm
    final Int _bits

    private TlsPrivateKey(TlsKeyHandle handle, String algorithm, Int bits) {
        _handle = handle
        _algorithm = algorithm
        _bits = bits
    }

    static Result<TlsPrivateKey, Error> parsePem(String pem) {
        if pem == null { throw "TlsPrivateKey.parsePem: null pem" }
        Result<PrivateKeyRaw, Error> raw = parsePrivateKeyPemRaw(pem)
        if raw.isErr() { return Err(raw.error()) }
        PrivateKeyRaw value = raw.value()
        return Ok(new TlsPrivateKey(value.handle(), value.algorithm(), value.bits()))
    }

    String algorithm() { return _algorithm }
    Int bits() { return _bits }

    String toString() {
        return "private-key(" + _algorithm + "-" + str(_bits) + ")"
    }
}
```

> `PrivateKeyRaw`、`parsePrivateKeyPemRaw`、`TlsKeyHandle` 是运行时私钥原语；不是 XDK 公共类型。私钥材料不得导出。
