# `MultipartOptions`

| 项 | 值 |
| --- | --- |
| 类型 | `class MultipartOptions` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

multipart 解析限制：最大 part 数、单 part、总字节、内存阈值。

不做：multipart 编码、流式落盘实现、内容嗅探。

---

## 2. 设计逻辑

- 可变 builder；解析时复制。
- 默认 128 parts、单 16MiB、总 64MiB、内存阈值 1MiB。
- 值 >0；非法 panic。
- 无 close；非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_maxParts` | `Int` | 最大 part |
| `_maxPartBytes` | `Long` | 单 part |
| `_maxTotalBytes` | `Long` | 总字节 |
| `_memoryThreshold` | `Long` | 内存阈值 |

不变量：全部 >0。

---

## 4. 生命周期

可变；解析器复制；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `MultipartOptions()` | 无 | 默认 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `maxParts` | 设置 | `Int` | `MultipartOptions` | ≤0 → panic |
| `maxPartBytes` | 设置 | `Long` | `MultipartOptions` | ≤0 → panic |
| `maxTotalBytes` | 设置 | `Long` | `MultipartOptions` | ≤0 → panic |
| `memoryThreshold` | 设置 | `Long` | `MultipartOptions` | ≤0 → panic |
| `getMaxParts` | 读取 | 无 | `Int` | 无 |
| `getMaxPartBytes` | 读取 | 无 | `Long` | 无 |
| `getMaxTotalBytes` | 读取 | 无 | `Long` | 无 |
| `getMemoryThreshold` | 读取 | 无 | `Long` | 无 |
| `copy` | 快照 | 无 | `MultipartOptions` | 无 |

---

## 8. 使用的技术

- builder；
- 上限。

---

## 9. 需要的支撑

- 语言：class、Int、Long；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

可变；非线程安全；无资源。

---

## 12. 示例与反例

正确：`new MultipartOptions().maxParts(32)`。  
反例：0 上限；修改 options 期望已有 form 变化。

---

## 13. 测试/场景义务

默认；setter；非法；copy；解析快照。

---

## 14. XNull 伪代码

```xnull
class MultipartOptions {
    Int _maxParts = 128
    Long _maxPartBytes = 16777216
    Long _maxTotalBytes = 67108864
    Long _memoryThreshold = 1048576

    MultipartOptions() {
    }

    MultipartOptions maxParts(Int value) {
        if value <= 0 { throw "MultipartOptions.maxParts: invalid" }
        _maxParts = value
        return self
    }

    MultipartOptions maxPartBytes(Long value) {
        if value <= 0 { throw "MultipartOptions.maxPartBytes: invalid" }
        _maxPartBytes = value
        return self
    }

    MultipartOptions maxTotalBytes(Long value) {
        if value <= 0 { throw "MultipartOptions.maxTotalBytes: invalid" }
        _maxTotalBytes = value
        return self
    }

    MultipartOptions memoryThreshold(Long value) {
        if value <= 0 { throw "MultipartOptions.memoryThreshold: invalid" }
        _memoryThreshold = value
        return self
    }

    Int getMaxParts() { return _maxParts }
    Long getMaxPartBytes() { return _maxPartBytes }
    Long getMaxTotalBytes() { return _maxTotalBytes }
    Long getMemoryThreshold() { return _memoryThreshold }

    MultipartOptions copy() {
        MultipartOptions result = new MultipartOptions()
        result.maxParts(_maxParts)
        result.maxPartBytes(_maxPartBytes)
        result.maxTotalBytes(_maxTotalBytes)
        result.memoryThreshold(_memoryThreshold)
        return result
    }
}
```
