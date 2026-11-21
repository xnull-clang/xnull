# `EnvSource`

| 项 | 值 |
| --- | --- |
| 类型 | `class EnvSource implements ConfigSource` |
| 包 | `xdk.config` |
| 稳定性 | `preview` |
| 依赖 | `sys.Env`、`ConfigEntry` |

---

## 1. 定位

环境变量来源：只读显式白名单键。

不做：全量环境导入、前缀自动映射、大小写转换。

---

## 2. 设计逻辑

- 字段 `_keys: List<String>`、`_name`、`_priority`。
- `load` 用 `Env.snapshot()`；只处理 keys；缺失跳过。
- 不做 key 名称转换；环境名即配置键。
- 无 close；不可变。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_keys` | `List<String>` | 白名单 |
| `_name` | `String` | 来源名 |
| `_priority` | `Int` | 优先级 |

不变量：keys 无 null；name 非空。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `EnvSource(List<String> keys)` | keys | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `load` | 加载 | `Context` | `Result<List<ConfigEntry>, Error>` | 无 |
| `name` | 名称 | 无 | `String` | 无 |
| `priority` | 优先级 | 无 | `Int` | 无 |
| `withName` | 派生 | `String` | `EnvSource` | 空 → panic |
| `withPriority` | 派生 | `Int` | `EnvSource` | 无 |

---

## 8. 使用的技术

- 环境快照；
- 白名单；
- 条目构造。

---

## 9. 需要的支撑

- 语言：class、List、String、Int、Result；
- 运行时：`sys.Env.snapshot`；
- 接口：`ConfigSource`、`ConfigEntry`。

---

## 10. 依赖的特性/接口/类

`ConfigSource`、`ConfigEntry`、`Env`。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`EnvSource(["APP_PORT","APP_ENV"])`。  
反例：导入全部 env（泄密）；自动小写；缺失键当空串。

---

## 13. 测试/场景义务

命中/缺失；顺序；空 keys；withName/priority；快照。

---

## 14. XNull 伪代码

```xnull
class EnvSource implements ConfigSource {
    final List<String> _keys
    final String _name
    final Int _priority

    EnvSource(List<String> keys) {
        if keys == null { throw "EnvSource: null keys" }
        _keys = keys.copy()
        _name = "env"
        _priority = 0
    }

    EnvSource withName(String name) {
        if name == "" { throw "EnvSource.withName: empty" }
        EnvSource result = new EnvSource(_keys)
        result._name = name
        return result
    }

    EnvSource withPriority(Int priority) {
        EnvSource result = new EnvSource(_keys)
        result._priority = priority
        return result
    }

    Result<List<ConfigEntry>, Error> load(Context context) {
        Env snapshot = Env.snapshot()
        List<ConfigEntry> result = []
        Int index = 0
        while index < _keys.length() {
            String key = _keys.get(index)
            String? value = snapshot.getOr(key, null)
            if value != null {
                result.push(new ConfigEntry(key, value))
            }
            index = index + 1
        }
        return Ok(result)
    }

    String name() { return _name }
    Int priority() { return _priority }
}
```
