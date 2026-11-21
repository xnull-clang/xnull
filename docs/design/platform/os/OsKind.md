# `OsKind`

| 项 | 值 |
| --- | --- |
| 类型 | `enum OsKind` |
| 包 | `xdk.os` |
| 稳定性 | `preview` |
| 依赖 | `OsFamily` |

---

## 1. 定位

当前/目标操作系统的封闭分类：Linux、Windows、macOS、Android、iOS、FreeBSD、WASM、未知。

不做：发行版识别（`OsInfo.name`）、版本比较、架构、桌面环境。

---

## 2. 设计逻辑

- 只区分**内核/平台族**，不把 Ubuntu/Debian/Fedora 等发行版塞进枚举。
- 发行版、版本、内核版本由 `OsInfo` 字符串字段承载。
- `Unknown` 是合法值；未知平台不得 panic，能力查询返回不支持。
- 值语义；可作 `Map`/`Set` 键；序号固定，只允许追加。
- 与 core `Platform.os()` 的关系：core 返回字符串；`OsKind` 是  的结构化分类。

---

## 3. 表示与不变量

| 成员 | 含义 | 家族 |
| --- | --- | --- |
| `Linux` | Linux 内核 | `Unix` |
| `Windows` | Windows NT | `Windows` |
| `MacOS` | macOS | `Unix` |
| `Android` | Android/Linux | `Unix` |
| `IOS` | iOS/Darwin | `Unix` |
| `FreeBsd` | FreeBSD | `Unix` |
| `Wasm` | WebAssembly 宿主 | `Wasm` |
| `Unknown` | 未知/未识别 | `Unknown` |

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
| `osKindName` | 稳定小写名 | `OsKind kind` | `String` | 无 |
| `osKindDisplayName` | 显示名 | `OsKind kind` | `String` | 无 |
| `osKindFromName` | 名称解析 | `String name` | `OsKind?` | 无；未知返回 null |
| `osKindFamily` | 平台家族 | `OsKind kind` | `OsFamily` | 无 |

---

## 8. 使用的技术

- 简单枚举；
- 名称映射；
- 家族映射。

---

## 9. 需要的支撑

- 语言：enum、String、Bool；
- 运行时：无；
- 接口：`OsFamily`。

---

## 10. 依赖的特性/接口/类

`OsFamily`、`OsInfo`、`OsProfile`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。

---

## 12. 示例与反例

正确：`OsKind kind = Os.kind()`；`osKindFamily(kind) == OsFamily.Unix`。  
反例：在业务里散落 `if os == "linux"`；把发行版塞进枚举；未知平台 panic。

---

## 13. 测试/场景义务

每个成员名称/显示名；大小写不敏感解析；家族映射；未知名称；WASM；Android/iOS。

---

## 14. XNull 伪代码

```xnull
enum OsKind {
    Linux,
    Windows,
    MacOS,
    Android,
    IOS,
    FreeBsd,
    Wasm,
    Unknown,
}

String osKindName(OsKind kind) {
    if kind == OsKind.Linux { return "linux" }
    if kind == OsKind.Windows { return "windows" }
    if kind == OsKind.MacOS { return "macos" }
    if kind == OsKind.Android { return "android" }
    if kind == OsKind.IOS { return "ios" }
    if kind == OsKind.FreeBsd { return "freebsd" }
    if kind == OsKind.Wasm { return "wasm" }
    return "unknown"
}

String osKindDisplayName(OsKind kind) {
    if kind == OsKind.Linux { return "Linux" }
    if kind == OsKind.Windows { return "Windows" }
    if kind == OsKind.MacOS { return "macOS" }
    if kind == OsKind.Android { return "Android" }
    if kind == OsKind.IOS { return "iOS" }
    if kind == OsKind.FreeBsd { return "FreeBSD" }
    if kind == OsKind.Wasm { return "WebAssembly" }
    return "Unknown"
}

OsKind? osKindFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "linux" { return OsKind.Linux }
    if normalized == "windows" { return OsKind.Windows }
    if normalized == "macos" || normalized == "darwin" { return OsKind.MacOS }
    if normalized == "android" { return OsKind.Android }
    if normalized == "ios" { return OsKind.IOS }
    if normalized == "freebsd" { return OsKind.FreeBsd }
    if normalized == "wasm" || normalized == "webassembly" { return OsKind.Wasm }
    if normalized == "unknown" { return OsKind.Unknown }
    return null
}

OsFamily osKindFamily(OsKind kind) {
    if kind == OsKind.Windows { return OsFamily.Windows }
    if kind == OsKind.Wasm { return OsFamily.Wasm }
    if kind == OsKind.Unknown { return OsFamily.Unknown }
    return OsFamily.Unix
}
```
