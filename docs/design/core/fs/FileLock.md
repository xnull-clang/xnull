# `FileLock`

| 项 | 值 |
| --- | --- |
| 类型 | `class FileLock` |
| 包 | `xdk.fs` |
| 稳定性 | `preview`（X） |
| 依赖 | `Path`、`Context`、`errors` |

---

## 1. 定位

文件锁：独占/共享锁；跨进程保护。

不做：分布式锁、公平性、锁优先级。

---

## 2. 设计逻辑

- 字段 `_path`、`_exclusive`、`_held`。
- `acquire` 阻塞/超时；Context 取消。
- `release` 幂等；关闭时释放。
- OS 锁语义差异由实现适配；不承诺公平。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_path` | `Path` | 锁文件 |
| `_exclusive` | `Bool` | 独占 |
| `_held` | `Bool` | 已持有 |

不变量：held=false 后 release Ok。

---

## 4. 生命周期

acquire 获得；release 释放；可重入？不支持；非线程安全。

---

## 5. 构造契约

构造器内部；公共工厂 `FileLock.acquire(Context, Path, Bool)`。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `acquire` | 获取 | `Context, Path, Bool exclusive` | `Result<FileLock, Error>` | `Busy`/`Cancelled`/`Io` |
| `release` | 释放 | 无 | `Result<Unit, Error>` | `Io` |
| `isHeld` | 是否持有 | 无 | `Bool` | 无 |
| `path` | 路径 | 无 | `Path` | 无 |
| `isExclusive` | 是否独占 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- OS 文件锁；
- 阻塞/超时；
- Context 取消。

---

## 9. 需要的支撑

- 语言：class、Path、Bool、Result、Context；
- 运行时/OS：flock/fcntl；
- 接口：`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Path`、`Context`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

持有锁；release 释放；非线程安全；跨进程由 OS 保证。

---

## 12. 示例与反例

正确：acquire 独占 → 修改 → release。  
反例：同一进程重复 acquire 期望成功（可能死锁）；忽略 Busy；不 release。

---

## 13. 测试/场景义务

独占/共享；Busy；取消；release 幂等；多进程；close。

---

## 14. XNull 伪代码

```xnull
class FileLock {
    Path _path
    Bool _exclusive
    Bool _held

    static Result<FileLock, Error> acquire(Context context, Path path, Bool exclusive) {
        if context == null || path == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "null lock argument"))
        }
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "cancelled"))
        }
        Result<LockHandle, Error> handle = acquireLockRaw(path.text(), exclusive)
        if handle.isErr() { return Err(handle.error()) }
        FileLock result = new FileLock()
        result._path = path
        result._exclusive = exclusive
        result._held = true
        return Ok(result)
    }

    Result<Unit, Error> release() {
        if !_held { return Ok(unit) }
        _held = false
        return releaseLockRaw(_path.text())
    }

    Bool isHeld() { return _held }
    Path path() { return _path }
    Bool isExclusive() { return _exclusive }
}
```

> `LockHandle`、`acquireLockRaw/releaseLockRaw` 是 OS/运行时锁原语； 标 X。
