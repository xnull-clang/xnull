# Annotation IR v1

| 项 | 值 |
| --- | --- |
| 版本 | `irVersion = 2`（兼容 v1；v1 无 `symbols`） |
| 入口 | `mini --dump-annotations <entry.x> --xdk-root <root>` |
| 构建时机 | `splitTypeUseAnnotations` / `resolveAnnotationUses` 之后，A8 展开与 `Mono` 之前 |
| 处理器协议 | [`ANNOTATION-PROCESSOR-MANIFEST.md`](ANNOTATION-PROCESSOR-MANIFEST.md) |
| 边界 | IR 只读快照；不依赖 Mono 克隆节点；不生成源码、不运行处理器 |
| 权威 | [`ANNOTATION-PLATFORM-PLAN.md`](ANNOTATION-PLATFORM-PLAN.md) P0-01/P0-02 |

## 1. 顶层 JSON

字段顺序固定：

```json
{
  "irVersion": 2,
  "declarations": [],
  "uses": [],
  "symbols": {"types": []}
}
```

- `declarations`：源码中 `@annotation` 声明，按源码顺序。
- `uses`：源码中所有注解使用，按遍历顺序。
- `symbols.types`：源码类型声明（Class/Struct/Enum/Protocol/Annotation），按源码顺序；不含 Mono 实例化重复类型。
- 空集合稳定输出 `[]`；不输出时间、随机数、绝对路径或哈希遍历顺序。
- v1 消费者仍可读取；v1 没有 `symbols`。

## 2. Declaration

```json
{
  "fullName": "app.Audit",
  "package": "app",
  "simpleName": "Audit",
  "targets": ["Type", "Field"],
  "retention": "Runtime",
  "repeatable": true,
  "fields": [],
  "line": 12,
  "col": 1,
  "owner": "app",
  "irVersion": 2
}
```

Field：

```json
{
  "name": "level",
  "type": "Int",
  "required": false,
  "default": {"kind": "int", "text": "1", "children": []}
}
```

## 3. Use

```json
{
  "name": "Audit",
  "resolvedName": "app.Audit",
  "target": "Type",
  "targetName": "app.Device",
  "arguments": [],
  "line": 24,
  "col": 1,
  "repeatIndex": 1
}
```

Target kind：`Package/Type/Annotation/TypeParameter/Field/Method/Constructor/Deinit/Parameter/TypeUse/EnumItem`。

`repeatIndex` 从 1 开始，只在同一 owner 的同一注解名内递增。

## 4. Value

| kind | text | children |
| --- | --- | --- |
| `bool` | `true`/`false` | `[]` |
| `int`/`long`/`float`/`double` | 数值文本 | `[]` |
| `char`/`string` | 去除源码引号后的文本 | `[]` |
| `enum` | 枚举成员路径 | `[]` |
| `type` | 类型引用路径 | `[]` |
| `array` | `""` | 元素值 |
| `annotation` | 简单注解名 | 位置参数值 |
| `null` | `""` | `[]` |

## 5. 确定性规则

- JSON 字段顺序由 schema 固定，不按 Map 遍历顺序输出。
- 字符串按 JSON 转义：`\\`、`\"`、`\n`、`\r`、`\t`。
- 不输出文件绝对路径；只输出源码位置 `line`/`col`。
- 同一输入、同一 xdk root、同一编译器版本产生相同字节。
- 失败时 exit 非零，诊断写 stderr；成功只写 stdout。
- `--dump-annotations` 不改变 `--emit-c`/`--sema` 行为。

## 6. Builtin Registry

内建注解由 `builtinDescriptors()` 数据驱动，`AnnotationChecker.initBuiltins()` 只遍历 descriptor：

| 字段 | 含义 |
| --- | --- |
| `name` | 内建名 |
| `targets` | 目标列表 |
| `retention` | 当前均为 `Binary` |
| `repeatable` | 是否可重复 |
| `handler` | 后续处理器 id（本批只存 id，不调度） |

当前 descriptor：`Target`、`Retention`、`Repeatable`、`Deprecated`、`SuppressWarnings`、`ReadOnly`、`WriteOnly`、`Override`、`MustUse`。新增内建应先加 descriptor + handler，不在 `initBuiltins` 散落分支。

## 7. 版本规则

- 不兼容变更必须升 `irVersion`。
- 新增可选字段不升版本，但必须在本文档登记字段顺序。
- 删除/改义字段、改 target 字符串、改值 kind 字符串属于不兼容变更。
- 消费者必须拒绝未知 major 版本；当前只接受 `1`。


## 8. IR v2 symbols（M0.6）

类型符号：

```json
{
  "kind": "Class",
  "fullName": "app.Widget",
  "package": "app",
  "simpleName": "Widget",
  "typeParams": ["T"],
  "base": "app.Base",
  "implements": ["app.Ready"],
  "fields": [
    {"name":"_name","type":"String","final":false,"static":false,"visibility":"unknown","line":1,"col":1}
  ],
  "methods": [
    {"name":"start","return":"Bool","params":[{"name":"x","type":"Int"}],
     "static":false,"visibility":"unknown","line":1,"col":1}
  ],
  "ctors": [{"params":[{"name":"name","type":"String"}],"visibility":"unknown","line":1,"col":1}],
  "enumItems": ["A","B"],
  "line": 1,
  "col": 1
}
```

规则：

- 类型 kind：`Class/Struct/Enum/Protocol/Annotation`；源码无 Singleton/Factory/Extension 节点。
- 字段/方法/构造器保留源码顺序；不输出方法体/表达式/初始值。
- `final` 用 `isFinalField`；`static` 用 `Static` 标记。
- visibility 当前 AST 不保留，统一 `"unknown"`，不伪造 `public`。
- 用户类型名按包限定；内置标量保持原名；泛型参数保留名称，不展开。
- 同一输入两次 dump 字节一致。
- 平台 v1/v2 都能读取；v1 没有 symbols。
