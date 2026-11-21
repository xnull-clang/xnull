# `Translator`

| 项 | 值 |
| --- | --- |
| 类型 | `class Translator` |
| 包 | `xdk.i18n` |
| 稳定性 | `preview` |
| 依赖 | `MessageCatalog`、`MessageFormatter`、`Locale`、`List`、`BasicError`、`ErrorKind` |

---

## 1. 定位

翻译门面：持有一个或多个 `MessageCatalog`，按 locale 选择活动目录，提供 `translate`/`translateWithArgs`，以及 `withLocale`/`withCatalog` 的不可变切换。

不做：全局翻译器、运行时语言协商、每键跨目录回退、翻译记忆库、热加载、复数/数字/日期规则本身。

---

## 2. 设计逻辑

- 字段 `_catalogs: List<MessageCatalog>`、`_active: MessageCatalog`、`_formatter: MessageFormatter`；不可变。
- 构造器只接受一个目录，复制后作为初始活动目录。
- `withCatalog` 复制新目录；同 locale 替换，不同 locale 追加；活动目录不变，除非替换的正是活动 locale。
- `withLocale` 按精确 locale → 同语言+国家（variant 空）→ 同语言（country/variant 空）→ root 的顺序找目录。
- 不做“同语言任意兄弟目录”回退；缺匹配返回 `NotFound`，保证结果确定。
- `translate` 只在活动目录查键；缺失返回 `NotFound`，不回显键、不查其他目录。
- `translateWithArgs` 查键后交给 `MessageFormatter.formatArgs`；占位符错误原样返回。
- 所有 `with*` 返回新实例；原实例不受影响。
- 没有全局翻译器/目录表。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_catalogs` | `List<MessageCatalog>` | 已注册目录，locale 唯一 |
| `_active` | `MessageCatalog` | 当前活动目录 |
| `_formatter` | `MessageFormatter` | 与活动 locale 绑定 |

不变量：`_active` 在 `_catalogs` 中；`_catalogs` 中 locale 不重复；`_formatter.locale()` 等于 `_active.locale()`；目录均为副本。

---

## 4. 生命周期

构造后不可变；无 close；`withLocale`/`withCatalog` 返回新实例；可共享；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Translator(MessageCatalog catalog)` | 目录 | 非 null | null → panic |
| `Translator(List<MessageCatalog>, MessageCatalog)` | 内部 | 非 null；active 在列表中 | 私有；非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `translate` | 查键 | `String key` | `Result<String, Error>` | `NotFound` |
| `translateWithArgs` | 查键并填参 | `String key, List<String> arguments` | `Result<String, Error>` | `NotFound`/`InvalidArgument` |
| `withLocale` | 切换 locale | `Locale locale` | `Result<Translator, Error>` | `NotFound` |
| `withCatalog` | 注册目录 | `MessageCatalog catalog` | `Translator` | null → panic |
| `catalog` | 活动目录副本 | 无 | `MessageCatalog` | 无 |
| `locale` | 活动 locale | 无 | `Locale` | 无 |

说明：

- `translate` 不解释占位符；含 `{0}` 的消息原样返回。
- `translateWithArgs` 的 `arguments` 是位置参数；缺失/非法占位符由 `MessageFormatter` 返回 `InvalidArgument`。
- `withLocale` 的精确匹配包含 variant；随后尝试同语言+国家且 variant 为空的目录；再尝试同语言且 country/variant 为空的目录；最后尝试 root。
- `withLocale` 不会选择同语言的任意国家目录；例如请求 `en-AU` 时，只有 `en-AU`、`en` 或 root 可匹配，`en-US` 不匹配。
- `withCatalog` 对同 locale 目录做替换；不同 locale 追加；不改变当前活动目录，除非替换的是活动 locale。
- `catalog` 返回 `copy`，调用方修改不影响翻译器。
- 缺失键是 `NotFound`，不是空串、不是键名、不是语言回退。

---

## 8. 使用的技术

- 目录列表与 locale 索引；
- 确定性回退链；
- 写时复制（copy-on-write）；
- 目录/格式化器组合；
- Result 错误传播。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Int、Result、List；
- 运行时：无；
- 接口：`Locale`、`MessageCatalog`、`MessageFormatter`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Locale`、`MessageCatalog`、`MessageFormatter`、`List<MessageCatalog>`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

不可变；引用语义；可跨任务共享；目录在构造/`withCatalog` 时复制；`translate`/`translateWithArgs` 只读；无资源。

---

## 12. 示例与反例

正确：`new Translator(enUsCatalog).translate("welcome")`。  
正确：`translator.withCatalog(frCatalog).withLocale(Locale.parse("fr").value()).value().translate("welcome")`。  
正确：`translateWithArgs("files", ["3"])` 填充 `{0}`。  
反例：缺失键期望回显 key；期望自动从 `en-US` 回退到 `en-GB`；`withLocale` 失败后期望沿用旧 locale；直接修改 `catalog()` 返回值期望影响翻译器；用全局翻译器；在 `translate` 里自动格式化占位符。

---

## 13. 测试/场景义务

构造/复制；translate 命中/缺失/空值；translateWithArgs 命中/缺失键/缺参/非法占位符；withCatalog 同 locale 替换/不同 locale 追加/替换活动目录/原实例不变；withLocale 精确/国家回退/语言回退/root/无匹配/变体；catalog 副本独立性；locale；并发只读；目录 locale 唯一性。

---

## 14. XNull 伪代码

```xnull
class Translator {
    final List<MessageCatalog> _catalogs
    final MessageCatalog _active
    final MessageFormatter _formatter

    Translator(MessageCatalog catalog) {
        if catalog == null {
            throw "Translator: null catalog"
        }
        MessageCatalog copied = catalog.copy()
        List<MessageCatalog> catalogs = []
        catalogs.push(copied)
        _catalogs = catalogs
        _active = copied
        _formatter = new MessageFormatter(copied.locale())
    }

    private Translator(List<MessageCatalog> catalogs, MessageCatalog active) {
        if catalogs == null || active == null {
            throw "Translator: null argument"
        }
        _catalogs = catalogs.copy()
        _active = active
        _formatter = new MessageFormatter(active.locale())
    }

    Result<String, Error> translate(String key) {
        if key == null {
            throw "Translator.translate: null key"
        }
        return _active.get(key)
    }

    Result<String, Error> translateWithArgs(String key, List<String> arguments) {
        if key == null || arguments == null {
            throw "Translator.translateWithArgs: null argument"
        }
        Result<String, Error> template = _active.get(key)
        if template.isErr() {
            return Err(new BasicError(ErrorKind.NotFound, "missing message: " + key))
        }
        return _formatter.formatArgs(template.value(), arguments)
    }

    Result<Translator, Error> withLocale(Locale locale) {
        if locale == null {
            throw "Translator.withLocale: null locale"
        }
        Int index = 0
        while index < _catalogs.length() {
            MessageCatalog candidate = _catalogs.get(index)
            if candidate.locale().equals(locale) {
                return Ok(new Translator(_catalogs, candidate))
            }
            index = index + 1
        }
        if locale.country() != "" {
            index = 0
            while index < _catalogs.length() {
                MessageCatalog candidate = _catalogs.get(index)
                Locale candidateLocale = candidate.locale()
                if candidateLocale.language() == locale.language()
                    && candidateLocale.country() == locale.country()
                    && candidateLocale.variant() == "" {
                    return Ok(new Translator(_catalogs, candidate))
                }
                index = index + 1
            }
        }
        index = 0
        while index < _catalogs.length() {
            MessageCatalog candidate = _catalogs.get(index)
            Locale candidateLocale = candidate.locale()
            if candidateLocale.language() == locale.language()
                && candidateLocale.country() == ""
                && candidateLocale.variant() == "" {
                return Ok(new Translator(_catalogs, candidate))
            }
            index = index + 1
        }
        index = 0
        while index < _catalogs.length() {
            MessageCatalog candidate = _catalogs.get(index)
            if candidate.locale().isRoot() {
                return Ok(new Translator(_catalogs, candidate))
            }
            index = index + 1
        }
        return Err(new BasicError(ErrorKind.NotFound,
            "no catalog for locale: " + locale.toString()))
    }

    Translator withCatalog(MessageCatalog catalog) {
        if catalog == null {
            throw "Translator.withCatalog: null catalog"
        }
        MessageCatalog copied = catalog.copy()
        List<MessageCatalog> updated = []
        Bool replaced = false
        Int index = 0
        while index < _catalogs.length() {
            MessageCatalog current = _catalogs.get(index)
            if current.locale().equals(copied.locale()) {
                updated.push(copied)
                replaced = true
            } else {
                updated.push(current)
            }
            index = index + 1
        }
        if !replaced {
            updated.push(copied)
        }
        MessageCatalog active = _active
        if _active.locale().equals(copied.locale()) {
            active = copied
        }
        return new Translator(updated, active)
    }

    MessageCatalog catalog() {
        return _active.copy()
    }

    Locale locale() {
        return _active.locale()
    }
}
```
