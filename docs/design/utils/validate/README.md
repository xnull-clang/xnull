# `xdk.validate` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.validate` |
| 层 | L7 应用服务（文档分组 `utils/`） |
| 依赖 | `xdk.errors`、`xdk.text`、`xdk.codec`、`xdk.collections` |
| 被依赖 | 应用、HTTP 请求校验、配置边界 |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

对 `JsonValue` 树做规则/字段/Schema 校验：必填、类型、长度、范围、模式、数组元素、组合规则、错误路径聚合。

不替代 `xdk.config.ConfigSchema`：配置来源加载仍走 `xdk.config`；本包面向 JSON/HTTP/表单/嵌套对象。

不做：JSON Schema 标准全集（X）、ORM、异步规则、消息国际化（X）、泛型协议。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 非泛型协议 | XNull 禁止泛型协议；`Validator` 固定操作 `JsonValue` |
| 错误聚合 | 默认收集全部字段错误；`failFast` 可选 |
| 路径明确 | 错误包含点/下标路径，如 `user.name`、`items[0]` |
| 不抛业务异常 | 无效数据通过 `ValidationContext.addError` 表达 |
| 无全局 | 无全局规则注册表/消息表 |
| 组合优先 | `Rule` 单规则；`Rules` 工厂；`Schema` 嵌套对象 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `Validator` | protocol | 校验协议 | [`Validator.md`](Validator.md) |
| `ValidationError` | class | 路径/码/消息 | [`ValidationError.md`](ValidationError.md) |
| `ValidationContext` | class | 路径/错误收集/failFast | [`ValidationContext.md`](ValidationContext.md) |
| `ValidationResult` | class | 结果/聚合/转 Result | [`ValidationResult.md`](ValidationResult.md) |
| `Rule` | class | 单规则实现 | [`Rule.md`](Rule.md) |
| `Rules` | class | 常用规则工厂 | [`Rules.md`](Rules.md) |
| `FieldRule` | class | 字段名/校验器/必填 | [`FieldRule.md`](FieldRule.md) |
| `Schema` | class | 对象字段 Schema | [`Schema.md`](Schema.md) |

X：JSON Schema 导入/导出、i18n 消息、异步/远程规则、错误码注册表。

---

## 4. 顶层函数

无；规则通过 `Rules` 静态工厂构造。

---

## 5. 技术/支撑/依赖

- 技术：规则组合、路径栈、错误聚合、JsonValue 类型检查、正则。
- 支撑：`JsonValue`/`JsonObject`/`JsonArray`/`JsonNumber`、`Regex`、`BasicError`。
- 依赖：`errors`、`text`、`codec`、`collections`。

---

## 6. 场景

### V1：请求体

`Schema` 定义 `name`/`age`/`email`；`validateValue(json)` 返回全部字段错误。

### V2：数组元素

`Rules.arrayOf(Rules.string().minLength?)`；错误路径 `items[2]`。

### V3：组合

`Rules.all([...])` 顺序执行；`Rules.any([...])` 至少一个通过；`Rules.not(...)` 取反。

### V4：快速失败

`new Schema(true)` 或 `new ValidationContext(true)`；首个错误后停止。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 泛型 Validator | 禁止；固定 `JsonValue` |
| 配置 Schema | 复用 `xdk.config`，不迁移 |
| JSON Schema | X |
| 跨字段规则 | 用 `Rules.custom` 捕获整体对象；专用 DSL X |
| 消息 i18n | X；当前 code + message |
| 线程安全 | 校验上下文非线程安全；Schema 构建后只读 |

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | `@Validate`、`@Min`、`@Max`、`@Pattern`、`@Email` |
| 本包消费 | `@Value`、`@Builder` |
| 处理器 | ValidateAnnotationProcessor（Validate/Generate） |
| 生成物 | 校验器、字段规则、错误路径 |
| 状态 | `@Validate`/`@Min`/`@Max`/`@Pattern`/`@Email` implemented (M4.2/M4.3)；A8 派生 implemented（含限制） |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 表单/请求类型 | `@Validate` | 校验入口 |
| 数值字段/参数 | `@Min`/`@Max` | 范围规则 |
| 字符串字段/参数 | `@Pattern`/`@Email` | 格式规则 |
| `ValidationError`/`ValidationResult`/`FieldRule` | `@Value`/`@Builder` | 值语义/规则构造 |

### 声明

```x
@Target(Type)
@Retention(Source)
@annotation Validate {
}

@Target(Field)
@Retention(Source)
@annotation Min {
    final Long value
}

@Target(Field)
@Retention(Source)
@annotation Max {
    final Long value
}

@Target(Field)
@Retention(Source)
@annotation Pattern {
    final String value
}

@Target(Field, Parameter)
@Retention(Source)
@annotation Email {
}
```

声明文件：每个注解单独一个 PascalCase 文件；处理器为构建期类型；生成代码在 `<package>/generated/`。

### 使用

```x
@Validate
class SignupForm {
    @Email String email
    @Min(18) @Max(120) Int age
    @Pattern("^[a-z0-9_]+$") String handle
}
```

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
