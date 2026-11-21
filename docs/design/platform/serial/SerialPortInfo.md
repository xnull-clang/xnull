# `SerialPortInfo`

| 项 | 值 |
| --- | --- |
| 类型 | `class SerialPortInfo` |
| 包 | `xdk.serial` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

串口枚举结果的只读快照：设备路径、显示名、可选厂商/产品编号。

不做：打开状态（没有 `isOpen`）、读写、控制线、驱动信息、热插拔事件、权限提升。

---

## 2. 设计逻辑

- 四个不可变字段：`_path`、`_name`、`_vendorId`、`_productId`。
- `path` 是 OS 设备路径（如 `/dev/ttyUSB0`、`COM3`），非空；仅在本次枚举上下文中稳定。
- `name` 是显示名，可为空串；不保证唯一。
- `vendorId`/`productId` 是可选元数据；为 null 表示未知/不适用；存在时范围 `0..65535`。
- 枚举结果不代表端口可打开，也不代表未被占用；没有 `isOpen` 字段。
- 不可变；`equals` 比较全部字段；可作 `Map`/`Set` 键。
- 无资源；无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_path` | `String` | final | 非空；设备路径 |
| `_name` | `String` | final | 非 null；可为空 |
| `_vendorId` | `Int?` | final | null 或 `0..65535` |
| `_productId` | `Int?` | final | null 或 `0..65535` |

不变量：`path` 非空；`name` 非 null；编号在范围内或 null；不可变；不携带打开状态。

---

## 4. 生命周期

构造后不可变；无 close；可共享；枚举后是快照，端口变化需重新 `Serial.ports`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `SerialPortInfo(String path, String name, Int? vendorId, Int? productId)` | 四个字段 | path 非空；name 非 null；编号 null 或 `0..65535` | null/空 path/编号越界 → panic |

主要供枚举适配器/测试构造；业务代码通过 `Serial.ports(context)` 获取。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `path` | 设备路径 | 无 | `String` | 无 |
| `name` | 显示名 | 无 | `String` | 无 |
| `vendorId` | 厂商编号 | 无 | `Int?` | 无 |
| `productId` | 产品编号 | 无 | `Int?` | 无 |
| `equals` | 值比较 | `SerialPortInfo other` | `Bool` | null → false |
| `describe` | 单行摘要 | 无 | `String` | 无 |

说明：

- `path`/`name`/编号为纯读取；编号 null 表示未知，不用 `0` 代替缺失。
- `equals` 比较路径、名称与两个可选编号；不做路径规范化。
- `describe` 用于日志；可选编号缺失显示为 `unknown`。
- 不提供 `isOpen`；打开状态只在 `SerialPort.isOpen()`。
- 不提供 `devicePath` 别名；统一使用 `path`。

---

## 8. 使用的技术

- 不可变快照；
- 可选编号；
- 字段相等；
- 路径/名称字符串。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Int?、Bool；
- 运行时：`str(Int)`；
- 接口：`Serial`、`SerialPort`。

---

## 10. 依赖的特性/接口/类

`Serial`、`SerialPort`、`SerialOptions`、`xdk.os.hardware`（设备清单边界，不复制其类型）。

---

## 11. 所有权与并发

不可变；无资源；可共享；无取消点。
`equals` 值语义；`==` 仍是引用身份；可作 `Map`/`Set` 键。

---

## 12. 示例与反例

正确：

```xnull
Result<List<SerialPortInfo>, Error> found = Serial.ports(context)
if found.isOk() {
    List<SerialPortInfo> ports = found.value()
    SerialPortInfo first = ports.get(0)
    String devicePath = first.path()
}
```

反例：用 `SerialPortInfo` 判断端口是否打开；把 `vendorId = 0` 当“未知”；依赖路径跨重启不变；把显示名当唯一键；假设枚举列表中的端口一定能打开。

---

## 13. 测试/场景义务

空名称；可选编号 null/0/65535/越界；path 空/null panic；`equals` 可选编号组合；`describe` 缺失编号；列表快照独立性；枚举后端口消失/被占用；与 `SerialPort.open` 组合。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class SerialPortInfo {
    final String _path
    final String _name
    final Int? _vendorId
    final Int? _productId

    SerialPortInfo(String path, String name, Int? vendorId, Int? productId) {
        if path == null || path.trim() == "" {
            throw "SerialPortInfo: empty path"
        }
        if name == null {
            throw "SerialPortInfo: null name"
        }
        if vendorId != null {
            Int vendorValue = vendorId as Int
            if vendorValue < 0 || vendorValue > 65535 {
                throw "SerialPortInfo: vendor id out of range"
            }
        }
        if productId != null {
            Int productValue = productId as Int
            if productValue < 0 || productValue > 65535 {
                throw "SerialPortInfo: product id out of range"
            }
        }
        _path = path
        _name = name
        _vendorId = vendorId
        _productId = productId
    }

    String path() { return _path }
    String name() { return _name }
    Int? vendorId() { return _vendorId }
    Int? productId() { return _productId }

    Bool equals(SerialPortInfo other) {
        if other == null { return false }
        if _path != other.path() || _name != other.name() { return false }
        if _vendorId == null {
            if other.vendorId() != null { return false }
        } else {
            if other.vendorId() == null { return false }
            if (_vendorId as Int) != (other.vendorId() as Int) {
                return false
            }
        }
        if _productId == null {
            if other.productId() != null { return false }
        } else {
            if other.productId() == null { return false }
            if (_productId as Int) != (other.productId() as Int) {
                return false
            }
        }
        return true
    }

    String describe() {
        String vendorText = "unknown"
        if _vendorId != null { vendorText = str(_vendorId as Int) }
        String productText = "unknown"
        if _productId != null { productText = str(_productId as Int) }
        return "serial port path=" + _path
            + " name=" + _name
            + " vendorId=" + vendorText
            + " productId=" + productText
    }
}
```
