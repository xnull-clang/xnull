# `xdk.i18n` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.i18n` |
| 层 | L7 应用服务（文档分组 `utils/`） |
| 依赖 | `xdk.errors`、`xdk.text`、`xdk.collections`、`xdk.io`、`xdk.bytes`、`xdk.fs`、`xdk.time`、`xdk.math`、`xdk.execution` |
| 被依赖 | 应用、CLI、HTTP 错误消息、配置校验消息 |
| 类型数 | 7 |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

`xdk.i18n` 提供显式 locale 驱动的消息目录、模板格式化、复数选择、数字/日期本地化：

- `Locale`：language/country/variant 值对象；
- `MessageCatalog`：单 locale 的键值目录，支持文件/Reader 加载；
- `MessageFormatter`：命名/位置占位符、plural、select；
- `PluralRules`：CLDR 子集的复数类别；
- `NumberFormat`：locale 分隔符 + 模式；
- `DateFormat`：locale 日期模式 + 固定偏移时区；
- `Translator`：目录选择与翻译入口。

不做：

- 全局默认 locale、全局目录、全局翻译器；
- 完整 CLDR 数据、脚本子标签、BCP 47 扩展、文本方向、排序/断词；
- ICU MessageFormat 语法、货币/百分比/科学计数法格式化；
- 运行时下载语言包、热更新目录、翻译管理平台；
- 分布式/跨进程缓存。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 显式 locale | 每个格式化器/目录/翻译器都持有一个 `Locale`；不读取进程默认 locale |
| 无全局状态 | 无全局目录表、无全局 pattern 注册表、无全局翻译器 |
| 严格失败 | 缺失键、缺失占位符、非法模式一律 `Result` 错误，不静默替换为空串 |
| 目录隔离 | 一个 `MessageCatalog` 只属于一个 locale；跨 locale 合并被拒绝 |
| 解析与格式分离 | `parse`/`format` 都是显式方法；构造期校验模式，运行期返回 `Result` |
| 资源明确 | 文件加载在内部关闭文件；Reader 由调用方关闭 |
| 可复制 | 目录与翻译器支持 `copy`/`with*`，避免共享可变状态 |
| XNull 形态 | 只使用 class/enum/泛型 class，不引入泛型协议或泛型枚举 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `Locale` | class | 语言/国家/变体、解析、规范化 | [`Locale.md`](Locale.md) |
| `MessageCatalog` | class | 单 locale 键值目录、加载、合并 | [`MessageCatalog.md`](MessageCatalog.md) |
| `MessageFormatter` | class | 占位符、plural、select | [`MessageFormatter.md`](MessageFormatter.md) |
| `PluralRules` | class | 复数类别与形式选择 | [`PluralRules.md`](PluralRules.md) |
| `NumberFormat` | class | 数字格式化/解析、分组/小数分隔符 | [`NumberFormat.md`](NumberFormat.md) |
| `DateFormat` | class | 日期格式化/解析、locale 模式、时区 | [`DateFormat.md`](DateFormat.md) |
| `Translator` | class | 目录选择、翻译、带参数翻译 | [`Translator.md`](Translator.md) |

X：完整 CLDR 复数/日期/数字规则、脚本子标签、BCP 47 扩展、IANA tzdb/DST、ICU MessageFormat、货币/百分比、文本方向、排序规则、翻译包热加载。

---

## 4. 顶层函数

无；所有入口都是类型上的静态工厂或实例方法。

---

## 5. 技术/支撑/依赖

- 技术：BCP 47 子集解析、属性文件解析、占位符扫描、CLDR 复数子集、模式驱动的数字/日期格式化、固定偏移时区换算。
- 支撑：`trim`/`split`/`replaceAll`/`toLower`/`toUpper`/`parseInt`/`parseDouble`/`utf8ToUtf16`、`BytesBuilder`、`File`/`OpenOptions`、`DateTimeFormatter`、`Decimal`/`RoundingMode`、`Context`。
- 依赖：`errors`、`text`、`collections`、`io`、`bytes`、`fs`、`time`、`math`、`xdk.execution`。

---

## 6. 场景

### I1：显式 locale 的消息

应用从请求/配置得到语言标签，`Locale.parse("en-us")` 得到 `en-US`；加载 `en-US` 目录；`Translator.translate("welcome")`。

### I2：属性文件目录

`MessageCatalog.load(context, locale, new Path("i18n/messages.properties"))`；UTF-8、`key=value`、注释、转义；重复键报错。

### I3：复数消息

`PluralRules.select(count, ["one": "{0} file", "other": "{0} files"])`；`MessageFormatter.formatArgs` 填充位置参数。

### I4：数字/日期显示

`NumberFormat.ofPattern(locale, "#,##0.00").format(12345.678)`；`DateFormat.ofStyle(locale, "date", TimeZone.fixed(8 * 3600000)).value().format(dateTime)`。

### I5：多目录回退

`Translator.withCatalog(frCatalog)` 注册多个 locale；`withLocale(fr)` 精确/语言回退选择；无匹配目录返回 `NotFound`。

### I6：缺失显式

缺失键、缺失占位符、缺失 `other` 复数形式都返回错误；调用方决定显示错误、回退键或跳过。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 全局默认 locale | 禁止；调用方必须显式传入 `Locale` |
| 完整 CLDR | X； 只支持文档化子集 |
| 脚本子标签 | 不支持；`zh-Hans` 等返回 `InvalidArgument` |
| BCP 47 扩展/私有段 | 不支持；超过三个子标签返回 `InvalidArgument` |
| 复数类别 | `zero/one/two/few/many/other` 字符串；不新增 enum |
| 复数规则 | 英语型、法语型、俄语/乌克兰语型、other-only；未知语言按英语型 |
| 日期月份名 | 不支持；只做数字模式；本地化名称 X |
| 时区 | 只支持 `TimeZone` 固定偏移；DST/tzdb X |
| 数字货币/百分比 | 不支持；X |
| 数字舍入 | 固定 `HalfUp`；可配置舍入 X |
| 数字解析 | 返回 `Double`；精确金额用 `Decimal`，但本包不提供 Decimal 解析 |
| 缺失占位符 | 严格 `InvalidArgument`，不保留原样、不替换空串 |
| 缺失翻译键 | `NotFound`，不回显键、不自动回退到其他目录 |
| ICU MessageFormat | 不支持 `{count, plural, ...}` 内联语法；用显式 `plural`/`select` |
| 目录线程安全 | 可变目录非线程安全；构造完成后只读共享；`Translator` 构造时复制 |
| 文件编码 | 固定 UTF-8；BOM 可跳过；非法 UTF-8 `DataCorrupted` |
