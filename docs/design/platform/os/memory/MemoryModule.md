# `MemoryModule`

| 项 | 值 |
| --- | --- |
| 类型 | `class MemoryModule` |
| 包 | `xdk.os.memory` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

一条物理内存条（DIMM）的只读快照：槽位、容量、类型、频率、厂商、型号。

不做：内存分配、ECC 错误、SPD 原始字节、序列号、热插拔。

---

## 2. 设计逻辑

- 不可变快照；由 `PhysicalMemory.modules()` 返回。
- `slot` 是主板槽位名（`DIMM_A1` 等）；未知为空串。
- `sizeBytes` 用 `Long`；`speedMhz` 用 `Int`。
- `kind` 是 `DDR4`/`DDR5`/`LPDDR5` 等字符串；未知为空串。
- `manufacturer`/`partNumber` 可为空；不提供序列号。
- 容器/虚拟化下可能为空列表。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_slot` | `String` | final | 可为空 |
| `_sizeBytes` | `Long` | final | ≥0 |
| `_kind` | `String` | final | 可为空 |
| `_speedMhz` | `Int` | final | ≥0 |
| `_manufacturer` | `String` | final | 可为空 |
| `_partNumber` | `String` | final | 可为空 |

不变量：字符串非 null；size/speed ≥0；不可变。

---

## 4. 生命周期

构造后不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `MemoryModule(...)` | 6 个字段 | 字符串非 null；size/speed ≥0 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `slot` | 槽位 | 无 | `String` | 无 |
| `sizeBytes` | 容量 | 无 | `Long` | 无 |
| `kind` | 类型 | 无 | `String` | 无 |
| `speedMhz` | 频率 | 无 | `Int` | 无 |
| `manufacturer` | 厂商 | 无 | `String` | 无 |
| `partNumber` | 型号 | 无 | `String` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |
| `equals` | 值比较 | `MemoryModule other` | `Bool` | null → false |
| `copy` | 复制 | 无 | `MemoryModule` | 无 |

---

## 8. 使用的技术

- 不可变快照；
- 字符串/整数；
- 脱敏策略。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Long、Int、Bool；
- 运行时/适配器：SMBIOS/DMI 读取；
- 接口：`PhysicalMemory`。

---

## 10. 依赖的特性/接口/类

`PhysicalMemory`、`NumaNode`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。
相等：`equals` 字段比较；`==` 仍是引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：显示槽位/容量/类型；日志中厂商/型号可选脱敏。  
反例：导出序列号；假设槽位存在；把频率当性能保证；容器内假设有 DIMM。

---

## 13. 测试/场景义务

字段非负；空字符串；未知类型；多槽位；equals/copy；脱敏；容器空列表。

---

## 14. XNull 伪代码

```xnull
class MemoryModule {
    final String _slot
    final Long _sizeBytes
    final String _kind
    final Int _speedMhz
    final String _manufacturer
    final String _partNumber

    MemoryModule(String slot, Long sizeBytes, String kind, Int speedMhz,
                 String manufacturer, String partNumber) {
        if slot == null || kind == null || manufacturer == null
            || partNumber == null {
            throw "MemoryModule: null string"
        }
        if sizeBytes < 0 || speedMhz < 0 {
            throw "MemoryModule: negative field"
        }
        _slot = slot
        _sizeBytes = sizeBytes
        _kind = kind
        _speedMhz = speedMhz
        _manufacturer = manufacturer
        _partNumber = partNumber
    }

    String slot() { return _slot }
    Long sizeBytes() { return _sizeBytes }
    String kind() { return _kind }
    Int speedMhz() { return _speedMhz }
    String manufacturer() { return _manufacturer }
    String partNumber() { return _partNumber }

    String describe() {
        return "dimm " + _slot
            + " size=" + str(_sizeBytes)
            + " kind=" + _kind
            + " speed=" + str(_speedMhz)
    }

    Bool equals(MemoryModule other) {
        if other == null { return false }
        return _slot == other.slot()
            && _sizeBytes == other.sizeBytes()
            && _kind == other.kind()
            && _speedMhz == other.speedMhz()
            && _manufacturer == other.manufacturer()
            && _partNumber == other.partNumber()
    }

    MemoryModule copy() {
        return new MemoryModule(_slot, _sizeBytes, _kind, _speedMhz,
            _manufacturer, _partNumber)
    }
}
```
