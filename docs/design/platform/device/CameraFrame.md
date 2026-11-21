# `CameraFrame`

| 项 | 值 |
| --- | --- |
| 类型 | `class CameraFrame` |
| 包 | `xdk.device` |
| 稳定性 | `preview` |
| 依赖 | `Bytes`、`CameraPixelFormat` |

---

## 1. 定位

不可变的相机原始帧快照：宽度、高度、像素格式、帧字节、单调时间戳。

不做：编码/解码、色彩空间转换、裁剪/缩放/旋转、JPEG/PNG、录像、文件 I/O、相机控制、帧池/零拷贝视图。

---

## 2. 设计逻辑

- 为什么是 class：帧是带多个字段的不可变值快照；不是 struct，因为 `Bytes` 是引用类型，需要防御性复制；不是 protocol，因为没有平台差异。
- 由 `CameraDevice.capture(context)` 返回；构造器公开供适配器/测试构造帧。
- 构造时复制 `data`；`data()` 返回副本；调用方持有的帧与相机、源缓冲区解耦。
- 已知格式校验字节数：`Rgb24` 3、`Rgba32` 4、`Gray8` 1、`Yuyv` 2 字节/像素；`Yuyv` 宽度必须偶数；`Unknown` 合法但不解释布局。
- 尺寸用 `Long` 计算，防止 `width * height * bytesPerPixel` 的 `Int` 溢出；帧必须非空。
- `timestampMono` 是单调时钟纳秒，起点未指定；只用于帧间差值/超时判断，不是墙上时钟。
- 无 `close`；帧不持有设备资源；GC 管理内存。
- 不可变；可共享；读取无锁。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_width` | `Int` | final | >0；像素宽 |
| `_height` | `Int` | final | >0；像素高 |
| `_format` | `CameraPixelFormat` | final | 非 null |
| `_data` | `Bytes` | final | 非 null；非空；构造时复制 |
| `_timestampMono` | `Long` | final | ≥0；单调纳秒 |

不变量：`width > 0`；`height > 0`；`width * height` 不超过 `Int` 上限；`format` 非 null；`data` 非空；已知格式的 `data.length()` 等于 `width * height * bytesPerPixel`；`Yuyv` 的 `width` 为偶数；`timestampMono ≥ 0`；`_data` 不被外部别名修改。

---

## 4. 生命周期

构造后不可变；无 `close`；无 `deinit` 依赖；可共享；GC 回收内存。帧的生命周期独立于产生它的 `CameraDevice`；相机关闭后帧仍可读。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `CameraFrame(Int width, Int height, CameraPixelFormat format, Bytes data, Long timestampMono)` | width、height、format、data、timestampMono | width>0；height>0；format 非 null；data 非 null 且非空；已知格式字节数匹配；`Yuyv` 宽度偶数；timestampMono≥0 | 非法 → panic |

构造器复制 `data`；调用方之后修改源 `Bytes` 不影响帧。`Unknown` 只要求 `data` 非空，不校验布局。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `width` | 像素宽 | 无 | `Int` | 无 |
| `height` | 像素高 | 无 | `Int` | 无 |
| `format` | 像素格式 | 无 | `CameraPixelFormat` | 无 |
| `data` | 帧字节副本 | 无 | `Bytes` | 无 |
| `timestampMono` | 单调纳秒时间戳 | 无 | `Long` | 无 |
| `byteLength` | 帧字节数 | 无 | `Int` | 无 |
| `pixelCount` | 像素数 | 无 | `Int` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |

说明：

- `width`/`height`/`format`/`timestampMono` 是纯读取；帧不可变，关闭相机后仍可读。
- `data` 返回 `copy(_data)`，调用方拥有副本；修改副本不影响帧；O(n)。
- `byteLength` 等于 `_data.length()`；`pixelCount` 等于 `width * height`，已由构造器保证不溢出。
- `describe` 只包含尺寸、格式名、字节数、时间戳；不输出帧内容；O(1)。
- 无 `close`/`isOpen`；帧不是资源；无取消点。
- 无 `equals`/`copy`；帧是引用语义的值快照，值比较由调用方逐字段进行；需要独立副本时重新构造。

---

## 8. 使用的技术

- 不可变快照；
- 防御性复制；
- 像素格式字节数校验；
- `Long` 尺寸算术防溢出；
- 单调时间戳；
- 字符串摘要。

---

## 9. 需要的支撑

- 语言：class、final 字段、Int、Long、Bool、Bytes、String；
- 运行时：`copy(Bytes)`、`Bytes.length()`、`str()`；
- 接口：`CameraPixelFormat`、`cameraPixelFormatBytesPerPixel`、`cameraPixelFormatName`；
- 适配器：`cameraCaptureRaw` 返回已构造的 `CameraFrame`；帧字节必须是紧打包、无 stride。

---

## 10. 依赖的特性/接口/类

`CameraPixelFormat`、`cameraPixelFormatBytesPerPixel`、`cameraPixelFormatName`、`CameraDevice`、`Bytes`。

---

## 11. 所有权与并发

不可变；可共享；`data()` 返回新副本；构造器复制输入；无资源；无取消点。
相等：引用身份；需要值比较时逐字段比较（`data` 用 `equals(Bytes, Bytes)` 或逐字节比较）；不推荐作 `Map` 键。
帧与相机解耦；相机 `close` 不会使已返回帧失效；多任务可同时读取同一帧。

---

## 12. 示例与反例

正确：`CameraFrame frame = camera.capture(context).value()`；用 `frame.width()`/`frame.height()`/`frame.format()` 解释 `frame.data()`；用相邻帧 `timestampMono()` 差值估算间隔。  
正确：对已知格式校验 `frame.byteLength() == frame.pixelCount() * cameraPixelFormatBytesPerPixel(frame.format())`。  
反例：构造后修改源 `Bytes` 并期望帧变化；把 `data()` 当视图做原地处理；把 `Unknown` 当 1 字节/像素；`Yuyv` 奇数宽；把时间戳当墙上时钟；把 JPEG/PNG 塞进 `data`；假设帧有 stride/padding；用 `==` 做帧内容比较。

---

## 13. 测试/场景义务

五种格式的合法帧；Rgb24/Rgba32/Gray8/Yuyv 字节数精确匹配；`Unknown` 任意非空布局；`Yuyv` 奇数宽 panic；字节数不匹配 panic；空数据 panic；负时间戳 panic；`width * height` 溢出 panic；`data()` 副本独立；源 `Bytes` 修改不影响帧；`byteLength`/`pixelCount`/`describe`；相机关闭后帧仍可读；多任务共享读；无 `close`。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class CameraFrame {
    final Int _width
    final Int _height
    final CameraPixelFormat _format
    final Bytes _data
    final Long _timestampMono

    CameraFrame(Int width, Int height, CameraPixelFormat format,
                Bytes data, Long timestampMono) {
        if width <= 0 || height <= 0 || format == null || data == null {
            throw "CameraFrame: invalid field"
        }
        if data.length() == 0 || timestampMono < 0 {
            throw "CameraFrame: invalid data or timestamp"
        }
        Long pixels = (width as Long) * (height as Long)
        if pixels > 2147483647 {
            throw "CameraFrame: frame too large"
        }
        if format == CameraPixelFormat.Yuyv && width % 2 != 0 {
            throw "CameraFrame: yuyv width must be even"
        }
        Int bytesPerPixel = cameraPixelFormatBytesPerPixel(format)
        if bytesPerPixel > 0 {
            Long expectedBytes = pixels * (bytesPerPixel as Long)
            if expectedBytes > 2147483647 {
                throw "CameraFrame: frame too large"
            }
            Int expectedLength = expectedBytes as Int
            if data.length() != expectedLength {
                throw "CameraFrame: data length mismatch"
            }
        }
        _width = width
        _height = height
        _format = format
        _data = copy(data)
        _timestampMono = timestampMono
    }

    Int width() { return _width }
    Int height() { return _height }
    CameraPixelFormat format() { return _format }
    Bytes data() { return copy(_data) }
    Long timestampMono() { return _timestampMono }
    Int byteLength() { return _data.length() }
    Int pixelCount() { return _width * _height }

    String describe() {
        return "camera-frame " + str(_width) + "x" + str(_height)
            + " " + cameraPixelFormatName(_format)
            + " " + str(_data.length()) + "B"
            + " mono=" + str(_timestampMono)
    }
}
```
