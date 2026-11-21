# `BiosInfo`

| 项 | 值 |
| --- | --- |
| 类型 | `class BiosInfo` |
| 包 | `xdk.os.hardware` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

BIOS/UEFI 只读快照：厂商、版本、发布日期、是否 UEFI。

不做：固件升级、Setup 变量、Secure Boot 密钥、SMBIOS 原始表。

---

## 2. 设计逻辑

- 不可变快照；由 `HardwareInventory.bios()` 返回。
- `releaseDate` 是 ISO 日期字符串；未知为空串。
- `isUefi` 表示当前引导模式；不表示 Secure Boot 状态。
- 字段可为空串；未知不 panic。
- 值语义；可复制/比较。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_vendor` | `String` | final | 可为空 |
| `_version` | `String` | final | 可为空 |
| `_releaseDate` | `String` | final | ISO 日期/空 |
| `_isUefi` | `Bool` | final | 是否 UEFI |

不变量：字符串非 null；不可变。

---

## 4. 生命周期

构造后不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `BiosInfo(...)` | 4 个字段 | 字符串非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `vendor` | 厂商 | 无 | `String` | 无 |
| `version` | 版本 | 无 | `String` | 无 |
| `releaseDate` | 发布日期 | 无 | `String` | 无 |
| `isUefi` | 是否 UEFI | 无 | `Bool` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |
| `equals` | 值比较 | `BiosInfo other` | `Bool` | null → false |
| `copy` | 复制 | 无 | `BiosInfo` | 无 |

---

## 8. 使用的技术

- 不可变快照；
- 字符串/布尔；
- 日期字符串。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Bool；
- 运行时/适配器：SMBIOS/UEFI 读取；
- 接口：`HardwareInventory`。

---

## 10. 依赖的特性/接口/类

`HardwareInventory`、`BoardInfo`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。
相等：`equals` 字段比较；`==` 仍是引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：诊断显示 BIOS 版本/日期/UEFI。  
反例：用 `isUefi` 推断 Secure Boot；导出固件密钥；假设日期格式固定。

---

## 13. 测试/场景义务

UEFI/Legacy；空字段；日期格式；equals/copy；未知平台。

---

## 14. XNull 伪代码

```xnull
class BiosInfo {
    final String _vendor
    final String _version
    final String _releaseDate
    final Bool _isUefi

    BiosInfo(String vendor, String version, String releaseDate, Bool isUefi) {
        if vendor == null || version == null || releaseDate == null {
            throw "BiosInfo: null string"
        }
        _vendor = vendor
        _version = version
        _releaseDate = releaseDate
        _isUefi = isUefi
    }

    String vendor() { return _vendor }
    String version() { return _version }
    String releaseDate() { return _releaseDate }
    Bool isUefi() { return _isUefi }

    String describe() {
        return _vendor + " " + _version
            + " date=" + _releaseDate
            + " uefi=" + str(_isUefi)
    }

    Bool equals(BiosInfo other) {
        if other == null { return false }
        return _vendor == other.vendor()
            && _version == other.version()
            && _releaseDate == other.releaseDate()
            && _isUefi == other.isUefi()
    }

    BiosInfo copy() {
        return new BiosInfo(_vendor, _version, _releaseDate, _isUefi)
    }
}
```
