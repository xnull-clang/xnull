# `RandomSource`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol RandomSource` |
| 包 | `xdk.random` |
| 稳定性 | `preview` |
| 依赖 | `Bytes` |

---

## 1. 定位

随机源最小协议：Long、Double、字节。

不做：种子、算法、洗牌、加权选择。

---

## 2. 设计逻辑

- 三个方法；Random/SecureRandom 实现。
- `nextDouble` 返回 [0,1)；`nextBytes` 填满 count。
- 无 close。

---

## 3. 表示与不变量

协议无字段。

---

## 4. 生命周期

协议无构造；实现决定。

---

## 5. 构造契约

协议无构造。

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `nextLong` | 随机 Long | 无 | `Long` | 无 |
| `nextDouble` | [0,1) | 无 | `Double` | 无 |
| `nextBytes` | 随机字节 | `Int count` | `Bytes` | 负值 → panic |

---

## 8. 使用的技术

- 非泛型协议。

---

## 9. 需要的支撑

- 语言：protocol、Long、Double、Bytes；
- 运行时：实现决定。

---

## 10. 依赖的特性/接口/类

`Bytes`。

---

## 11. 所有权与并发

实现自行声明；无资源关闭。

---

## 12. 示例与反例

正确：`WeightedChoice.pick(randomSource)`。  
反例：负 count；假设线程安全。

---

## 13. 测试/场景义务

范围；nextBytes 长度；负值；实现一致性。

---

## 14. XNull 伪代码

```xnull
protocol RandomSource {
    Long nextLong();
    Double nextDouble();
    Bytes nextBytes(Int count);
}
```
