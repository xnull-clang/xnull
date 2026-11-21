# `CameraDevice`

| 项 | 值 |
| --- | --- |
| 类型 | `class CameraDevice` |
| 包 | `xdk.device` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Error`、`DeviceBus`、`CameraFrame` |

---

## 1. 定位

相机描述符与已打开句柄：名称、平台路径、枚举、打开、抓取单帧、关闭、是否打开。

不做：曝光/增益/白平衡/变焦/对焦控制、格式协商、持续流、热插拔监听、录像/编码、音频采集、图像处理、相机权限提升。

---

## 2. 设计逻辑

- 为什么是 class：描述符需要携带 `name`/`path`，打开后又持有不透明句柄与状态；不是 protocol，因为平台差异在适配器内部。
- 不新增 `CameraDeviceInfo`：`list` 直接返回**未打开的描述符**（`_handle = 0`，`_open = false`），`open` 原地打开同一对象；避免“信息类型 + 句柄类型”两套重复模型。
- `list` 每次重新枚举；不缓存、不监听热插拔；顺序由适配器决定，调用方不应依赖。
- `_handle` 是 `Long` 不透明句柄；关闭时为 0，打开时 >0；不暴露 fd、指针、平台设备对象。
- `name`/`path` 在对象生命周期内固定；`close` 后仍可读，可再次 `open`。
- `open` 幂等：已打开返回 `Ok(unit)`，不重复获取句柄；失败保持关闭。
- `capture` 只允许打开状态；每次返回新的 `CameraFrame`，帧归调用方，与相机关闭解耦。
- `close` 幂等；关闭后 `name`/`path`/`bus`/`isOpen`/`close` 可用，`capture` 返回 `Unavailable`；可再次 `open`。
- 打开受 OS 能力/权限/隐私门控：不支持 `Unsupported`，无权限 `PermissionDenied`，被占用 `Busy`，I/O `Io`；可能触发 OS 隐私指示。
- 非线程安全；同一描述符的 `open`/`capture`/`close` 必须串行化。
- 无全局注册表；相机由调用方持有并关闭。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_name` | `String` | final | 非空；人类可读名 |
| `_path` | `String` | final | 非空；平台设备路径/标识 |
| `_handle` | `Long` | 内部 | 0 或 >0；0 表示关闭 |
| `_open` | `Bool` | 内部 | 是否打开 |

不变量：`_name`/`_path` 非空；`_open = false` 时 `_handle = 0`；`_open = true` 时 `_handle > 0`；`list` 返回的描述符全部 `_open = false`；`open` 成功后 `_handle > 0`；`close` 后 `_handle = 0`、`_open = false`；`close` 幂等；关闭后不再调用原生采集/关闭原语。

---

## 4. 生命周期

`list`/构造器创建**关闭的描述符**；`open(context)` 获取句柄并置为打开；`capture(context)` 可重复；`close()` 释放句柄但保留描述符；关闭后可再次 `open`。
无 `deinit` 依赖；GC 不替代 `close`；进程退出由 OS 回收句柄，但设计仍要求显式关闭。
关闭后只允许 `name`/`path`/`bus`/`isOpen`/`close`；`capture` 返回 `Unavailable`；`open` 可重新打开。

---

## 5. 构造契约

| 构造/工厂 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `CameraDevice(String name, String path)` | name、path | 非空 | 非法 → panic；创建关闭描述符 |
| `CameraDevice.list(Context context)` | context | 非 null | null → panic；`PermissionDenied`/`Unsupported`/`Io`/`Cancelled`/`Timeout`；适配器返回非法描述符 → `DataCorrupted` |

构造器主要供适配器/测试使用；业务代码用 `list` 或 `DeviceManager.cameras`。`list` 返回新列表副本；列表元素是未打开描述符，不是已打开句柄。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `list` | 枚举相机描述符 | `Context context` | `Result<List<CameraDevice>, Error>` | null → panic；`PermissionDenied`/`Unsupported`/`Io`/`Cancelled`/`Timeout`/`DataCorrupted` |
| `name` | 人类可读名 | 无 | `String` | 无 |
| `path` | 平台路径/标识 | 无 | `String` | 无 |
| `bus` | 总线分类 | 无 | `DeviceBus` | 无 |
| `isOpen` | 是否打开 | 无 | `Bool` | 无 |
| `open` | 打开相机 | `Context context` | `Result<Unit, Error>` | null → panic；`PermissionDenied`/`Unsupported`/`Busy`/`Io`/`Cancelled`/`Timeout` |
| `capture` | 抓取一帧 | `Context context` | `Result<CameraFrame, Error>` | null → panic；关闭 → `Unavailable`；`Io`/`Cancelled`/`Timeout`/`Unsupported` |
| `close` | 关闭相机 | 无 | `Result<Unit, Error>` | `Io`（诊断） |

说明：

- `list` 是静态工厂；`context == null` panic；每次调用重新枚举；顺序不承诺；列表返回副本；列表元素必须未打开，否则 `DataCorrupted`；不提供热插拔回调。
- `name`/`path`/`bus` 是纯读取；关闭后仍返回原值；`bus` 恒为 `DeviceBus.Camera`。
- `open`：`context == null` panic；已打开返回 `Ok(unit)`；失败保持关闭；成功置 `_open = true`、`_handle > 0`；可阻塞，取消/超时同上。
- `capture`：`context == null` panic；关闭后 `Unavailable`；每次返回新的 `CameraFrame`；帧归调用方，相机关闭后仍可读；适配器返回 null 帧视为 `Internal`；可阻塞，取消 `Cancelled`，超时 `Timeout`。
- `close`：第一次调用保存句柄、置 `_handle = 0`、`_open = false`，再调用原生关闭；后续调用返回 `Ok(unit)`；关闭失败返回 `Io`，状态仍视为关闭；描述符可再次 `open`。
- `isOpen`：不触碰原生句柄；关闭后为 false。
- 不提供 `describe`/`equals`/`copy`；相机是资源/描述符，不是值对象。

---

## 8. 使用的技术

- 描述符 + 不透明 `Long` 句柄；
- 幂等 `open`/`close`；
- `Context`/`Result`；
- 隐私/权限门控；
- 列表复制；
- 原生错误映射。

---

## 9. 需要的支撑

- 语言：class、final 字段、Long、String、Bool、List、Result；
- 运行时/适配器：
  - `cameraListRaw(Context context) -> Result<List<CameraDevice>, Error>`，返回未打开描述符；
  - `cameraOpenRaw(Context context, String path) -> Result<Long, Error>`；
  - `cameraCaptureRaw(Context context, Long handle) -> Result<CameraFrame, Error>`；
  - `cameraCloseRaw(Long handle) -> Result<Unit, Error>`；
- 适配器负责设备枚举、路径映射、隐私/权限检查、帧格式/尺寸、平台错误映射；
- 原生句柄必须 >0；0/负数视为适配器内部错误（`open` 返回 `Internal`，构造器 panic）；
- 接口：`Context`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`、`DeviceBus`、`CameraFrame`、`CameraPixelFormat`。

---

## 10. 依赖的特性/接口/类

`Context`、`Error`、`BasicError`、`ErrorKind`、`DeviceBus`、`CameraFrame`、`CameraPixelFormat`、`DeviceManager`。

`xdk.os.hardware` 的只读清单不提供相机采集控制；本类型不复制任何清单类型。

---

## 11. 所有权与并发

引用语义；描述符由调用方持有；打开后持有句柄；`close` 释放句柄但保留描述符；无全局注册表；无循环引用。
非线程安全：同一描述符的 `open`/`capture`/`close` 不得并发；调用方需串行化，或确保 close 时没有其它调用。`close`/`open` 幂等指重复调用安全，不承诺并发调用安全。
`list` 每次返回新的描述符列表；调用方拥有列表与元素；帧由 `capture` 返回并归调用方。
无 `equals`/`copy`；不推荐作 `Map` 键；描述符状态可变，不能作为稳定身份。
`name`/`path`/`bus`/`isOpen` 是纯读取，但不要依赖与并发 `open`/`close` 的时序。

---

## 12. 示例与反例

正确：`List<CameraDevice> devices = CameraDevice.list(context).value()`；按 `path()` 找到目标；`device.open(context)`；`CameraFrame frame = device.capture(context).value()`；使用 `frame.data()`；最后 `device.close()`。  
正确：关闭后保留描述符，稍后再次 `open`；采集失败返回错误而不是空帧。  
反例：未 `open` 就 `capture`；close 后继续 `capture`；假设 `list` 顺序稳定或自动热插拔；假设格式固定；对同一描述符并发 `open`；打开后不关闭；把 `path` 当跨平台稳定 ID；把帧当编码后的 JPEG；后台偷偷采集；忽略 OS 隐私指示。

---

## 13. 测试/场景义务

`list` 空/单/多设备；null context；列表元素未打开；列表副本独立；排序不承诺；无权限；不支持；占用；取消/超时；
`open`/`close`；`open` 幂等；关闭后 `capture` 返回 `Unavailable`；关闭后 `name`/`path`/`bus` 可读；关闭后可再次 `open`；
`capture` 成功返回帧；null 帧 → `Internal`；帧在相机关闭后仍可读；取消/超时；格式/尺寸由适配器决定；
构造非法空 name/path panic；适配器非法描述符 → `DataCorrupted`；`bus()` 为 `DeviceBus.Camera`；桌面上无相机返回空列表，或返回 `Unsupported`/`PermissionDenied`；close 失败只诊断。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class CameraDevice {
    final String _name
    final String _path
    Long _handle
    Bool _open

    CameraDevice(String name, String path) {
        if name == null || name == "" || path == null || path == "" {
            throw "CameraDevice: invalid field"
        }
        _name = name
        _path = path
        _handle = 0
        _open = false
    }

    static Result<List<CameraDevice>, Error> list(Context context) {
        if context == null { throw "CameraDevice.list: null context" }
        Result<List<CameraDevice>, Error> listed = cameraListRaw(context)
        if listed.isErr() { return Err(listed.error()) }
        List<CameraDevice> devices = listed.value()
        if devices == null {
            return Err(new BasicError(ErrorKind.Internal, "null camera list"))
        }
        Int index = 0
        while index < devices.length() {
            CameraDevice device = devices.get(index)
            if device == null || device.isOpen() {
                return Err(new BasicError(ErrorKind.DataCorrupted,
                    "invalid camera descriptor"))
            }
            index = index + 1
        }
        return Ok(devices.copy())
    }

    String name() { return _name }
    String path() { return _path }
    DeviceBus bus() { return DeviceBus.Camera }
    Bool isOpen() { return _open }

    Result<Unit, Error> open(Context context) {
        if context == null { throw "CameraDevice.open: null context" }
        if _open { return Ok(unit) }
        Result<Long, Error> opened = cameraOpenRaw(context, _path)
        if opened.isErr() { return Err(opened.error()) }
        if opened.value() <= 0 {
            return Err(new BasicError(ErrorKind.Internal,
                "invalid camera handle"))
        }
        _handle = opened.value()
        _open = true
        return Ok(unit)
    }

    Result<CameraFrame, Error> capture(Context context) {
        if context == null { throw "CameraDevice.capture: null context" }
        if !_open { return Err(unavailableError("camera device")) }
        Result<CameraFrame, Error> captured = cameraCaptureRaw(context, _handle)
        if captured.isErr() { return Err(captured.error()) }
        if captured.value() == null {
            return Err(new BasicError(ErrorKind.Internal, "null camera frame"))
        }
        return Ok(captured.value())
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        Long closingHandle = _handle
        _handle = 0
        _open = false
        return cameraCloseRaw(closingHandle)
    }
}
```
