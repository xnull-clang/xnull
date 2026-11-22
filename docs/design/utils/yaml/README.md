# `xdk.yaml` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.yaml` |
| 层 | L4 数据/编码（文档分组 `utils/`） |
| 依赖 | `xdk.errors`、`xdk.codec`（`JsonValue`/`JsonObject`/`JsonArray`/`JsonNumber`） |
| 被依赖 | 配置加载、Spring Boot 风格多文档配置、CI/部署文件、应用 |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

Spring Boot 级 YAML 解析/生成，值树复用 [`xdk.codec`](../codec/README.md)：

- YAML 1.1/1.2 文档 → `JsonValue`；
- 多文档流 `---` → `YamlDocument` 列表；
- 锚点/别名/合并键 `<<`；
- 按配置键提取 profile 文档（默认键可配置，Spring Boot 用 `spring.config.activate.on-profile`）；
- 属性扁平化 → `YamlPropertySource`（`server.port`、`list[0].name`）；
- 生成单文档/多文档 YAML。

不做：对象绑定/反射、`${...}` 占位符解析（保留字符串，由 config/Environment 层解析）、Schema 校验、注释/格式保留、文件 IO、流式 Reader、Spring `@ConfigurationProperties` 绑定。

本包是 YAML 与 codec 值树/属性源之间的适配层，不是完整 Spring 容器。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 复用值树 | 不新增 YAML 节点类型；对象/数组/标量直接用 codec 类型 |
| Spring Boot 兼容面 | 多文档、profiles、锚点/别名、合并键、属性扁平化、YAML 1.1 布尔 |
| 严格解析 | 语法错误、重复键、别名环、超限 → 明确错误 |
| 资源有界 | `maxDepth`/`maxBytes`/`maxDocuments`/`maxAliases` |
| 安全默认 | 拒绝重复键；锚点/别名有数量上限；不解析外部实体/自定义构造函数 |
| 输出确定 | 固定缩进、键顺序、字符串 quoting；不保留注释/空行 |
| 占位符不猜 | `${...}` 原样保留，由上层解析，避免 YAML 层依赖 Environment |
| 无全局/无 IO | 静态无状态；无全局 parser/registry；不读文件 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `YamlVersion` | enum | YAML 1.1 / 1.2 | [`YamlVersion.md`](YamlVersion.md) |
| `YamlOptions` | class | 版本/预算/锚点/合并键/profile 键 | [`YamlOptions.md`](YamlOptions.md) |
| `YamlDocument` | class | 文档索引/值树/profiles | [`YamlDocument.md`](YamlDocument.md) |
| `YamlPropertySource` | class | 扁平属性源/文档元数据 | [`YamlPropertySource.md`](YamlPropertySource.md) |
| `Yaml` | class | 解析/多文档/属性源/生成 | [`Yaml.md`](Yaml.md) |

共 5/5 个类型文件；README 索引与文件一一对应。

X：完整 YAML 1.1 canonical equality、复杂键、`!!timestamp`/`!!binary` 保真、profile 表达式 `&`/`|`、占位符解析、流式 Reader、Schema。

---

## 4. 顶层函数

无；解析/生成使用静态入口 `Yaml`，选项使用 `YamlOptions`。

---

## 5. 技术/支撑/依赖

- 技术：YAML 1.1/1.2、多文档、锚点表/别名、合并键、属性扁平化、profile 提取、确定性 quoting。
- 支撑：`parseYamlAllRaw`、`formatYamlRaw`、`toUtf8`、`toLong`。
- 依赖：`xdk.errors`（`Error`/`BasicError`/`ErrorKind`）、`xdk.codec`（值树与数字）。
- 不依赖：第三方 YAML 库、全局 parser、文件系统、Spring 容器。

---

## 6. 场景

### Y1：Spring Boot 风格 application.yml

```yaml
server:
  port: 8080
---
spring:
  config:
    activate:
      on-profile: prod
server:
  port: 9090
```

`Yaml.parsePropertySources("application.yml", text, options.profileKey("spring.config.activate.on-profile"))` 返回两个属性源：第二个带 `prod` profile。

### Y2：锚点/合并键

```yaml
defaults: &defaults
  timeout: 30
  retries: 3
service:
  <<: *defaults
  timeout: 60
```

`Yaml.parse` 生成合并后的对象；`allowMergeKeys(false)` 时 `<<` 作为普通键还是拒绝，由实现明确（ 选择拒绝）。

### Y3：多文档

`Yaml.parseAll(text)` 返回 `List<YamlDocument>`；`Yaml.parse` 只接受恰好一个文档。

### Y4：属性扁平化

嵌套映射 → `a.b.c`；序列 → `list[0].name`；null → 空字符串；空容器不产生属性。

### Y5：生成

`Yaml.stringify(value)` 单文档；`Yaml.stringifyAll(documents)` 用 `---` 分隔。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 多文档 | 支持；`maxDocuments` 限制；`parse` 要求恰好一个 |
| profiles | 由可配置 `profileKey` 提取；无键 → 始终激活；简单 `!name` 支持；`&`/`|` X |
| 锚点/别名 | 默认开启；`maxAliases` 限制；拒绝前向引用/环 |
| 合并键 `<<` | 默认开启；`allowMergeKeys(false)` 时拒绝 |
| YAML 1.1 bool | `yes/no/on/off` 在 `Yaml11` 下按 bool；`Yaml12` 下按 string |
| 时间戳/二进制标签 | 映射为字符串；保真类型 X |
| 重复键 | 默认拒绝；`allowDuplicateKeys(true)` 后者覆盖 |
| 属性扁平化 | 映射点号、序列下标；复杂键转义/`[key]` X |
| 占位符 `${...}` | 保留字符串，不解析 |
| 注释/格式 | 不做 |
| Spring 绑定 | 不做；由 config/应用层完成 |

---

## 8. 依赖与顺序

```text
xdk.errors / xdk.codec
  └─ xdk.yaml
       ├─ 配置加载
       ├─ Spring Boot 风格多文档属性源
       ├─ CI/部署工具
       └─ 应用
```

规则：

- 只依赖 `xdk.errors` 与 `xdk.codec`；不依赖 `fs`/`io`/`net`/Spring。
- `codec` 不反向依赖本包；YAML/TOML/XML 各自独立。
- 调用方读取文本并完成 UTF-8 解码；本包不读取文件、不建立全局 parser。

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | `@YamlName` |
| 本包消费 | `@Value`、`@Builder`、`@Serializable` |
| 处理器 | YamlAnnotationProcessor（Validate/Generate） |
| 生成物 | YAML 字段名映射、文档元数据 |
| 状态 | 领域注解 planned；A8 派生 implemented（含限制）；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| DTO 字段 | `@YamlName` | 字段名映射 |
| `YamlDocument`/`YamlOptions`/`YamlPropertySource` | `@Value`/`@Builder` | 值语义/选项 |

### 声明

```x
@Target(Field)
@Retention(Source)
@annotation YamlName {
    final String value
}
```

声明文件：每个注解单独一个 PascalCase 文件；处理器为构建期类型；生成代码在 `<package>/generated/`。

### 使用

```x
@Serializable
class ServiceConfig {
    @YamlName("service_name") String name
}
```

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
