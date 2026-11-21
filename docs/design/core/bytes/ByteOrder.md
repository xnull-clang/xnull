# `ByteOrder`

| 项 | 值 |
| --- | --- |
| 类型 | `enum ByteOrder` |
| 包 | `xdk.bytes` |
| 稳定性 | `stable` |
| 依赖 | 无 |

---

## 1. 定位

字节序标记：大端/小端，用于 `ByteBuffer` 和端序读写。

不做：宿主端序自动选择；必须显式声明。

---

## 2. 设计逻辑

- 只有 `BigEndian`/`LittleEndian` 两项。
- 值语义；可作 Map 键。
- 默认端序由使用方决定；`ByteBuffer` 默认大端。
- 不提供“本机端序”隐式默认，避免跨平台不一致。

---

## 3. 表示与不变量

| 成员 | 含义 |
| --- | --- |
| `BigEndian` | 高字节在前 |
| `LittleEndian` | 低字节在前 |

不变量：成员固定；只允许追加；值语义。

---

## 4. 生命周期

值类型；无 close；可共享。

---

## 5. 构造契约

枚举成员直接使用。

---

## 6. 字段表

无实例字段。

---

## 7. 方法面

`ByteOrder` 没有实例方法。端序操作由 `Endian` 顶层函数和 `ByteBuffer` 使用。

---

## 8. 使用的技术

- 枚举；
- 端序分支。

---

## 9. 需要的支撑

- 语言：enum、Bool；
- 运行时：无；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

值语义；可共享；无资源。

---

## 12. 示例与反例

正确：`ByteBuffer.order(ByteOrder.LittleEndian)`。  
反例：依赖宿主端序；同一协议混用 BE/LE；把端序当全局状态。

---

## 13. 测试/场景义务

BE/LE 读写向量；ByteBuffer 切换端序；序列化往返。

---

## 14. XNull 伪代码

```xnull
enum ByteOrder {
    BigEndian,
    LittleEndian,
}
```
