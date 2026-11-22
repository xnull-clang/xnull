# `Args`

| 项 | 值 |
| --- | --- |
| 类型 | `class Args` |
| 包 | `xdk.cli` |
| 稳定性 | `preview` |
| 依赖 | `Error`、`BasicError` |

---

## 1. 定位

原始 argv 的只读快照，提供按索引读取、选项存在性、原始选项值查询。

不做：命令树、位置参数权威分类、必填/重复校验、默认值、帮助文本。这些由 `Parser`/`ParseResult` 负责。

---

## 2. 设计逻辑

- 字段 `_raw: List<String>`；构造时复制，外部无法修改。
- `Args` 是**无规格视图**：它不知道某个选项是否带值，因此不提供权威 `positionals()`。
- `has`/`valueOrNull`/`values` 只按 token 形态工作，遇到 `--` 停止识别选项。
- `valueOrNull` 对 `--name value` 与 `--name=value` 都支持；重复出现时返回最后一次带值的值。
- `optionNames` 返回原始选项名（去掉 `-`/`--` 与 `=value`），保留顺序与重复。
- 不抛可恢复错误；非法 flag 名字是合同错误。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_raw` | `List<String>` | argv 快照 |

不变量：`_raw` 非 null；元素非 null；构造后不修改。

---

## 4. 生命周期

构造后只读；无 close；可共享；线程安全（不修改内部列表）。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Args(List<String> raw)` | raw | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `raw` | 原始 token 快照 | 无 | `List<String>` | 无 |
| `length` | token 数 | 无 | `Int` | 无 |
| `isEmpty` | 是否为空 | 无 | `Bool` | 无 |
| `get` | 按索引 | `Int index` | `String` | 越界 → panic |
| `has` | 选项是否存在 | `String flag` | `Bool` | 非法 flag → panic |
| `valueOrNull` | 原始值/缺失 | `String flag` | `String?` | 非法 flag → panic |
| `valueOr` | 原始值/兜底 | `String flag, String fallback` | `String` | 非法 flag → panic |
| `value` | 首次值/缺失空串（1.x 兼容） | `String flag` | `String` | 非法 flag → panic |
| `lastValue` | 末次值/缺失空串（1.x 兼容） | `String flag` | `String` | 非法 flag → panic |
| `tryValue` | checked 原始值 | `String flag` | `Result<String, Error>` | `NotFound`；非法 flag → panic |
| `values` | 全部原始值 | `String flag` | `List<String>` | 非法 flag → panic |
| `terminatorIndex` | `--` 下标 | 无 | `Int` | 无；缺失 `-1` |
| `expandShortFlags` | 展开 `-abc` | `List<String> knownShortFlags` | `Args` | null → panic；未知短名原样保留 |
| `optionNames` | 原始选项名 | 无 | `List<String>` | 无 |

说明：

- `has` 匹配 `flag` 本身或 `flag + "="` 前缀；不匹配 `--names` 对 `--name`。
- `valueOrNull` 的“缺失”只指没有出现或 `--` 后不再识别；空串 `--name=` 是合法值，不是缺失。
- `valueOrNull` 在 `--name` 后没有 token，或下一 token 恰为 `--` 时返回 null。
- `values` 不合并、不去重；按出现顺序返回。
- `value` 返回首次出现值，缺失返回空串；`lastValue` 返回末次值，缺失返回空串；二者是 1.x 兼容入口，不改变 `valueOrNull` 的 last-wins 语义。
- `terminatorIndex` 返回第一个 `--` 的下标；没有返回 `-1`。
- `expandShortFlags(known)` 只在 `-abc` 的每个短名都在 `known` 中时展开为 `-a -b -c`；含未知短名或 `--` 后原样保留。`Parser` 不自动调用它；需要 1.x 短选项簇时显式预展开。
- `Args` 不提供 `positionals()`；使用 `ParseResult.positionals()`，因为它知道哪些选项消费值。

---

## 8. 使用的技术

- argv 线性扫描；
- `--` 终止符；
- 前缀匹配；
- 列表快照；
- 可选返回值。

---

## 9. 需要的支撑

- 语言：class、List、String、Bool、Int、Result；
- 运行时：无；
- 接口：`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Error`、`BasicError`、`ErrorKind`、顶层 `isOptionToken`。

---

## 11. 所有权与并发

构造复制入参；`raw` 返回副本；内部不修改；只读可共享。

---

## 12. 示例与反例

正确：`new Args(["--output","a.txt","x"]).valueOr("--output","-")` → `"a.txt"`。

正确：`new Args(["-abc"]).expandShortFlags(["a","b","c"])` → `["-a","-b","-c"]`。

反例：用 `Args` 判断位置参数；把空串当缺失；期望 `Args` 拒绝重复选项；期望 `Parser` 自动展开 `-abc`；未知短名被静默丢弃。

---

## 13. 测试/场景义务

空 argv；`--name value`；`--name=value`；空值；缺失；重复；`value`/`lastValue`/`values` 三种重复策略；`terminatorIndex`；`expandShortFlags` 全已知/含未知/`--` 后；`--` 终止；非法 flag；`get` 越界；快照独立性。

---

## 14. XNull 伪代码

```xnull
class Args {
    final List<String> _raw

    Args(List<String> raw) {
        if raw == null { throw "Args: null raw" }
        _raw = raw.copy()
        Int index = 0
        while index < _raw.length() {
            if _raw.get(index) == null { throw "Args: null element" }
            index = index + 1
        }
    }

    List<String> raw() { return _raw.copy() }
    Int length() { return _raw.length() }
    Bool isEmpty() { return _raw.length() == 0 }

    String get(Int index) {
        if index < 0 || index >= _raw.length() {
            throw "Args.get: index out of range"
        }
        return _raw.get(index)
    }

    Bool has(String flag) {
        if !isOptionToken(flag) { throw "Args.has: invalid flag" }
        String prefix = flag + "="
        Bool terminated = false
        Int index = 0
        while index < _raw.length() {
            String token = _raw.get(index)
            if !terminated && token == "--" {
                terminated = true
            } else if !terminated && (token == flag || token.startsWith(prefix)) {
                return true
            }
            index = index + 1
        }
        return false
    }

    String? valueOrNull(String flag) {
        if !isOptionToken(flag) { throw "Args.valueOrNull: invalid flag" }
        String prefix = flag + "="
        String? result = null
        Bool terminated = false
        Int index = 0
        while index < _raw.length() {
            String token = _raw.get(index)
            if !terminated && token == "--" {
                terminated = true
                index = index + 1
                continue
            }
            if !terminated && token == flag {
                if index + 1 < _raw.length() && _raw.get(index + 1) != "--" {
                    result = _raw.get(index + 1)
                    index = index + 2
                    continue
                }
            } else if !terminated && token.startsWith(prefix) {
                result = token.substring(prefix.length(), token.length() - prefix.length())
            }
            index = index + 1
        }
        return result
    }

    String valueOr(String flag, String fallback) {
        if fallback == null { throw "Args.valueOr: null fallback" }
        String? value = self.valueOrNull(flag)
        if value == null { return fallback }
        return value as String
    }

    String value(String flag) {
        List<String> all = self.values(flag)
        if all.length() == 0 { return "" }
        return all.get(0)
    }

    String lastValue(String flag) {
        List<String> all = self.values(flag)
        if all.length() == 0 { return "" }
        return all.get(all.length() - 1)
    }

    Int terminatorIndex() {
        Int index = 0
        while index < _raw.length() {
            if _raw.get(index) == "--" { return index }
            index = index + 1
        }
        return -1
    }

    Args expandShortFlags(List<String> knownShortFlags) {
        if knownShortFlags == null { throw "Args.expandShortFlags: null" }
        List<String> expanded = []
        Bool terminated = false
        Int index = 0
        while index < _raw.length() {
            String token = _raw.get(index)
            if !terminated && token == "--" {
                terminated = true
                expanded.push(token)
                index = index + 1
                continue
            }
            Bool isCluster = !terminated && token.startsWith("-")
                && !token.startsWith("--") && token.length() > 2
            if isCluster {
                Bool allKnown = true
                Int cursor = 1
                while cursor < token.length() {
                    String shortName = token.substring(cursor, 1)
                    Bool found = false
                    Int knownIndex = 0
                    while knownIndex < knownShortFlags.length() {
                        if knownShortFlags.get(knownIndex) == shortName {
                            found = true
                            break
                        }
                        knownIndex = knownIndex + 1
                    }
                    if !found { allKnown = false; break }
                    cursor = cursor + 1
                }
                if allKnown {
                    cursor = 1
                    while cursor < token.length() {
                        expanded.push("-" + token.substring(cursor, 1))
                        cursor = cursor + 1
                    }
                    index = index + 1
                    continue
                }
            }
            expanded.push(token)
            index = index + 1
        }
        return new Args(expanded)
    }

    Result<String, Error> tryValue(String flag) {
        String? value = self.valueOrNull(flag)
        if value == null {
            return Err(new BasicError(ErrorKind.NotFound, "option value missing: " + flag))
        }
        return Ok(value as String)
    }

    List<String> values(String flag) {
        if !isOptionToken(flag) { throw "Args.values: invalid flag" }
        String prefix = flag + "="
        List<String> result = []
        Bool terminated = false
        Int index = 0
        while index < _raw.length() {
            String token = _raw.get(index)
            if !terminated && token == "--" {
                terminated = true
                index = index + 1
                continue
            }
            if !terminated && token == flag {
                if index + 1 < _raw.length() && _raw.get(index + 1) != "--" {
                    result.push(_raw.get(index + 1))
                    index = index + 2
                    continue
                }
            } else if !terminated && token.startsWith(prefix) {
                result.push(token.substring(prefix.length(), token.length() - prefix.length()))
            }
            index = index + 1
        }
        return result
    }

    List<String> optionNames() {
        List<String> result = []
        Bool terminated = false
        Int index = 0
        while index < _raw.length() {
            String token = _raw.get(index)
            if !terminated && token == "--" {
                terminated = true
            } else if !terminated && isOptionToken(token) {
                String? name = optionName(token)
                if name != null { result.push(name) }
            }
            index = index + 1
        }
        return result
    }
}
```
