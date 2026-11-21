# `CorsPolicy`

| 项 | 值 |
| --- | --- |
| 类型 | `class CorsPolicy` |
| 包 | `xdk.api` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`ApiContext`、`HttpMethod`、`ProblemDetails`、`Error` |

---

## 1. 定位

CORS 策略：允许源、方法、请求头、暴露头、凭据、预检缓存时间；处理实际请求头与 OPTIONS 预检。

不做：CSRF 防护、认证、通配子域、私有网络访问、代理、浏览器安全策略实现。

---

## 2. 设计逻辑

- 只允许显式 origin；`*` 仅用于无凭据请求。
- `allowCredentials(true)` 与 `*` 互斥：任一方向先设置都会 panic，避免生成非法组合。
- 实际请求：回显允许的 origin，按需加 `Access-Control-Allow-Credentials`/`Access-Control-Expose-Headers`，继续路由。
- 预检：`OPTIONS` + `Access-Control-Request-Method`；校验方法与请求头，成功 204，失败 403 ProblemDetails 并结束。
- 实际请求的 origin 不允许时不写 CORS 头，但仍继续处理（浏览器自行拦截）；预检不允许时直接 403。
- 回显 origin 时加 `Vary: Origin`；预检再加 `Access-Control-Request-Method`/`Access-Control-Request-Headers`。
- `null` origin 必须显式允许；不支持子域通配。
- 头名比较大小写不敏感；`*` 请求头只在无凭据时回显请求列表；重复 `Origin` 头按非法处理。
- 策略构建期可变；无 close；非线程安全（bind 时复制）。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_allowedOrigins` | `List<String>` | 精确 origin 或 `*`/`null` |
| `_allowedMethods` | `List<HttpMethod>` | 允许方法 |
| `_allowedHeaders` | `List<String>` | 允许请求头 |
| `_exposedHeaders` | `List<String>` | 暴露响应头 |
| `_allowCredentials` | `Bool` | 是否允许凭据 |
| `_maxAgeSeconds` | `Long` | 预检缓存秒数，≥0 |

不变量：origin/header 去重；`*` 与凭据不同时存在；maxAge ≥0；列表非 null。

---

## 4. 生命周期

构造后配置；`ApiOptions` 快照时复制；无 close；非线程安全；运行期只读。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `CorsPolicy()` | 无 | 默认方法 GET/POST/PUT/PATCH/DELETE/HEAD/OPTIONS；无 origin | 无 |

---

## 6. 字段表

见 §3；字段私有。`_allowedMethods` 默认包含常用 REST 方法；`_allowedHeaders`/`_exposedHeaders` 默认为空。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `allowOrigin` | 允许源 | `String origin` | `CorsPolicy` | 非法/与凭据冲突 → panic |
| `allowOrigins` | 批量允许源 | `List<String> origins` | `CorsPolicy` | 同上 |
| `allowAnyOrigin` | 允许 `*` | 无 | `CorsPolicy` | 凭据已开 → panic |
| `allowedOrigins` | 源快照 | 无 | `List<String>` | 无 |
| `isOriginAllowed` | 源是否允许 | `String origin` | `Bool` | 无 |
| `allowMethod` | 允许方法 | `HttpMethod method` | `CorsPolicy` | null → panic |
| `allowedMethods` | 方法快照 | 无 | `List<HttpMethod>` | 无 |
| `allowHeader` | 允许请求头 | `String name` | `CorsPolicy` | 非法/与凭据冲突 → panic |
| `allowAnyHeader` | 允许任意请求头 | 无 | `CorsPolicy` | 凭据已开 → panic |
| `allowedHeaders` | 请求头快照 | 无 | `List<String>` | 无 |
| `exposeHeader` | 暴露响应头 | `String name` | `CorsPolicy` | 非法 → panic |
| `exposedHeaders` | 暴露头快照 | 无 | `List<String>` | 无 |
| `allowCredentials` | 设置凭据 | `Bool value` | `CorsPolicy` | 与 `*` 冲突 → panic |
| `isAllowCredentials` | 是否允许凭据 | 无 | `Bool` | 无 |
| `maxAgeSeconds` | 设置缓存秒数 | `Long value` | `CorsPolicy` | <0 → panic |
| `maxAgeSeconds` | 读取缓存秒数 | 无 | `Long` | 无 |
| `process` | 处理请求 | `Context context, ApiContext exchange` | `Result<Bool, Error>` | 写响应失败 |
| `copy` | 复制策略 | 无 | `CorsPolicy` | 无 |

说明：

- `process` 返回 true 表示已结束（预检成功或预检拒绝）；false 表示继续路由。
- 无 `Origin` 头时直接返回 false。
- 实际请求 origin 不允许时不写 CORS 头，返回 false。
- 预检方法/头不允许时写 403 ProblemDetails，返回 true。
- `allowAnyOrigin` 等价于 `allowOrigin("*")`；`allowAnyHeader` 等价于 `allowHeader("*")`。
- 头名去重大小写不敏感；保留首次写法。
- `copy` 独立列表与标量。

---

## 8. 使用的技术

- Origin 允许列表；
- 预检判定；
- 头名大小写不敏感比较；
- 通配/凭据约束；
- Vary 去重；
- ProblemDetails 403。

---

## 9. 需要的支撑

- 语言：class、List、String、Bool、Long、Result；
- 运行时：`Uri.parse`（origin 校验）、`parseHttpMethod`、`httpMethodName`；
- 接口：`Context`、`ApiContext`、`HttpMethod`、`ProblemDetails`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Context`、`ApiContext`、`HttpMethod`、`ProblemDetails`、`Uri`、`parseHttpMethod`、`httpMethodName`、`Error`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

引用语义；构建期非线程安全；快照后只读；`process` 不修改策略，只修改 `ApiContext` 响应头；可被并发请求共享；无资源；无取消点。

---

## 12. 示例与反例

正确：

```text
CorsPolicy cors = new CorsPolicy()
    .allowOrigin("https://app.example")
    .allowMethod(HttpMethod.Post)
    .allowHeader("Content-Type")
    .allowHeader("Authorization")
    .exposeHeader("RateLimit-Limit")
    .maxAgeSeconds(600)
```

反例：

- `allowCredentials(true)` 后再 `allowAnyOrigin()`；
- 把 `https://*.example` 当通配；
- 回显任意 Origin；
- 预检失败仍继续路由；
- 实际请求 origin 不允许却回显；
- `null` origin 未显式允许。

---

## 13. 测试/场景义务

默认值；允许/拒绝 origin；`*`；凭据互斥；`null` origin；实际请求头；预检成功 204；预检方法拒绝；预检头拒绝/通配；Vary 去重；Max-Age；暴露头；copy 独立；多 Origin 头防御。

---

## 14. XNull 伪代码

> 非可执行设计伪代码。

```xnull
class CorsPolicy {
    List<String> _allowedOrigins = []
    List<HttpMethod> _allowedMethods = [HttpMethod.Get, HttpMethod.Post,
        HttpMethod.Put, HttpMethod.Patch, HttpMethod.Delete,
        HttpMethod.Head, HttpMethod.Options]
    List<String> _allowedHeaders = []
    List<String> _exposedHeaders = []
    Bool _allowCredentials = false
    Long _maxAgeSeconds = 0

    CorsPolicy() {
    }

    CorsPolicy allowOrigin(String origin) {
        if origin == null || origin == "" {
            throw "CorsPolicy.allowOrigin: empty origin"
        }
        String normalized = self.normalizeOrigin(origin)
        if normalized == "*" && _allowCredentials {
            throw "CorsPolicy.allowOrigin: wildcard with credentials"
        }
        Int index = 0
        while index < _allowedOrigins.length() {
            if _allowedOrigins.get(index) == normalized { return self }
            index = index + 1
        }
        _allowedOrigins.push(normalized)
        return self
    }

    CorsPolicy allowOrigins(List<String> origins) {
        if origins == null { throw "CorsPolicy.allowOrigins: null" }
        Int index = 0
        while index < origins.length() {
            self.allowOrigin(origins.get(index))
            index = index + 1
        }
        return self
    }

    CorsPolicy allowAnyOrigin() {
        return self.allowOrigin("*")
    }

    List<String> allowedOrigins() { return _allowedOrigins.copy() }

    private String normalizeOrigin(String origin) {
        String value = origin.trim()
        if value == "*" || value == "null" { return value }
        if value.endsWith("/") { value = value.substring(0, value.length() - 1) }
        Result<Uri, Error> parsed = Uri.parse(value)
        if parsed.isErr() {
            throw "CorsPolicy.allowOrigin: invalid origin"
        }
        Uri uri = parsed.value()
        if uri.scheme() == null || uri.host() == null {
            throw "CorsPolicy.allowOrigin: origin needs scheme and host"
        }
        if uri.userInfo() != null {
            throw "CorsPolicy.allowOrigin: origin must not have user info"
        }
        String scheme = (uri.scheme() as String).toLower()
        if scheme != "http" && scheme != "https" {
            throw "CorsPolicy.allowOrigin: unsupported scheme"
        }
        if uri.path() != "" && uri.path() != "/" {
            throw "CorsPolicy.allowOrigin: origin must not have path"
        }
        if uri.hasQuery() || uri.fragment() != null {
            throw "CorsPolicy.allowOrigin: origin must not have query or fragment"
        }
        return value
    }

    Bool isOriginAllowed(String origin) {
        if origin == null || origin == "" { return false }
        Int index = 0
        while index < _allowedOrigins.length() {
            String allowed = _allowedOrigins.get(index)
            if allowed == "*" {
                return !_allowCredentials
            }
            if allowed == origin { return true }
            index = index + 1
        }
        return false
    }

    CorsPolicy allowMethod(HttpMethod method) {
        if method == null { throw "CorsPolicy.allowMethod: null" }
        if _allowedMethods.indexOf(method) < 0 { _allowedMethods.push(method) }
        return self
    }

    List<HttpMethod> allowedMethods() { return _allowedMethods.copy() }

    CorsPolicy allowHeader(String name) {
        if name == null || name == "" {
            throw "CorsPolicy.allowHeader: empty name"
        }
        if name.indexOf("\n") >= 0 || name.indexOf("\r") >= 0 {
            throw "CorsPolicy.allowHeader: multiline name"
        }
        if name == "*" && _allowCredentials {
            throw "CorsPolicy.allowHeader: wildcard with credentials"
        }
        if self.hasHeader(_allowedHeaders, name) { return self }
        _allowedHeaders.push(name)
        return self
    }

    CorsPolicy allowAnyHeader() {
        return self.allowHeader("*")
    }

    List<String> allowedHeaders() { return _allowedHeaders.copy() }

    CorsPolicy exposeHeader(String name) {
        if name == null || name == "" {
            throw "CorsPolicy.exposeHeader: empty name"
        }
        if name.indexOf("\n") >= 0 || name.indexOf("\r") >= 0 {
            throw "CorsPolicy.exposeHeader: multiline name"
        }
        if !self.hasHeader(_exposedHeaders, name) {
            _exposedHeaders.push(name)
        }
        return self
    }

    List<String> exposedHeaders() { return _exposedHeaders.copy() }

    CorsPolicy allowCredentials(Bool value) {
        if value && (_allowedOrigins.indexOf("*") >= 0
            || _allowedHeaders.indexOf("*") >= 0) {
            throw "CorsPolicy.allowCredentials: wildcard already configured"
        }
        _allowCredentials = value
        return self
    }

    Bool isAllowCredentials() { return _allowCredentials }

    CorsPolicy maxAgeSeconds(Long value) {
        if value < 0 { throw "CorsPolicy.maxAgeSeconds: invalid" }
        _maxAgeSeconds = value
        return self
    }

    Long maxAgeSeconds() { return _maxAgeSeconds }

    private Bool hasHeader(List<String> values, String name) {
        String lower = name.toLower()
        Int index = 0
        while index < values.length() {
            if values.get(index).toLower() == lower { return true }
            index = index + 1
        }
        return false
    }

    Result<Bool, Error> process(Context context, ApiContext exchange) {
        if context == null || exchange == null {
            throw "CorsPolicy.process: null argument"
        }
        String? origin = exchange.header("Origin")
        Bool preflight = exchange.method() == HttpMethod.Options
            && exchange.header("Access-Control-Request-Method") != null
        List<String> origins = exchange.headers().getAll("Origin")
        if origins.length() > 1 {
            if preflight {
                return self.rejectPreflight(context, exchange,
                    "multiple Origin headers")
            }
            return Ok(false)
        }
        if origin == null || origin == "" { return Ok(false) }
        String requestOrigin = origin as String
        self.addVary(exchange, "Origin")
        if !self.isOriginAllowed(requestOrigin) {
            if preflight {
                ProblemDetails problem = ProblemDetails.of(403)
                    .withType("urn:xdk:api:cors")
                    .withTitle("CORS preflight rejected")
                    .withDetail("origin is not allowed")
                Result<Unit, Error> written = exchange.respondProblem(context, problem)
                if written.isErr() { return Err(written.error()) }
                return Ok(true)
            }
            return Ok(false)
        }
        if !preflight {
            exchange.setHeader("Access-Control-Allow-Origin", self.allowOriginValue(requestOrigin))
            if _allowCredentials {
                exchange.setHeader("Access-Control-Allow-Credentials", "true")
            }
            if !_exposedHeaders.isEmpty() {
                exchange.setHeader("Access-Control-Expose-Headers",
                    self.joinHeaders(_exposedHeaders))
            }
            return Ok(false)
        }
        String requestedMethodText =
            exchange.header("Access-Control-Request-Method") as String
        Result<HttpMethod, Error> requestedMethod = parseHttpMethod(requestedMethodText)
        if requestedMethod.isErr()
            || _allowedMethods.indexOf(requestedMethod.value()) < 0 {
            return self.rejectPreflight(context, exchange, "method is not allowed")
        }
        String? requestedHeadersText =
            exchange.header("Access-Control-Request-Headers")
        List<String> requestedHeaders = []
        if requestedHeadersText != null && requestedHeadersText != "" {
            List<String> parts = requestedHeadersText.split(",")
            Int index = 0
            while index < parts.length() {
                String name = parts.get(index).trim()
                if name != "" {
                    if !self.isHeaderAllowed(name) {
                        return self.rejectPreflight(context, exchange,
                            "request header is not allowed")
                    }
                    requestedHeaders.push(name)
                }
                index = index + 1
            }
        }
        exchange.setHeader("Access-Control-Allow-Origin", self.allowOriginValue(requestOrigin))
        exchange.setHeader("Access-Control-Allow-Methods",
            self.joinMethods(_allowedMethods))
        if !requestedHeaders.isEmpty() {
            exchange.setHeader("Access-Control-Allow-Headers",
                self.joinHeaders(requestedHeaders))
        }
        if _allowCredentials {
            exchange.setHeader("Access-Control-Allow-Credentials", "true")
        }
        if _maxAgeSeconds > 0 {
            exchange.setHeader("Access-Control-Max-Age", str(_maxAgeSeconds))
        }
        self.addVary(exchange, "Access-Control-Request-Method")
        self.addVary(exchange, "Access-Control-Request-Headers")
        Result<Unit, Error> written = exchange.respondEmpty(context, 204)
        if written.isErr() { return Err(written.error()) }
        return Ok(true)
    }

    private Result<Bool, Error> rejectPreflight(Context context, ApiContext exchange,
                                                String detail) {
        ProblemDetails problem = ProblemDetails.of(403)
            .withType("urn:xdk:api:cors")
            .withTitle("CORS preflight rejected")
            .withDetail(detail)
        Result<Unit, Error> written = exchange.respondProblem(context, problem)
        if written.isErr() { return Err(written.error()) }
        return Ok(true)
    }

    private String allowOriginValue(String origin) {
        if _allowedOrigins.indexOf("*") >= 0 && !_allowCredentials {
            return "*"
        }
        return origin
    }

    private Bool isHeaderAllowed(String name) {
        if _allowedHeaders.indexOf("*") >= 0 && !_allowCredentials {
            return true
        }
        return self.hasHeader(_allowedHeaders, name)
    }

    private String joinHeaders(List<String> values) {
        String result = ""
        Int index = 0
        while index < values.length() {
            if result != "" { result = result + ", " }
            result = result + values.get(index)
            index = index + 1
        }
        return result
    }

    private String joinMethods(List<HttpMethod> values) {
        String result = ""
        Int index = 0
        while index < values.length() {
            if result != "" { result = result + ", " }
            result = result + httpMethodName(values.get(index))
            index = index + 1
        }
        return result
    }

    private void addVary(ApiContext exchange, String value) {
        List<String> existing = exchange.responseHeaders().getAll("Vary")
        Int index = 0
        while index < existing.length() {
            if existing.get(index).toLower() == value.toLower() { return }
            index = index + 1
        }
        exchange.addHeader("Vary", value)
    }

    CorsPolicy copy() {
        CorsPolicy result = new CorsPolicy()
        result._allowedOrigins = _allowedOrigins.copy()
        result._allowedMethods = _allowedMethods.copy()
        result._allowedHeaders = _allowedHeaders.copy()
        result._exposedHeaders = _exposedHeaders.copy()
        result._allowCredentials = _allowCredentials
        result._maxAgeSeconds = _maxAgeSeconds
        return result
    }
}
```
