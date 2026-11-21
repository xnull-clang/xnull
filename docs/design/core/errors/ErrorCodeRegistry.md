# `ErrorCodeRegistry`

| 项 | 值 |
| --- | --- |
| 类型 | `class ErrorCodeRegistry` |
| 包 | `xdk.errors` |
| 稳定性 | `preview` |
| 依赖 | `ErrorCode`、`BasicError` |

---

## 1. 定位

显式错误码注册表；应用/库自己持有；无全局单例。

---

## 2. 设计逻辑

- 码 → `ErrorCode` 映射；同码唯一。
- 无全局状态；无隐式初始化。
- 非线程安全；共享需外部同步。
- `lookup` 缺失返回 `NotFound`；`tryRegister` 重复返回 `AlreadyExists`。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_codes` | `Map<String, ErrorCode>` | 可变 | code → ErrorCode |

不变量：key = code；同码唯一；元素非 null。

---

## 4. 生命周期

- 构造空；无 close；非线程安全。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ErrorCodeRegistry()` | 无 | 无 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `register` | 注册 | `ErrorCode code` | `Bool` | null → panic |
| `tryRegister` | checked 注册 | `ErrorCode code` | `Result<Unit, Error>` | `InvalidArgument`/`AlreadyExists` |
| `get` | 按码取 | `String code` | `ErrorCode?` | 无 |
| `contains` | 是否存在 | `String code` | `Bool` | 无 |
| `remove` | 删除 | `String code` | `Bool` | 无 |
| `all` | 全部快照 | 无 | `List<ErrorCode>` | 无 |
| `length` | 数量 | 无 | `Int` | 无 |
| `clear` | 清空 | 无 | `void` | 无 |
| `lookup` | 按码转错误 | `String code` | `Result<BasicError, Error>` | `NotFound` |

---

## 8. 使用的技术

- Map 注册表；
- 重复检测；
- 显式生命周期；
- 错误转换。

---

## 9. 需要的支撑

- 语言：class、Map、List、String、Bool、Result；
- 运行时：无；
- 接口：`ErrorCode`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`ErrorCode`、`BasicError`、`ErrorKind`、`Map`、`List`、`Result`。

---

## 11. 所有权与并发

- 可变；非线程安全。
- `all()` 返回快照。
- 无资源、无 close。

---

## 12. 示例与反例

正确：启动注册；`lookup` 转错误；`all()` 导出。  
反例：全局静态 registry；热路径重复注册；用 registry 做业务分支。

---

## 13. 测试/场景义务

register/tryRegister；重复；get/contains/remove；all/length/clear；lookup 缺失；并发外部同步。

---

## 14. XNull 伪代码

```xnull
class ErrorCodeRegistry {
    Map<String, ErrorCode> _codes = [:]

    ErrorCodeRegistry() {
    }

    Bool register(ErrorCode code) {
        if code == null {
            throw "ErrorCodeRegistry.register: null"
        }
        if _codes.has(code.code()) {
            return false
        }
        _codes.put(code.code(), code)
        return true
    }

    Result<Unit, Error> tryRegister(ErrorCode code) {
        if code == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "null code"))
        }
        if _codes.has(code.code()) {
            return Err(new BasicError(ErrorKind.AlreadyExists, "code exists"))
        }
        _codes.put(code.code(), code)
        return Ok(unit)
    }

    ErrorCode? get(String code) {
        if !_codes.has(code) {
            return null
        }
        return _codes.getOr(code, null)
    }

    Bool contains(String code) {
        return _codes.has(code)
    }

    Bool remove(String code) {
        return _codes.remove(code)
    }

    List<ErrorCode> all() {
        List<ErrorCode> result = []
        List<String> keys = _codes.keys()
        Int index = 0
        while index < keys.length() {
            result.push(_codes.getOr(keys.get(index), null))
            index = index + 1
        }
        return result
    }

    Int length() {
        return _codes.length()
    }

    void clear() {
        _codes.clear()
    }

    Result<BasicError, Error> lookup(String code) {
        if !_codes.has(code) {
            return Err(new BasicError(ErrorKind.NotFound, "unknown code: " + code))
        }
        return Ok(_codes.getOr(code, null).toBasicError())
    }
}
```
