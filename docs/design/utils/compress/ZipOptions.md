# `ZipOptions`

| 项 | 值 |
| --- | --- |
| 类型 | `class ZipOptions` |
| 包 | `xdk.compress` |
| 稳定性 | `preview` |
| 依赖 | `CompressionLevel` |

---

## 1. 定位

zip 读写选项：压缩级别、单条目/总解压上限、CRC 校验、归档注释。

不做：ZIP64、加密、分卷、符号链接、权限位映射。

---

## 2. 设计逻辑

- 可变 builder；`ZipArchive`/`ZipWriter` 构造时复制，之后修改不影响已创建对象。
- 默认：`Default`、单条目 64 MiB、总量 256 MiB、校验 CRC、无注释。
- 读取时使用上限和 `verifyCrc`；写出时使用压缩级别、上限和注释。
- `maxEntryBytes > 0`；`maxTotalBytes >= maxEntryBytes`；注释最长 65535 字符。
- 无 close；非线程安全；builder 不共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_compressionLevel` | `CompressionLevel` | 写出压缩级别 |
| `_maxEntryBytes` | `Int` | 单条目解压上限 |
| `_maxTotalBytes` | `Int` | 总解压上限 |
| `_verifyCrc` | `Bool` | 读取时校验 CRC |
| `_comment` | `String?` | 归档注释 |

不变量：`_maxEntryBytes > 0`；`_maxTotalBytes >= _maxEntryBytes`；注释长度 ≤65535。

---

## 4. 生命周期

可变；由调用方持有；无 close；复制后独立。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ZipOptions()` | 无 | 默认值 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `compressionLevel` | 设置级别 | `CompressionLevel` | `ZipOptions` | null → panic |
| `maxEntryBytes` | 设置单条目上限 | `Int` | `ZipOptions` | ≤0 或大于总量 → panic |
| `maxTotalBytes` | 设置总上限 | `Int` | `ZipOptions` | 小于单条目 → panic |
| `verifyCrc` | 设置 CRC 校验 | `Bool` | `ZipOptions` | 无 |
| `comment` | 设置注释 | `String?` | `ZipOptions` | 超长 → panic |
| `getCompressionLevel` | 读取级别 | 无 | `CompressionLevel` | 无 |
| `getMaxEntryBytes` | 读取单条目上限 | 无 | `Int` | 无 |
| `getMaxTotalBytes` | 读取总上限 | 无 | `Int` | 无 |
| `isVerifyCrc` | 是否校验 | 无 | `Bool` | 无 |
| `getComment` | 读取注释 | 无 | `String?` | 无 |
| `copy` | 独立副本 | 无 | `ZipOptions` | 无 |

---

## 8. 使用的技术

- builder 模式；
- 边界校验；
- 防御性复制；
- 解压资源上限。

---

## 9. 需要的支撑

- 语言：class、Int、Bool、String、可空引用；
- 运行时：无；
- 接口：`CompressionLevel`。

---

## 10. 依赖的特性/接口/类

`CompressionLevel`。

---

## 11. 所有权与并发

可变；非线程安全；无资源；传入归档后被复制，外部修改不影响归档。

---

## 12. 示例与反例

正确：`new ZipOptions().maxEntryBytes(1048576).maxTotalBytes(8388608)`。  
反例：单条目上限大于总量；注释超长；读取时依赖压缩级别；创建后继续改 options 期望生效。

---

## 13. 测试/场景义务

默认值；每个 setter；上限交叉校验；注释边界；复制独立性；读取忽略压缩级别；写入忽略 CRC 开关。

---

## 14. XNull 伪代码

```xnull
class ZipOptions {
    CompressionLevel _compressionLevel = CompressionLevel.Default
    Int _maxEntryBytes = 67108864
    Int _maxTotalBytes = 268435456
    Bool _verifyCrc = true
    String? _comment = null

    ZipOptions() {
    }

    ZipOptions compressionLevel(CompressionLevel value) {
        if value == null { throw "ZipOptions.compressionLevel: null" }
        _compressionLevel = value
        return self
    }

    ZipOptions maxEntryBytes(Int value) {
        if value <= 0 { throw "ZipOptions.maxEntryBytes: not positive" }
        if value > _maxTotalBytes {
            throw "ZipOptions.maxEntryBytes: greater than total"
        }
        _maxEntryBytes = value
        return self
    }

    ZipOptions maxTotalBytes(Int value) {
        if value < _maxEntryBytes {
            throw "ZipOptions.maxTotalBytes: less than entry limit"
        }
        _maxTotalBytes = value
        return self
    }

    ZipOptions verifyCrc(Bool value) {
        _verifyCrc = value
        return self
    }

    ZipOptions comment(String? value) {
        if value != null && value.length() > 65535 {
            throw "ZipOptions.comment: too long"
        }
        _comment = value
        return self
    }

    CompressionLevel getCompressionLevel() { return _compressionLevel }
    Int getMaxEntryBytes() { return _maxEntryBytes }
    Int getMaxTotalBytes() { return _maxTotalBytes }
    Bool isVerifyCrc() { return _verifyCrc }
    String? getComment() { return _comment }

    ZipOptions copy() {
        ZipOptions result = new ZipOptions()
        result._compressionLevel = _compressionLevel
        result._maxEntryBytes = _maxEntryBytes
        result._maxTotalBytes = _maxTotalBytes
        result._verifyCrc = _verifyCrc
        result._comment = _comment
        return result
    }
}
```
