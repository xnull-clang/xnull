# `Table`

| 项 | 值 |
| --- | --- |
| 类型 | `class Table` |
| 包 | `xdk.terminal` |
| 稳定性 | `preview` |
| 依赖 | `Ansi` |

---

## 1. 定位

宽度感知的纯文本表格：列名、逐行数据、按终端列宽收缩、ANSI 单元格不破坏对齐、`render` 返回字符串。

不做：外框/主题、自动换行、跨行/跨列、树表、排序/过滤、CSV 导入导出、终端探测、全 Unicode 宽度表。

---

## 2. 设计逻辑

- 构造时复制列名；列数 ≥1；列名非空、无换行/回车/除 ESC 外的控制字符。
- `addRow` 要求单元格数正好等于列数；复制单元格；行数据不保留调用方列表引用。
- 单元格可以包含 ANSI CSI/SGR；宽度统计跳过 CSI，宽字符按 2 列、组合字符按 0 列估算。ANSI 单元格必须自包含（有开有关，例如使用 `Ansi.fg`）；Table 只在截断时补 reset。
- Table 不接收 `Terminal`、不判断终端；非终端输出前调用方不得传入 ANSI 单元格，或先用 `new Terminal(context, writer, false, 0, 0)` 写入以剥离 CSI/SGR。
- `render` 先按内容计算每列自然宽度，再用 `_maxWidth` 从最宽列开始逐列减 1，直到总宽适配或每列只剩 1。
- `maxWidth` 包含列间 ` | ` 与分隔线 `-+-`；0 表示不限制。调用方通常传入 `Terminal.width()`；Table 本身不持有 Terminal。
- 若 `maxWidth` 小于“每列 1 格 + 分隔符”的最小结构宽度，结构优先，允许超出 `maxWidth`，不破坏列数。
- 单元格超宽时按可见宽度截断；截断内容若含 ANSI，追加 `Ansi.reset()`，避免颜色泄漏到后续列。
- 补齐使用可见宽度，不把 ANSI 字节计入列宽。
- `render` 不加外框、不写终端、不追加末尾换行；由 `Terminal.writeLine` 或调用方决定输出。
- `clear` 只清空数据行，保留列名和 `maxWidth`。
- 无全局表样式、无日志/i18n、无线程；非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_columns` | `List<String>` | 非空；构造时复制；元素非空 |
| `_rows` | `List<List<String>>` | 每行长度等于列数 |
| `_maxWidth` | `Int` | ≥0；0 表示不限制 |

不变量：列数 ≥1；所有行列数一致；列名/单元格不含 `\n`/`\r`；`render` 不修改字段；`maxWidth` 只影响渲染宽度，不裁剪存储内容。

---

## 4. 生命周期

构造后列固定；行可追加/清空；无 close、无资源；不可变列名与可变行集合共同存在。可复用渲染，输出字符串独立。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Table(List<String> columns)` | columns | 非 null、非空、元素非空合法 | 非法 → panic；maxWidth=0 |
| `Table(List<String> columns, Int maxWidth)` | columns、maxWidth | 同上；maxWidth ≥0 | 非法 → panic |

构造时复制 `columns`；之后修改原列表不影响 Table。

---

## 6. 字段表

见 §3；字段私有。列名只读，行集合只通过 `addRow`/`clear` 修改。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `addRow` | 追加一行 | `List<String> cells` | `void` | 长度不符/null/非法字符 → panic |
| `clear` | 清空数据行 | 无 | `void` | 无 |
| `render` | 生成表格文本 | 无 | `String` | 无 |
| `columns` | 列名快照 | 无 | `List<String>` | 无 |
| `rowCount` | 数据行数 | 无 | `Int` | 无 |
| `maxWidth` | 最大宽度 | 无 | `Int` | 无 |

说明：

- `addRow` 的每个单元格先校验非 null、无 `\n`/`\r`、无非法控制字符（含 DEL），再复制。
- `clear` 等价 `_rows.clear()`；列名、宽度不变。
- `render` 的列顺序固定为构造顺序；无排序。
- 表头后紧跟一条 `-+-` 规则线；每行以 ` | ` 分隔。
- 自然宽度取列名与所有单元格的最大可见宽度。
- 收缩时选当前最宽列；并列时选索引最小者；每列最小 1。
- 截断按可见宽度；遇到宽字符若剩余 1 列则不放半个字符。
- 截断时只保留完整 CSI 序列；若保留部分含 ANSI，则追加一次 reset。
- `columns` 返回副本；`maxWidth` 返回构造值。
- `render` 无行时返回表头 + 换行 + 规则线，无末尾换行。
- 不提供 `removeRow`/`sort`；需要时由调用方重建。

---

## 8. 使用的技术

- 可见宽度扫描；
- ANSI CSI 跳过；
- 宽字符/组合字符估算；
- 列宽收缩；
- 单元格截断与补齐；
- StringBuilder 拼装。

---

## 9. 需要的支撑

- 语言：class、List、String、Int、Bool、Char、StringBuilder；
- 运行时：无；
- 接口：`Ansi.reset`；不依赖 `Terminal`、`Writer`、`Context`。

---

## 10. 依赖的特性/接口/类

`Ansi.reset`、`List`、`StringBuilder`；不依赖 `log`、`i18n`、`Unicode` 宽度表（本类内置估算）。

---

## 11. 所有权与并发

- 列名和单元格在写入时复制，Table 拥有自己的字符串列表。
- 引用语义；非线程安全；并发 `addRow`/`render` 需外部同步。
- `render` 只读，可与其他只读操作并发（前提是无并发修改）。
- 无资源、无 close、无全局样式。

---

## 12. 示例与反例

正确：`new Table(["Name", "Status"], 40)`；`addRow(["api", Ansi.fg(Color.green(), "ok")])`；`Terminal.writeLine(table.render())`。  
反例：用 `String.length()` 计算含 ANSI 的宽度；单元格含换行破坏行结构；`addRow` 少一列；`maxWidth` 小于最小结构仍期望不溢出；截断 ANSI 单元格后不追加 reset；传入未闭合的原始 SGR；`clear` 后期望列名消失；构造后修改原列名列表期望 Table 变化。

---

## 13. 测试/场景义务

纯文本对齐；含 SGR 的单元格；256/RGB 单元格；截断含 ANSI 并 reset；宽 CJK；emoji/代理对；组合字符；正好等于 `maxWidth`；需要收缩；`maxWidth=0`；`maxWidth` 小于最小宽度；无行；多行；`clear`；列数不匹配；null 单元格/列名；换行/回车/控制字符；无末尾换行；并发修改检测。

---

## 14. XNull 伪代码

```xnull
class Table {
    final List<String> _columns
    final List<List<String>> _rows
    final Int _maxWidth

    Table(List<String> columns) {
        _columns = Table.copyColumns(columns)
        _rows = []
        _maxWidth = 0
    }

    Table(List<String> columns, Int maxWidth) {
        if maxWidth < 0 { throw "Table: negative maxWidth" }
        _columns = Table.copyColumns(columns)
        _rows = []
        _maxWidth = maxWidth
    }

    void addRow(List<String> cells) {
        if cells == null { throw "Table.addRow: null cells" }
        if cells.length() != _columns.length() {
            throw "Table.addRow: cell count does not match columns"
        }
        List<String> copied = []
        Int index = 0
        while index < cells.length() {
            Table.validateText(cells.get(index), "Table.addRow")
            copied.add(cells.get(index))
            index = index + 1
        }
        _rows.add(copied)
    }

    void clear() {
        _rows.clear()
    }

    List<String> columns() {
        return _columns.copy()
    }

    Int rowCount() {
        return _rows.length()
    }

    Int maxWidth() {
        return _maxWidth
    }

    String render() {
        List<Int> widths = []
        Int columnIndex = 0
        while columnIndex < _columns.length() {
            Int width = self.visibleWidth(_columns.get(columnIndex))
            Int rowIndex = 0
            while rowIndex < _rows.length() {
                Int cellWidth = self.visibleWidth(_rows.get(rowIndex).get(columnIndex))
                if cellWidth > width { width = cellWidth }
                rowIndex = rowIndex + 1
            }
            widths.add(width)
            columnIndex = columnIndex + 1
        }
        if _maxWidth > 0 {
            while self.totalWidth(widths) > _maxWidth {
                Int widest = widths.get(0)
                Int widestIndex = 0
                Int index = 1
                while index < widths.length() {
                    if widths.get(index) > widest {
                        widest = widths.get(index)
                        widestIndex = index
                    }
                    index = index + 1
                }
                if widest <= 1 { break }
                widths.set(widestIndex, widest - 1)
            }
        }
        StringBuilder builder = new StringBuilder()
        builder.append(self.renderLine(_columns, widths))
        builder.append("\n")
        builder.append(self.renderRule(widths))
        Int rowIndex = 0
        while rowIndex < _rows.length() {
            builder.append("\n")
            builder.append(self.renderLine(_rows.get(rowIndex), widths))
            rowIndex = rowIndex + 1
        }
        return builder.build()
    }

    private static void validateText(String text, String label) {
        if text == null { throw label + ": null text" }
        Int index = 0
        while index < text.length() {
            Int code = text.charAt(index) as Int
            if code == 10 || code == 13 {
                throw label + ": newline is not allowed"
            }
            if code < 32 && code != 27 || code == 127 {
                throw label + ": control character is not allowed"
            }
            index = index + 1
        }
    }

    private static List<String> copyColumns(List<String> columns) {
        if columns == null || columns.length() == 0 {
            throw "Table: empty columns"
        }
        List<String> copied = []
        Int index = 0
        while index < columns.length() {
            Table.validateText(columns.get(index), "Table.column")
            if columns.get(index) == "" { throw "Table: empty column name" }
            copied.add(columns.get(index))
            index = index + 1
        }
        return copied
    }

    private Int ansiEnd(String text, Int start) {
        Int index = start + 2
        while index < text.length() {
            Int code = text.charAt(index) as Int
            index = index + 1
            if code >= 64 && code <= 126 { return index }
        }
        return index
    }

    private Int codePointWidth(Int codePoint) {
        if codePoint >= 768 && codePoint <= 879 { return 0 }
        if codePoint >= 8203 && codePoint <= 8207 { return 0 }
        if codePoint >= 65024 && codePoint <= 65039 { return 0 }
        if codePoint >= 4352 && codePoint <= 4447 { return 2 }
        if codePoint >= 11904 && codePoint <= 42191 { return 2 }
        if codePoint >= 44032 && codePoint <= 55203 { return 2 }
        if codePoint >= 63744 && codePoint <= 64255 { return 2 }
        if codePoint >= 65040 && codePoint <= 65049 { return 2 }
        if codePoint >= 65072 && codePoint <= 65135 { return 2 }
        if codePoint >= 65280 && codePoint <= 65376 { return 2 }
        if codePoint >= 65504 && codePoint <= 65510 { return 2 }
        if codePoint >= 127744 && codePoint <= 129791 { return 2 }
        return 1
    }

    private Int visibleWidth(String text) {
        Int width = 0
        Int index = 0
        while index < text.length() {
            Char character = text.charAt(index)
            if (character as Int) == 27 && index + 1 < text.length() && text.charAt(index + 1) == '[' {
                index = self.ansiEnd(text, index)
            } else {
                Int codePoint = character as Int
                Int charCount = 1
                if codePoint >= 55296 && codePoint <= 56319 && index + 1 < text.length() {
                    Int low = text.charAt(index + 1) as Int
                    if low >= 56320 && low <= 57343 {
                        codePoint = 65536 + ((codePoint - 55296) * 1024) + (low - 56320)
                        charCount = 2
                    }
                }
                width = width + self.codePointWidth(codePoint)
                index = index + charCount
            }
        }
        return width
    }

    private String truncate(String text, Int maxWidth) {
        if self.visibleWidth(text) <= maxWidth { return text }
        StringBuilder builder = new StringBuilder()
        Int width = 0
        Int index = 0
        Bool sawAnsi = false
        while index < text.length() && width < maxWidth {
            Char character = text.charAt(index)
            if (character as Int) == 27 && index + 1 < text.length() && text.charAt(index + 1) == '[' {
                Int start = index
                index = self.ansiEnd(text, index)
                builder.append(text.substring(start, index - start))
                sawAnsi = true
            } else {
                Int codePoint = character as Int
                Int charCount = 1
                if codePoint >= 55296 && codePoint <= 56319 && index + 1 < text.length() {
                    Int low = text.charAt(index + 1) as Int
                    if low >= 56320 && low <= 57343 {
                        codePoint = 65536 + ((codePoint - 55296) * 1024) + (low - 56320)
                        charCount = 2
                    }
                }
                Int cellWidth = self.codePointWidth(codePoint)
                if width + cellWidth > maxWidth { break }
                builder.append(text.substring(index, charCount))
                width = width + cellWidth
                index = index + charCount
            }
        }
        if sawAnsi {
            builder.append(Ansi.reset())
        }
        return builder.build()
    }

    private String pad(String text, Int width) {
        String result = self.truncate(text, width)
        Int missing = width - self.visibleWidth(result)
        while missing > 0 {
            result = result + " "
            missing = missing - 1
        }
        return result
    }

    private String renderLine(List<String> cells, List<Int> widths) {
        StringBuilder builder = new StringBuilder()
        Int index = 0
        while index < cells.length() {
            if index > 0 { builder.append(" | ") }
            builder.append(self.pad(cells.get(index), widths.get(index)))
            index = index + 1
        }
        return builder.build()
    }

    private String renderRule(List<Int> widths) {
        StringBuilder builder = new StringBuilder()
        Int index = 0
        while index < widths.length() {
            if index > 0 { builder.append("-+-") }
            Int count = widths.get(index)
            while count > 0 {
                builder.append("-")
                count = count - 1
            }
            index = index + 1
        }
        return builder.build()
    }

    private Int totalWidth(List<Int> widths) {
        Int total = 0
        Int index = 0
        while index < widths.length() {
            total = total + widths.get(index)
            index = index + 1
        }
        return total + 3 * (widths.length() - 1)
    }
}
```
