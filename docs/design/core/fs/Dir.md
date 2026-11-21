# `Dir`

| 项 | 值 |
| --- | --- |
| 类型 | `class Dir implements Closer` |
| 包 | `xdk.fs` |
| 稳定性 | `stable` |
| 依赖 | `Path`、`DirEntry` |

---

## 1. 定位

目录句柄：逐个读取条目/一次列出/遍历/创建/删除。

不做：递归内容读取（`FileSystem.walk`）、排序承诺、文件锁。

---

## 2. 设计逻辑

- 字段 `_path`、`_entries: List<DirEntry>`、`_index`、`_open`。
- `open` 读取条目快照；`next` 返回下一个或 null。
- 顺序不承诺；`.`/`..` 由实现决定（ 不包含）。
- `close` 幂等；关闭后 next `Unavailable`。
- 非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_path` | `Path` | 目录 |
| `_entries` | `List<DirEntry>` | 快照 |
| `_index` | `Int` | 当前位置 |
| `_open` | `Bool` | 可用 |

不变量：0 ≤ index ≤ entries.length。

---

## 4. 生命周期

`open` 创建；必须 close；close 幂等。

---

## 5. 构造契约

构造器内部；公共入口 `Dir.open(Path)`。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `open` | 打开 | `Path path` | `Result<Dir, Error>` | `NotFound`/`PermissionDenied` |
| `next` | 下一个 | 无 | `Result<DirEntry?, Error>` | `Unavailable` |
| `nextOrNull` | 下一个/null | 无 | `DirEntry?` | 无 |
| `entries` | 全部剩余 | 无 | `Result<List<DirEntry>, Error>` | `Unavailable` |
| `list` | 名称列表 | 无 | `Result<List<String>, Error>` | `Unavailable` |
| `walk` | 递归路径 | 无 | `Result<List<Path>, Error>` | `Io` |
| `glob` | 通配 | `String pattern` | `Result<List<Path>, Error>` | `InvalidArgument` |
| `create` | 创建目录 | 无 | `Result<Unit, Error>` | `AlreadyExists`/`Io` |
| `remove` | 删除空目录 | 无 | `Result<Unit, Error>` | `Io` |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | 无 |
| `isOpen` | 可用 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 目录枚举快照；
- 索引游标；
- 递归遍历；
- glob 匹配。

---

## 9. 需要的支撑

- 语言：class、Path、DirEntry、List、Int、Result；
- 运行时/OS：opendir/readdir/stat；
- 接口：`Closer`、`Path`、`DirEntry`、`PathMatcher`。

---

## 10. 依赖的特性/接口/类

`Path`、`DirEntry`、`Closer`、`PathMatcher`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

持有目录快照/句柄；close 释放；单任务。

---

## 12. 示例与反例

正确：open → while next → close。  
反例：依赖顺序；close 后 next；把 `.`/`..` 当业务条目。

---

## 13. 测试/场景义务

空/单/多；next 到 EOF；entries/list；walk/glob；create/remove；close 幂等。

---

## 14. XNull 伪代码

```xnull
class Dir implements Closer {
    Path _path
    List<DirEntry> _entries
    Int _index
    Bool _open

    static Result<Dir, Error> open(Path path) {
        if path == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "null path"))
        }
        Result<List<DirEntry>, Error> entries = readDirRaw(path.text())
        if entries.isErr() { return Err(entries.error()) }
        Dir result = new Dir()
        result._path = path
        result._entries = entries.value()
        result._index = 0
        result._open = true
        return Ok(result)
    }

    Result<DirEntry?, Error> next() {
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "dir closed"))
        }
        if _index >= _entries.length() { return Ok(null) }
        DirEntry entry = _entries.get(_index)
        _index = _index + 1
        return Ok(entry)
    }

    DirEntry? nextOrNull() {
        Result<DirEntry?, Error> result = self.next()
        if result.isErr() { return null }
        return result.value()
    }

    Result<List<DirEntry>, Error> entries() {
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "dir closed"))
        }
        List<DirEntry> result = []
        while _index < _entries.length() {
            result.push(_entries.get(_index))
            _index = _index + 1
        }
        return Ok(result)
    }

    Result<List<String>, Error> list() {
        Result<List<DirEntry>, Error> all = self.entries()
        if all.isErr() { return Err(all.error()) }
        List<String> result = []
        Int index = 0
        while index < all.value().length() {
            result.push(all.value().get(index).name())
            index = index + 1
        }
        return Ok(result)
    }

    Result<Unit, Error> close() { _open = false; return Ok(unit) }
    Bool isOpen() { return _open }
}
```

> `readDirRaw` 是 OS 目录原语；walk/glob/create/remove 复用 FileSystem/PathMatcher。
