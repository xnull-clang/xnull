# `Ansi`

| 项 | 值 |
| --- | --- |
| 类型 | `class Ansi` |
| 包 | `xdk.terminal` |
| 稳定性 | `preview` |
| 依赖 | `Color` |

---

## 1. 定位

无状态 ANSI 转义构造器：SGR 文本样式、前景/背景色、256 色、RGB、光标上下移动、清屏、光标隐藏/显示。

不做：终端能力探测、ANSI 解析/剥离、颜色降级、样式叠加状态、输出写入、全局开关。

---

## 2. 设计逻辑

- 全部是静态方法；构造器私有；无实例字段、无全局可变状态。
- 所有方法返回新的 `String`；不写 `Writer`，是否输出由调用方决定。
- 文本包装方法采用“前缀 + 文本 + reset”形式，嵌套时每个内层 reset 只影响其后的文本。
- `fg`/`bg` 只接受 `Color`；根据 `Color` 的模式分派到基础色、256 色或 RGB。
- `Color` 不包含 ANSI；转义只在本类生成。
- `color256`/`rgb` 是直接前景包装；`bg` 对应背景版本。
- 光标移动只生成 CSI，不检查终端尺寸；行数参数必须 ≥1。
- `clearScreen` 返回清屏并归位序列；是否真的清屏由终端决定。
- 本类不判断 `isTerminal`；调用方（通常是 `Terminal` 或组件）负责门控。
- 无 close、无可变状态；可并发调用。

---

## 3. 表示与不变量

无实例字段。内部只使用常量转义字节（ESC `\u001B` 与 `[`）和调用参数。

不变量：所有颜色通道在 0..255；256 色索引在 0..255；光标行数 ≥1；文本参数非 null；返回字符串不共享可变状态。

---

## 4. 生命周期

静态命名空间；无构造实例、无 close、无资源；首次调用即可用。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Ansi()` | 无 | 私有 | 外部构造 → 编译错误 |

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `reset` | 重置样式 | 无 | `String` | 无 |
| `bold` | 粗体包装 | `String text` | `String` | null → panic |
| `dim` | 暗色包装 | `String text` | `String` | null → panic |
| `italic` | 斜体包装 | `String text` | `String` | null → panic |
| `underline` | 下划线包装 | `String text` | `String` | null → panic |
| `fg` | 前景色包装 | `Color color, String text` | `String` | null/非法颜色 → panic |
| `bg` | 背景色包装 | `Color color, String text` | `String` | null/非法颜色 → panic |
| `color256` | 256 色前景包装 | `Int index, String text` | `String` | 越界/null → panic |
| `rgb` | RGB 前景包装 | `Int redChannel, Int greenChannel, Int blueChannel, String text` | `String` | 越界/null → panic |
| `cursorUp` | 光标上移 | `Int rows` | `String` | rows <1 → panic |
| `cursorDown` | 光标下移 | `Int rows` | `String` | rows <1 → panic |
| `clearScreen` | 清屏并归位 | 无 | `String` | 无 |
| `hideCursor` | 隐藏光标 | 无 | `String` | 无 |
| `showCursor` | 显示光标 | 无 | `String` | 无 |

说明：

- 基础 8 色前景为 30..37，亮色 8..15 映射 90..97；背景对应 40..47 / 100..107。
- 256 色前景为 `38;5;index`，背景为 `48;5;index`。
- RGB 前景为 `38;2;r;g;b`，背景为 `48;2;r;g;b`。
- `cursorUp`/`cursorDown` 仅生成 CSI `A`/`B`，不改变行列模型。
- `clearScreen` 为 `ESC[2J` 后接 `ESC[H`，不保存/恢复光标位置。
- `hideCursor`/`showCursor` 使用 `?25l`/`?25h`。
- 本类不提供 `clearLine`；组件需要时自行组合 `\r` 与空格，避免 API 面扩张。

---

## 8. 使用的技术

- ANSI CSI/SGR 序列；
- 静态工具类；
- 值对象颜色分派；
- 字符串拼接；
- 参数校验。

---

## 9. 需要的支撑

- 语言：class、static 方法、String、Int、Bool、Char；
- 运行时：字符串拼接、UTF-8 输出由调用方处理；
- 接口：`Color.isBasic/isIndexed/isRgb`、`Color.basicIndex/index/redChannel/greenChannel/blueChannel`。

---

## 10. 依赖的特性/接口/类

`Color`、`String`、`Int`；不依赖 `Writer`、`Terminal`、`Context`、`Error`。

---

## 11. 所有权与并发

无实例、无所有权；返回的字符串是独立值；可跨任务并发调用。调用方负责决定是否把结果写到终端，以及是否在非终端模式丢弃。

---

## 12. 示例与反例

正确：`Ansi.fg(Color.red(), "error")`；`Ansi.bold(Ansi.fg(Color.green(), "ok"))`；`Ansi.cursorUp(1)`。  
反例：在 `Color` 里存 ANSI 字符串；把 `Ansi.bold` 的结果写到非终端；用 `cursorUp(0)`；期望 `Ansi` 自己判断终端能力；把 `clearScreen` 当作清行。

---

## 13. 测试/场景义务

16 个基础色的前景/背景映射；256 色边界 0/255；RGB 0/255；越界 panic；null 参数；嵌套样式 reset；cursorUp/Down 的 rows=1/大值/0；clearScreen 序列；hide/show 序列；无状态并发调用；颜色模式分派。

---

## 14. XNull 伪代码

```xnull
class Ansi {
    private Ansi() {
    }

    private static String csi() {
        return "\u001B["
    }

    private static String wrap(String code, String text) {
        return Ansi.csi() + code + text + Ansi.csi() + "0m"
    }

    static String reset() {
        return Ansi.csi() + "0m"
    }

    static String bold(String text) {
        if text == null { throw "Ansi.bold: null text" }
        return Ansi.wrap("1m", text)
    }

    static String dim(String text) {
        if text == null { throw "Ansi.dim: null text" }
        return Ansi.wrap("2m", text)
    }

    static String italic(String text) {
        if text == null { throw "Ansi.italic: null text" }
        return Ansi.wrap("3m", text)
    }

    static String underline(String text) {
        if text == null { throw "Ansi.underline: null text" }
        return Ansi.wrap("4m", text)
    }

    static String fg(Color color, String text) {
        if color == null || text == null { throw "Ansi.fg: null argument" }
        if color.isBasic() {
            Int index = color.basicIndex()
            if index < 8 {
                return Ansi.wrap(str(30 + index) + "m", text)
            }
            return Ansi.wrap(str(90 + index - 8) + "m", text)
        }
        if color.isIndexed() {
            return Ansi.color256(color.index(), text)
        }
        return Ansi.rgb(color.redChannel(), color.greenChannel(), color.blueChannel(), text)
    }

    static String bg(Color color, String text) {
        if color == null || text == null { throw "Ansi.bg: null argument" }
        if color.isBasic() {
            Int index = color.basicIndex()
            if index < 8 {
                return Ansi.wrap(str(40 + index) + "m", text)
            }
            return Ansi.wrap(str(100 + index - 8) + "m", text)
        }
        if color.isIndexed() {
            return Ansi.wrap("48;5;" + str(color.index()) + "m", text)
        }
        return Ansi.wrap("48;2;" + str(color.redChannel()) + ";" + str(color.greenChannel()) + ";" + str(color.blueChannel()) + "m", text)
    }

    static String color256(Int index, String text) {
        if text == null { throw "Ansi.color256: null text" }
        if index < 0 || index > 255 { throw "Ansi.color256: index out of range" }
        return Ansi.wrap("38;5;" + str(index) + "m", text)
    }

    static String rgb(Int redChannel, Int greenChannel, Int blueChannel, String text) {
        if text == null { throw "Ansi.rgb: null text" }
        if redChannel < 0 || redChannel > 255 || greenChannel < 0 || greenChannel > 255 || blueChannel < 0 || blueChannel > 255 {
            throw "Ansi.rgb: channel out of range"
        }
        return Ansi.wrap("38;2;" + str(redChannel) + ";" + str(greenChannel) + ";" + str(blueChannel) + "m", text)
    }

    static String cursorUp(Int rows) {
        if rows < 1 { throw "Ansi.cursorUp: rows must be positive" }
        return Ansi.csi() + str(rows) + "A"
    }

    static String cursorDown(Int rows) {
        if rows < 1 { throw "Ansi.cursorDown: rows must be positive" }
        return Ansi.csi() + str(rows) + "B"
    }

    static String clearScreen() {
        return Ansi.csi() + "2J" + Ansi.csi() + "H"
    }

    static String hideCursor() {
        return Ansi.csi() + "?25l"
    }

    static String showCursor() {
        return Ansi.csi() + "?25h"
    }
}
```
