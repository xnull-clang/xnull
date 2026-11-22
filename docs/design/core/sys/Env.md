# `Env`

| 项 | 值 |
| --- | --- |
| 类型 | `class Env` |
| 包 | `xdk.sys` |
| 稳定性 | `stable` |
| 依赖 | 无 |

---

## 1. 定位

环境变量只读快照；用于配置/诊断/启动参数。

不做：全局 set/unset、线程局部 env、隐式刷新。

---

## 2. 设计逻辑

- 字段 `_values: Map<String,String>`；`snapshot()` 复制当前环境。
- `getOr` 缺失返回 fallback；`tryGet` 返回 `NotFound`。
- 不提供修改；需要修改时通过 `ProcessBuilder.env` 传给子进程。
- 不可变；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_values` | `Map<String,String>` | 快照 |

不变量：键值非 null；快照后不随进程环境变化。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

构造器内部；公共入口 `Env.snapshot()`。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `snapshot` | 当前快照 | 无 | `Env` | 无 |
| `get` | 取值 | `String name` | `String` | 缺失 → panic |
| `getOr` | 取值/兜底 | `String name, String fallback` | `String` | 无 |
| `tryGet` | checked 取 | `String name` | `Result<String, Error>` | `NotFound` |
| `has` | 是否存在 | `String name` | `Bool` | 无 |
| `keys` | 键快照 | 无 | `List<String>` | 无 |
| `names` | 升序键快照（1.x） | 无 | `List<String>` | 无 |
| `values` | 值快照 | 无 | `List<String>` | 无 |
| `all` | 映射快照 | 无 | `Map<String,String>` | 无 |
| `length` | 数量 | 无 | `Int` | 无 |

---

## 8. 使用的技术

- 环境快照；
- 映射复制；
- 缺失通道。

---

## 9. 需要的支撑

- 语言：class、Map、List、String、Bool、Result；
- 运行时：进程环境；文本比较 `compareText`；
- 接口：`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`BasicError`、`ErrorKind`、`Map`、`compareText`。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`Env.snapshot().getOr("PATH", "")`；`Env.snapshot().names()` 返回升序名称。

反例：期望 snapshot 实时更新；用空串表示缺失；全局修改 env；期望 `names()` 返回值。

---

## 13. 测试/场景义务

快照独立性；get/getOr/tryGet；has；keys/names 排序；values/all；空环境。

---

## 14. XNull 伪代码

```xnull
class Env {
    final Map<String, String> _values

    Env(Map<String, String> values) {
        _values = [:]
        List<String> keys = values.keys()
        Int index = 0
        while index < keys.length() {
            _values.put(keys.get(index), values.getOr(keys.get(index), ""))
            index = index + 1
        }
    }

    static Env snapshot() {
        return new Env(readEnvironmentRaw())
    }

    String get(String name) {
        if !_values.has(name) {
            throw "Env.get: missing " + name
        }
        return _values.getOr(name, "")
    }

    String getOr(String name, String fallback) {
        if !_values.has(name) { return fallback }
        return _values.getOr(name, fallback)
    }

    Result<String, Error> tryGet(String name) {
        if !_values.has(name) {
            return Err(new BasicError(ErrorKind.NotFound, "env missing: " + name))
        }
        return Ok(_values.getOr(name, ""))
    }

    Bool has(String name) { return _values.has(name) }
    List<String> keys() { return _values.keys() }

    List<String> names() {
        List<String> result = self.keys()
        result.sort((String left, String right) -> compareText(left, right))
        return result
    }

    List<String> values() { return _values.values() }
    Map<String, String> all() { return _values.copy() }
    Int length() { return _values.length() }
}
```

> `readEnvironmentRaw` 是运行时环境快照原语。
