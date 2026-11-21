# `OsProfile`

| 项 | 值 |
| --- | --- |
| 类型 | `class OsProfile` |
| 包 | `xdk.os` |
| 稳定性 | `preview` |
| 依赖 | `OsInfo`、`OsCapability` |

---

## 1. 定位

OS 平台画像：OS 身份 + 可用 OS/硬件能力集合。与 core `CoreProfile` 组合使用。

不做：权限、运行时探测、设备清单、资源配额、全局单例。

---

## 2. 设计逻辑

- 不可变快照；由 `OsHost.profile()` 返回。
- `OsProfile` 只表达“这个 OS/宿主提供什么能力”，不表达“语言/网络核心能力”；后者是 `CoreProfile`。
- 能力可以比实际少（保守声明）；调用具体服务仍可能失败。
- 能力集合去重、保序；修改返回新对象。
- 名称用于诊断（如 `linux-server`、`linux-headless`、`wasm-sandbox`）。
- 不依赖 `Error/Context`；服务调用才返回 `Result`。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_name` | `String` | final | 非空 |
| `_info` | `OsInfo` | final | 非 null |
| `_capabilities` | `List<OsCapability>` | final | 去重、保序 |

不变量：name 非空；info 非 null；能力无重复；不可变。

---

## 4. 生命周期

构造后不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `OsProfile(String name, OsInfo info, List<OsCapability> capabilities)` | 全部 | name 非空；info/capabilities 非 null | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | 画像名 | 无 | `String` | 无 |
| `info` | OS 快照 | 无 | `OsInfo` | 无 |
| `kind` | OS 类型 | 无 | `OsKind` | 无 |
| `family` | OS 家族 | 无 | `OsFamily` | 无 |
| `capabilities` | 能力快照 | 无 | `List<OsCapability>` | 无 |
| `has` | 是否支持能力 | `OsCapability capability` | `Bool` | null → panic |
| `missing` | 缺少的能力 | `List<OsCapability> required` | `List<OsCapability>` | null → panic |
| `withCapability` | 派生添加 | `OsCapability capability` | `OsProfile` | null → panic |
| `withoutCapability` | 派生移除 | `OsCapability capability` | `OsProfile` | null → panic |
| `withName` | 派生名称 | `String value` | `OsProfile` | 空名 → panic |
| `describe` | 单行摘要 | 无 | `String` | 无 |
| `equals` | 值比较 | `OsProfile other` | `Bool` | null → false |
| `copy` | 复制 | 无 | `OsProfile` | 无 |

---

## 8. 使用的技术

- 不可变快照；
- 能力列表去重；
- 与 `CoreProfile` 组合；
- 字符串描述。

---

## 9. 需要的支撑

- 语言：class、final 字段、List、String、Bool；
- 运行时：无；
- 接口：`OsInfo`、`OsCapability`、`osCapabilityName`。

---

## 10. 依赖的特性/接口/类

`OsInfo`、`OsCapability`、`osCapabilityName`、`CoreProfile`（组合，不继承）。

---

## 11. 所有权与并发

不可变；可跨任务共享；`capabilities` 返回副本；无资源；无取消点。
相等：引用身份；值比较用 `equals`；不推荐作为 `Map` 键。

---

## 12. 示例与反例

正确：

```xnull
OsProfile os = Os.profile()
if os.has(OsCapability.Firewall) && os.has(OsCapability.Container) {
    // 服务器路径
}
```

反例：用 `OsProfile` 替代 `CoreProfile`；能力存在就假设有权限；运行时修改共享画像；
把 `Linux` 字符串当能力。

---

## 13. 测试/场景义务

四类画像（桌面/服务器/移动/WASM）；能力去重；has/missing；with/without；name 校验；
copy/equals；与 `CoreProfile` 组合；未知能力。

---

## 14. XNull 伪代码

```xnull
class OsProfile {
    final String _name
    final OsInfo _info
    final List<OsCapability> _capabilities

    OsProfile(String name, OsInfo info, List<OsCapability> capabilities) {
        if name == null || name == "" { throw "OsProfile: empty name" }
        if info == null || capabilities == null {
            throw "OsProfile: null field"
        }
        _name = name
        _info = info
        _capabilities = []
        Int index = 0
        while index < capabilities.length() {
            OsCapability capability = capabilities.get(index)
            if capability == null { throw "OsProfile: null capability" }
            if !self.has(capability) {
                _capabilities.push(capability)
            }
            index = index + 1
        }
    }

    String name() { return _name }
    OsInfo info() { return _info }
    OsKind kind() { return _info.kind() }
    OsFamily family() { return _info.family() }

    List<OsCapability> capabilities() {
        List<OsCapability> result = []
        Int index = 0
        while index < _capabilities.length() {
            result.push(_capabilities.get(index))
            index = index + 1
        }
        return result
    }

    Bool has(OsCapability capability) {
        if capability == null { throw "OsProfile.has: null capability" }
        Int index = 0
        while index < _capabilities.length() {
            if _capabilities.get(index) == capability { return true }
            index = index + 1
        }
        return false
    }

    List<OsCapability> missing(List<OsCapability> required) {
        if required == null { throw "OsProfile.missing: null list" }
        List<OsCapability> result = []
        Int index = 0
        while index < required.length() {
            OsCapability capability = required.get(index)
            if !self.has(capability) {
                result.push(capability)
            }
            index = index + 1
        }
        return result
    }

    OsProfile withCapability(OsCapability capability) {
        if capability == null { throw "OsProfile.withCapability: null" }
        List<OsCapability> next = self.capabilities()
        if !self.has(capability) { next.push(capability) }
        return new OsProfile(_name, _info, next)
    }

    OsProfile withoutCapability(OsCapability capability) {
        if capability == null { throw "OsProfile.withoutCapability: null" }
        List<OsCapability> next = []
        Int index = 0
        while index < _capabilities.length() {
            if _capabilities.get(index) != capability {
                next.push(_capabilities.get(index))
            }
            index = index + 1
        }
        return new OsProfile(_name, _info, next)
    }

    OsProfile withName(String value) {
        if value == null || value == "" { throw "OsProfile.withName: empty" }
        return new OsProfile(value, _info, self.capabilities())
    }

    String describe() {
        return "os " + _name
            + " kind=" + osKindName(_info.kind())
            + " caps=" + str(_capabilities.length())
    }

    Bool equals(OsProfile other) {
        if other == null { return false }
        if _name != other.name() { return false }
        if !_info.equals(other.info()) { return false }
        List<OsCapability> values = other.capabilities()
        if _capabilities.length() != values.length() { return false }
        Int index = 0
        while index < values.length() {
            if !self.has(values.get(index)) { return false }
            index = index + 1
        }
        return true
    }

    OsProfile copy() {
        return new OsProfile(_name, _info.copy(), self.capabilities())
    }
}
```
