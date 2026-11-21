# `Closer`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol Closer` |
| 包 | `xdk.io` |
| 稳定性 | `stable` |
| 依赖 | `Error` |

---

## 1. 定位

通用关闭协议：close/isOpen；供 Reader/Writer/Seekable 组合。

不做：读/写/定位；资源类型本身仍需显式 close。

---

## 2. 设计逻辑

- `close` 幂等；第一次释放，第二次 Ok。
- 关闭失败只报告诊断，资源仍视为释放。
- `isOpen` 关闭后 false。
- 不替代 Reader/Writer 的资源合同。

---

## 3. 表示与不变量

协议无字段。实现保证 close 幂等、关闭后操作失败。

---

## 4. 生命周期

由实现决定；资源流必须 close。

---

## 5. 构造契约

协议无构造。

---

## 6. 字段表

无协议字段。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 非泛型协议；
- 幂等关闭；
- 诊断失败。

---

## 9. 需要的支撑

- 语言：protocol、Bool、Result；
- 运行时：实现决定；
- 接口：`Error`。

---

## 10. 依赖的特性/接口/类

`Error`、`Result`。

---

## 11. 所有权与并发

close 可由实现声明是否并发安全；默认非线程安全。

---

## 12. 示例与反例

正确：defer close；重复 close。  
反例：close 失败当未关闭；关闭后继续读；用 Closer 替代 Reader。

---

## 13. 测试/场景义务

close 幂等；isOpen；关闭后操作；close 失败诊断；并发 close。

---

## 14. XNull 伪代码

```xnull
protocol Closer {
    Result<Unit, Error> close();
    Bool isOpen();
}
```
