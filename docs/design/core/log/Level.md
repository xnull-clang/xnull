# `Level`

| 项 | 值 |
| --- | --- |
| 类型 | `enum Level` |
| 包 | `xdk.log` |
| 稳定性 | `stable` |
| 依赖 | 无 |

---

## 1. 定位

日志级别：Debug/Info/Warn/Error；顺序固定。

不做：自定义级别、级别名称本地化、动态注册。

---

## 2. 设计逻辑

- 4 个成员，rank 0..3。
- `levelRank`/`levelName` 顶层函数；枚举不定义实例方法。
- 阈值比较用 rank；未知级别不允许。
- 值语义。

---

## 3. 表示与不变量

| 成员 | rank |
| --- | ---: |
| `Debug` | 0 |
| `Info` | 1 |
| `Warn` | 2 |
| `Error` | 3 |

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

## 7. 相关顶层函数

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `levelRank` | 级别序 | `Level level` | `Int` | 无 |
| `levelName` | 大写名 | `Level level` | `String` | 无 |

---

## 8. 使用的技术

- 枚举；
- 固定 rank。

---

## 9. 需要的支撑

- 语言：enum、Int、String；
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

正确：`enabled(Level.Warn)` 对 Error 为 true。  
反例：用字符串级别；自定义 rank；把 Debug 当最高。

---

## 13. 测试/场景义务

4 级别 rank/name；阈值比较；顺序。

---

## 14. XNull 伪代码

```xnull
enum Level {
    Debug,
    Info,
    Warn,
    Error,
}

Int levelRank(Level level) {
    if level == Level.Debug { return 0 }
    if level == Level.Info { return 1 }
    if level == Level.Warn { return 2 }
    return 3
}

String levelName(Level level) {
    if level == Level.Debug { return "DEBUG" }
    if level == Level.Info { return "INFO" }
    if level == Level.Warn { return "WARN" }
    return "ERROR"
}
```
