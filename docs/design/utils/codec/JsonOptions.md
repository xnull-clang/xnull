# `JsonOptions`

| 项 | 值 |
| --- | --- |
| 类型 | `class JsonOptions` |
| 包 | `xdk.codec` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

JSON 解析/生成选项：最大深度、最大字节、注释、尾逗号、pretty。

不做：Schema、对象映射、JSON Pointer、流式 SAX。

---

## 2. 设计逻辑

- 可变 builder；解析/生成时复制。
- 默认深度 128、16MiB、不允许注释/尾逗号、不 pretty。
- 值 >0；非法 panic。
- 无 close；非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_maxDepth` | `Int` | 最大深度 |
| `_maxBytes` | `Long` | 最大输入 |
| `_allowComments` | `Bool` | 注释 |
| `_allowTrailingComma` | `Bool` | 尾逗号 |
| `_pretty` | `Bool` | 美化 |

---

## 4. 生命周期

可变；无 close；copy 独立。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `JsonOptions()` | 无 | 默认 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `maxDepth` | 设置 | `Int` | `JsonOptions` | ≤0 → panic |
| `maxBytes` | 设置 | `Long` | `JsonOptions` | ≤0 → panic |
| `allowComments` | 设置 | `Bool` | `JsonOptions` | 无 |
| `allowTrailingComma` | 设置 | `Bool` | `JsonOptions` | 无 |
| `pretty` | 设置 | `Bool` | `JsonOptions` | 无 |
| `getMaxDepth` | 读取 | 无 | `Int` | 无 |
| `getMaxBytes` | 读取 | 无 | `Long` | 无 |
| `isAllowComments` | 读取 | 无 | `Bool` | 无 |
| `isAllowTrailingComma` | 读取 | 无 | `Bool` | 无 |
| `isPretty` | 读取 | 无 | `Bool` | 无 |
| `copy` | 快照 | 无 | `JsonOptions` | 无 |

---

## 8. 使用的技术

- builder；
- 上限/开关。

---

## 9. 需要的支撑

- 语言：class、Int、Long、Bool；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

可变；非线程安全；无资源。

---

## 12. 示例与反例

正确：`new JsonOptions().pretty(true)`。  
反例：0 深度；负字节；修改 options 期望已有值变化。

---

## 13. 测试/场景义务

默认；setter；非法；copy；解析/生成快照。

---

## 14. XNull 伪代码

```xnull
class JsonOptions {
    Int _maxDepth = 128
    Long _maxBytes = 16777216
    Bool _allowComments = false
    Bool _allowTrailingComma = false
    Bool _pretty = false

    JsonOptions() {
    }

    JsonOptions maxDepth(Int value) {
        if value <= 0 { throw "JsonOptions.maxDepth: invalid" }
        _maxDepth = value
        return self
    }

    JsonOptions maxBytes(Long value) {
        if value <= 0 { throw "JsonOptions.maxBytes: invalid" }
        _maxBytes = value
        return self
    }

    JsonOptions allowComments(Bool value) { _allowComments = value; return self }
    JsonOptions allowTrailingComma(Bool value) { _allowTrailingComma = value; return self }
    JsonOptions pretty(Bool value) { _pretty = value; return self }

    Int getMaxDepth() { return _maxDepth }
    Long getMaxBytes() { return _maxBytes }
    Bool isAllowComments() { return _allowComments }
    Bool isAllowTrailingComma() { return _allowTrailingComma }
    Bool isPretty() { return _pretty }

    JsonOptions copy() {
        JsonOptions result = new JsonOptions()
        result.maxDepth(_maxDepth)
        result.maxBytes(_maxBytes)
        result.allowComments(_allowComments)
        result.allowTrailingComma(_allowTrailingComma)
        result.pretty(_pretty)
        return result
    }
}
```
