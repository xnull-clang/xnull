# `UsbDevice`

| 项 | 值 |
| --- | --- |
| 类型 | `class UsbDevice` |
| 包 | `xdk.os.hardware` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

USB 设备只读快照：总线号、设备地址、厂商/产品 ID、厂商/产品名、连接状态。

不做：描述符原始字节、序列号、端点/传输、驱动绑定、热插拔事件。

---

## 2. 设计逻辑

- 不可变快照；由 `HardwareInventory.usbDevices()` 返回。
- `busNumber`/`deviceAddress` 是 OS 枚举值；未知为 0。
- `vendorId`/`productId` 是 16 位 ID。
- `manufacturer`/`product` 可为空；不提供序列号。
- `isConnected` 表示当前连接。
- 不提供写操作/端点 I/O。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_busNumber` | `Int` | final | ≥0 |
| `_deviceAddress` | `Int` | final | ≥0 |
| `_vendorId` | `Int` | final | 0..65535 |
| `_productId` | `Int` | final | 0..65535 |
| `_manufacturer` | `String` | final | 可为空 |
| `_product` | `String` | final | 可为空 |
| `_isConnected` | `Bool` | final | 是否连接 |

不变量：数值 ≥0/在 ID 范围；字符串非 null；不可变。

---

## 4. 生命周期

构造后不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `UsbDevice(...)` | 7 个字段 | bus/address ≥0；ID 0..65535；字符串非 null | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `busNumber` | 总线号 | 无 | `Int` | 无 |
| `deviceAddress` | 设备地址 | 无 | `Int` | 无 |
| `vendorId` | 厂商 ID | 无 | `Int` | 无 |
| `productId` | 产品 ID | 无 | `Int` | 无 |
| `manufacturer` | 厂商 | 无 | `String` | 无 |
| `product` | 产品名 | 无 | `String` | 无 |
| `isConnected` | 是否连接 | 无 | `Bool` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |
| `equals` | 值比较 | `UsbDevice other` | `Bool` | null → false |
| `copy` | 复制 | 无 | `UsbDevice` | 无 |

---

## 8. 使用的技术

- 不可变快照；
- USB 枚举；
- 字符串描述。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Int、Bool；
- 运行时/适配器：sysfs/SetupAPI/IOKit；
- 接口：`HardwareInventory`。

---

## 10. 依赖的特性/接口/类

`HardwareInventory`、`PciDevice`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。
相等：`equals` 字段比较；`==` 仍是引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：按 vendor/product ID 识别设备；显示连接状态。  
反例：导出序列号；用 bus/address 做持久 ID；假设设备一直连接。

---

## 13. 测试/场景义务

ID 边界；空厂商/产品；连接/断开；equals/copy；多设备；容器可见性。

---

## 14. XNull 伪代码

```xnull
class UsbDevice {
    final Int _busNumber
    final Int _deviceAddress
    final Int _vendorId
    final Int _productId
    final String _manufacturer
    final String _product
    final Bool _isConnected

    UsbDevice(Int busNumber, Int deviceAddress, Int vendorId, Int productId,
              String manufacturer, String product, Bool isConnected) {
        if manufacturer == null || product == null {
            throw "UsbDevice: null string"
        }
        if busNumber < 0 || deviceAddress < 0 {
            throw "UsbDevice: negative address"
        }
        if vendorId < 0 || vendorId > 65535 || productId < 0 || productId > 65535 {
            throw "UsbDevice: invalid id"
        }
        _busNumber = busNumber
        _deviceAddress = deviceAddress
        _vendorId = vendorId
        _productId = productId
        _manufacturer = manufacturer
        _product = product
        _isConnected = isConnected
    }

    Int busNumber() { return _busNumber }
    Int deviceAddress() { return _deviceAddress }
    Int vendorId() { return _vendorId }
    Int productId() { return _productId }
    String manufacturer() { return _manufacturer }
    String product() { return _product }
    Bool isConnected() { return _isConnected }

    String describe() {
        return "usb " + str(_busNumber) + ":" + str(_deviceAddress)
            + " " + str(_vendorId) + ":" + str(_productId)
            + " " + _manufacturer + " " + _product
    }

    Bool equals(UsbDevice other) {
        if other == null { return false }
        return _busNumber == other.busNumber()
            && _deviceAddress == other.deviceAddress()
            && _vendorId == other.vendorId()
            && _productId == other.productId()
            && _manufacturer == other.manufacturer()
            && _product == other.product()
            && _isConnected == other.isConnected()
    }

    UsbDevice copy() {
        return new UsbDevice(_busNumber, _deviceAddress, _vendorId, _productId,
            _manufacturer, _product, _isConnected)
    }
}
```
