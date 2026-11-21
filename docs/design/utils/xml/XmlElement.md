# `XmlElement`

| 项 | 值 |
| --- | --- |
| 类型 | `class XmlElement` |
| 包 | `xdk.xml` |
| 稳定性 | `preview` |
| 依赖 | `String`、`Map`、`List`（语言内建）；运行时 XML 名称/字符校验 |

---

## 1. 定位

可变的 XML 元素树节点：名称、属性表、子元素列表、可选文本。元素可独立构造，也可由 `Xml.parse*` 生成。

不做：命名空间解析、混合内容保序、父指针、文档节点、注释/处理指令、DTD/实体、XPath、序列化（由 `Xml.stringify*` 负责）。

---

## 2. 设计逻辑

- 构造器只接收名称；名称必须是非空、合法的 XML 1.0 Name。属性、子元素、文本初始为空。
- 节点可变；`setAttribute`/`addChild`/`setText` 修改当前节点并返回当前节点以便链式构造；`removeAttribute` 返回是否删除。
- 元素内容是二选一：有非空文本时不能有子元素；有子元素时不能有文本。`addChild` 与 `setText` 在冲突时 panic，不自动丢弃任何内容。
- 空文本等价于无文本：`setText(null)` 与 `setText("")` 都清空 `_text`。
- 属性名唯一；同名 `setAttribute` 覆盖值。属性顺序无语义，`attributes()` 返回快照，`Xml.stringify` 按名称排序。
- `children()` 返回列表快照，但子节点对象仍共享；需要独立树时用 `copy()`。
- `addChild` 拒绝 null 与自引用；模型不保存父指针，更深层的环由调用方保证不构造。`Xml.stringify` 用 `maxDepth` 终止环；`copy` 要求输入树无环，否则会无限递归。
- 名称中的冒号按普通字符保留，不做前缀绑定；`xmlns` 只是普通属性。
- 文本和属性值只做 XML 字符合法性校验；`<`、`&`、`>` 等由 `Xml.stringify` 转义，不在节点层拒绝。
- 无 close；引用语义；非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_name` | `String` | final | 非空；合法 XML Name；冒号按普通字符 |
| `_attributes` | `Map<String,String>` | 可变 | 名称唯一；key/value 非 null；key 合法 |
| `_children` | `List<XmlElement>` | 可变 | 子元素；不含 null；调用方保证无环 |
| `_text` | `String?` | 可变 | null 表示无文本；非 null 时不得有子元素 |

不变量：

- `_name` 构造后不变且非空；
- 属性 key 是合法 XML Name，value 是合法 XML 字符序列；
- `_text != null` 与 `_children` 非空互斥；
- 空文本规范化为 null；
- 调用方必须保持树无环、同一节点只挂一个父节点；API 只拒绝自引用，无法检测共享父节点；
- `describe` 不递归，不依赖树大小。

---

## 4. 生命周期

构造后长期可变；无 close、无资源、无外部句柄。`copy()` 产生独立深拷贝；快照方法（`attributes()`、`children()`）只复制容器，不复制节点。对象可被多个引用共享；释放由 GC 负责。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `XmlElement(String name)` | name | 非 null、非空、合法 XML Name | 非法 → panic |

构造后：属性空、子元素空、文本 null。名称不提供 setter；需要改名时构造新节点并迁移内容。

---

## 6. 字段表

见 §3；字段私有。只有 `_name` 是 final，另外三个字段通过 §7 的方法修改。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | 元素名 | 无 | `String` | 无 |
| `attributes` | 属性快照 | 无 | `Map<String,String>` | 无 |
| `attributeOrNull` | 读取单个属性 | `String name` | `String?` | null 名称 → panic |
| `setAttribute` | 新增/覆盖属性 | `String name, String value` | `XmlElement` | 非法名称/值 → panic |
| `removeAttribute` | 删除属性 | `String name` | `Bool` | null 名称 → panic |
| `children` | 子元素快照 | 无 | `List<XmlElement>` | 无 |
| `addChild` | 追加子元素 | `XmlElement child` | `XmlElement` | null/自引用/已有文本 → panic |
| `textOrNull` | 读取文本 | 无 | `String?` | 无 |
| `setText` | 设置/清除文本 | `String? value` | `XmlElement` | 已有子元素/非法字符 → panic |
| `copy` | 深拷贝 | 无 | `XmlElement` | 无（无环树前提） |
| `describe` | 紧凑摘要 | 无 | `String` | 无 |

说明：

- `attributes()` 返回新 `Map`；修改返回值不影响节点。值字符串不可变，无需深拷贝。
- `attributeOrNull` 只做查找；属性不存在返回 null。空名称不特殊处理，按普通 key 查找；null 名称 panic。
- `setAttribute` 的 name 必须非空且合法；value 非 null，字符必须满足 XML 1.0 Char。覆盖已有 key 时值替换，不改变集合语义；新 key 插入。
- `removeAttribute` 的 name 为 null 时 panic；不存在（包括空串）返回 `false`，存在删除并返回 `true`。
- `children()` 返回新 `List`；修改列表不影响节点。返回的子节点仍是原对象，修改子节点会影响原树。
- `addChild` 要求 child 非 null、不是当前节点；若当前节点已有非 null 文本（包括纯空白文本）则 panic。追加到末尾；同一 child 可被重复追加，调用方应避免把节点挂到两个父节点。
- `setText` 的 value 为 null 或空串时清空 `_text`。非空时：当前节点必须无子元素；字符必须合法；保存原字符串，不裁剪空白。
- `copy` 递归复制属性、文本和整棵子树；副本与原树不共享可变容器或节点。调用前必须保证树无环；有环会无限递归。深树受运行时调用栈限制，解析产生的树默认已被 `XmlOptions.maxDepth` 约束。
- `describe` 输出名称、属性数、子元素数和文本长度；不展开属性值或子树，不保证可解析。空文本显示 `none`。

---

## 8. 使用的技术

- 元素树/邻接表；
- 防御性容器复制；
- XML 1.0 Name/Char 校验；
- 递归深拷贝；
- 链式修改；
- 紧凑摘要。

---

## 9. 需要的支撑

- 语言：class、String、Map、List、Bool、Int；
- 运行时：`xmlNameIsValidRaw`、`xmlCharDataIsValidRaw`；
- 接口：无；不依赖 `Context`、`Error`、`Bytes`。

---

## 10. 依赖的特性/接口/类

`String`、`Map<String,String>`、`List<XmlElement>`、`Bool`、`Int`；XML 名称/字符校验原语。不依赖 `Xml` 或 `XmlOptions`，避免包内循环。

---

## 11. 所有权与并发

- 引用语义；节点拥有自己的属性表和子元素列表，但子节点对象可被外部引用。
- `attributes()`/`children()` 只提供浅快照；调用方不能通过快照容器增删节点，但能修改共享子节点。
- `copy()` 提供独立深拷贝；复制后两棵树互不影响。
- 非线程安全；并发读写或并发修改需外部同步。只读遍历可并发，前提是无写入。
- 无资源、无 close、无全局注册表。

---

## 12. 示例与反例

正确：

```xnull
XmlElement root = new XmlElement("config")
root.setAttribute("version", "1")
root.addChild(new XmlElement("name").setText("demo"))
String? version = root.attributeOrNull("version")
XmlElement independent = root.copy()
```

反例：先 `addChild` 再 `setText`（混合内容 panic）；修改 `attributes()` 返回值期望影响节点；把 `children()` 当深拷贝；期望冒号名称自动绑定命名空间；构造环或把同一节点挂到两个父节点；把 `describe()` 当 XML 解析；用 null/空名称构造；在有子元素时用非空 `setText`（混合内容 panic）；对含环的树调用 `copy`。

---

## 13. 测试/场景义务

合法/非法名称；空名称/null；冒号名称；Unicode 名称；属性新增/覆盖/删除/缺失；属性快照隔离；非法属性字符；子元素追加；自引用拒绝；有文本时 `addChild` panic；有子元素时 `setText` panic；空文本清空；文本合法/非法字符；`children()` 浅快照；`copy()` 深拷贝且互不影响；`describe()` 计数；null 参数；重复挂载同一 child 的文档化行为；无环树前提下的深层复制。

---

## 14. XNull 伪代码

```xnull
class XmlElement {
    final String _name
    Map<String, String> _attributes = [:]
    List<XmlElement> _children = []
    String? _text = null

    XmlElement(String name) {
        if name == null || name == "" {
            throw "XmlElement: empty name"
        }
        if !xmlNameIsValidRaw(name) {
            throw "XmlElement: invalid name"
        }
        _name = name
    }

    String name() { return _name }

    Map<String, String> attributes() { return _attributes.copy() }

    String? attributeOrNull(String name) {
        if name == null { throw "XmlElement.attributeOrNull: null name" }
        return _attributes.get(name)
    }

    XmlElement setAttribute(String name, String value) {
        if name == null || name == "" {
            throw "XmlElement.setAttribute: empty name"
        }
        if !xmlNameIsValidRaw(name) {
            throw "XmlElement.setAttribute: invalid name"
        }
        if value == null {
            throw "XmlElement.setAttribute: null value"
        }
        if !xmlCharDataIsValidRaw(value) {
            throw "XmlElement.setAttribute: invalid character"
        }
        _attributes.put(name, value)
        return self
    }

    Bool removeAttribute(String name) {
        if name == null {
            throw "XmlElement.removeAttribute: null name"
        }
        if !_attributes.has(name) { return false }
        _attributes.remove(name)
        return true
    }

    List<XmlElement> children() { return _children.copy() }

    XmlElement addChild(XmlElement child) {
        if child == null {
            throw "XmlElement.addChild: null child"
        }
        if child == self {
            throw "XmlElement.addChild: self cycle"
        }
        if _text != null {
            throw "XmlElement.addChild: element has text"
        }
        _children.push(child)
        return self
    }

    String? textOrNull() { return _text }

    XmlElement setText(String? value) {
        if value == null || value == "" {
            _text = null
            return self
        }
        if !_children.isEmpty() {
            throw "XmlElement.setText: element has children"
        }
        if !xmlCharDataIsValidRaw(value) {
            throw "XmlElement.setText: invalid character"
        }
        _text = value
        return self
    }

    XmlElement copy() {
        XmlElement clone = new XmlElement(_name)
        clone._attributes = _attributes.copy()
        clone._text = _text
        Int index = 0
        while index < _children.length() {
            clone._children.push(_children.get(index).copy())
            index = index + 1
        }
        return clone
    }

    String describe() {
        String textPart = "none"
        if _text != null {
            textPart = "len=" + str(_text.length())
        }
        return "XmlElement(name=" + _name
            + ", attributes=" + str(_attributes.length())
            + ", children=" + str(_children.length())
            + ", text=" + textPart + ")"
    }
}
```

> `xmlNameIsValidRaw`/`xmlCharDataIsValidRaw` 是运行时 XML 字符校验原语；不是 XDK 公共类型，不访问 IO。
