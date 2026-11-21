# `ParseResult`

| 项 | 值 |
| --- | --- |
| 类型 | `class ParseResult` |
| 包 | `xdk.cli` |
| 稳定性 | `preview` |
| 依赖 | `Command`、`OptionSpec`、`Args`、`Error` |

---

## 1. 定位

一次成功解析的结果：选中的命令、命令路径、原始 args、权威位置参数、选项出现次数、有效值、选项规格。

不做：再次解析、帮助渲染、命令执行、进程退出。

---

## 2. 设计逻辑

- 不可变快照；构造时复制列表/Map。
- `_occurrences` 记录显式出现次数；默认值不写入 occurrence。
- `_values` 记录显式值或默认值；flag 不写值。
- `_specs` 保存路径上所有选项规格，用于区分 flag/值选项和 `tryValue` 失败类型。
- `valueOrNull` 对 flag 返回 null；flag 必须用 `hasOption`/`count`。
- 位置参数由 `Parser` 权威分类；不再从 `Args` 猜测。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_command` | `Command` | 选中命令 |
| `_path` | `List<String>` | 根到选中命令 |
| `_args` | `Args` | 原始 argv |
| `_positionals` | `List<String>` | 权威位置参数 |
| `_occurrences` | `Map<String,Int>` | 显式出现次数 |
| `_values` | `Map<String,List<String>>` | 有效值 |
| `_optionOrder` | `List<String>` | 首次出现顺序 |
| `_specs` | `Map<String,OptionSpec>` | 路径选项规格 |

不变量：path 非空；positionals 非 null；occurrences ≥0；values 只含值选项；flag 不在 values 中；不可变。

---

## 4. 生命周期

解析成功后创建；无 close；可共享；线程安全（只读快照）。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ParseResult(Command, List<String>, Args, List<String>, Map<String,Int>, Map<String,List<String>>, List<String>, Map<String,OptionSpec>)` | 见 §6 | 非 null；path 非空 | null/空 path → panic |

构造器主要供 `Parser` 使用；调用方通常不直接创建。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `command` | 选中命令 | 无 | `Command` | 无 |
| `path` | 命令路径快照 | 无 | `List<String>` | 无 |
| `commandPath` | 路径文本 | 无 | `String` | 无 |
| `args` | 原始 args | 无 | `Args` | 无 |
| `positionals` | 位置参数快照 | 无 | `List<String>` | 无 |
| `hasOption` | 是否显式出现 | `String name` | `Bool` | 无 |
| `count` | 出现次数 | `String name` | `Int` | 无 |
| `values` | 有效值快照 | `String name` | `List<String>` | 无 |
| `valueOrNull` | 最后一个有效值 | `String name` | `String?` | 无 |
| `valueOr` | 有效值/兜底 | `String name, String fallback` | `String` | null fallback → panic |
| `tryValue` | checked 有效值 | `String name` | `Result<String, Error>` | `NotFound`/`InvalidArgument` |
| `optionNames` | 显式选项名 | 无 | `List<String>` | 无 |

说明：

- `name` 是 canonical 长名，不带 `--`。
- `hasOption` 只看显式 occurrence；使用默认值不算出现。
- `values` 返回显式值或默认值；flag 返回空列表。
- `valueOrNull` 对 flag 返回 null；`tryValue` 对 flag 返回 `InvalidArgument`。
- `optionNames` 按首次出现顺序，不含默认值。

---

## 8. 使用的技术

- 不可变快照；
- 深复制值 Map；
- 出现次数表；
- 规格表。

---

## 9. 需要的支撑

- 语言：class、List、Map、String、Bool、Int、Result；
- 运行时：无；
- 接口：`Command`、`OptionSpec`、`Args`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Command`、`OptionSpec`、`Args`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

不可变；`path`/`positionals`/`values`/`optionNames` 返回副本；可共享。

---

## 12. 示例与反例

正确：`result.valueOr("output","-")`；`result.hasOption("verbose")`。  
反例：对 flag 调 `valueOrNull` 期望 `"true"`；把默认值当作显式出现；修改返回列表。

---

## 13. 测试/场景义务

路径；位置参数；选项出现次数；flag/值选项；默认值；重复值；`valueOrNull`/`tryValue` 失败类型；快照独立性。

---

## 14. XNull 伪代码

```xnull
class ParseResult {
    final Command _command
    final List<String> _path
    final Args _args
    final List<String> _positionals
    final Map<String, Int> _occurrences
    final Map<String, List<String>> _values
    final List<String> _optionOrder
    final Map<String, OptionSpec> _specs

    ParseResult(Command command, List<String> path, Args args, List<String> positionals,
                Map<String, Int> occurrences, Map<String, List<String>> values,
                List<String> optionOrder, Map<String, OptionSpec> specs) {
        if command == null || path == null || args == null || positionals == null {
            throw "ParseResult: null argument"
        }
        if occurrences == null || values == null || optionOrder == null || specs == null {
            throw "ParseResult: null map"
        }
        if path.length() == 0 { throw "ParseResult: empty path" }
        _command = command
        _path = path.copy()
        _args = args
        _positionals = positionals.copy()
        _occurrences = occurrences.copy()
        _values = [:]
        List<String> valueKeys = values.keys()
        Int valueIndex = 0
        while valueIndex < valueKeys.length() {
            String key = valueKeys.get(valueIndex)
            List<String> current = values.getOr(key, []).copy()
            _values.put(key, current)
            valueIndex = valueIndex + 1
        }
        _optionOrder = optionOrder.copy()
        _specs = specs.copy()
    }

    Command command() { return _command }
    List<String> path() { return _path.copy() }
    Args args() { return _args }
    List<String> positionals() { return _positionals.copy() }

    String commandPath() {
        String result = ""
        Int index = 0
        while index < _path.length() {
            if index > 0 { result = result + " " }
            result = result + _path.get(index)
            index = index + 1
        }
        return result
    }

    Bool hasOption(String name) {
        if !_occurrences.has(name) { return false }
        return _occurrences.getOr(name, 0) > 0
    }

    Int count(String name) {
        if !_occurrences.has(name) { return 0 }
        return _occurrences.getOr(name, 0)
    }

    List<String> values(String name) {
        if !_values.has(name) { return [] }
        return _values.getOr(name, []).copy()
    }

    String? valueOrNull(String name) {
        if !_specs.has(name) { return null }
        OptionSpec? spec = _specs.getOr(name, null)
        if spec == null { return null }
        if spec.isFlag() { return null }
        if !_values.has(name) { return null }
        List<String> current = _values.getOr(name, [])
        if current.length() == 0 { return null }
        return current.get(current.length() - 1)
    }

    String valueOr(String name, String fallback) {
        if fallback == null { throw "ParseResult.valueOr: null fallback" }
        String? value = self.valueOrNull(name)
        if value == null { return fallback }
        return value as String
    }

    Result<String, Error> tryValue(String name) {
        if !_specs.has(name) {
            return Err(new BasicError(ErrorKind.NotFound, "unknown option: " + name))
        }
        OptionSpec? spec = _specs.getOr(name, null)
        if spec == null {
            return Err(new BasicError(ErrorKind.NotFound, "unknown option: " + name))
        }
        if !_occurrences.has(name) && !_values.has(name) {
            return Err(new BasicError(ErrorKind.NotFound, "option not provided: " + name))
        }
        if spec.isFlag() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "flag has no value: " + name))
        }
        if !_values.has(name) {
            return Err(new BasicError(ErrorKind.NotFound, "option value missing: " + name))
        }
        List<String> current = _values.getOr(name, [])
        if current.length() == 0 {
            return Err(new BasicError(ErrorKind.NotFound, "option value missing: " + name))
        }
        return Ok(current.get(current.length() - 1))
    }

    List<String> optionNames() { return _optionOrder.copy() }
}
```
