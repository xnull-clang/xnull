# `OsFamily`

| 项 | 值 |
| --- | --- |
| 类型 | `enum OsFamily` |
| 包 | `xdk.os` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

OS 家族粗分类：Unix、Windows、WASM、未知。用于 ABI/路径/服务模型的粗分支。

不做：发行版、内核版本、桌面环境、架构。

---

## 2. 设计逻辑

- `Unix` 覆盖 Linux/macOS/Android/iOS/FreeBSD；具体差异由 `OsKind`/适配器处理。
- `Windows` 独立；`Wasm` 独立；`Unknown` 是合法值。
- 只用于粗分支；不替代能力查询。
- 值语义；可作 Map/Set 键；成员固定，只允许追加。

---

## 3. 表示与不变量

| 成员 | 含义 |
| --- | --- |
| `Unix` | Unix-like |
| `Windows` | Windows NT |
| `Wasm` | WebAssembly 宿主 |
| `Unknown` | 未知 |

不变量：成员固定；只允许追加；值语义；可作 Map/Set 键。

---

## 4. 生命周期

值类型；无构造器、无 close；可共享。

---

## 5. 构造契约

枚举项直接使用，无构造器。

---

## 6. 字段表

无实例字段。

---

## 7. 方法面

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `osFamilyName` | 稳定小写名 | `OsFamily family` | `String` | 无 |
| `osFamilyFromName` | 名称解析 | `String name` | `OsFamily?` | 无；未知返回 null |
| `osFamilyIsUnixLike` | 是否 Unix-like | `OsFamily family` | `Bool` | 无 |

---

## 8. 使用的技术

- 简单枚举；
- 名称映射；
- 粗分类。

---

## 9. 需要的支撑

- 语言：enum、String、Bool；
- 运行时：无；
- 接口：`OsKind`。

---

## 10. 依赖的特性/接口/类

`OsKind`、`OsProfile`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。

---

## 12. 示例与反例

正确：`osFamilyIsUnixLike(profile.family())` 选择 Unix 路径规则。  
反例：把 `Unix` 当“所有 POSIX 细节一致”；用家族替代能力查询；未知家族 panic。

---

## 13. 测试/场景义务

每个成员名称/解析；Unix-like 判定；Windows/Wasm/Unknown；与 `OsKind` 映射一致。

---

## 14. XNull 伪代码

```xnull
enum OsFamily {
    Unix,
    Windows,
    Wasm,
    Unknown,
}

String osFamilyName(OsFamily family) {
    if family == OsFamily.Unix { return "unix" }
    if family == OsFamily.Windows { return "windows" }
    if family == OsFamily.Wasm { return "wasm" }
    return "unknown"
}

OsFamily? osFamilyFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "unix" { return OsFamily.Unix }
    if normalized == "windows" { return OsFamily.Windows }
    if normalized == "wasm" { return OsFamily.Wasm }
    if normalized == "unknown" { return OsFamily.Unknown }
    return null
}

Bool osFamilyIsUnixLike(OsFamily family) {
    return family == OsFamily.Unix
}
```
