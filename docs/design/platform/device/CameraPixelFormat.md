# `CameraPixelFormat`

| 项 | 值 |
| --- | --- |
| 类型 | `enum CameraPixelFormat` |
| 包 | `xdk.device` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

相机原始帧的像素布局：RGB24、RGBA32、Gray8、YUYV、未知。

不做：图像编码/解码、色彩空间转换、alpha 预乘、裁剪/缩放、JPEG/PNG、HDR/位深转换、帧率协商。

---

## 2. 设计逻辑

- 为什么是 enum：baseline 只支持少量紧打包格式，值语义、可穷举；比字符串/像素格式整数更不容易误用。
- 格式描述**内存布局**，不是相机输出协商能力；baseline 不提供格式枚举/切换，`capture` 返回适配器当前格式。
- `Rgb24`/`Rgba32`/`Gray8` 是紧打包、无 stride/padding；`Yuyv` 是 4:2:2，宽度必须偶数。
- `Unknown` 是合法值：帧数据存在但布局不可解释；`cameraPixelFormatBytesPerPixel` 返回 0，不 panic。
- 像素格式不携带色彩空间/传输函数/白平衡；这些是 X。
- 成员固定，只允许追加；名称映射稳定小写。

---

## 3. 表示与不变量

| 成员 | 布局 | 每像素字节 | 说明 |
| --- | --- | --- | --- |
| `Rgb24` | R,G,B 各 8 位 | 3 | 无 alpha；紧打包 |
| `Rgba32` | R,G,B,A 各 8 位 | 4 | alpha 不预乘；紧打包 |
| `Gray8` | 单通道 8 位 | 1 | 灰度 |
| `Yuyv` | Y0,U,Y1,V | 2（平均） | 4:2:2；宽度必须偶数 |
| `Unknown` | 不解释 | 0 | 数据存在但布局未知 |

不变量：成员固定；只允许追加；值语义；`Yuyv` 的帧宽度为偶数；`Rgb24`/`Rgba32`/`Gray8`/`Yuyv` 的帧字节数由 `CameraFrame` 校验；`Unknown` 不校验布局。

---

## 4. 生命周期

值类型；无构造器、无 `close`；可共享；无资源；无取消点。

---

## 5. 构造契约

枚举项直接使用，无构造器。不允许应用扩展成员；未知格式用 `Unknown`。

---

## 6. 字段表

无实例字段；成员表见 §3。

---

## 7. 方法总表 / 详表

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `cameraPixelFormatName` | 稳定小写名 | `CameraPixelFormat format` | `String` | 无；null 返回 `"unknown"` |
| `cameraPixelFormatFromName` | 名称解析 | `String name` | `CameraPixelFormat?` | 无；未知/null 返回 null |
| `cameraPixelFormatBytesPerPixel` | 每像素字节数 | `CameraPixelFormat format` | `Int` | 无；`Unknown`/null 返回 0 |

说明：

- `cameraPixelFormatName` 对 `Rgb24`/`Rgba32`/`Gray8`/`Yuyv`/`Unknown` 返回 `"rgb24"`/`"rgba32"`/`"gray8"`/`"yuyv"`/`"unknown"`；null 返回 `"unknown"`。
- `cameraPixelFormatFromName` 先 `trim()` 再 `toLower()`；只接受稳定名；不接受 `"rgb"`/`"yuv"`/`"jpeg"` 等近似名。
- `cameraPixelFormatBytesPerPixel` 对 `Rgb24`/`Rgba32`/`Gray8`/`Yuyv` 返回 3/4/1/2；`Unknown`/null 返回 0。0 表示“未知”，不是 1 字节。
- 三个函数都是纯函数、O(1)、无锁、可并发调用。

---

## 8. 使用的技术

- 简单枚举；
- 稳定名称映射；
- 像素布局表；
- 值语义。

---

## 9. 需要的支撑

- 语言：enum、String、Int；
- 运行时：无；
- 接口：`CameraFrame` 使用本枚举校验字节数；`CameraDevice` 返回带格式的帧。

---

## 10. 依赖的特性/接口/类

`CameraFrame`、`CameraDevice`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。
相等：按枚举底层值比较；可作 `Map`/`Set` 键；排序按声明顺序稳定。

---

## 12. 示例与反例

正确：已知格式用 `width * height * cameraPixelFormatBytesPerPixel(format)` 估算帧字节数；`cameraPixelFormatName(format)` 写日志；`format == CameraPixelFormat.Unknown` 时不做像素解释。  
反例：把 `Unknown` 当 1 字节/像素；把 `Yuyv` 当 3 字节/像素；假设帧有 stride/padding；把格式当编解码器；用 `"jpeg"` 解析格式；应用扩展枚举；`Yuyv` 奇数宽度。

---

## 13. 测试/场景义务

五个成员名称/解析往返；大小写与空白；未知名称；null；`cameraPixelFormatBytesPerPixel` 的 3/4/1/2/0；`Yuyv` 偶数宽度；`Unknown` 不解释；`CameraFrame` 字节数校验；枚举作 `Map` 键；日志名称稳定。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
enum CameraPixelFormat {
    Rgb24,
    Rgba32,
    Gray8,
    Yuyv,
    Unknown,
}

String cameraPixelFormatName(CameraPixelFormat format) {
    if format == CameraPixelFormat.Rgb24 { return "rgb24" }
    if format == CameraPixelFormat.Rgba32 { return "rgba32" }
    if format == CameraPixelFormat.Gray8 { return "gray8" }
    if format == CameraPixelFormat.Yuyv { return "yuyv" }
    return "unknown"
}

CameraPixelFormat? cameraPixelFormatFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "rgb24" { return CameraPixelFormat.Rgb24 }
    if normalized == "rgba32" { return CameraPixelFormat.Rgba32 }
    if normalized == "gray8" { return CameraPixelFormat.Gray8 }
    if normalized == "yuyv" { return CameraPixelFormat.Yuyv }
    if normalized == "unknown" { return CameraPixelFormat.Unknown }
    return null
}

Int cameraPixelFormatBytesPerPixel(CameraPixelFormat format) {
    if format == CameraPixelFormat.Rgb24 { return 3 }
    if format == CameraPixelFormat.Rgba32 { return 4 }
    if format == CameraPixelFormat.Gray8 { return 1 }
    if format == CameraPixelFormat.Yuyv { return 2 }
    return 0
}
```
