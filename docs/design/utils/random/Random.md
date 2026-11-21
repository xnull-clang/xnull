# `Random`

| 项 | 值 |
| --- | --- |
| 类型 | `class Random implements RandomSource` |
| 包 | `xdk.random` |
| 稳定性 | `preview` |
| 依赖 | `RandomSource`、`Bytes`、`List` |

---

## 1. 定位

可种子 PRNG：基本随机、范围、Gaussian、字节、洗牌、选择、采样、fork、状态。

不做：加密安全、全局单例、并行 PRNG、自定义算法。

---

## 2. 设计逻辑

- 字段 `_handle: RandomHandle`；构造创建。
- `Random()` 随机种子；`Random(seed)` 可复现。
- 范围方法半开/闭区间明确：`nextInt(max)` [0,max)，`nextInt(min,max)` [min,max)。
- `shuffle` 原地 Fisher-Yates；`choice` 非空；`sample` 不重复抽样。
- 非线程安全；无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_handle` | `RandomHandle` | 运行时 PRNG |

---

## 4. 生命周期

构造；无 close；可 `fork` 出新实例。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Random()` | 无 | 随机种子 | 无 |
| `Random(Long seed)` | seed | 任意 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `seed` | 重设种子 | `Long` | `void` | 无 |
| `nextLong` | Long | 无 | `Long` | 无 |
| `nextDouble` | [0,1) | 无 | `Double` | 无 |
| `nextBool` | Bool | 无 | `Bool` | 无 |
| `nextInt` | Int | 无 | `Int` | 无 |
| `nextInt` | [0,max) | `Int max` | `Int` | ≤0 → panic |
| `nextInt` | [min,max) | `Int min,max` | `Int` | 空区间 → panic |
| `nextLong` | [min,max) | `Long min,max` | `Long` | 空区间 → panic |
| `nextGaussian` | 高斯 | 无 | `Double` | 无 |
| `nextBytes` | 字节 | `Int count` | `Bytes` | 负值 → panic |
| `shuffle` | 洗牌 | `List<T>` | `void` | null → panic |
| `choice` | 选择一个 | `List<T>` | `T` | 空 → panic |
| `sample` | 不重复抽样 | `List<T>, Int count` | `List<T>` | 越界 → panic |
| `fork` | 派生 | 无 | `Random` | 无 |
| `state` | 状态 | 无 | `Long` | 无 |

---

## 8. 使用的技术

- PRNG；
- Fisher-Yates；
- 不重复抽样；
- 高斯分布。

---

## 9. 需要的支撑

- 语言：class、List、Int、Long、Double、Bool；
- 运行时：`randomCreateRaw`、`randomNextLongRaw`、`randomNextDoubleRaw`、`randomNextBytesRaw`、`randomSeedRaw`、`randomForkRaw`、`randomStateRaw`、`toInt`、`RandomHandle`；
- 接口：`RandomSource`、`Bytes`。

---

## 10. 依赖的特性/接口/类

`RandomSource`、`Bytes`、`List`、随机运行时原语。

---

## 11. 所有权与并发

引用语义；非线程安全；无资源；fork 独立。

---

## 12. 示例与反例

正确：`new Random(42)` 可复现。  
反例：用 Random 生成令牌；多任务共享不加锁；空 choice。

---

## 13. 测试/场景义务

同 seed 序列；范围边界；shuffle 置换；sample 不重复；choice；fork；bytes；Gaussian。

---

## 14. XNull 伪代码

```xnull
class Random implements RandomSource {
    final RandomHandle _handle

    Random() {
        _handle = randomCreateRaw(null)
    }

    Random(Long seed) {
        _handle = randomCreateRaw(seed)
    }

    void seed(Long value) { randomSeedRaw(_handle, value) }

    Long nextLong() { return randomNextLongRaw(_handle) }
    Double nextDouble() { return randomNextDoubleRaw(_handle) }
    Bool nextBool() { return (self.nextInt(2) == 1) }

    Int nextInt() {
        Long value = self.nextLong()
        return toInt(value % 2147483647)
    }

    Int nextInt(Int max) {
        if max <= 0 { throw "Random.nextInt: max <= 0" }
        return randomIntRaw(_handle, 0, max)
    }

    Int nextInt(Int min, Int max) {
        if min >= max { throw "Random.nextInt: empty range" }
        return randomIntRaw(_handle, min, max)
    }

    Long nextLong(Long min, Long max) {
        if min >= max { throw "Random.nextLong: empty range" }
        return randomLongRaw(_handle, min, max)
    }

    Double nextGaussian() { return randomGaussianRaw(_handle) }

    Bytes nextBytes(Int count) {
        if count < 0 { throw "Random.nextBytes: negative" }
        return randomNextBytesRaw(_handle, count)
    }

    void shuffle<T>(List<T> values) {
        if values == null { throw "Random.shuffle: null" }
        Int index = values.length() - 1
        while index > 0 {
            Int other = self.nextInt(index + 1)
            T temporary = values.get(index)
            values.set(index, values.get(other))
            values.set(other, temporary)
            index = index - 1
        }
    }

    T choice<T>(List<T> values) {
        if values == null || values.length() == 0 {
            throw "Random.choice: empty"
        }
        return values.get(self.nextInt(values.length()))
    }

    List<T> sample<T>(List<T> values, Int count) {
        if values == null { throw "Random.sample: null" }
        if count < 0 || count > values.length() {
            throw "Random.sample: invalid count"
        }
        List<T> copy = values.copy()
        self.shuffle(copy)
        List<T> result = []
        Int index = 0
        while index < count {
            result.push(copy.get(index))
            index = index + 1
        }
        return result
    }

    Random fork() { return new Random(randomForkRaw(_handle)) }
    Long state() { return randomStateRaw(_handle) }
}
```

> `RandomHandle`、`random*Raw`、`toInt` 是运行时 PRNG 原语；不是 XDK 公共类型。
