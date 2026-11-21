# `MultipartForm`

| 项 | 值 |
| --- | --- |
| 类型 | `class MultipartForm` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`HttpRequest`、`MultipartOptions`、`MultipartPart`、`Error` |

---

## 1. 定位

解析后的 multipart 表单：parts、按名查找、关闭全部 part body。

不做：multipart 写出（`MultipartWriter`）、文件持久化、内容嗅探。

---

## 2. 设计逻辑

- 字段 `_parts: List<MultipartPart>`；解析时复制。
- `parse` 读取 request body，按 options 限制；错误 `InvalidArgument`/`DataCorrupted`。
- `getOrNull` 首个；`getAll` 全部。
- `close` 幂等，关闭所有 part body。
- 无全局；调用方持有。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_parts` | `List<MultipartPart>` | part 列表 |

不变量：元素非 null；parts 数量 ≤ options.maxParts。

---

## 4. 生命周期

`parse` 创建；必须 close；close 幂等。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `MultipartForm.parse(Context, HttpRequest, MultipartOptions)` | 非 null | 非 null | `InvalidArgument`/`DataCorrupted`/`Cancelled` |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `parse` | 解析 | `Context, HttpRequest, MultipartOptions` | `Result<MultipartForm, Error>` | 解析失败 |
| `parts` | 快照 | 无 | `List<MultipartPart>` | 无 |
| `getOrNull` | 首个 part/无 | `String name` | `MultipartPart?` | 无 |
| `getAll` | 全部 part | `String name` | `List<MultipartPart>` | 无 |
| `close` | 关闭全部 | 无 | `Result<Unit, Error>` | `Io`（诊断） |

---

## 8. 使用的技术

- multipart 解析；
- 资源关闭。

---

## 9. 需要的支撑

- 语言：class、List、String、Bool、Result；
- 运行时：`parseMultipartRaw`、`MultipartFormRaw`；
- 接口：`Context`、`HttpRequest`、`MultipartOptions`、`MultipartPart`、`Error`。

---

## 10. 依赖的特性/接口/类

`Context`、`HttpRequest`、`MultipartOptions`、`MultipartPart`、`Error`、`parseMultipartRaw`。

---

## 11. 所有权与并发

引用语义；拥有 parts；close 可并发；无全局。

---

## 12. 示例与反例

正确：`MultipartForm.parse(ctx, request, options)`。  
反例：不 close；多任务共享 part body；超限不报错。

---

## 13. 测试/场景义务

正常/空 form；多 part；重复名；超限；非法 boundary；取消；close 幂等。

---

## 14. XNull 伪代码

```xnull
class MultipartForm {
    final List<MultipartPart> _parts
    Bool _closed

    private MultipartForm(List<MultipartPart> parts) {
        _parts = parts.copy()
        _closed = false
    }

    static Result<MultipartForm, Error> parse(Context context, HttpRequest request,
                                               MultipartOptions options) {
        if context == null || request == null || options == null {
            throw "MultipartForm.parse: null argument"
        }
        Result<MultipartFormRaw, Error> raw = parseMultipartRaw(context, request, options.copy())
        if raw.isErr() { return Err(raw.error()) }
        return Ok(new MultipartForm(raw.value().parts()))
    }

    List<MultipartPart> parts() { return _parts.copy() }

    MultipartPart? getOrNull(String name) {
        Int index = 0
        while index < _parts.length() {
            if _parts.get(index).name() == name {
                return _parts.get(index)
            }
            index = index + 1
        }
        return null
    }

    List<MultipartPart> getAll(String name) {
        List<MultipartPart> result = []
        Int index = 0
        while index < _parts.length() {
            if _parts.get(index).name() == name {
                result.push(_parts.get(index))
            }
            index = index + 1
        }
        return result
    }

    Result<Unit, Error> close() {
        if _closed { return Ok(unit) }
        _closed = true
        Int index = 0
        while index < _parts.length() {
            Result<Unit, Error> closed = _parts.get(index).close()
            if closed.isErr() { return closed }
            index = index + 1
        }
        return Ok(unit)
    }
}
```

> `MultipartFormRaw`、`parseMultipartRaw` 是运行时 multipart 原语；不是 XDK 公共类型。
