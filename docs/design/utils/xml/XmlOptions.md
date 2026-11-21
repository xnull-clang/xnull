# `XmlOptions`

| 项 | 值 |
| --- | --- |
| 类型 | `class XmlOptions` |
| 包 | `xdk.xml` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

XML 解析/生成选项：最大深度、最大字节、是否保留空白、是否允许 DOCTYPE。

不做：DTD/实体解析开关、外部 resolver、命名空间开关、编码选择、美化/缩进、Schema 校验。

---

## 2. 设计逻辑

- 可变 builder；`parse*`/`stringify*` 在调用开始时读取并复制各值，之后的修改不影响进行中的调用。
- 默认：`maxDepth=128`、`maxBytes=16777216`（16 MiB）、`preserveWhitespace=true`、`allowDoctype=false`。
- `maxDepth` 与 `maxBytes` 必须 ≥1；非法值 panic。布尔开关无失败。
- `allowDoctype=false` 是 XXE 安全默认；即使设为 true，也只容忍不含内部子集的 DOCTYPE，不启用 DTD、不解析外部实体、不打开任何外部标识。
- `preserveWhitespace` 只影响纯文本元素：true 保留解析到的文本；false 去掉首尾空白，内部连续空白不折叠。元素间用于缩进的空白文本在存在子元素时总被丢弃（元素中心模型无法保存其位置）。
- `maxDepth` 的根元素深度为 1；`maxBytes` 在 `parse(String)` 中按 UTF-8 字节计，在 `parseBytes` 中按输入长度计，在 `stringify` 中按输出 UTF-8 字节计。
- 无 close；非线程安全；`copy()` 产生独立选项。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_maxDepth` | `Int` | ≥1；默认 128 |
| `_maxBytes` | `Long` | ≥1；默认 16777216 |
| `_preserveWhitespace` | `Bool` | 默认 true |
| `_allowDoctype` | `Bool` | 默认 false |

不变量：两个上限始终 ≥1；布尔值总有效；选项不持有解析器、树或 IO 资源。

---

## 4. 生命周期

构造后可变；无 close、无资源。`copy()` 独立；选项可在多次调用间复用。调用方不要在 `parse*`/`stringify*` 期间修改同一选项对象；需要不同值请用 `copy()` 或新建。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `XmlOptions()` | 无 | 使用默认值 | 无 |

所有字段通过 §7 的 setter 修改；setter 返回当前对象以支持链式调用。

---

## 6. 字段表

见 §3；字段私有。setter 校验后写入，getter 只读返回。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `maxDepth` | 设置最大深度 | `Int value` | `XmlOptions` | `<1` → panic |
| `maxBytes` | 设置最大字节 | `Long value` | `XmlOptions` | `<1` → panic |
| `preserveWhitespace` | 设置空白策略 | `Bool value` | `XmlOptions` | 无 |
| `allowDoctype` | 设置 DOCTYPE 容忍 | `Bool value` | `XmlOptions` | 无 |
| `getMaxDepth` | 读取深度 | 无 | `Int` | 无 |
| `getMaxBytes` | 读取字节上限 | 无 | `Long` | 无 |
| `isPreserveWhitespace` | 读取空白策略 | 无 | `Bool` | 无 |
| `isAllowDoctype` | 读取 DOCTYPE 开关 | 无 | `Bool` | 无 |
| `copy` | 独立复制 | 无 | `XmlOptions` | 无 |

说明：

- `maxDepth` 计数根元素为 1；属性不占深度。
- `maxBytes` 同时约束输入和输出；调用方处理更大文档时必须显式提高。
- `preserveWhitespace` 为 false 时只裁剪纯文本元素的首尾空白，不重排、不折叠内部空白，也不改变属性值。
- `allowDoctype=true` 仍不提供 DTD 语义：含内部子集 → `Unsupported`；外部标识只按语法跳过、永不打开；参数实体与实体声明不处理。默认 false 时任何 DOCTYPE 都被拒绝。
- `copy` 逐字段复制；修改原对象或副本互不影响。

---

## 8. 使用的技术

- Builder/链式 setter；
- 上限校验；
- 安全默认（deny by default）；
- 防御性复制。

---

## 9. 需要的支撑

- 语言：class、Int、Long、Bool；
- 运行时：无；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无；不依赖 `Xml`、`XmlElement`、`Error` 或任何 IO 类型。

---

## 11. 所有权与并发

- 引用语义；可变；非线程安全。
- `parse*`/`stringify*` 在调用开始时读取各字段，等价于快照；之后修改不影响该次调用。
- 无资源、无 close；可由调用方在多次调用间复用。
- 不提供全局默认选项；每个入口用 `new XmlOptions()` 创建默认值。

---

## 12. 示例与反例

正确：`new XmlOptions().maxDepth(64).maxBytes(1048576).allowDoctype(false)`；需要保留当前值供后续复用时调用 `copy()`。

反例：`maxDepth(0)`/`maxBytes(0)`（panic）；认为 `allowDoctype(true)` 会展开实体或读取外部 DTD；在另一个任务正在解析时修改同一选项对象；用 `maxBytes` 限制属性个数（它限制的是字节）；期望 `preserveWhitespace(false)` 折叠内部空白。

---

## 13. 测试/场景义务

默认值；每个 setter/getter；`maxDepth=1` 边界；`maxBytes=1` 边界；0/负数 panic；链式调用；`copy()` 独立；`allowDoctype` 只影响 DOCTYPE 容忍；`preserveWhitespace` 对纯文本元素的效果；调用开始后修改选项不影响该次解析/生成。

---

## 14. XNull 伪代码

```xnull
class XmlOptions {
    Int _maxDepth = 128
    Long _maxBytes = 16777216
    Bool _preserveWhitespace = true
    Bool _allowDoctype = false

    XmlOptions() {
    }

    XmlOptions maxDepth(Int value) {
        if value < 1 {
            throw "XmlOptions.maxDepth: must be >= 1"
        }
        _maxDepth = value
        return self
    }

    XmlOptions maxBytes(Long value) {
        if value < 1 {
            throw "XmlOptions.maxBytes: must be >= 1"
        }
        _maxBytes = value
        return self
    }

    XmlOptions preserveWhitespace(Bool value) {
        _preserveWhitespace = value
        return self
    }

    XmlOptions allowDoctype(Bool value) {
        _allowDoctype = value
        return self
    }

    Int getMaxDepth() { return _maxDepth }
    Long getMaxBytes() { return _maxBytes }
    Bool isPreserveWhitespace() { return _preserveWhitespace }
    Bool isAllowDoctype() { return _allowDoctype }

    XmlOptions copy() {
        XmlOptions result = new XmlOptions()
        result.maxDepth(_maxDepth)
        result.maxBytes(_maxBytes)
        result.preserveWhitespace(_preserveWhitespace)
        result.allowDoctype(_allowDoctype)
        return result
    }
}
```
