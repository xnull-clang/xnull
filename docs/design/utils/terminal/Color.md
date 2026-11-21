# `Color`

| 项 | 值 |
| --- | --- |
| 类型 | `class Color` |
| 包 | `xdk.terminal` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

不可变颜色值对象：基础 8/16 色、256 索引色、RGB 真彩色；提供静态工厂和模式查询。

不做：ANSI 转义、颜色解析字符串、调色板注册表、颜色混合、终端色域检测、全局主题。

---

## 2. 设计逻辑

- 一个类承载三种模式，用私有 `_mode` 区分：0 基础、1 索引、2 RGB。
- 基础模式只使用 `_index`（0..15）；索引模式只使用 `_index`（0..255）；RGB 模式只使用 `_r/_g/_b`。
- 构造器私有；外部只能用静态工厂，保证每个模式的字段合法。
- `basic` 接受 0..15：0..7 为常规色，8..15 为亮色。
- 提供 16 个命名工厂，避免调用方记忆索引。
- `indexed` 接受 0..255，表示 256 色终端索引。
- `rgb` 接受三个 0..255 通道。
- `equals` 按模式比较：基础/索引比较 `_index`，RGB 比较三个通道。
- 访问器按模式校验；在错误模式上读取返回 panic，而不是静默返回 0。
- `Color` 不保存 ANSI 字符串；由 `Ansi` 根据模式生成。
- 不可变、无 close、可并发共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_mode` | `Int` | 0 基础、1 索引、2 RGB |
| `_index` | `Int` | 基础 0..15；索引 0..255；RGB 模式无意义 |
| `_r` | `Int` | RGB 模式 0..255；其他模式无意义 |
| `_g` | `Int` | RGB 模式 0..255；其他模式无意义 |
| `_b` | `Int` | RGB 模式 0..255；其他模式无意义 |

不变量：mode ∈ {0,1,2}；基础索引 0..15；索引色 0..255；RGB 三通道 0..255；模式之外的字段不参与语义。

---

## 4. 生命周期

构造后不可变；无 close、无资源；可作为常量、Map 键或跨任务共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Color(Int mode, Int index, Int redChannel, Int greenChannel, Int blueChannel)` | mode、index、redChannel、greenChannel、blueChannel | 私有；mode 0..2；按模式校验 | 非法 → panic |
| `Color.basic(Int index)` | index | 0..15 | 越界 → panic |
| `Color.indexed(Int index)` | index | 0..255 | 越界 → panic |
| `Color.rgb(Int redChannel, Int greenChannel, Int blueChannel)` | red/green/blue | 均 0..255 | 越界 → panic |

外部代码使用工厂；命名色工厂内部委托 `Color.basic`。

---

## 6. 字段表

见 §3；字段全部私有且 final，构造后不可修改。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `basic` | 基础 0..15 色 | `Int index` | `Color` | 越界 → panic |
| `black`…`white` | 8 个常规色（0..7） | 无 | `Color` | 无 |
| `brightBlack`…`brightWhite` | 8 个亮色（8..15） | 无 | `Color` | 无 |
| `indexed` | 256 索引色 | `Int index` | `Color` | 越界 → panic |
| `rgb` | RGB 真彩色 | `Int redChannel, Int greenChannel, Int blueChannel` | `Color` | 越界 → panic |
| `isBasic` | 是否基础模式 | 无 | `Bool` | 无 |
| `isIndexed` | 是否索引模式 | 无 | `Bool` | 无 |
| `isRgb` | 是否 RGB 模式 | 无 | `Bool` | 无 |
| `basicIndex` | 基础索引 | 无 | `Int` | 非基础 → panic |
| `index` | 索引值 | 无 | `Int` | 非索引 → panic |
| `redChannel` | 红色通道 | 无 | `Int` | 非 RGB → panic |
| `greenChannel` | 绿色通道 | 无 | `Int` | 非 RGB → panic |
| `blueChannel` | 蓝色通道 | 无 | `Int` | 非 RGB → panic |
| `equals` | 值相等 | `Color other` | `Bool` | null → false |
| `describe` | 调试描述 | 无 | `String` | 无 |

说明：

- 常规色顺序：`black=0`、`red=1`、`green=2`、`yellow=3`、`blue=4`、`magenta=5`、`cyan=6`、`white=7`。
- 亮色顺序：`brightBlack=8` 到 `brightWhite=15`。
- `describe` 只返回类似 `basic(1)`、`indexed(196)`、`rgb(255,0,0)` 的文本，不含 ESC。
- `equals` 不比较 `describe`，直接比较模式与语义字段；不同模式永不相等。

---

## 8. 使用的技术

- 单类多模式值对象；
- 私有构造器；
- 静态工厂；
- 范围校验；
- 不可变字段。

---

## 9. 需要的支撑

- 语言：class、Int、Bool、String、静态方法、私有构造器；
- 运行时：无；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。`Color` 不依赖 `Ansi`、`Terminal`、`Writer` 或任何 core 类型。

---

## 11. 所有权与并发

值语义；字段不可变；可自由复制、共享、并发读取。无资源、无 close、无全局调色板。

---

## 12. 示例与反例

正确：`Color.red()`；`Color.brightBlue()`；`Color.indexed(196)`；`Color.rgb(255, 128, 0)`；`Ansi.fg(Color.rgb(0, 128, 255), "link")`。  
反例：在 `Color` 里保存 `"\u001B[31m"`；`Color.indexed(300)`；对 `Color.red()` 调 `redChannel()` 访问器；在 RGB 模式下读 `index()`；把 Color 当作可变主题单例。

---

## 13. 测试/场景义务

16 个命名色索引；`basic` 边界 0/15/16/-1；`indexed` 边界 0/255/256；RGB 边界 0/255/-1；模式查询互斥；错误模式访问 panic；`equals` 同模式相等/跨模式不等/RGB 通道差异；`describe` 三种模式；不可变性；并发读取；与 `Ansi` 的 16 色/256/RGB 映射联调。

---

## 14. XNull 伪代码

```xnull
class Color {
    final Int _mode
    final Int _index
    final Int _r
    final Int _g
    final Int _b

    private Color(Int mode, Int index, Int redChannel, Int greenChannel, Int blueChannel) {
        if mode < 0 || mode > 2 { throw "Color: invalid mode" }
        if mode == 0 && (index < 0 || index > 15) { throw "Color: basic index out of range" }
        if mode == 1 && (index < 0 || index > 255) { throw "Color: index out of range" }
        if mode == 2 && (redChannel < 0 || redChannel > 255 || greenChannel < 0 || greenChannel > 255 || blueChannel < 0 || blueChannel > 255) {
            throw "Color: RGB channel out of range"
        }
        _mode = mode
        _index = index
        _r = redChannel
        _g = greenChannel
        _b = blueChannel
    }

    static Color basic(Int index) {
        if index < 0 || index > 15 { throw "Color.basic: index out of range" }
        return new Color(0, index, 0, 0, 0)
    }

    static Color black() { return Color.basic(0) }
    static Color red() { return Color.basic(1) }
    static Color green() { return Color.basic(2) }
    static Color yellow() { return Color.basic(3) }
    static Color blue() { return Color.basic(4) }
    static Color magenta() { return Color.basic(5) }
    static Color cyan() { return Color.basic(6) }
    static Color white() { return Color.basic(7) }

    static Color brightBlack() { return Color.basic(8) }
    static Color brightRed() { return Color.basic(9) }
    static Color brightGreen() { return Color.basic(10) }
    static Color brightYellow() { return Color.basic(11) }
    static Color brightBlue() { return Color.basic(12) }
    static Color brightMagenta() { return Color.basic(13) }
    static Color brightCyan() { return Color.basic(14) }
    static Color brightWhite() { return Color.basic(15) }

    static Color indexed(Int index) {
        if index < 0 || index > 255 { throw "Color.indexed: index out of range" }
        return new Color(1, index, 0, 0, 0)
    }

    static Color rgb(Int redChannel, Int greenChannel, Int blueChannel) {
        if redChannel < 0 || redChannel > 255 || greenChannel < 0 || greenChannel > 255 || blueChannel < 0 || blueChannel > 255 {
            throw "Color.rgb: channel out of range"
        }
        return new Color(2, 0, redChannel, greenChannel, blueChannel)
    }

    Bool isBasic() { return _mode == 0 }
    Bool isIndexed() { return _mode == 1 }
    Bool isRgb() { return _mode == 2 }

    Int basicIndex() {
        if !self.isBasic() { throw "Color.basicIndex: not a basic color" }
        return _index
    }

    Int index() {
        if !self.isIndexed() { throw "Color.index: not an indexed color" }
        return _index
    }

    Int redChannel() {
        if !self.isRgb() { throw "Color.redChannel: not an RGB color" }
        return _r
    }

    Int greenChannel() {
        if !self.isRgb() { throw "Color.greenChannel: not an RGB color" }
        return _g
    }

    Int blueChannel() {
        if !self.isRgb() { throw "Color.blueChannel: not an RGB color" }
        return _b
    }

    Bool equals(Color other) {
        if other == null { return false }
        if _mode != other._mode { return false }
        if _mode == 0 || _mode == 1 { return _index == other._index }
        return _r == other._r && _g == other._g && _b == other._b
    }

    String describe() {
        if self.isBasic() { return "basic(" + str(_index) + ")" }
        if self.isIndexed() { return "indexed(" + str(_index) + ")" }
        return "rgb(" + str(_r) + "," + str(_g) + "," + str(_b) + ")"
    }
}
```
