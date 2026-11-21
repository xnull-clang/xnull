# `TempFile`

| 项 | 值 |
| --- | --- |
| 类型 | `class TempFile implements Closer` |
| 包 | `xdk.fs` |
| 稳定性 | `preview` |
| 依赖 | `Path`、`File` |

---

## 1. 定位

临时文件：创建/读写/关闭/持久化 rename。

不做：自动清理线程、原子跨设备、权限定制。

---

## 2. 设计逻辑

- 字段 `_path: Path`、`_file: File`、`_open`。
- `create(prefix,suffix)` 在临时目录创建唯一文件。
- `persist(target)` rename 到目标；成功后 TempFile 不再拥有文件。
- `close` 删除临时文件；幂等。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_path` | `Path` | 临时路径 |
| `_file` | `File` | 句柄 |
| `_open` | `Bool` | 未关闭 |

不变量：close 后文件删除；persist 后路径改变。

---

## 4. 生命周期

create 创建；close/persist 结束；close 幂等。

---

## 5. 构造契约

构造器内部；公共入口 `TempFile.create(prefix,suffix)`。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `create` | 创建 | `String prefix, String suffix` | `Result<TempFile, Error>` | `Io` |
| `path` | 路径 | 无 | `Path` | 无 |
| `file` | 句柄 | 无 | `File` | 无 |
| `persist` | 持久化 | `String target` | `Result<Unit, Error>` | `AlreadyExists`/`Io` |
| `close` | 关闭/删除 | 无 | `Result<Unit, Error>` | `Io` |
| `isOpen` | 可用 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 唯一文件名；
- 临时目录；
- rename；
- 删除。

---

## 9. 需要的支撑

- 语言：class、Path、File、Bool、Result；
- 运行时/OS：mkstemp/rename/unlink；
- 接口：`Closer`、`Path`、`File`。

---

## 10. 依赖的特性/接口/类

`Path`、`File`、`Closer`。

---

## 11. 所有权与并发

持有临时文件；close 删除；单任务。

---

## 12. 示例与反例

正确：create → write → persist → close。  
反例：persist 后 close 期望删除目标；close 后写；跨设备 rename 期望原子。

---

## 13. 测试/场景义务

create 唯一；写/读；persist；close 删除；close 幂等；失败清理。

---

## 14. XNull 伪代码

```xnull
class TempFile implements Closer {
    Path _path
    File _file
    Bool _open

    static Result<TempFile, Error> create(String prefix, String suffix) {
        Result<String, Error> created = createTempFileRaw(prefix, suffix)
        if created.isErr() { return Err(created.error()) }
        Path path = new Path(created.value())
        Result<File, Error> opened = File.open(path, OpenOptions.write())
        if opened.isErr() {
            removeFileRaw(path.text())
            return Err(opened.error())
        }
        TempFile result = new TempFile()
        result._path = path
        result._file = opened.value()
        result._open = true
        return Ok(result)
    }

    Path path() { return _path }
    File file() { return _file }

    Result<Unit, Error> persist(String target) {
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "temp file closed"))
        }
        Result<Unit, Error> closed = _file.close()
        if closed.isErr() { return Err(closed.error()) }
        Result<Unit, Error> renamed = renameRaw(_path.text(), target)
        if renamed.isErr() { return Err(renamed.error()) }
        _open = false
        _path = new Path(target)
        return Ok(unit)
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        _file.close()
        return removeFileRaw(_path.text())
    }

    Bool isOpen() { return _open }
}
```

> `createTempFileRaw/renameRaw/removeFileRaw` 是 OS/运行时文件原语；跨设备 rename 可能失败。
