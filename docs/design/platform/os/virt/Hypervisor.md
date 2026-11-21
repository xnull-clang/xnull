# `Hypervisor`

| 项 | 值 |
| --- | --- |
| 类型 | `class Hypervisor` |
| 包 | `xdk.os.virt` |
| 稳定性 | `preview` |
| 依赖 | `HypervisorKind` |

---

## 1. 定位

单个 hypervisor 条目的只读快照：类型、稳定名、版本、是否当前宿主。

不做：启动/停止 hypervisor、管理 VM、设备直通、虚拟网络/磁盘、hypervisor 专有 API。

---

## 2. 设计逻辑

- 不可变快照；由 `VirtualizationHost.hypervisors(context)` 返回。
- `kind` 是 `HypervisorKind` 分类；`name` 是稳定小写标识，通常等于 `hypervisorKindName(kind)`；
  未知/适配器自定义时可为其他小写名或空串。
- `version` 是适配器报告的版本字符串；未知时为空串；不保证可解析/可比较。
- `isHost` 表示当前 OS 是否为该 hypervisor 的宿主：true = 本机可管理本地 VM；
  false = 仅检测到客户机侧或管理端线索，不承诺本地 VM 管理能力。
- 不提供控制/探测刷新；不持有 hypervisor 句柄。
- 为什么是 class：四个字段组成稳定快照；不用 enum 因为版本/宿主标志是开放值。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_kind` | `HypervisorKind` | final | 非 null |
| `_name` | `String` | final | 非 null；稳定小写；可为空 |
| `_version` | `String` | final | 非 null；可为空 |
| `_isHost` | `Bool` | final | 是否当前宿主 |

不变量：`kind`/`name`/`version` 非 null；`name` 若为非空则是稳定小写标识；不可变；无资源。

---

## 4. 生命周期

构造后不可变；无 close；可共享；无取消点。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Hypervisor(HypervisorKind kind, String name, String version, Bool isHost)` | 4 个字段 | kind/name/version 非 null | null → panic |

构造器主要供适配器/测试使用；业务代码通过 `VirtualizationHost.hypervisors` 获取。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `kind` | hypervisor 类型 | 无 | `HypervisorKind` | 无 | O(1) |
| `name` | 稳定小写名 | 无 | `String` | 无 | O(1)；可为空 |
| `version` | 版本字符串 | 无 | `String` | 无 | O(1)；可为空 |
| `isHost` | 是否当前宿主 | 无 | `Bool` | 无 | O(1) |
| `describe` | 单行摘要 | 无 | `String` | 无 | O(n)；仅诊断 |

无 equals/copy：需要比较时逐字段比较；`==` 是引用身份。

---

## 8. 使用的技术

- 不可变快照；
- 枚举分类；
- 字符串归一；
- 字符串描述。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Bool、Enum；
- 运行时/适配器：hypervisor 探测与版本读取；
- 接口：`HypervisorKind`、`VirtualizationHost`。

---

## 10. 依赖的特性/接口/类

`HypervisorKind`、`VirtualMachine`、`VirtualizationHost`。

---

## 11. 所有权与并发

引用语义；不可变；可跨任务共享；无资源；无取消点。
相等：`==` 是引用身份；本基线不提供 `equals`；需要比较时逐字段比较；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：按 `kind()` 选择诊断文本；用 `isHost()` 区分宿主/客户机。  
反例：解析 `version()` 做版本排序；把 `name()` 当枚举；假设 `isHost` 一定为 true；
把 hypervisor 名称写入敏感日志。

---

## 13. 测试/场景义务

KVM/Hyper-V/Xen/VMware/Parallels/QEMU TCG；宿主/客户机；空版本；空名称；`Unknown`；
`describe`；null 构造 panic；与 `VirtualMachine.hypervisor()` 关联。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class Hypervisor {
    final HypervisorKind _kind
    final String _name
    final String _version
    final Bool _isHost

    Hypervisor(HypervisorKind kind, String name, String version, Bool isHost) {
        if kind == null || name == null || version == null {
            throw "Hypervisor: null field"
        }
        _kind = kind
        _name = name
        _version = version
        _isHost = isHost
    }

    HypervisorKind kind() { return _kind }

    String name() { return _name }

    String version() { return _version }

    Bool isHost() { return _isHost }

    String describe() {
        String role = "guest"
        if _isHost { role = "host" }
        if _version == "" {
            return "hypervisor " + _name + " (" + role + ")"
        }
        return "hypervisor " + _name + " " + _version + " (" + role + ")"
    }
}
```
