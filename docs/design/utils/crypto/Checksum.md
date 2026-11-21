# `Checksum`

| 项 | 值 |
| --- | --- |
| 类型 | `class Checksum` |
| 包 | `xdk.crypto` |
| 稳定性 | `preview` |
| 依赖 | `ChecksumAlgorithm`、`Bytes` |

---

## 1. 定位

非加密校验和静态入口：CRC32/CRC32C/CRC64、Adler32、FNV-1a。

不做：MAC、摘要、纠错。

---

## 2. 设计逻辑

- 无状态；构造器私有。
- `compute` 返回 Long（32 位算法也用 Long 无符号）。
- `hex` 固定宽度。
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
| `Checksum()` | 无 | 私有 | 外部构造 → 编译错误 |

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `compute` | 校验和 | `ChecksumAlgorithm, Bytes` | `Long` | 无 |
| `hex` | 十六进制 | `ChecksumAlgorithm, Bytes` | `String` | 无 |

---

## 8. 使用的技术

- CRC/Adler/FNV。

---

## 9. 需要的支撑

- 语言：class、Bytes、Long、String；
- 运行时：`checksumRaw`、`checksumHexRaw`。

---

## 10. 依赖的特性/接口/类

`ChecksumAlgorithm`、`Bytes`、校验和运行时原语。

---

## 11. 所有权与并发

无状态；无资源；可并发。

---

## 12. 示例与反例

正确：`Checksum.hex(Crc32, data)`。  
反例：CRC 当 MAC；忽略无符号范围。

---

## 13. 测试/场景义务

已知向量；空数据；各算法；hex 宽度。

---

## 14. XNull 伪代码

```xnull
class Checksum {
    private Checksum() {
    }

    static Long compute(ChecksumAlgorithm algorithm, Bytes data) {
        if data == null { throw "Checksum.compute: null" }
        return checksumRaw(algorithm, data)
    }

    static String hex(ChecksumAlgorithm algorithm, Bytes data) {
        return checksumHexRaw(algorithm, data)
    }
}
```

> `checksum*Raw` 是运行时校验和原语；不是 XDK 公共类型。
