# `BoardInfo`

| 项 | 值 |
| --- | --- |
| 类型 | `class BoardInfo` |
| 包 | `xdk.os.hardware` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

主板只读快照：厂商、产品名、版本。

不做：序列号、资产标签、BIOS 设置、固件升级、SMBIOS 原始表。

---

## 2. 设计逻辑

- 不可变快照；由 `HardwareInventory.board()` 返回。
- 字段可为空串；未知不 panic。
- 不提供序列号/资产标签，避免隐私与安全风险。
- 值语义；可复制/比较。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_manufacturer` | `String` | final | 可为空 |
| `_product` | `String` | final | 可为空 |
| `_version` | `String` | final | 可为空 |

不变量：字符串非 null；不可变。

---

## 4. 生命周期

构造后不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `BoardInfo(...)` | 3 个字段 | 字符串非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `manufacturer` | 厂商 | 无 | `String` | 无 |
| `product` | 产品名 | 无 | `String` | 无 |
| `version` | 版本 | 无 | `String` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |
| `equals` | 值比较 | `BoardInfo other` | `Bool` | null → false |
| `copy` | 复制 | 无 | `BoardInfo` | 无 |

---

## 8. 使用的技术

- 不可变快照；
- 字符串描述。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Bool；
- 运行时/适配器：SMBIOS/DMI 读取；
- 接口：`HardwareInventory`。

---

## 10. 依赖的特性/接口/类

`HardwareInventory`、`BiosInfo`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。
相等：`equals` 字段比较；`==` 仍是引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：启动日志显示厂商/产品/版本。  
反例：导出序列号；假设字段非空；用主板型号做能力判断。

---

## 13. 测试/场景义务

字段空/非空；equals/copy；脱敏；未知平台。

---

## 14. XNull 伪代码

```xnull
class BoardInfo {
    final String _manufacturer
    final String _product
    final String _version

    BoardInfo(String manufacturer, String product, String version) {
        if manufacturer == null || product == null || version == null {
            throw "BoardInfo: null string"
        }
        _manufacturer = manufacturer
        _product = product
        _version = version
    }

    String manufacturer() { return _manufacturer }
    String product() { return _product }
    String version() { return _version }

    String describe() {
        return _manufacturer + " " + _product + " " + _version
    }

    Bool equals(BoardInfo other) {
        if other == null { return false }
        return _manufacturer == other.manufacturer()
            && _product == other.product()
            && _version == other.version()
    }

    BoardInfo copy() {
        return new BoardInfo(_manufacturer, _product, _version)
    }
}
```
