# `CompressionLevel`

| 项 | 值 |
| --- | --- |
| 类型 | `enum CompressionLevel` |
| 包 | `xdk.compress` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

压缩强度：存储、最快、快、默认、最大。

不做：算法选择（由 Gzip/Zlib/Deflate 决定）、数值级别透传、压缩后端私有参数。

---

## 2. 设计逻辑

- 固定五档，映射到后端整数级别：`None=0`、`Fastest=1`、`Fast=3`、`Default=6`、`Maximum=9`。
- 只表达速度/压缩率取舍，不改变格式。
- `None` 仍生成合法 gzip/zlib/deflate 容器，只是不压缩。
- 值语义；无 close；可作 Map 键。

---

## 3. 表示与不变量

| 成员 | 后端级别 | 说明 |
| --- | ---: | --- |
| `None` | 0 | 仅存储 |
| `Fastest` | 1 | 最低 CPU |
| `Fast` | 3 | 偏速度 |
| `Default` | 6 | 默认 |
| `Maximum` | 9 | 最高压缩率 |

不变量：成员固定；映射在实现内稳定；不接受枚举外整数。

---

## 4. 生命周期

值类型；无 close；无资源。

---

## 5. 构造契约

枚举成员直接使用；不提供 `CompressionLevel(Int)`。

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

无实例方法；数值映射由压缩后端内部完成。

---

## 8. 使用的技术

- 简单枚举；
- 固定级别映射；
- 编译期穷尽检查。

---

## 9. 需要的支撑

- 语言：enum、Int。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

值语义；无资源；可跨任务共享。

---

## 12. 示例与反例

正确：`Gzip.compress(data, CompressionLevel.Fast)`。  
反例：把 `Maximum` 当无损/有损开关；把级别当格式版本；传任意整数。

---

## 13. 测试/场景义务

每个成员；后端映射；`None` 输出仍可解压；默认值；边界数据。

---

## 14. XNull 伪代码

```xnull
enum CompressionLevel {
    None,
    Fastest,
    Fast,
    Default,
    Maximum,
}
```
