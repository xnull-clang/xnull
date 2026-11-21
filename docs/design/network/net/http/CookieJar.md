# `CookieJar`

| 项 | 值 |
| --- | --- |
| 类型 | `class CookieJar` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | `Cookie`、`Uri` |

---

## 1. 定位

客户端 Cookie 存储：存 Cookie、按 URI 生成 Cookie 头、清理过期、清空、计数。

不做：PSL、跨站策略、持久化、线程安全、CookiePolicy。

---

## 2. 设计逻辑

- 字段 `_cookies: List<Cookie>`。
- `store` 按 name/domain/path 替换同名 Cookie；否则追加。
- `headerForRequest` 过滤 `Cookie.matches`；无匹配返回 null。
- `removeExpired` 删除过期项并返回数量。
- 可变；非线程安全；无 close；建议每客户端一个实例。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_cookies` | `List<Cookie>` | Cookie 列表 |

不变量：元素非 null；同名/域/路径唯一。

---

## 4. 生命周期

构造后可变；无 close；`cookies` 快照。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `CookieJar()` | 无 | 空 jar | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `store` | 存储/替换 | `Cookie cookie` | `void` | null → panic |
| `cookies` | 快照 | 无 | `List<Cookie>` | 无 |
| `headerForRequest` | Cookie 头/无 | `Uri requestUri` | `String?` | 无 |
| `removeExpired` | 删除过期 | `Long nowMillis` | `Int` | 无 |
| `clear` | 清空 | 无 | `void` | 无 |
| `length` | 数量 | 无 | `Int` | 无 |

---

## 8. 使用的技术

- 线性匹配；
- 名称/域/路径替换；
- 头拼接。

---

## 9. 需要的支撑

- 语言：class、List、String、Int、Bool；
- 运行时：无；
- 接口：`Cookie`、`Uri`。

---

## 10. 依赖的特性/接口/类

`Cookie`、`Uri`。

---

## 11. 所有权与并发

可变；非线程安全；无资源；快照。

---

## 12. 示例与反例

正确：`jar.store(cookie); jar.headerForRequest(uri)`。  
反例：多任务共享 jar 不加锁；实现 PSL；把 HttpOnly 当网络限制。

---

## 13. 测试/场景义务

存储/替换；匹配；过期；清空；长度；空 jar；Secure/路径；快照。

---

## 14. XNull 伪代码

```xnull
class CookieJar {
    List<Cookie> _cookies = []

    CookieJar() {
    }

    void store(Cookie cookie) {
        if cookie == null { throw "CookieJar.store: null" }
        Int index = 0
        while index < _cookies.length() {
            Cookie current = _cookies.get(index)
            if current.name() == cookie.name()
                && current.domain() == cookie.domain()
                && current.path() == cookie.path() {
                _cookies.set(index, cookie)
                return
            }
            index = index + 1
        }
        _cookies.push(cookie)
    }

    List<Cookie> cookies() { return _cookies.copy() }

    String? headerForRequest(Uri requestUri) {
        if requestUri == null { return null }
        String result = ""
        Bool has = false
        Int index = 0
        while index < _cookies.length() {
            Cookie cookie = _cookies.get(index)
            if cookie.matches(requestUri) {
                if has { result = result + "; " }
                result = result + cookie.name() + "=" + cookie.value()
                has = true
            }
            index = index + 1
        }
        if !has { return null }
        return result
    }

    Int removeExpired(Long nowMillis) {
        Int removed = 0
        Int index = _cookies.length() - 1
        while index >= 0 {
            Cookie cookie = _cookies.get(index)
            if cookie.expiresMillis() != null {
                Long expires = cookie.expiresMillis() as Long
                if expires <= nowMillis {
                    _cookies.remove(index)
                    removed = removed + 1
                }
            }
            index = index - 1
        }
        return removed
    }

    void clear() { _cookies.clear() }
    Int length() { return _cookies.length() }
}
```
