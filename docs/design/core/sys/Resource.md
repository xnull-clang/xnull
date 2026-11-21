# `Resource`

| 项 | 值 |
| --- | --- |
| 类型 | `class Resource` |
| 包 | `xdk.sys` |
| 稳定性 | `preview` |
| 依赖 | `Bytes`、`Context`、`errors` |

---

## 1. 定位

内嵌资源句柄：路径/存在/大小/读取/列表。

不做：写入、文件系统回退、资源热更新。

---

## 2. 设计逻辑

- 字段 `_path: String`、`_exists: Bool`、`_size: Long`。
- `Resource.of(path)` 查询资源表；缺失仍可构造，`exists=false`。
- `bytes/text` 读取并返回 `Result`；可取消。
- 无 close；资源只读。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_path` | `String` | 资源路径 |
| `_exists` | `Bool` | 是否存在 |
| `_size` | `Long` | 大小 |

不变量：path 规范化（相对、`/` 分隔）；size ≥0。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Resource.of(String path)` | path | 相对路径 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `path` | 路径 | 无 | `String` | 无 |
| `exists` | 存在 | 无 | `Bool` | 无 |
| `size` | 大小 | 无 | `Long` | 无 |
| `bytes` | 读字节 | `Context` | `Result<Bytes, Error>` | `NotFound`/`Cancelled` |
| `text` | 读文本 | `Context` | `Result<String, Error>` | 同上 |
| `list` | 同前缀资源 | `Context` | `Result<List<String>, Error>` | `Cancelled` |

---

## 8. 使用的技术

- 资源表查找；
- 只读读取；
- 路径规范化；
- 取消。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Long、Bytes、Result、Context；
- 运行时：内嵌资源表；
- 接口：`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Bytes`、`Context`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

不可变；可共享；只读；无资源。

---

## 12. 示例与反例

正确：`Resource.of("config/default.conf").text(ctx)`。  
反例：用 Resource 读普通文件；期望写入；路径 `..` 越界。

---

## 13. 测试/场景义务

存在/缺失；大小；bytes/text；取消；路径非法；list 前缀。

---

## 14. XNull 伪代码

```xnull
class Resource {
    final String _path
    final Bool _exists
    final Long _size

    Resource(String path, Bool exists, Long size) {
        _path = path
        _exists = exists
        _size = size
    }

    static Resource of(String path) {
        if !resourcePathOk(path) {
            throw "Resource.of: invalid path"
        }
        Bool exists = resourceExistsRaw(path)
        Long size = 0
        if exists { size = resourceSizeRaw(path) }
        return new Resource(path, exists, size)
    }

    String path() { return _path }
    Bool exists() { return _exists }
    Long size() { return _size }

    Result<Bytes, Error> bytes(Context context) {
        if !_exists {
            return Err(new BasicError(ErrorKind.NotFound, "resource missing"))
        }
        return readResourceRaw(context, _path)
    }

    Result<String, Error> text(Context context) {
        Result<Bytes, Error> data = self.bytes(context)
        if data.isErr() { return Err(data.error()) }
        return Ok(toUtf8(data.value()))
    }

    Result<List<String>, Error> list(Context context) {
        return listResourcesRaw(context, _path)
    }
}
```

> `resourcePathOk/resourceExistsRaw/resourceSizeRaw/readResourceRaw/listResourcesRaw` 是运行时资源原语。
