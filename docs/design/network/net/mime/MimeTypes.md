# `MimeTypes`

| 项 | 值 |
| --- | --- |
| 类型 | `class MimeTypes` |
| 包 | `xdk.net.mime` |
| 稳定性 | `preview` |
| 依赖 | `MediaType` |

---

## 1. 定位

常用 MediaType 映射：扩展名 ↔ 类型、默认 charset、常用类型常量。

不做：完整 IANA 表、内容嗅探、自定义全局注册、文件检测。

---

## 2. 设计逻辑

- 无状态；构造器私有；全部静态方法。
- 内置常用映射；未知扩展名/类型返回 null。
- `json/text/octetStream/formUrlEncoded/multipartFormData` 返回固定 MediaType。
- 不做全局可变注册表；自定义映射 X。
- 无 close；可并发。

---

## 3. 表示与不变量

无实例字段。

---

## 4. 生命周期

静态命名空间；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `MimeTypes()` | 无 | 私有 | 外部构造 → 编译错误 |

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `fromExtension` | 扩展名 → 类型 | `String extension` | `MediaType?` | 无 |
| `extensionFor` | 类型 → 扩展名 | `MediaType type` | `String?` | 无 |
| `charsetFor` | 默认 charset | `MediaType type` | `String?` | 无 |
| `json` | application/json | 无 | `MediaType` | 无 |
| `text` | text/plain | 无 | `MediaType` | 无 |
| `octetStream` | application/octet-stream | 无 | `MediaType` | 无 |
| `formUrlEncoded` | form 类型 | 无 | `MediaType` | 无 |
| `multipartFormData` | multipart/form-data | 无 | `MediaType` | 无 |

---

## 8. 使用的技术

- 只读映射表；
- 静态方法。

---

## 9. 需要的支撑

- 语言：class、String、Bool；
- 运行时：`mimeFromExtensionRaw`、`mimeExtensionForRaw`、`mimeCharsetForRaw`；
- 接口：`MediaType`。

---

## 10. 依赖的特性/接口/类

`MediaType`、MIME 映射运行时原语。

---

## 11. 所有权与并发

无状态；无资源；可并发。

---

## 12. 示例与反例

正确：`MimeTypes.fromExtension("png")`。  
反例：期望完整 IANA；未知扩展名抛错；全局注册自定义类型。

---

## 13. 测试/场景义务

常见扩展名；未知 → null；类型 → 扩展名；charset；常用常量；大小写扩展名。

---

## 14. XNull 伪代码

```xnull
class MimeTypes {
    private MimeTypes() {
    }

    static MediaType? fromExtension(String extension) {
        if extension == null || extension == "" { return null }
        return mimeFromExtensionRaw(extension.toLower())
    }

    static String? extensionFor(MediaType type) {
        if type == null { return null }
        return mimeExtensionForRaw(type.text())
    }

    static String? charsetFor(MediaType type) {
        if type == null { return null }
        return mimeCharsetForRaw(type.text())
    }

    static MediaType json() { return MediaType.parse("application/json").value() }
    static MediaType text() { return MediaType.parse("text/plain").value() }
    static MediaType octetStream() { return MediaType.parse("application/octet-stream").value() }
    static MediaType formUrlEncoded() { return MediaType.parse("application/x-www-form-urlencoded").value() }
    static MediaType multipartFormData() { return MediaType.parse("multipart/form-data").value() }
}
```

> `mime*Raw` 是运行时 MIME 映射原语；不是 XDK 公共类型。`MediaType.parse(...).value()` 在固定字面量上不会失败。
