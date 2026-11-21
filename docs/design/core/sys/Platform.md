# `Platform`

| 项 | 值 |
| --- | --- |
| 类型 | `class Platform` |
| 包 | `xdk.sys` |
| 稳定性 | `stable` |
| 依赖 | 无 |

---

## 1. 定位

运行平台标识：OS/架构/家族/主机名/pid/cwd/home/temp/分隔符。

不做：构建目标（`meta`）、能力探测（`meta`）、动态库。

---

## 2. 设计逻辑

- 静态类；无实例状态。
- OS/架构字符串稳定小写；未知 → `"unknown"`。
- 分隔符/行分隔符用于文本/路径。
- 不提供隐式 chdir；`chdir` 显式。
- 与 `meta.targetPlatform` 区分：这里是运行平台。

---

## 3. 表示与不变量

无实例字段。

---

## 4. 生命周期

静态；无 close。

---

## 5. 构造契约

静态类，不公开构造。

---

## 6. 字段表

无。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `os` | 操作系统 | 无 | `String` | 无 |
| `arch` | 架构 | 无 | `String` | 无 |
| `family` | 平台族 | 无 | `String` | 无 |
| `hostname` | 主机名 | 无 | `String` | 无 |
| `pid` | 进程 ID | 无 | `Long` | 无 |
| `cwd` | 工作目录 | 无 | `String` | 无 |
| `chdir` | 切换目录 | `String path` | `Bool` | 无 |
| `homeDir` | home | 无 | `String` | 无 |
| `tempDir` | 临时目录 | 无 | `String` | 无 |
| `separator` | 路径分隔符 | 无 | `String` | 无 |
| `pathSeparator` | PATH 分隔符 | 无 | `String` | 无 |
| `lineSeparator` | 行分隔符 | 无 | `String` | 无 |
| `isWindows` | Windows | 无 | `Bool` | 无 |
| `isLinux` | Linux | 无 | `Bool` | 无 |
| `isMacOS` | macOS | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 编译期/运行时常量；
- OS 查询；
- 路径/行分隔符。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Long；
- 运行时：OS 标识/pid/cwd/home/temp；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

静态只读；可共享；无资源。

---

## 12. 示例与反例

正确：`Platform.isWindows()` 分支；`Platform.separator()`。  
反例：用 `meta.targetPlatform` 当运行平台；依赖 `cwd` 稳定；硬编码 `/`。

---

## 13. 测试/场景义务

OS/arch/family；pid>0；cwd/home/temp 非空；分隔符；chdir；平台布尔。

---

## 14. XNull 伪代码

```xnull
class Platform {
    static String os() {
        return platformOsRaw()
    }

    static String arch() {
        return platformArchRaw()
    }

    static String family() {
        String os = self.os()
        if os == "windows" { return "windows" }
        if os == "linux" || os == "macos" { return "unix" }
        return "unknown"
    }

    static String hostname() {
        return hostnameRaw()
    }

    static Long pid() {
        return processIdRaw()
    }

    static String cwd() {
        return currentDirectoryRaw()
    }

    static Bool chdir(String path) {
        return changeDirectoryRaw(path) == 0
    }

    static String homeDir() {
        return homeDirectoryRaw()
    }

    static String tempDir() {
        return temporaryDirectoryRaw()
    }

    static String separator() {
        if self.isWindows() { return "\\" }
        return "/"
    }

    static String pathSeparator() {
        if self.isWindows() { return ";" }
        return ":"
    }

    static String lineSeparator() {
        if self.isWindows() { return "\r\n" }
        return "\n"
    }

    static Bool isWindows() { return self.os() == "windows" }
    static Bool isLinux() { return self.os() == "linux" }
    static Bool isMacOS() { return self.os() == "macos" }
}
```

> `platformOsRaw/platformArchRaw/hostnameRaw/processIdRaw/currentDirectoryRaw/changeDirectoryRaw/homeDirectoryRaw/temporaryDirectoryRaw` 是运行时平台原语。
