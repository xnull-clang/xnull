# `xdk.xml` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.xml` |
| 层 | L4 数据/编码（文档分组 `utils/`） |
| 依赖 | `xdk.errors`、`xdk.bytes`、`xdk.text`、`xdk.collections` |
| 被依赖 | 应用、配置/文档导入、测试夹具 |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

`xdk.xml` 提供 XML 1.0 元素树的解析与生成：

- `XmlElement`：可变元素节点，保存名称、属性、子元素和可选文本；
- `XmlOptions`：解析/生成的深度、字节上限与空白、DOCTYPE 开关；
- `Xml`：静态入口，`parse`/`parseBytes`/`stringify`/`isXml`。

不做：

- DTD 处理、实体声明/展开、外部实体、XInclude、XML Schema/Relax NG、XPath/XSLT；
- 命名空间展开、前缀绑定校验或 `xmlns` 语义处理（X 不做）；
- 文件/网络 IO；调用方用 `fs`/`io` 读取后传 `String` 或 `Bytes`；
- 流式 SAX/StAX（X）；
- 新的 JSON/YAML/TOML 映射类型；XML 树就是 `XmlElement`，不扩展 `codec`；
- 全局 parser、全局实体表、全局缓存或全局选项单例。

XML 树与 [`../codec/JsonValue.md`](../codec/JsonValue.md) 平行：两者都是显式值树，但 XML 有元素/属性/文本三种角色，因此使用独立的 `XmlElement`，不塞进 `JsonValue`。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 安全默认 | `XmlOptions.allowDoctype` 默认 `false`；解析器不处理 DTD、不展开实体、不解析外部实体；即使开启也只跳过不含内部子集的 DOCTYPE，不打开任何外部标识 |
| 无 IO | 解析只接受内存中的 `String`/`Bytes`；运行时原语不得访问文件、网络、环境或外部 resolver |
| 单节点类型 | 不搞子类多态；元素统一为 `XmlElement`；属性/子元素/文本由字段区分 |
| 元素中心 | 同一元素只能是“纯文本”或“有子元素”；混合内容明确失败，不静默重排 |
| 上限先行 | 深度、输入字节、输出字节在解析/生成时强制；超限返回 `InvalidArgument` |
| 确定性输出 | 不输出 XML 声明、不缩进、不美化；属性按名称排序；文本/属性值统一转义 |
| 严格失败 | 语法错误 `DataCorrupted`；策略拒绝 `PermissionDenied`；不支持构造 `Unsupported`；超限 `InvalidArgument` |
| 无全局 | 静态方法无状态；每次调用独立；不缓存解析结果；不使用全局可变选项 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `XmlElement` | class | 可变元素树节点/属性/子元素/文本/深拷贝 | [`XmlElement.md`](XmlElement.md) |
| `XmlOptions` | class | 深度/字节/空白/DOCTYPE 选项 | [`XmlOptions.md`](XmlOptions.md) |
| `Xml` | class | 解析/生成/字节探测 | [`Xml.md`](Xml.md) |

X：DTD/实体解析、命名空间展开、混合内容保序模型、流式解析、UTF-16/其他编码、XPath/Schema/XSLT。

---

## 4. 顶层函数

无；解析/生成通过 `Xml` 静态方法，树构造通过 `XmlElement` 构造器和方法。

---

## 5. 技术/支撑/依赖

- 技术：XML 1.0 词法分析、元素树构建、预定义/数字字符引用解码、文本/属性转义、深度与字节上限、UTF-8 校验。
- 支撑：`xmlParseRaw`、`xmlParseBytesRaw`、`xmlFormatRaw`、`xmlIsRaw`、`xmlNameIsValidRaw`、`xmlCharDataIsValidRaw`；全部为纯内存原语。
- 依赖：`xdk.errors`、`xdk.bytes`、`xdk.text`、`xdk.collections`；不依赖 `io`、`fs`、`net`、`codec`。

---

## 6. 场景

### X1：解析配置文档

```xnull
XmlOptions options = new XmlOptions().maxDepth(64).maxBytes(1048576)
Result<XmlElement, Error> parsed = Xml.parse(text, options)
if parsed.isErr() {
    diagnose("xml: " + parsed.error().describe())
    return 2
}
XmlElement root = parsed.value()
String? version = root.attributeOrNull("version")
```

### X2：字节输入

`Xml.parseBytes(data)` 只接受 UTF-8（可带 UTF-8 BOM）；非法 UTF-8 返回 `DataCorrupted`，UTF-16 BOM 或非 UTF-8 编码声明返回 `Unsupported`。XML 声明中的 `encoding` 只允许 `utf-8`（大小写不敏感）。

### X3：构造并生成

```xnull
XmlElement root = new XmlElement("config")
root.setAttribute("version", "1")
root.addChild(new XmlElement("name").setText("demo"))
Result<String, Error> written = Xml.stringify(root, new XmlOptions().maxBytes(1048576))
```

输出无 XML 声明、无缩进；空元素写成 `<name/>`，文本与属性值被转义。

### X4：XXE 拒绝

```text
<!DOCTYPE foo [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>
<foo>&xxe;</foo>
```

默认 `allowDoctype=false` → `PermissionDenied`。设置 `allowDoctype(true)` 后，含内部子集的 DOCTYPE 仍返回 `Unsupported`；外部标识即使出现也只被语法跳过，永不打开文件/网络，`&xxe;` 也不会被解析。

### X5：字节嗅探

`Xml.isXml(bytes)` 只做启发式判断（BOM、空白、`<` 及其后字符），可快速过滤明显非 XML 的输入；返回 `true` 不代表格式合法，仍必须调用 `parseBytes` 并处理 `Result`。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| DTD/实体声明 | 不实现；`allowDoctype` 只是容忍声明，不启用 DTD 语义 |
| 外部实体/XXE | 永不解析、永不打开；内部子集直接 `Unsupported`；无 resolver 钩子 |
| 命名空间 | 不展开；`prefix:name` 与 `xmlns` 均按普通名称/属性保留 |
| 混合内容 | 不支持；同一元素只能有文本或子元素；解析遇混合内容 → `Unsupported` |
| 注释/处理指令 | 跳过，不保留；`stringify` 无法还原 |
| CDATA | 解析时并入文本，输出时按普通文本转义，不保留 CDATA 分隔 |
| XML 声明/DOCTYPE 输出 | 不生成；`stringify` 只输出根元素 |
| 编码 | 只支持 UTF-8；UTF-16/其他编码 X |
| 属性顺序 | 无语义；`stringify` 按属性名排序，保证稳定输出 |
| 文本/子元素顺序 | 元素中心模型不保存混合顺序；需要保序文档用 X 流式模型 |
| 对象映射 | 不做；XML 树就是 `XmlElement` |
| 改名/删子元素 | 不提供 `setName`/`removeChild`；构造新节点或用 `children()` 快照重建 |
| 父指针/环 | 不保存父指针；`addChild` 拒绝自引用，更深环由调用方保证；`Xml.stringify` 以 `maxDepth` 终止，`copy` 要求无环树 |
| 全局状态 | 禁止全局 parser/registry/options 单例 |
| 默认值 | `maxDepth=128`、`maxBytes=16777216`、`preserveWhitespace=true`、`allowDoctype=false` |
