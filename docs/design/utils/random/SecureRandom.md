# `SecureRandom`

| 项 | 值 |
| --- | --- |
| 类型 | `class SecureRandom implements RandomSource` |
| 包 | `xdk.random` |
| 稳定性 | `preview` |
| 依赖 | `RandomSource`、`Bytes`、`List` |

---

## 1. 定位

加密安全随机：字节/Long/Double/范围/洗牌/重播种。

不做：PRNG 可复现、全局单例、自定义算法。

---

## 2. 设计逻辑

- 无状态；每次调用走运行时安全随机源。
- `nextBytes` 使用 OS CSPRNG；`reseed` 由实现定义（可为 no-op）。
- 实现 `RandomSource`；可传 `WeightedChoice`。
- 无 close；线程安全由运行时声明。

---

## 3. 表示与不变量

无实例字段。

---

## 4. 生命周期

构造；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `SecureRandom()` | 无 | 无 | 无 |

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `nextLong` | Long | 无 | `Long` | 无 |
| `nextDouble` | [0,1) | 无 | `Double` | 无 |
| `nextBytes` | 字节 | `Int count` | `Bytes` | 负值 → panic |
| `nextInt` | [0,max) | `Int max` | `Int` | ≤0 → panic |
| `shuffle` | 洗牌 | `List<T>` | `void` | null → panic |
| `reseed` | 重播种 | 无 | `void` | 无 |

---

## 8. 使用的技术

- CSPRNG；
- 均匀范围；
- Fisher-Yates。

---

## 9. 需要的支撑

- 语言：class、List、Int、Long、Double、Bytes；
- 运行时：`secureRandomLongRaw`、`secureRandomDoubleRaw`、`secureRandomBytes`、`secureRandomReseedRaw`、`toInt`；
- 接口：`RandomSource`。

---

## 10. 依赖的特性/接口/类

`RandomSource`、`Bytes`、安全随机运行时原语。

---

## 11. 所有权与并发

无状态；可共享；线程安全由运行时声明；无资源。

---

## 12. 示例与反例

正确：`new SecureRandom().nextBytes(32)` 生成令牌。  
反例：用 seed 期望复现；用 Random 生成密钥；负 count。

---

## 13. 测试/场景义务

字节长度；范围；shuffle；reseed；分布 sanity；并发。

---

## 14. XNull 伪代码

```xnull
class SecureRandom implements RandomSource {
    SecureRandom() {
    }

    Long nextLong() { return secureRandomLongRaw() }
    Double nextDouble() { return secureRandomDoubleRaw() }

    Bytes nextBytes(Int count) {
        if count < 0 { throw "SecureRandom.nextBytes: negative" }
        return secureRandomBytes(count)
    }

    Int nextInt(Int max) {
        if max <= 0 { throw "SecureRandom.nextInt: max <= 0" }
        Long value = secureRandomLongRaw()
        return toInt(value % toLong(max))
    }

    void shuffle<T>(List<T> values) {
        if values == null { throw "SecureRandom.shuffle: null" }
        Int index = values.length() - 1
        while index > 0 {
            Int other = self.nextInt(index + 1)
            T temporary = values.get(index)
            values.set(index, values.get(other))
            values.set(other, temporary)
            index = index - 1
        }
    }

    void reseed() { secureRandomReseedRaw() }
}
```

> `secureRandom*Raw`、`toInt`、`toLong` 是运行时安全随机原语；不是 XDK 公共类型。
