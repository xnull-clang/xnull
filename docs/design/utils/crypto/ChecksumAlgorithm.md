# `ChecksumAlgorithm`

| 项 | 值 |
| --- | --- |
| 类型 | `enum ChecksumAlgorithm` |
| 包 | `xdk.crypto` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

非加密校验和：CRC32/CRC32C/CRC64、Adler32、FNV-1a 32/64。

不做：MAC、摘要、纠错码。

---

## 2. 设计逻辑

- 固定枚举；不是密码学安全。
- 值语义；无 close。

---

## 3. 表示与不变量

| 成员 | 说明 |
| --- | --- |
| `Crc32`/`Crc32c`/`Crc64` | CRC |
| `Adler32` | Adler |
| `Fnv1a32`/`Fnv1a64` | FNV-1a |

---

## 4. 生命周期

值类型；无 close。

---

## 5. 构造契约

枚举成员直接使用。

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

无实例方法；`Checksum` 使用。

---

## 8. 使用的技术

- 简单枚举。

---

## 9. 需要的支撑

- 语言：enum。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

值语义；无资源。

---

## 12. 示例与反例

正确：`Checksum.compute(ChecksumAlgorithm.Crc32, data)`。  
反例：用 CRC 做 MAC；FNV 当加密哈希。

---

## 13. 测试/场景义务

每个算法；空数据；已知向量；十六进制。

---

## 14. XNull 伪代码

```xnull
enum ChecksumAlgorithm {
    Crc32,
    Crc32c,
    Crc64,
    Adler32,
    Fnv1a32,
    Fnv1a64,
}
```
