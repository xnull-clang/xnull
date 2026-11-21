# `Style`

| 项 | 值 |
| --- | --- |
| 类型 | `class Style` |
| 包 | `xdk.terminal` |
| 稳定性 | `preview` |
| 依赖 | `Ansi`、`Color` |

---

## 1. 定位

不可变文本样式组合：前景色、背景色、粗体、斜体、下划线；提供链式构建和 `apply(String)`。

不做：全局主题、样式注册表、ANSI 解析、颜色降级、闪烁/删除线/反转等扩展属性、终端能力判断。

---

## 2. 设计逻辑

- 字段全部 final；每个构建方法返回**新** `Style`，不修改当前实例。
- 无参构造器创建空样式；可链式 `new Style().fg(Color.green()).bold()`。
- `fg`/`bg` 接受 `Color`，null 视为编程错误并 panic。
- `bold`/`italic`/`underline` 只置位；没有“关闭”方法，空样式或新链表达关闭。
- `apply` 依次包裹文本：先内层下划线/斜体/粗体，再背景，再前景；文本为空时仍返回带样式的空串。
- 每个 `Ansi` 包装自带 reset；嵌套 reset 不会泄漏到后续文本。
- 本类不判断终端；是否应用由调用方根据 `Terminal.isTerminal()` 决定。
- 无全局样式、无共享可变 builder、无 close、可并发使用（不可变）。
- `isPlain` 用于判断是否所有属性为空，便于跳过 `apply`。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_fg` | `Color?` | 前景色；null 表示不设置 |
| `_bg` | `Color?` | 背景色；null 表示不设置 |
| `_bold` | `Bool` | 是否粗体 |
| `_italic` | `Bool` | 是否斜体 |
| `_underline` | `Bool` | 是否下划线 |

不变量：字段 final；`_fg`/`_bg` 非 null 时必须是 `Color`；`isPlain` 等价于四类属性全空；`apply` 不修改实例。

---

## 4. 生命周期

构造后不可变；无 close、无资源；可缓存为常量、共享、作为 Map 值。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Style()` | 无 | 空样式 | 无 |
| `Style(Color? fg, Color? bg, Bool bold, Bool italic, Bool underline)` | 全部 | 私有；fg/bg 可空 | 外部构造 → 编译错误 |

构建方法不做深拷贝；`Color` 本身不可变，可直接共享。

---

## 6. 字段表

见 §3；字段全部私有且 final。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `fg` | 设置前景色 | `Color color` | `Style` | null → panic |
| `bg` | 设置背景色 | `Color color` | `Style` | null → panic |
| `bold` | 开启粗体 | 无 | `Style` | 无 |
| `italic` | 开启斜体 | 无 | `Style` | 无 |
| `underline` | 开启下划线 | 无 | `Style` | 无 |
| `apply` | 应用到文本 | `String text` | `String` | null → panic |
| `isPlain` | 是否无样式 | 无 | `Bool` | 无 |

说明：

- `fg`/`bg` 返回新样式，保留其他属性；重复设置以后一次为准。
- `bold`/`italic`/`underline` 幂等置位；没有 `noBold` 等反向方法，关闭用重新构建。
- `apply` 顺序固定：underline → italic → bold → bg → fg；顺序只影响转义嵌套，不影响可见结果。
- `apply("")` 返回带 reset 的样式串；调用方可先用 `isPlain()` 跳过。
- 不提供 `toString`；需要日志描述时由调用方组合 `isPlain` 与颜色信息。
- 无线程、无缓存、无全局状态。

---

## 8. 使用的技术

- 不可变值对象；
- 复制写（copy-on-write）式构建；
- ANSI 组合；
- 可空颜色字段；
- 链式 API。

---

## 9. 需要的支撑

- 语言：class、final 字段、可空类型、Bool、String；
- 运行时：无；
- 接口：`Ansi.bold/dim/italic/underline/fg/bg`、`Color`。

---

## 10. 依赖的特性/接口/类

`Ansi`、`Color`；不依赖 `Terminal`、`Writer`、`Context`、`Error`。

---

## 11. 所有权与并发

不可变引用语义；构建方法返回新实例；可跨任务共享；读取无锁。`Color` 字段不可变，无需防御性复制。

---

## 12. 示例与反例

正确：`Style title = new Style().fg(Color.brightWhite()).bold().underline()`；`title.apply("Report")`；`Style plain = new Style()`。  
反例：把 `Style` 当可变全局主题；在 `apply` 后修改原实例期望影响旧字符串；在非终端仍调用 `apply`；重复设置背景色期望叠加；用 null 颜色表达“默认色”而不是不调用 `bg`。

---

## 13. 测试/场景义务

空样式 `isPlain`；单属性；全属性；重复 fg/bg；`apply` 空串/普通/Unicode；嵌套 reset；颜色模式（基础/256/RGB）联调；不可变性（旧实例不变）；并发读取；null 参数 panic。

---

## 14. XNull 伪代码

```xnull
class Style {
    final Color? _fg
    final Color? _bg
    final Bool _bold
    final Bool _italic
    final Bool _underline

    Style() {
        _fg = null
        _bg = null
        _bold = false
        _italic = false
        _underline = false
    }

    private Style(Color? fg, Color? bg, Bool bold, Bool italic, Bool underline) {
        _fg = fg
        _bg = bg
        _bold = bold
        _italic = italic
        _underline = underline
    }

    Style fg(Color color) {
        if color == null { throw "Style.fg: null color" }
        return new Style(color, _bg, _bold, _italic, _underline)
    }

    Style bg(Color color) {
        if color == null { throw "Style.bg: null color" }
        return new Style(_fg, color, _bold, _italic, _underline)
    }

    Style bold() {
        return new Style(_fg, _bg, true, _italic, _underline)
    }

    Style italic() {
        return new Style(_fg, _bg, _bold, true, _underline)
    }

    Style underline() {
        return new Style(_fg, _bg, _bold, _italic, true)
    }

    String apply(String text) {
        if text == null { throw "Style.apply: null text" }
        String result = text
        if _underline { result = Ansi.underline(result) }
        if _italic { result = Ansi.italic(result) }
        if _bold { result = Ansi.bold(result) }
        Color? background = _bg
        if background != null { result = Ansi.bg(background as Color, result) }
        Color? foreground = _fg
        if foreground != null { result = Ansi.fg(foreground as Color, result) }
        return result
    }

    Bool isPlain() {
        return _fg == null && _bg == null && !_bold && !_italic && !_underline
    }
}
```
