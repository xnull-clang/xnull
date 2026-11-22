# `xdk.serial` 串口

| 项 | 值 |
| --- | --- |
| 包 | `xdk.serial` |
| 层 |  |
| 依赖 | `xdk.core`；设备清单边界与 `xdk.os.hardware` 对齐 |
| 能力 | 串口枚举、打开、读、写、刷新、关闭 |
| 稳定性 | `preview` |

---

## 1. 定位

串口设备控制面：枚举可见端口、按路径打开、读写字节、刷新输出、关闭句柄。

只做：

- 端口枚举快照（路径/名称/可选厂商与产品编号）；
- 串口参数（波特率/数据位/校验/停止位/超时）；
- 打开、读取、写入、刷新、关闭；
- 不可用/无权限/取消的显式失败。

不做：

- PTY/虚拟串口创建；
- termios 原始标志、控制线（DTR/RTS/CTS/DSR）、流控；
- 驱动安装、厂商 SDK、裸 ioctl；
- 热插拔事件、自动重连、全局端口注册表；
- 串口协议解析（Modbus/GPS/NMEA 等）——归 ecosystem。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 不透明句柄 | `SerialPort` 只暴露 `Long` 句柄；不暴露 fd/指针/驱动句柄 |
| 可失败 | 打开/枚举/读写/刷新返回 `Result`；无权限 `PermissionDenied`；平台无能力 `Unsupported` |
| 可取消 | 可阻塞方法首参 `Context`；取消 `Cancelled` |
| 显式超时 | 读/写超时为 `Long` 毫秒；0 = 非阻塞；正数 = 有界等待 |
| 幂等关闭 | `close()` 可重复调用；关闭后操作 `Unavailable` |
| 快照枚举 | `Serial.ports` 不自动刷新；热插拔需重新枚举 |
| 不做驱动 | 不绑定厂商 SDK、不写驱动、不暴露裸设备控制 |
| 平台透明 | 公开 API 不出现 termios/DCB/IOKit 等平台类型 |

---

## 3. 类型索引

| 类型 | 种类 | 文件 |
| --- | --- | --- |
| `SerialParity` | enum | [`SerialParity.md`](SerialParity.md) |
| `SerialStopBits` | enum | [`SerialStopBits.md`](SerialStopBits.md) |
| `SerialOptions` | class | [`SerialOptions.md`](SerialOptions.md) |
| `SerialPortInfo` | class | [`SerialPortInfo.md`](SerialPortInfo.md) |
| `SerialPort` | class | [`SerialPort.md`](SerialPort.md) |
| `Serial` | class（静态入口） | [`Serial.md`](Serial.md) |

---

## 4. 跨类型规则

- `SerialOptions` 只校验本地域：`baudRate>0`、`dataBits 5..8`、枚举非 null、超时非负；硬件组合由 `SerialPort.open` 判定。
- `SerialPortInfo` 没有 `isOpen`；枚举成功不代表能打开；`vendorId`/`productId` 缺失用 null，不用 0 代替。
- `SerialPort.open` 不要求端口出现在 `Serial.ports` 结果中；不承诺独占；OS 报告冲突时返回 `Busy`。
- `read` 返回 `0..buffer.length()`；读超时是 `Ok(0)`，不是 `Timeout`。
- `write` 返回实际写入数；部分写合法；无进展超时返回 `Timeout`，有部分进展则 `Ok(count)`。
- `flush` 使用写超时；超时 `Timeout`；不改变打开状态。
- `close` 幂等；关闭后 `read`/`write`/`flush` 返回 `Unavailable`；`path`/`isOpen` 仍可读。
- 所有 `Bytes` 由调用方拥有；方法不保留引用；空 buffer 不触发原生调用。
- 无控制线/流控/PTY/termios 原始设置；这些是 X。

---

## 5. 场景

### S1：嵌入式设备诊断

`Serial.ports` 枚举 `/dev/ttyUSB*`/`COM*`；按路径与参数打开；短超时读取设备响应；关闭。用于传感器/开发板，不实现协议。

### S2：串口控制台

打开设备，`read` 轮询/有界等待，`write` 命令；不创建 PTY，不修改 termios 原始模式。

### S3：枚举/资产清单

记录路径、名称、可选厂商/产品编号；用于日志/兼容性检查；不把枚举结果当实时状态。

### S4：失败/取消/权限

平台无串口 → `Unsupported`；路径不存在 → `NotFound`；无权限 → `PermissionDenied`；被占用 → `Busy`；`Context` 取消 → `Cancelled`；关闭后 → `Unavailable`。

### S5：部分写/超时

`write` 返回小于 buffer 长度的计数；调用方移动剩余区间重试；无进展超时返回 `Timeout`；读超时返回 0 并继续轮询。

---

## 6. 缺口

| 项 | 决策 |
| --- | --- |
| PTY/虚拟串口 | X |
| termios/DCB 原始设置 | X |
| 控制线 DTR/RTS/CTS/DSR | X |
| 硬件/软件流控 | X |
| 独占锁/端口抢占 | X |
| 热插拔/端口事件 | X |
| 自动重连/守护 | ecosystem |
| 驱动/厂商 SDK/裸 ioctl | ecosystem/FFI |
| 串口协议解析 | ecosystem |
| 端口枚举的序列号/拓扑 | 默认不导出 |

---

## 7. 验收谓词

- 6 个类型文件与索引一一对应；
- 每个类型 14 段；
- 所有相对链接可达；
- `check_doc_naming.py` PASS；
- 无 PTY/termios/控制线/驱动 API；
- 可阻塞方法首参 `Context`；
- `SerialPort` 使用不透明 `Long`，`close` 幂等；
- 无权限/不支持/取消/超时/部分写均有明确通道。

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | `@SerialBinding` |
| 本包消费 | `@Value`、`@Builder`、`@Packed`、`@Align` |
| 处理器 | SerialAnnotationProcessor（Validate/Generate） |
| 生成物 | 串口配置、端口信息、布局校验 |
| 状态 | 领域注解 planned；A8 派生 implemented（含限制）；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 端口配置字段/参数 | `@SerialBinding` | 端口绑定 |
| `SerialOptions`/`SerialPortInfo` | `@Value`/`@Builder` | 值语义/选项 |

### 声明

```x
@Target(Field, Parameter)
@Retention(Source)
@annotation SerialBinding {
    final String path
}
```

声明文件：每个注解单独一个 PascalCase 文件；处理器为构建期类型；生成代码在 `<package>/generated/`。

### 使用

```x
class ConsoleConfig {
    @SerialBinding("/dev/ttyUSB0") String port
}
```

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
