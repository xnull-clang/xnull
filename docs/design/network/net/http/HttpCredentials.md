# `HttpCredentials`

| 项 | 值 |
| --- | --- |
| 类型 | `class HttpCredentials` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

HTTP Authorization 凭据值对象：方案 + 参数。

不做：发送、挑战、加密、令牌刷新。

---

## 2. 设计逻辑

- 字段 `_scheme`、`_parameters: Map<String,String>`；不可变。
- scheme 小写；参数名小写；值保留。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_scheme` | `String` | 方案 |
| `_parameters` | `Map<String,String>` | 参数 |

---

## 4. 生命周期

不可变；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `HttpCredentials(String scheme, Map<String,String> parameters)` | 非 null | scheme 非空 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `scheme` | 方案 | 无 | `String` | 无 |
| `parameter` | 参数/无 | `String name` | `String?` | 无 |
| `parameters` | 参数快照 | 无 | `Map<String,String>` | 无 |
| `toString` | 摘要 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 不可变值对象；
- 参数表。

---

## 9. 需要的支撑

- 语言：class、String、Map；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

不可变；无资源；可共享。

---

## 12. 示例与反例

正确：`new HttpCredentials("basic", params)`。  
反例：把密码写进 toString；方案大写；可变参数。

---

## 13. 测试/场景义务

方案/参数；大小写；快照；toString 不含秘密。

---

## 14. XNull 伪代码

```xnull
class HttpCredentials {
    final String _scheme
    final Map<String, String> _parameters

    HttpCredentials(String scheme, Map<String, String> parameters) {
        if scheme == null || scheme == "" { throw "HttpCredentials: empty scheme" }
        if parameters == null { throw "HttpCredentials: null parameters" }
        _scheme = scheme.toLower()
        _parameters = parameters.copy()
    }

    String scheme() { return _scheme }

    String? parameter(String name) {
        if name == null { return null }
        String key = name.toLower()
        if !_parameters.has(key) { return null }
        return _parameters.getOr(key, "")
    }

    Map<String, String> parameters() { return _parameters.copy() }
    String toString() { return _scheme }
}
```
