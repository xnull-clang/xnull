# `Uri`

| 项 | 值 |
| --- | --- |
| 类型 | `class Uri` |
| 包 | `xdk.net.uri` |
| 稳定性 | `preview` |
| 依赖 | `Query`、`Error` |

---

## 1. 定位

不可变 URI 值对象：解析、组件读取、派生、查询串、相对引用解析、规范文本。

不做：HTTP 请求、DNS、抓取、IDN/Punycode、完整 RFC 规范化、file URI 特殊语义。

---

## 2. 设计逻辑

- 字段保存 scheme/userInfo/host/port/path/query/fragment；可选组件用 null，不用空串哨兵。
- `parse` 调用运行时 URI 解析原语；本类只做组件持有、派生和查询串校验。
- `text()` 由运行时格式化原语组装；IPv6 方括号由原语处理。
- `with*` 返回新实例；`query` 保存 `Query` 副本，避免外部修改 Uri。
- `resolve` 调用 RFC 3986 相对引用解析原语。
- 组件保留原始百分号编码；`Query` 解码查询键值。
- 不可变；无 close；可跨任务共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_scheme` | `String?` | 无 scheme → null |
| `_userInfo` | `String?` | 无 userInfo → null |
| `_host` | `String?` | 无 host → null |
| `_port` | `Int?` | 无端口 → null |
| `_path` | `String` | 可为空串 |
| `_query` | `Query` | 查询副本；可空 Query |
| `_hasQuery` | `Bool` | 是否存在 `?` |
| `_fragment` | `String?` | 无 fragment → null |

不变量：scheme 合法或 null；port 0..65535 或 null；query 非 null；不可变。

---

## 4. 生命周期

`parse`/`with*` 创建；无 close；不可变；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Uri.parse(String text)` | text | 非 null | 非法 → `InvalidArgument`/`DataCorrupted` |

构造器私有；业务代码用 `parse` 或 `with*`。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `parse` | 解析 URI | `String text` | `Result<Uri, Error>` | `InvalidArgument`/`DataCorrupted` |
| `scheme` | 方案 | 无 | `String?` | 无 |
| `userInfo` | 用户信息 | 无 | `String?` | 无 |
| `host` | 主机 | 无 | `String?` | 无 |
| `port` | 端口 | 无 | `Int?` | 无 |
| `path` | 路径 | 无 | `String` | 无 |
| `query` | 查询副本 | 无 | `Query` | 无 |
| `hasQuery` | 是否有查询 | 无 | `Bool` | 无 |
| `fragment` | 片段 | 无 | `String?` | 无 |
| `isAbsolute` | 是否有 scheme | 无 | `Bool` | 无 |
| `authority` | authority 文本 | 无 | `String?` | 无 |
| `text` | 规范文本 | 无 | `String` | 无 |
| `withScheme` | 派生 scheme | `String scheme` | `Uri` | 非法 → panic |
| `withUserInfo` | 派生 userInfo | `String? userInfo` | `Uri` | 无 |
| `withHost` | 派生 host | `String host` | `Uri` | 空/null → panic |
| `withPort` | 派生 port | `Int? port` | `Uri` | 越界 → panic |
| `withPath` | 派生 path | `String path` | `Uri` | null → panic |
| `withQuery` | 派生 query | `Query query` | `Uri` | null → panic |
| `withoutQuery` | 移除 query | 无 | `Uri` | 无 |
| `withFragment` | 派生 fragment | `String? fragment` | `Uri` | 无 |
| `withoutFragment` | 移除 fragment | 无 | `Uri` | 无 |
| `resolve` | 相对引用解析 | `Uri reference` | `Result<Uri, Error>` | `InvalidArgument` |
| `equals` | 值相等 | `Uri other` | `Bool` | 无 |
| `toString` | 文本 | 无 | `String` | 无 |

说明：

- `port()` 无端口返回 null；不返回 `-1`。
- `query()` 返回副本；修改副本不影响 Uri。
- `withScheme` 只接受 `isValidScheme`。
- `resolve` 对相对/绝对引用都可用；结果由运行时原语规范化。
- `equals` 按 `text()` 比较；不做大小写/点段规范化。

---

## 8. 使用的技术

- URI 解析/格式化；
- 查询串；
- 不可变派生；
- IPv6 authority 格式化。

---

## 9. 需要的支撑

- 语言：class、String、Int、Bool、Result；
- 运行时：`parseUriRaw`、`formatUriRaw`、`resolveUriRaw`、`UriParts`；
- 接口：`Query`、`Error`、`isValidScheme`。

---

## 10. 依赖的特性/接口/类

`Query`、`Error`、`isValidScheme`、`UriParts`、`parseUriRaw`、`formatUriRaw`、`resolveUriRaw`。

---

## 11. 所有权与并发

不可变；可共享；`query()` 返回副本；无资源。

---

## 12. 示例与反例

正确：`Uri.parse("https://example.com:8443/a?q=1").host()`。  
反例：用 `-1` 表示无端口；修改 `query()` 期望 Uri 变化；把非法 `%` 当普通字符；依赖 `text()` 与输入逐字节相同。

---

## 13. 测试/场景义务

绝对/相对 URI；scheme/host/port；userInfo；IPv6；query 存在/缺失；fragment；with*；resolve；非法端口/百分号；equals/text。

---

## 14. XNull 伪代码

```xnull
class Uri {
    final String? _scheme
    final String? _userInfo
    final String? _host
    final Int? _port
    final String _path
    final Query _query
    final Bool _hasQuery
    final String? _fragment

    private Uri(String? scheme, String? userInfo, String? host, Int? port,
                String path, Query query, Bool hasQuery, String? fragment) {
        _scheme = scheme
        _userInfo = userInfo
        _host = host
        _port = port
        _path = path
        _query = query.copy()
        _hasQuery = hasQuery
        _fragment = fragment
    }

    static Result<Uri, Error> parse(String text) {
        if text == null { throw "Uri.parse: null text" }
        Result<UriParts, Error> parsed = parseUriRaw(text)
        if parsed.isErr() { return Err(parsed.error()) }
        UriParts parts = parsed.value()
        Query query = new Query()
        if parts.hasQuery() {
            Result<Query, Error> parsedQuery = Query.parse(parts.rawQuery())
            if parsedQuery.isErr() { return Err(parsedQuery.error()) }
            query = parsedQuery.value()
        }
        return Ok(new Uri(
            parts.scheme(), parts.userInfo(), parts.host(), parts.port(),
            parts.path(), query, parts.hasQuery(), parts.fragment()))
    }

    String? scheme() { return _scheme }
    String? userInfo() { return _userInfo }
    String? host() { return _host }
    Int? port() { return _port }
    String path() { return _path }
    Query query() { return _query.copy() }
    Bool hasQuery() { return _hasQuery }
    String? fragment() { return _fragment }
    Bool isAbsolute() { return _scheme != null }

    String? authority() {
        if _host == null { return null }
        String hostText = _host as String
        String result = ""
        if _userInfo != null {
            result = (_userInfo as String) + "@"
        }
        if hostText.indexOf(":") >= 0 {
            result = result + "[" + hostText + "]"
        } else {
            result = result + hostText
        }
        if _port != null {
            result = result + ":" + str(_port as Int)
        }
        return result
    }

    String text() {
        return formatUriRaw(
            _scheme, _userInfo, _host, _port, _path, _query, _hasQuery, _fragment)
    }

    Uri withScheme(String scheme) {
        if !isValidScheme(scheme) { throw "Uri.withScheme: invalid scheme" }
        return new Uri(scheme, _userInfo, _host, _port, _path, _query, _hasQuery, _fragment)
    }

    Uri withUserInfo(String? userInfo) {
        return new Uri(_scheme, userInfo, _host, _port, _path, _query, _hasQuery, _fragment)
    }

    Uri withHost(String host) {
        if host == null || host == "" { throw "Uri.withHost: empty host" }
        return new Uri(_scheme, _userInfo, host, _port, _path, _query, _hasQuery, _fragment)
    }

    Uri withPort(Int? port) {
        if port != null {
            Int value = port as Int
            if value < 0 || value > 65535 {
                throw "Uri.withPort: invalid port"
            }
        }
        return new Uri(_scheme, _userInfo, _host, port, _path, _query, _hasQuery, _fragment)
    }

    Uri withPath(String path) {
        if path == null { throw "Uri.withPath: null path" }
        return new Uri(_scheme, _userInfo, _host, _port, path, _query, _hasQuery, _fragment)
    }

    Uri withQuery(Query query) {
        if query == null { throw "Uri.withQuery: null query" }
        return new Uri(_scheme, _userInfo, _host, _port, _path, query, true, _fragment)
    }

    Uri withoutQuery() {
        return new Uri(_scheme, _userInfo, _host, _port, _path, new Query(), false, _fragment)
    }

    Uri withFragment(String? fragment) {
        return new Uri(_scheme, _userInfo, _host, _port, _path, _query, _hasQuery, fragment)
    }

    Uri withoutFragment() {
        return new Uri(_scheme, _userInfo, _host, _port, _path, _query, _hasQuery, null)
    }

    Result<Uri, Error> resolve(Uri reference) {
        if reference == null { throw "Uri.resolve: null reference" }
        return resolveUriRaw(self, reference)
    }

    Bool equals(Uri other) {
        if other == null { return false }
        return self.text() == other.text()
    }

    String toString() { return self.text() }
}
```

> `UriParts`、`parseUriRaw`、`formatUriRaw`、`resolveUriRaw` 是运行时 URI 原语；不是 XDK 公共类型。
