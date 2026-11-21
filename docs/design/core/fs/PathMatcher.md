# `PathMatcher`

| 项 | 值 |
| --- | --- |
| 类型 | `class PathMatcher` |
| 包 | `xdk.fs` |
| 稳定性 | `preview` |
| 依赖 | `Path` |

---

## 1. 定位

glob/通配路径匹配：`*`、`?`、`**`、字符类；用于 `FileSystem.glob`。

不做：正则完整引擎、brace 展开、大小写规则。

---

## 2. 设计逻辑

- 字段 `_pattern: String`。
- `matches(Path)` 按 `/` 分段；`*` 不跨段；`**` 跨段。
- `?` 单字符；`[abc]` 字符类；`[!abc]` 取反。
- 不可变；无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_pattern` | `String` | glob |

不变量：pattern 非空；不可变。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `PathMatcher(String pattern)` | pattern | 非空 | 空 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `matches` | 匹配 | `Path path` | `Bool` | null → panic |
| `matchesText` | 匹配文本 | `String path` | `Bool` | null → panic |
| `pattern` | 模式 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 分段匹配；
- 通配符；
- 字符类；
- 递归 `**`。

---

## 9. 需要的支撑

- 语言：class、String、Bool、List；
- 运行时：无；
- 接口：`Path`。

---

## 10. 依赖的特性/接口/类

`Path`。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`*.txt`；`src/**/*.x`；`file?.log`。  
反例：期望 `*` 跨目录；brace 展开；大小写无关。

---

## 13. 测试/场景义务

`*`/`?`/`**`/字符类/取反；根/多段；空段；非法 pattern。

---

## 14. XNull 伪代码

```xnull
class PathMatcher {
    final String _pattern

    PathMatcher(String pattern) {
        if pattern == "" { throw "PathMatcher: empty pattern" }
        _pattern = pattern
    }

    static PathMatcher of(String pattern) {
        return new PathMatcher(pattern)
    }

    Bool matches(Path path) {
        if path == null { throw "PathMatcher.matches: null" }
        return self.matchesText(path.text())
    }

    Bool matchesText(String path) {
        if path == null { throw "PathMatcher.matchesText: null" }
        List<String> patternParts = _pattern.split("/")
        List<String> pathParts = path.split("/")
        return matchParts(patternParts, 0, pathParts, 0)
    }

    Bool matchParts(List<String> pattern, Int patternIndex, List<String> path, Int pathIndex) {
        if patternIndex >= pattern.length() {
            return pathIndex >= path.length()
        }
        String part = pattern.get(patternIndex)
        if part == "**" {
            Int skip = pathIndex
            while skip <= path.length() {
                if matchParts(pattern, patternIndex + 1, path, skip) {
                    return true
                }
                skip = skip + 1
            }
            return false
        }
        if pathIndex >= path.length() {
            return false
        }
        if !matchSegment(part, path.get(pathIndex)) {
            return false
        }
        return matchParts(pattern, patternIndex + 1, path, pathIndex + 1)
    }

    Bool matchSegment(String pattern, String value) {
        if pattern == "" { return value == "" }
        if pattern == "*" { return true }
        Int pi = 0
        Int vi = 0
        while pi < pattern.length() {
            Char pc = pattern.charAt(pi)
            if pc == '*' {
                Int next = pi + 1
                while vi <= value.length() {
                    if matchSegment(pattern.substring(next, pattern.length() - next), value.substring(vi, value.length() - vi)) {
                        return true
                    }
                    vi = vi + 1
                }
                return false
            }
            if vi >= value.length() { return false }
            if pc == '?' {
                pi = pi + 1
                vi = vi + 1
                continue
            }
            if pc == '[' {
                Int end = pattern.indexOf("]", pi + 1)
                if end < 0 { return false }
                Bool negated = false
                Int start = pi + 1
                if start < pattern.length() && pattern.charAt(start) == '!' {
                    negated = true
                    start = start + 1
                }
                Bool found = false
                Int index = start
                while index < end {
                    if pattern.charAt(index) == value.charAt(vi) {
                        found = true
                    }
                    index = index + 1
                }
                if found == negated { return false }
                pi = end + 1
                vi = vi + 1
                continue
            }
            if pc != value.charAt(vi) { return false }
            pi = pi + 1
            vi = vi + 1
        }
        return vi == value.length()
    }

    String pattern() { return _pattern }
}
```
