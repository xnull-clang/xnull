# `Regex`

| 项 | 值 |
| --- | --- |
| 类型 | `class Regex` |
| 包 | `xdk.text` |
| 稳定性 | `preview` |
| 依赖 | `RegexOptions`、`Match`、`errors` |

---

## 1. 定位

编译后的正则：匹配、查找、替换、切分、捕获组/命名组。

不做：完整 PCRE/ICU、流式匹配、跨行文本数据库。

---

## 2. 设计逻辑

- `compile` 失败返回 `InvalidArgument`，不 panic。
- 不可变；无 close；可跨任务共享。
- 索引是字节索引；调用方需保证 UTF-8 边界。
- `findAll` 跳过空匹配并前进 1 字节，避免死循环。
- `replaceAllWith` 是 X；调用方回调返回替换文本。
- 引擎是内部依赖；不暴露 AST。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_pattern` | `String` | 原始 pattern |
| `_options` | `RegexOptions` | 选项 |
| `_engine` | 引擎句柄 | 内部编译结果 |

不变量：pattern/options 非 null；engine 已编译；不可变；线程安全只读。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

构造器内部；公共入口 `Regex.compile`。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `compile` | 默认选项编译 | `String pattern` | `Result<Regex, Error>` | `InvalidArgument` |
| `compile` | 带选项编译 | `String pattern, RegexOptions options` | `Result<Regex, Error>` | `InvalidArgument` |
| `isMatch` | 是否匹配 | `String text` | `Bool` | 无 |
| `find` | 首个匹配 | `String text` | `Match?` | 无 |
| `findFirst` | 首个匹配 | `String text` | `Match?` | 无 |
| `findAll` | 全部匹配 | `String text` | `List<Match>` | 无 |
| `matchAll` | 全部匹配 | `String text` | `List<Match>` | 无 |
| `replaceAll` | 全部替换 | `String text, String replacement` | `String` | 无 |
| `replaceFirst` | 首个替换 | 同上 | `String` | 无 |
| `replaceAllWith` | 回调替换 | `String text, String(Match) replacement` | `String` | null callback → panic |
| `split` | 切分 | `String text` | `List<String>` | 无 |
| `splitLimit` | 限制切分 | `String text, Int limit` | `List<String>` | limit ≤0 → panic |
| `groupCount` | 捕获组数 | 无 | `Int` | 无 |
| `namedGroups` | 命名组名 | 无 | `List<String>` | 无 |
| `pattern` | 原始 pattern | 无 | `String` | 无 |
| `options` | 选项 | 无 | `RegexOptions` | 无 |
| `escape` | 转义元字符 | `String text` | `String` | 无 |

---

## 8. 使用的技术

- 正则编译/AST 或 NFA；
- 捕获组；
- 命名组；
- 空匹配前进；
- 替换回调/字面量；
- 切分。

---

## 9. 需要的支撑

- 语言：class、String、Int、Bool、List、Result；
- 运行时/引擎：正则编译、匹配、捕获组；
- 接口：`RegexOptions`、`Match`、`BasicError`、`ErrorKind`、`StringBuilder`。

---

## 10. 依赖的特性/接口/类

`RegexOptions`、`Match`、`BasicError`、`ErrorKind`、`StringBuilder`。

---

## 11. 所有权与并发

不可变；可共享；`Match` 快照；无资源。

---

## 12. 示例与反例

正确：`Regex.compile("a+").findAll("aa b a")`；`replaceAll` 字面量替换。  
反例：编译失败期望 panic；用字节索引切 UTF-8 中间；空匹配不前进导致死循环。

---

## 13. 测试/场景义务

编译成功/失败；匹配/查找/全部；空匹配；捕获组/命名组；替换/切分；选项；转义；大文本。

---

## 14. XNull 伪代码

```xnull
class Regex {
    String _pattern
    RegexOptions _options
    RegexEngine _engine

    Regex(String pattern, RegexOptions options, RegexEngine engine) {
        _pattern = pattern
        _options = options
        _engine = engine
    }

    static Result<Regex, Error> compile(String pattern) {
        return Regex.compile(pattern, new RegexOptions())
    }

    static Result<Regex, Error> compile(String pattern, RegexOptions options) {
        if pattern == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "null pattern"))
        }
        if options == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "null options"))
        }
        Result<RegexEngine, Error> compiled = regexEngineCompile(pattern, options)
        if compiled.isErr() {
            return Err(compiled.error())
        }
        return Ok(new Regex(pattern, options, compiled.value()))
    }

    Bool isMatch(String text) {
        return regexEngineFind(_engine, text, 0) != null
    }

    Match? find(String text) {
        return regexEngineFind(_engine, text, 0)
    }

    Match? findFirst(String text) {
        return self.find(text)
    }

    List<Match> findAll(String text) {
        List<Match> result = []
        Int start = 0
        while start <= text.length() {
            Match? match = regexEngineFind(_engine, text, start)
            if match == null {
                break
            }
            result.push(match)
            if match.length() == 0 {
                start = match.end() + 1
            } else {
                start = match.end()
            }
        }
        return result
    }

    List<Match> matchAll(String text) {
        return self.findAll(text)
    }

    String replaceAll(String text, String replacement) {
        List<Match> matches = self.findAll(text)
        String result = ""
        Int position = 0
        Int index = 0
        while index < matches.length() {
            Match match = matches.get(index)
            result = result + text.substring(position, match.start() - position)
            result = result + replacement
            position = match.end()
            index = index + 1
        }
        result = result + text.substring(position, text.length() - position)
        return result
    }

    String replaceFirst(String text, String replacement) {
        Match? match = self.find(text)
        if match == null {
            return text
        }
        return text.substring(0, match.start())
            + replacement
            + text.substring(match.end(), text.length() - match.end())
    }

    String replaceAllWith(String text, String(Match) replacement) {
        if replacement == null {
            throw "Regex.replaceAllWith: null callback"
        }
        List<Match> matches = self.findAll(text)
        String result = ""
        Int position = 0
        Int index = 0
        while index < matches.length() {
            Match match = matches.get(index)
            result = result + text.substring(position, match.start() - position)
            result = result + replacement(match)
            position = match.end()
            index = index + 1
        }
        result = result + text.substring(position, text.length() - position)
        return result
    }

    List<String> split(String text) {
        return self.splitLimit(text, 0)
    }

    List<String> splitLimit(String text, Int limit) {
        if limit < 0 {
            throw "Regex.splitLimit: negative limit"
        }
        List<String> result = []
        Int position = 0
        Int start = 0
        while position < text.length() {
            Match? match = regexEngineFind(_engine, text, position)
            if match == null {
                break
            }
            if match.length() == 0 {
                position = position + 1
            } else {
                result.push(text.substring(start, match.start() - start))
                position = match.end()
                start = position
                if limit > 0 && result.length() >= limit - 1 {
                    break
                }
            }
        }
        result.push(text.substring(start, text.length() - start))
        return result
    }

    Int groupCount() {
        return regexEngineGroupCount(_engine)
    }

    List<String> namedGroups() {
        return regexEngineNamedGroups(_engine)
    }

    String pattern() { return _pattern }
    RegexOptions options() { return _options }

    String escape(String text) {
        String result = ""
        Int index = 0
        while index < text.length() {
            Char character = text.charAt(index)
            if character == '\\' || character == '.' || character == '^'
                || character == '$' || character == '|' || character == '?'
                || character == '*' || character == '+' || character == '('
                || character == ')' || character == '[' || character == ']'
                || character == '{' || character == '}' {
                result = result + "\\"
            }
            result = result + str(character)
            index = index + 1
        }
        return result
    }
}
```

> `RegexEngine`、`regexEngineCompile/Find/GroupCount/NamedGroups` 是文本包内部正则引擎接口，不是 XDK 公共类型。
