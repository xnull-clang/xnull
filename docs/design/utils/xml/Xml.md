# `Xml`

| 项 | 值 |
| --- | --- |
| 类型 | `class Xml` |
| 包 | `xdk.xml` |
| 稳定性 | `preview` |
| 依赖 | `XmlElement`、`XmlOptions`、`Bytes`、`Error` |

---

## 1. 定位

XML 静态入口：从 `String`/`Bytes` 解析为 `XmlElement` 树，把 `XmlElement` 生成 XML 文本，探测字节是否“看起来像 XML”。

不做：文件/网络读取、DTD/实体解析、外部实体、命名空间展开、流式解析、XPath/Schema/XSLT、对象映射、全局 parser。

---

## 2. 设计逻辑

- 无实例状态；构造器私有。
- `parse(String)`/`parseBytes(Bytes)` 使用默认 `XmlOptions`；带选项重载在调用开始时读取选项快照。
- 解析只接受一个根元素；根前后的空白、注释、处理指令和 XML 声明按规则跳过；第二个根或尾随普通内容失败。
- 默认拒绝 DOCTYPE；`allowDoctype=true` 只容忍并跳过声明，不启用 DTD；含内部子集 → `Unsupported`，`SYSTEM`/`PUBLIC` 标识只按语法跳过、永不打开。
- 不展开命名空间：名称按词法保留，冒号是普通字符，`xmlns` 是普通属性。
- 解析执行深度与输入字节上限；生成执行深度与输出字节上限。
- `stringify` 输出确定、紧凑、无 XML 声明、无缩进；属性按名称排序；文本/属性值转义。
- `isXml` 只是字节启发式，不解析、不校验、不分配树。
- 失败分类：语法 → `DataCorrupted`；策略拒绝 → `PermissionDenied`；不支持构造 → `Unsupported`；超限/非法树 → `InvalidArgument`。
- 无 close；结果树归调用方；静态方法可并发。

---

## 3. 表示与不变量

无实例字段。

不变量：

- 入参 `String`/`Bytes` 不被修改；
- 每次 `parse*` 返回独立树；每次 `stringify*` 返回独立 `String`；
- 选项在调用开始时快照，调用中修改不影响本次结果；
- 没有全局 parser/registry/缓存/选项单例；
- `stringify` 不修改输入树；
- `isXml` 只读前导字节，不建立解析状态。

---

## 4. 生命周期

静态命名空间；无 close、无资源。解析结果由调用方拥有；生成结果字符串独立；无跨调用状态。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Xml()` | 无 | 私有 | 外部构造 → 编译错误 |

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `parse` | 文本解析 | `String text` | `Result<XmlElement, Error>` | `DataCorrupted`/`InvalidArgument`/`PermissionDenied`/`Unsupported` |
| `parse` | 文本解析（选项） | `String text, XmlOptions options` | `Result<XmlElement, Error>` | 同上 |
| `parseBytes` | 字节解析 | `Bytes data` | `Result<XmlElement, Error>` | 同上 |
| `parseBytes` | 字节解析（选项） | `Bytes data, XmlOptions options` | `Result<XmlElement, Error>` | 同上 |
| `stringify` | 生成 XML | `XmlElement element` | `Result<String, Error>` | `InvalidArgument` |
| `stringify` | 生成 XML（选项） | `XmlElement element, XmlOptions options` | `Result<String, Error>` | `InvalidArgument` |
| `isXml` | 字节启发式 | `Bytes data` | `Bool` | null → panic |

说明：

- 无选项重载等价于传入 `new XmlOptions()`；选项对象只在调用开始时读取。
- null 的 `text`/`data`/`element`/`options` 是编程错误，panic；格式错误通过 `Result` 返回。
- `parse` 的 `maxBytes` 按 `text` 的 UTF-8 编码字节计；`parseBytes` 按 `data.length()` 计。超限立即 `InvalidArgument`，不返回部分树。
- `maxDepth` 从根元素深度 1 开始；子元素递增；超过上限 `InvalidArgument`。属性不占深度。

**解析语法与内容**

- 输入必须恰好一个根元素。空输入、只有声明/注释/空白、多个根、根后除空白/注释/处理指令外的内容 → `DataCorrupted`。
- 可选 UTF-8 BOM；XML 声明若出现，必须是 BOM 之后的第一个构造（前面不能有空白、注释或其他内容）。声明只接受 `version="1.0"`，`encoding` 若出现只接受 `utf-8`（大小写不敏感），`standalone` 忽略；其他版本/编码 → `Unsupported`，声明位置错误 → `DataCorrupted`。`<?xml ...?>` 只能作为声明出现，元素内部或根之后一律 `DataCorrupted`。
- 注释 `<!-- ... -->` 和处理指令 `<?target ...?>` 可出现在根前后和元素内部，解析时跳过，不保留。
- CDATA `<![CDATA[...]]>` 并入相邻文本；CDATA 内容按字面保留、不解码实体；不保留 CDATA 边界；未闭合 CDATA → `DataCorrupted`。
- 普通文本中出现裸 `]]>` → `DataCorrupted`；`stringify` 会转义 `>`，避免生成该序列。
- 文本与属性值中的预定义实体 `&amp;`、`&lt;`、`&gt;`、`&quot;`、`&apos;` 与数字字符引用 `&#...;`/`&#x...;` 被解码；裸 `&` 或非法引用 → `DataCorrupted`；未知实体引用 → `Unsupported`。不读取 DTD，因此不存在自定义实体。
- 属性必须带引号且名称唯一；重复属性、未加引号、缺少 `=`、属性值中裸 `<`、标签不匹配、未闭合标签、非法名称、非法字符 → `DataCorrupted`。
- 属性值中的制表符/换行/回车按 XML 规则规范化为空格；文本中的 CRLF/CR 规范化为 LF。规范化先于字符引用解码；`&#9;`/`&#10;`/`&#13;` 表示的字符保留，不被再次规范化。
- 内容是元素中心模型：元素要么只有文本，要么只有子元素。元素有子元素时，其前后的纯空白文本丢弃；同一元素同时出现非空白文本和子元素 → `Unsupported`（混合内容），不静默重排。
- `preserveWhitespace=true`：纯文本元素的文本按实体解码、CDATA 合并后的结果保留（仅做 XML 行尾规范化）。`false`：去掉纯文本元素首尾空白，内部连续空白不折叠；裁剪后为空则为无文本。

**DOCTYPE 与 XXE**

- `allowDoctype=false`（默认）：任何 `<!DOCTYPE ...>` → `PermissionDenied`，在构建树前终止。
- `allowDoctype=true`：只跳过 DOCTYPE 声明，不建立 DTD；含内部子集 `[ ... ]` → `Unsupported`；`SYSTEM`/`PUBLIC` 标识只按语法跨过，永不打开文件、URL 或网络。
- 不实现参数实体、外部实体、实体声明、默认属性、条件段；没有 resolver/回调/环境查询入口。
- 因此 `<!ENTITY xxe SYSTEM "file:///...">` 无法被声明；`&xxe;` 等未支持实体引用直接 `Unsupported`。

**编码**

- `parseBytes` 只接受 UTF-8，可带 UTF-8 BOM；UTF-16 BOM → `Unsupported`；非法 UTF-8 → `DataCorrupted`。
- `parse` 接收已解码的 `String`；若声明了非 UTF-8 的 `encoding`，仍按声明不匹配处理 → `Unsupported`。
- `parse` 首字符为 U+FEFF 时按 BOM 跳过；其他位置的 U+FEFF 作为普通字符处理。
- 不自动探测其他编码，不做代码页转换。

**生成**

- 输出根元素，不含 XML 声明、DOCTYPE、注释、处理指令或 CDATA 段。
- 空元素写 `<name/>`；有子元素写开始标签、子元素、结束标签；有文本写开始标签、文本、结束标签。
- 属性按名称的 Unicode 码点升序输出，形式 ` name="value"`；属性顺序无语义。
- 文本转义 `&`→`&amp;`、`<`→`&lt;`、`>`→`&gt;`、CR→`&#13;`；属性值额外转义 `"`→`&quot;`，并把制表符/换行/回车写成 `&#9;`/`&#10;`/`&#13;`，保证重新解析不丢字符。
- `preserveWhitespace=false` 时先裁剪文本首尾空白；`true` 时按树中文本原样输出。
- 深度超过 `maxDepth`、输出 UTF-8 超过 `maxBytes`、树含环、名称/字符非法 → `InvalidArgument`，不返回部分字符串。
- 不做命名空间重写：`prefix:name`、`xmlns`、`xml:lang` 等按原字符串输出。

**字节启发式**

- `isXml` 跳过可选 UTF-8 BOM 和 ASCII XML 空白，检查首字节 `<`，再检查下一字节是 ASCII 字母、`_`、`:`、`?` 或 `!`。
- 返回 `true` 只表示“可能像 XML”；HTML、残缺 XML、只有 DOCTYPE 的输入也可能为 true。返回 `false` 表示明显不是 UTF-8 XML。
- 不解析、不校验、不检查大小；不能替代 `parseBytes`；UTF-16 输入返回 false。

---

## 8. 使用的技术

- XML 1.0 词法与元素树构建；
- 预定义/数字字符引用解码；
- 文本与属性转义；
- UTF-8/BOM 校验；
- 深度与字节上限；
- 确定性属性排序；
- 纯内存字节启发式。

---

## 9. 需要的支撑

- 语言：class、String、Bytes、Bool、Int、Long、Result；
- 运行时：
  - `xmlParseRaw(String text, Int maximumDepth, Long maximumBytes, Bool preserveWhitespace, Bool allowDoctype)`；
  - `xmlParseBytesRaw(Bytes data, Int maximumDepth, Long maximumBytes, Bool preserveWhitespace, Bool allowDoctype)`；
  - `xmlFormatRaw(XmlElement element, Int maximumDepth, Long maximumBytes, Bool preserveWhitespace)`；
  - `xmlIsRaw(Bytes data)`；
  - `xmlNameIsValidRaw`、`xmlCharDataIsValidRaw`。
- 接口：`XmlElement`、`XmlOptions`、`BasicError`、`ErrorKind`；不使用 `Context`、`Reader`、`Writer`、`Path`。

运行时原语必须是纯内存、无 IO、无 resolver、无全局状态的；`allowDoctype` 只控制跳过策略，不能触发外部读取。

---

## 10. 依赖的特性/接口/类

`XmlElement`、`XmlOptions`、`Bytes`、`Error`、`BasicError`、`ErrorKind`；XML 运行时原语。不依赖 `codec`、`io`、`fs`、`net`、`config`。

---

## 11. 所有权与并发

- 无状态；每次调用独立；结果树/字符串归调用方。
- 解析不修改输入 `String`/`Bytes`；生成不修改输入树。
- 多个任务可并发调用静态方法；运行时原语必须可重入且无全局 mutable 状态。
- 同一棵 `XmlElement` 树在 `stringify` 期间被其他任务修改属于数据竞争，调用方负责同步。
- 同一 `XmlOptions` 在调用期间被修改属于数据竞争；建议每次调用使用独立选项或只读共享。
- 无资源、无 close。

---

## 12. 示例与反例

正确：

```xnull
Result<XmlElement, Error> parsed = Xml.parseBytes(data)
if parsed.isErr() {
    diagnose("xml: " + parsed.error().describe())
    return 1
}
XmlElement root = parsed.value()
Result<String, Error> rendered = Xml.stringify(root, new XmlOptions().maxBytes(2097152))
if rendered.isErr() {
    diagnose("xml: " + rendered.error().describe())
    return 1
}
```

反例：忽略 `Result` 直接取树；用 `isXml` 代替 `parseBytes`；期望 `allowDoctype(true)` 展开实体或读取外部 DTD；把未闭合的 HTML 当 XML；期望命名空间前缀被解析；期望注释/CDATA/声明在 `stringify` 后保留；用 UTF-16 字节调用 `parseBytes`；对含环或超深的树调用 `stringify`；不提高 `maxBytes` 就解析大文档；在 `stringify` 同时修改树；期望混合内容保序。

---

## 13. 测试/场景义务

最小根元素；自闭合；嵌套；属性；单/双引号；文本；实体与数字引用；CDATA；注释/处理指令；XML 声明；UTF-8 BOM；根前空白；空输入；多根；尾随垃圾；标签不匹配；未闭合；重复属性；未加引号属性；非法名称/字符；混合内容；`preserveWhitespace` true/false；深度 1/上限/超限；UTF-8 多字节字节上限；DOCTYPE 默认拒绝；`allowDoctype` 容忍裸声明；内部子集拒绝；`SYSTEM`/`PUBLIC` 不触发读取；未知实体；UTF-16 BOM；非法 UTF-8；非 UTF-8 编码声明；`stringify` 转义/排序/空元素/深度/输出上限/环；`parse`→`stringify`→`parse` 往返（元素中心内容）；`isXml` 正例/反例/HTML 假阳性；null 参数。

---

## 14. XNull 伪代码

```xnull
class Xml {
    private Xml() {
    }

    static Result<XmlElement, Error> parse(String text) {
        return Xml.parse(text, new XmlOptions())
    }

    static Result<XmlElement, Error> parse(String text, XmlOptions options) {
        if text == null {
            throw "Xml.parse: null text"
        }
        if options == null {
            throw "Xml.parse: null options"
        }
        return xmlParseRaw(text,
            options.getMaxDepth(),
            options.getMaxBytes(),
            options.isPreserveWhitespace(),
            options.isAllowDoctype())
    }

    static Result<XmlElement, Error> parseBytes(Bytes data) {
        return Xml.parseBytes(data, new XmlOptions())
    }

    static Result<XmlElement, Error> parseBytes(Bytes data, XmlOptions options) {
        if data == null {
            throw "Xml.parseBytes: null data"
        }
        if options == null {
            throw "Xml.parseBytes: null options"
        }
        return xmlParseBytesRaw(data,
            options.getMaxDepth(),
            options.getMaxBytes(),
            options.isPreserveWhitespace(),
            options.isAllowDoctype())
    }

    static Result<String, Error> stringify(XmlElement element) {
        return Xml.stringify(element, new XmlOptions())
    }

    static Result<String, Error> stringify(XmlElement element, XmlOptions options) {
        if element == null {
            throw "Xml.stringify: null element"
        }
        if options == null {
            throw "Xml.stringify: null options"
        }
        return xmlFormatRaw(element,
            options.getMaxDepth(),
            options.getMaxBytes(),
            options.isPreserveWhitespace())
    }

    static Bool isXml(Bytes data) {
        if data == null {
            throw "Xml.isXml: null data"
        }
        return xmlIsRaw(data)
    }
}
```

> `xml*Raw` 是运行时 XML 原语；不是 XDK 公共类型。它们必须无 IO、无外部实体解析、无全局状态。
