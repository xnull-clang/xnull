# `JsonNumber`

| 项 | 值 |
| --- | --- |
| 类型 | `class JsonNumber` |
| 包 | `xdk.codec` |
| 稳定性 | `preview` |
| 依赖 | `Error` |

---

## 1. 定位

JSON 数字：保存原始文本，显式转 Int/Long/Double，判定是否整数。

不做：任意精度 Decimal、自动数值类型推断、隐式转换。

---

## 2. 设计逻辑

- 字段 `_raw: String`；构造时校验 JSON 数字语法。
- `isInteger` 判断是否无小数点/指数。
- `asLong`/`asDouble` 显式转换；失败 `InvalidArgument`。
- 不可变；无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_raw` | `String` | JSON 数字文本 |

不变量：raw 合法；不可变。

---

## 4. 生命周期

不可变；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `JsonNumber(String raw)` | raw | JSON number | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `raw` | 原始文本 | 无 | `String` | 无 |
| `isInteger` | 是否整数 | 无 | `Bool` | 无 |
| `asLong` | Long | 无 | `Result<Long, Error>` | 溢出/非法 |
| `asDouble` | Double | 无 | `Result<Double, Error>` | 非法 |
| `toString` | 原始文本 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 原始文本；
- 显式解析；
- 精度保留。

---

## 9. 需要的支撑

- 语言：class、String、Long、Double、Bool、Result；
- 运行时：`parseLong`、`parseDouble`；
- 接口：`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Error`、`BasicError`、`ErrorKind`、`parseLong`、`parseDouble`。

---

## 11. 所有权与并发

不可变；无资源；可共享。

---

## 12. 示例与反例

正确：`new JsonNumber("9007199254740993").asLong()` 保留整数。  
反例：先转 Double 再比整数；把 `1e3` 当整数文本。

---

## 13. 测试/场景义务

整数/小数/指数；溢出；非法；raw 往返；isInteger。

---

## 14. XNull 伪代码

```xnull
class JsonNumber {
    final String _raw

    JsonNumber(String raw) {
        if raw == null || raw == "" { throw "JsonNumber: empty" }
        _raw = raw
    }

    String raw() { return _raw }

    Bool isInteger() {
        return _raw.indexOf(".") < 0 && _raw.indexOf("e") < 0 && _raw.indexOf("E") < 0
    }

    Result<Long, Error> asLong() { return parseLong(_raw) }

    Result<Double, Error> asDouble() { return parseDouble(_raw) }

    String toString() { return _raw }
}
```
