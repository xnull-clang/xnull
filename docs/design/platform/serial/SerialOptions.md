# `SerialOptions`

| 项 | 值 |
| --- | --- |
| 类型 | `class SerialOptions` |
| 包 | `xdk.serial` |
| 稳定性 | `preview` |
| 依赖 | `SerialParity`、`SerialStopBits` |

---

## 1. 定位

串口打开参数值对象：波特率、数据位、校验位、停止位、读/写超时。

不做：流控、控制线、termios 原始标志、驱动参数、端口路径。

---

## 2. 设计逻辑

- 六个不可变字段：`_baudRate`、`_dataBits`、`_parity`、`_stopBits`、`_readTimeoutMillis`、`_writeTimeoutMillis`。
- 本地校验：`baudRate > 0`；`dataBits` 为 `5..8`；`parity`/`stopBits` 非 null；超时 `>= 0`。
- 超时单位毫秒，类型 `Long`；`0` 表示非阻塞/立即返回，正数表示有界等待；不支持负数或无限哨兵。
- 硬件组合（如 `OnePointFive` 与某些数据位、`Mark`/`Space` 校验）不在本类判定；`SerialPort.open` 失败时返回 `InvalidArgument`/`Unsupported`。
- 不可变；`equals` 比较全部字段；可作 `Map`/`Set` 键。
- 无资源；无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_baudRate` | `Int` | final | `>0` |
| `_dataBits` | `Int` | final | `5..8` |
| `_parity` | `SerialParity` | final | 非 null |
| `_stopBits` | `SerialStopBits` | final | 非 null |
| `_readTimeoutMillis` | `Long` | final | `>=0`；0 = 非阻塞 |
| `_writeTimeoutMillis` | `Long` | final | `>=0`；0 = 非阻塞 |

不变量：字段范围合法；枚举非 null；超时非负；不可变；`equals` 与六个字段一一对应。

---

## 4. 生命周期

构造后不可变；无 close；可共享；无需刷新。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `SerialOptions(Int baudRate, Int dataBits, SerialParity parity, SerialStopBits stopBits, Long readTimeoutMillis, Long writeTimeoutMillis)` | 六个字段 | baudRate>0；dataBits 5..8；枚举非 null；超时≥0 | null/越界/负超时 → panic |

构造 panic 表示调用方违反合同；来自外部配置的值应先校验再构造。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `baudRate` | 波特率 | 无 | `Int` | 无 |
| `dataBits` | 数据位 | 无 | `Int` | 无 |
| `parity` | 校验位 | 无 | `SerialParity` | 无 |
| `stopBits` | 停止位 | 无 | `SerialStopBits` | 无 |
| `readTimeoutMillis` | 读超时 | 无 | `Long` | 无 |
| `writeTimeoutMillis` | 写超时 | 无 | `Long` | 无 |
| `equals` | 值比较 | `SerialOptions other` | `Bool` | null → false |
| `describe` | 单行摘要 | 无 | `String` | 无 |

说明：

- 所有读取方法纯读取；返回不可变枚举/值。
- `readTimeoutMillis`/`writeTimeoutMillis` 的语义由 `SerialPort` 使用：0 = 非阻塞；正数 = 最长等待毫秒数。
- `equals` 比较全部六个字段；不做波特率容差。
- `describe` 用于日志；包含稳定枚举名，不保证可解析。
- 不提供 `copy`/`with*`；需要新参数时构造新对象。

---

## 8. 使用的技术

- 不可变配置对象；
- 范围校验；
- 毫秒超时；
- 字段相等；
- 枚举名称映射。

---

## 9. 需要的支撑

- 语言：class、final 字段、Int、Long、Bool、String；
- 运行时：`serialParityName`、`serialStopBitsName`、`str`；
- 接口：`SerialParity`、`SerialStopBits`、`SerialPort`。

---

## 10. 依赖的特性/接口/类

`SerialParity`、`SerialStopBits`、`SerialPort`、`SerialPortInfo`。

---

## 11. 所有权与并发

不可变；无资源；可共享；无取消点。
`equals` 值语义；`==` 仍是引用身份；可作 `Map`/`Set` 键。

---

## 12. 示例与反例

正确：

```xnull
SerialOptions options = new SerialOptions(
    115200, 8, SerialParity.None, SerialStopBits.One, 1000, 1000)
Result<SerialPort, Error> opened = SerialPort.open(
    context, "/dev/ttyUSB0", options)
```

反例：`baudRate = 0`；`dataBits = 9`；负超时表示无限等待；把 `0` 超时当无限；在 `SerialOptions` 中塞入端口路径或流控；假设 `OnePointFive` 一定可打开。

---

## 13. 测试/场景义务

边界 baudRate `1`/大值；dataBits 5/6/7/8 与 4/9；每个 parity/stopBits 成员；超时 0/正数/负数；null 枚举；`equals`；`describe`；与 `SerialPort.open` 组合；`OnePointFive`/`Mark` 不支持路径。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class SerialOptions {
    final Int _baudRate
    final Int _dataBits
    final SerialParity _parity
    final SerialStopBits _stopBits
    final Long _readTimeoutMillis
    final Long _writeTimeoutMillis

    SerialOptions(Int baudRate, Int dataBits, SerialParity parity,
                  SerialStopBits stopBits, Long readTimeoutMillis,
                  Long writeTimeoutMillis) {
        if baudRate <= 0 {
            throw "SerialOptions: baud rate must be positive"
        }
        if dataBits < 5 || dataBits > 8 {
            throw "SerialOptions: data bits out of range"
        }
        if parity == null || stopBits == null {
            throw "SerialOptions: null parity or stop bits"
        }
        if readTimeoutMillis == null || writeTimeoutMillis == null {
            throw "SerialOptions: null timeout"
        }
        if readTimeoutMillis < 0 || writeTimeoutMillis < 0 {
            throw "SerialOptions: negative timeout"
        }
        _baudRate = baudRate
        _dataBits = dataBits
        _parity = parity
        _stopBits = stopBits
        _readTimeoutMillis = readTimeoutMillis
        _writeTimeoutMillis = writeTimeoutMillis
    }

    Int baudRate() { return _baudRate }
    Int dataBits() { return _dataBits }
    SerialParity parity() { return _parity }
    SerialStopBits stopBits() { return _stopBits }
    Long readTimeoutMillis() { return _readTimeoutMillis }
    Long writeTimeoutMillis() { return _writeTimeoutMillis }

    Bool equals(SerialOptions other) {
        if other == null { return false }
        return _baudRate == other.baudRate()
            && _dataBits == other.dataBits()
            && _parity == other.parity()
            && _stopBits == other.stopBits()
            && _readTimeoutMillis == other.readTimeoutMillis()
            && _writeTimeoutMillis == other.writeTimeoutMillis()
    }

    String describe() {
        return "serial options baud=" + str(_baudRate)
            + " dataBits=" + str(_dataBits)
            + " parity=" + serialParityName(_parity)
            + " stopBits=" + serialStopBitsName(_stopBits)
            + " readTimeoutMillis=" + str(_readTimeoutMillis)
            + " writeTimeoutMillis=" + str(_writeTimeoutMillis)
    }
}
```
