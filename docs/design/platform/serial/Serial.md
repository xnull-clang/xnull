# `Serial`

| 项 | 值 |
| --- | --- |
| 类型 | `class Serial`（静态入口） |
| 包 | `xdk.serial` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Error`、`SerialPortInfo`、`SerialPort`、`SerialOptions` |

---

## 1. 定位

串口静态入口：枚举当前可见串口、按路径打开串口。

不做：全局端口注册表、自动重连、PTY、控制线、驱动/厂商 SDK、权限提升。

---

## 2. 设计逻辑

- 所有方法静态；无实例字段；无全局可变状态。
- `ports(context)` 每次重新枚举；返回新列表；列表为空表示平台支持但当前无端口。
- 平台不支持串口时返回 `Unsupported`，不返回空列表、不模拟端口。
- `open(context, devicePath, options)` 是 `SerialPort.open` 的便捷转发；不预先枚举，不缓存句柄。
- 枚举可能受权限/容器限制；失败返回 `PermissionDenied`/`Unsupported`，不重试、不提权。
- `SerialPortInfo` 无打开状态；端口可能被其它进程占用；枚举成功不代表 `open` 成功。

---

## 3. 表示与不变量

无实例字段。

不变量：静态方法不读写全局状态；`ports` 返回新列表；`open` 返回调用方拥有的独立句柄。

---

## 4. 生命周期

静态类；无实例；无 close；无全局初始化/关闭；端口句柄由调用方关闭。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Serial()` | 无 | 私有；禁止实例化 | 无 |

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `ports` | 枚举可见串口 | `Context context` | `Result<List<SerialPortInfo>, Error>` | `Unsupported`/`PermissionDenied`/`Cancelled`/`Io` |
| `open` | 打开串口 | `Context context, String devicePath, SerialOptions options` | `Result<SerialPort, Error>` | `InvalidArgument`/`NotFound`/`PermissionDenied`/`Busy`/`Unsupported`/`Cancelled`/`Io` |

说明：

- `ports`：`context == null` panic；成功返回新列表，元素是不可变 `SerialPortInfo`；空列表 = 支持但无端口；`Unsupported` = 平台无串口能力。
- `open`：`context`/`devicePath`/`options` 为 null panic；空路径由 `SerialPort.open` 返回 `InvalidArgument`；其余失败语义与 `SerialPort.open` 一致。
- 不提供 `defaultPort()`/自动选择；调用方按 `SerialPortInfo.path()` 选择。
- 不提供 `isSupported()`；用 `ports` 的 `Unsupported` 判断。
- 不提供端口事件/热插拔；重新 `ports` 获取快照。

---

## 8. 使用的技术

- 静态入口；
- 平台枚举适配器；
- `Context`/`Result`；
- 列表快照；
- 句柄转发。

---

## 9. 需要的支撑

- 语言：class、static、List、String、Result；
- 运行时/适配器：`serialPortsRaw(Context context) -> Result<List<SerialPortInfo>, Error>`；
- 接口：`Context`、`Error`、`SerialPort`、`SerialPortInfo`、`SerialOptions`。

---

## 10. 依赖的特性/接口/类

`SerialPort`、`SerialPortInfo`、`SerialOptions`、`SerialParity`、`SerialStopBits`、`Context`、`Error`。

---

## 11. 所有权与并发

静态无状态；`ports` 返回调用方拥有的新列表；`open` 返回调用方拥有的新句柄；可并发调用，平台适配器可自行串行化。
无实例；相等不适用。

---

## 12. 示例与反例

正确：

```xnull
Result<List<SerialPortInfo>, Error> found = Serial.ports(context)
if found.isOk() {
    List<SerialPortInfo> ports = found.value()
    if ports.length() > 0 {
        SerialOptions options = new SerialOptions(
            115200, 8, SerialParity.None, SerialStopBits.One, 1000, 1000)
        Result<SerialPort, Error> opened = Serial.open(
            context, ports.get(0).path(), options)
    }
}
```

反例：把空列表当 `Unsupported`；在 `Unsupported` 平台上模拟端口；假设枚举后端口仍可用；用 `Serial` 保存全局打开的端口；在 `ports` 失败后无限重试；不关闭 `Serial.open` 返回的句柄。

---

## 13. 测试/场景义务

无端口/多端口/无权限/平台不支持/取消；列表快照独立性；路径空/错误；`open` 转发与失败映射；并发枚举；容器可见性；枚举后端口被占用/消失；与 `SerialPortInfo`/`SerialOptions` 组合。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class Serial {
    private Serial() {}

    static Result<List<SerialPortInfo>, Error> ports(Context context) {
        if context == null {
            throw "Serial.ports: null context"
        }
        Result<List<SerialPortInfo>, Error> found = serialPortsRaw(context)
        if found.isErr() { return Err(found.error()) }
        return Ok(found.value().copy())
    }

    static Result<SerialPort, Error> open(Context context, String devicePath,
                                          SerialOptions options) {
        if context == null || devicePath == null || options == null {
            throw "Serial.open: null argument"
        }
        return SerialPort.open(context, devicePath, options)
    }
}
```
