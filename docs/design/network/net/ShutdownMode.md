# `ShutdownMode`

| 项 | 值 |
| --- | --- |
| 类型 | `enum ShutdownMode` |
| 包 | `xdk.net` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

TCP 半关闭方向：只关读、只关写、或双向。

不做：完整关闭（用 `close`）、socket 选项、UDP 语义。

---

## 2. 设计逻辑

- 简单枚举：`Read`、`Write`、`Both`。
- `shutdown(Write)` 后对端读 EOF，本地仍可读。
- `Both` 等价于半关闭两个方向，但不等价于资源 close；仍应调用 `close()`。
- 值语义；无 close；可共享。

---

## 3. 表示与不变量

| 成员 | 含义 |
| --- | --- |
| `Read` | 关闭本地读方向 |
| `Write` | 关闭本地写方向 |
| `Both` | 两个方向 |

不变量：成员固定；只允许追加。

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

## 7. 方法总表 / 详表

无实例方法。

---

## 8. 使用的技术

- 简单枚举。

---

## 9. 需要的支撑

- 语言：enum；
- 运行时：无；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

值语义；无资源；可共享。

---

## 12. 示例与反例

正确：`stream.shutdown(ShutdownMode.Write)`。  
反例：用 `shutdown(Both)` 代替 `close`；期望 shutdown 后资源自动释放。

---

## 13. 测试/场景义务

三个方向；shutdown 后读/写行为；close 仍幂等；对端 EOF。

---

## 14. XNull 伪代码

```xnull
enum ShutdownMode {
    Read,
    Write,
    Both,
}
```
