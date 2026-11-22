# `OsInfo`

| 项 | 值 |
| --- | --- |
| 类型 | `class OsInfo` |
| 包 | `xdk.os` |
| 稳定性 | `preview` |
| 依赖 | `OsKind`、`OsFamily` |

---

## 1. 定位

OS 身份与版本快照：类型、家族、名称、版本、内核、架构、主机名、OS 会话、libc、是否容器化。

不做：硬件清单、CPU/内存/GPU、能力控制、动态探测循环。

---

## 2. 设计逻辑

- 不可变快照；由 `Os.host().profile().info()` 提供。
- `name` 是发行版/OS 名（如 `Ubuntu`、`Windows 11`、`macOS`）；未知时可为空串。
- `version` 是发行版版本；`kernelVersion` 是内核版本；两者分开。
- `architecture` 是运行架构（`arm64`/`x86_64` 等）。
- `session` 是 OS 会话标识（如 `gnome`、`kde`、`wayland`、`windows-shell`），不是 UI 服务；无会话为空串。
- `libc` 是运行库标识（`glibc`/`musl`/`msvcrt`/`bionic`）；未知为空串。
- `isContainerized` 表示当前进程是否在容器内；不是“是否有容器能力”。
- 全部字段只读；缺失字段用空串/`false`，不 panic。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_kind` | `OsKind` | final | 非 null |
| `_family` | `OsFamily` | final | 非 null；与 kind 一致 |
| `_name` | `String` | final | 非空（未知用 `"unknown"`） |
| `_version` | `String` | final | 可为空 |
| `_kernelVersion` | `String` | final | 可为空 |
| `_architecture` | `String` | final | 非空 |
| `_hostname` | `String` | final | 可为空 |
| `_session` | `String` | final | 可为空；空 = 无会话 |
| `_libc` | `String` | final | 可为空 |
| `_isContainerized` | `Bool` | final | 是否容器内 |

不变量：kind/family 非 null；name/architecture 非空；family 与 kind 映射一致；不可变。

---

## 4. 生命周期

构造后不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `OsInfo(...)` | 10 个字段 | kind/family/name/architecture 非 null；name/architecture 非空 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `kind` | OS 类型 | 无 | `OsKind` | 无 |
| `family` | OS 家族 | 无 | `OsFamily` | 无 |
| `name` | OS/发行版名 | 无 | `String` | 无 |
| `version` | 发行版版本 | 无 | `String` | 无 |
| `kernelVersion` | 内核版本 | 无 | `String` | 无 |
| `architecture` | 架构 | 无 | `String` | 无 |
| `hostname` | 主机名 | 无 | `String` | 无 |
| `session` | OS 会话标识 | 无 | `String` | 无 |
| `libc` | 运行库 | 无 | `String` | 无 |
| `isContainerized` | 是否容器内 | 无 | `Bool` | 无 |
| `isHeadless` | 是否无 OS 会话 | 无 | `Bool` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |
| `equals` | 值比较 | `OsInfo other` | `Bool` | null → false |
| `copy` | 复制 | 无 | `OsInfo` | 无 |

---

## 8. 使用的技术

- 不可变快照；
- OS 标识/版本读取；
- 字符串归一；
- 容器检测。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Bool；
- 运行时/适配器：OS 标识、内核版本、架构、OS 会话、libc、容器检测；
- 接口：`OsKind`、`OsFamily`。

---

## 10. 依赖的特性/接口/类

`OsKind`、`OsFamily`、`OsProfile`。

---

## 11. 所有权与并发

不可变；可共享；无资源；无取消点。

---

## 12. 示例与反例

正确：`Os.info().name()` 写启动日志；`Os.info().isHeadless()` 决定是否走无头路径。
反例：用版本字符串做能力判断；把容器检测当安全边界；未知字段 panic。

---

## 13. 测试/场景义务

每个字段；未知 OS；无会话；容器内；版本/内核为空；family/kind 一致；equals/copy；
敏感信息不写日志（hostname 可选脱敏）。

---

## 14. XNull 伪代码

```xnull
class OsInfo {
    final OsKind _kind
    final OsFamily _family
    final String _name
    final String _version
    final String _kernelVersion
    final String _architecture
    final String _hostname
    final String _session
    final String _libc
    final Bool _isContainerized

    OsInfo(OsKind kind, OsFamily family, String name, String version,
           String kernelVersion, String architecture, String hostname,
           String session, String libc, Bool isContainerized) {
        if kind == null || family == null { throw "OsInfo: null kind/family" }
        if name == null || name == "" { throw "OsInfo: empty name" }
        if architecture == null || architecture == "" {
            throw "OsInfo: empty architecture"
        }
        if version == null || kernelVersion == null || hostname == null
            || session == null || libc == null {
            throw "OsInfo: null string"
        }
        if family != osKindFamily(kind) {
            throw "OsInfo: family does not match kind"
        }
        _kind = kind
        _family = family
        _name = name
        _version = version
        _kernelVersion = kernelVersion
        _architecture = architecture
        _hostname = hostname
        _session = session
        _libc = libc
        _isContainerized = isContainerized
    }

    OsKind kind() { return _kind }
    OsFamily family() { return _family }
    String name() { return _name }
    String version() { return _version }
    String kernelVersion() { return _kernelVersion }
    String architecture() { return _architecture }
    String hostname() { return _hostname }
    String session() { return _session }
    String libc() { return _libc }
    Bool isContainerized() { return _isContainerized }
    Bool isHeadless() { return _session == "" }

    String describe() {
        return osKindName(_kind) + " " + _name
            + " version=" + _version
            + " kernel=" + _kernelVersion
            + " arch=" + _architecture
            + " session=" + _session
    }

    Bool equals(OsInfo other) {
        if other == null { return false }
        return _kind == other.kind()
            && _family == other.family()
            && _name == other.name()
            && _version == other.version()
            && _kernelVersion == other.kernelVersion()
            && _architecture == other.architecture()
            && _hostname == other.hostname()
            && _session == other.session()
            && _libc == other.libc()
            && _isContainerized == other.isContainerized()
    }

    OsInfo copy() {
        return new OsInfo(_kind, _family, _name, _version, _kernelVersion,
            _architecture, _hostname, _session, _libc, _isContainerized)
    }
}
```
