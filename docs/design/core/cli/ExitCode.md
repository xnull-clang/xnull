# `ExitCode`

| 项 | 值 |
| --- | --- |
| 类型 | `enum ExitCode` |
| 包 | `xdk.cli` |
| 稳定性 | `stable` |
| 依赖 | 无 |

---

## 1. 定位

命令行程序常用退出码：成功、一般错误、用法错误、命令不存在、信号基值。

不做：业务退出码注册表、shell 特定码、进程退出调用。

---

## 2. 设计逻辑

- 简单枚举，成员值固定。
- 枚举不定义方法；进程码由顶层 `exitCodeValue` 映射。
- `ExitCode.Usage` 固定为 2；`NotFound` 为 127；`SignalBase` 为 128。
- 业务码可高于 128，但不在本枚举内。

---

## 3. 表示与不变量

| 成员 | 值 | 含义 |
| --- | ---: | --- |
| `Ok` | 0 | 成功 |
| `Error` | 1 | 一般失败 |
| `Usage` | 2 | 参数/用法错误 |
| `NotFound` | 127 | 命令不存在 |
| `SignalBase` | 128 | 信号退出基值 |

不变量：成员固定；值固定；只允许追加新成员。

---

## 4. 生命周期

值类型；无 close；可共享。

---

## 5. 构造契约

枚举成员直接使用；不允许 `new`。

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

`ExitCode` 无实例方法。相关顶层函数：

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `exitCodeValue` | 枚举 → 进程码 | `ExitCode code` | `Int` | 无 |
| `exitCodeName` | 枚举 → 稳定名 | `ExitCode code` | `String` | 无 |

`exitCodeValue` 的映射由 §3 固定；未知成员不可能出现。

---

## 8. 使用的技术

- 简单枚举；
- 固定码表；
- 顶层映射函数。

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

正确：`exitCodeValue(ExitCode.Usage)` → `2`。  
反例：把业务码塞进枚举；用 `128 + signal` 替代 `SignalBase` 语义；依赖字符串比较退出码。

---

## 13. 测试/场景义务

五个成员的值；`exitCodeValue`；`exitCodeName`；未知业务码不在枚举内；进程码稳定性。

---

## 14. XNull 伪代码

```xnull
enum ExitCode {
    Ok = 0,
    Error = 1,
    Usage = 2,
    NotFound = 127,
    SignalBase = 128,
}

Int exitCodeValue(ExitCode code) {
    if code == ExitCode.Ok { return 0 }
    if code == ExitCode.Error { return 1 }
    if code == ExitCode.Usage { return 2 }
    if code == ExitCode.NotFound { return 127 }
    return 128
}

String exitCodeName(ExitCode code) {
    if code == ExitCode.Ok { return "ok" }
    if code == ExitCode.Error { return "error" }
    if code == ExitCode.Usage { return "usage" }
    if code == ExitCode.NotFound { return "not_found" }
    return "signal_base"
}
```
