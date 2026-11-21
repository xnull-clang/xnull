# `OpenOptions`

| 项 | 值 |
| --- | --- |
| 类型 | `class OpenOptions` |
| 包 | `xdk.fs` |
| 稳定性 | `stable` |
| 依赖 | `Permissions` |

---

## 1. 定位

文件打开选项：读/写/追加/创建/新建/截断/同步/权限。

不做：文件锁、内存映射、异步。

---

## 2. 设计逻辑

- 可变 builder；`with*` 返回 self（或新实例？本设计返回 self，便于链式）。
- 默认全 false；`read()`/`write()`/`append()` 静态工厂给出常用组合。
- `createNew` 与 `create` 互斥；`append` 隐含写。
- 打开时校验组合；非法组合 `InvalidArgument`。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_read` | `Bool` | 读 |
| `_write` | `Bool` | 写 |
| `_append` | `Bool` | 追加 |
| `_create` | `Bool` | 创建 |
| `_createNew` | `Bool` | 必须新建 |
| `_truncate` | `Bool` | 截断 |
| `_sync` | `Bool` | 同步写 |
| `_permissions` | `Permissions?` | 创建权限 |

不变量：append → write；createNew 与 create 不共存；truncate 仅写。

---

## 4. 生命周期

可变构建期；传给 `File.open` 后不再修改。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `OpenOptions()` | 无 | 全 false | 无 |
| `read()` | 无 | read=true | 无 |
| `write()` | 无 | write=true/create=true/truncate=true | 无 |
| `append()` | 无 | write=true/create=true/append=true | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `withRead` | 设置读 | `Bool` | `OpenOptions` | 无 |
| `withWrite` | 设置写 | `Bool` | `OpenOptions` | 无 |
| `withAppend` | 设置追加 | `Bool` | `OpenOptions` | 无 |
| `withCreate` | 创建 | `Bool` | `OpenOptions` | 无 |
| `withCreateNew` | 必须新建 | `Bool` | `OpenOptions` | 无 |
| `withTruncate` | 截断 | `Bool` | `OpenOptions` | 无 |
| `withSync` | 同步 | `Bool` | `OpenOptions` | 无 |
| `withPermissions` | 创建权限 | `Permissions` | `OpenOptions` | null → panic |
| `isRead` | 读？ | 无 | `Bool` | 无 |
| `isWrite` | 写？ | 无 | `Bool` | 无 |
| `isAppend` | 追加？ | 无 | `Bool` | 无 |
| `isCreate` | 创建？ | 无 | `Bool` | 无 |
| `isCreateNew` | 新建？ | 无 | `Bool` | 无 |
| `isTruncate` | 截断？ | 无 | `Bool` | 无 |
| `isSync` | 同步？ | 无 | `Bool` | 无 |
| `permissions` | 权限 | 无 | `Permissions?` | 无 |
| `validate` | 校验组合 | 无 | `Result<Unit, Error>` | `InvalidArgument` |

---

## 8. 使用的技术

- Builder；
- 打开模式组合；
- 权限位。

---

## 9. 需要的支撑

- 语言：class、Bool、Result；
- 运行时：无；
- 接口：`Permissions`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Permissions`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

可变 builder；打开后不应修改；无资源。

---

## 12. 示例与反例

正确：`OpenOptions.write().withSync(true)`。  
反例：append 但 write=false；createNew+create；truncate 只读。

---

## 13. 测试/场景义务

工厂；每个 with；validate；权限；append 隐含写；truncate 只写。

---

## 14. XNull 伪代码

```xnull
class OpenOptions {
    Bool _read = false
    Bool _write = false
    Bool _append = false
    Bool _create = false
    Bool _createNew = false
    Bool _truncate = false
    Bool _sync = false
    Permissions? _permissions = null

    OpenOptions() {
    }

    static OpenOptions read() {
        OpenOptions result = new OpenOptions()
        result._read = true
        return result
    }

    static OpenOptions write() {
        OpenOptions result = new OpenOptions()
        result._write = true
        result._create = true
        result._truncate = true
        return result
    }

    static OpenOptions append() {
        OpenOptions result = new OpenOptions()
        result._write = true
        result._create = true
        result._append = true
        return result
    }

    OpenOptions withRead(Bool value) { _read = value; return self }
    OpenOptions withWrite(Bool value) { _write = value; return self }
    OpenOptions withAppend(Bool value) { _append = value; return self }
    OpenOptions withCreate(Bool value) { _create = value; return self }
    OpenOptions withCreateNew(Bool value) { _createNew = value; return self }
    OpenOptions withTruncate(Bool value) { _truncate = value; return self }
    OpenOptions withSync(Bool value) { _sync = value; return self }

    OpenOptions withPermissions(Permissions value) {
        if value == null { throw "OpenOptions.withPermissions: null" }
        _permissions = value
        return self
    }

    Bool isRead() { return _read }
    Bool isWrite() { return _write }
    Bool isAppend() { return _append }
    Bool isCreate() { return _create }
    Bool isCreateNew() { return _createNew }
    Bool isTruncate() { return _truncate }
    Bool isSync() { return _sync }
    Permissions? permissions() { return _permissions }

    Result<Unit, Error> validate() {
        if _append && !_write {
            return Err(new BasicError(ErrorKind.InvalidArgument, "append requires write"))
        }
        if _createNew && _create {
            return Err(new BasicError(ErrorKind.InvalidArgument, "createNew conflicts create"))
        }
        if _truncate && !_write {
            return Err(new BasicError(ErrorKind.InvalidArgument, "truncate requires write"))
        }
        return Ok(unit)
    }
}
```
