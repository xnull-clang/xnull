# `TempDir`

| 项 | 值 |
| --- | --- |
| 类型 | `class TempDir implements Closer` |
| 包 | `xdk.fs` |
| 稳定性 | `preview` |
| 依赖 | `Path` |

---

## 1. 定位

临时目录：创建/路径/关闭删除/持久化 rename。

不做：自动清理、权限定制、跨设备 rename。

---

## 2. 设计逻辑

- 字段 `_path: Path`、`_open`。
- `create(prefix)` 在临时目录创建唯一目录。
- `close` 递归删除；幂等。
- `persist(target)` rename；成功后不再拥有目录。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_path` | `Path` | 目录 |
| `_open` | `Bool` | 未关闭 |

不变量：close 后目录删除；persist 后路径改变。

---

## 4. 生命周期

create 创建；close/persist 结束；close 幂等。

---

## 5. 构造契约

构造器内部；公共入口 `TempDir.create(prefix)`。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `create` | 创建 | `String prefix` | `Result<TempDir, Error>` | `Io` |
| `path` | 路径 | 无 | `Path` | 无 |
| `persist` | 持久化 | `String target` | `Result<Unit, Error>` | `AlreadyExists`/`Io` |
| `close` | 删除 | 无 | `Result<Unit, Error>` | `Io` |
| `isOpen` | 可用 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 临时目录创建；
- 递归删除；
- rename。

---

## 9. 需要的支撑

- 语言：class、Path、Bool、Result；
- 运行时/OS：mkdir/rename/removeTree；
- 接口：`Closer`、`Path`。

---

## 10. 依赖的特性/接口/类

`Path`、`Closer`、`FileSystem.removeTree`。

---

## 11. 所有权与并发

持有目录；close 删除；单任务。

---

## 12. 示例与反例

正确：create → 使用 → close。  
反例：persist 后 close 期望删除目标；close 后使用；跨设备 rename。

---

## 13. 测试/场景义务

create 唯一；path；persist；close 删除；close 幂等；失败清理。

---

## 14. XNull 伪代码

```xnull
class TempDir implements Closer {
    Path _path
    Bool _open

    static Result<TempDir, Error> create(String prefix) {
        Result<String, Error> created = createTempDirRaw(prefix)
        if created.isErr() { return Err(created.error()) }
        TempDir result = new TempDir()
        result._path = new Path(created.value())
        result._open = true
        return Ok(result)
    }

    Path path() { return _path }

    Result<Unit, Error> persist(String target) {
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "temp dir closed"))
        }
        Result<Unit, Error> renamed = renameRaw(_path.text(), target)
        if renamed.isErr() { return Err(renamed.error()) }
        _open = false
        _path = new Path(target)
        return Ok(unit)
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        return removeTreeRaw(_path.text())
    }

    Bool isOpen() { return _open }
}
```

> `createTempDirRaw/renameRaw/removeTreeRaw` 是 OS/运行时文件原语。
