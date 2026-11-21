# `Seekable`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol Seekable` |
| 包 | `xdk.io` |
| 稳定性 | `stable` |
| 依赖 | `SeekOrigin`、`Error` |

---

## 1. 定位

可定位流的协议：seek/position/size。

不做：读/写（由 Reader/Writer 组合）、文件系统、网络。

---

## 2. 设计逻辑

- `seek(offset, origin)` 返回新位置；失败位置不变。
- `position()` 当前偏移；`size()` 总大小。
- 偏移用 `Long`，避免大文件截断。
- 关闭后 seek/position/size 返回 `Unavailable`。

---

## 3. 表示与不变量

协议无字段。实现保证：

- 位置合法 `0 ≤ position ≤ size`（可写流可能允许超过 size）。
- seek 失败不改位置。
- size 是当前可读/可写范围。

---

## 4. 生命周期

由实现决定；资源流 close 后失效。

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
| `seek` | 定位 | `Long offset, SeekOrigin origin` | `Result<Long, Error>` | `InvalidArgument`/`Unavailable` |
| `position` | 当前位置 | 无 | `Long` | 无 |
| `size` | 总大小 | 无 | `Result<Long, Error>` | `Unavailable`/`Io` |

---

## 8. 使用的技术

- 64 位偏移；
- 起始点枚举；
- 失败位置不变。

---

## 9. 需要的支撑

- 语言：protocol、Long、Result；
- 运行时：实现决定；
- 接口：`SeekOrigin`、`Error`。

---

## 10. 依赖的特性/接口/类

`SeekOrigin`、`Error`、`Result`。

---

## 11. 所有权与并发

单 seeker；非线程安全。

---

## 12. 示例与反例

正确：`seek(0, SeekOrigin.End)`；`size()`。  
反例：负偏移；seek 失败后期望位置变化；用 Int 偏移。

---

## 13. 测试/场景义务

Start/Current/End；负偏移；越界；size；关闭后；大文件 Long。

---

## 14. XNull 伪代码

```xnull
protocol Seekable {
    Result<Long, Error> seek(Long offset, SeekOrigin origin);
    Long position();
    Result<Long, Error> size();
}
```
