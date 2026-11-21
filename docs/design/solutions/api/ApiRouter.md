# `ApiRouter`

| 项 | 值 |
| --- | --- |
| 类型 | `class ApiRouter` |
| 包 | `xdk.api` |
| 稳定性 | `preview` |
| 依赖 | `HttpMethod`、`ApiRoute`、`ApiHandler`、`ApiMiddleware`、`Error` |

---

## 1. 定位

显式路由表：注册方法+路径模式+处理器，保存路由级中间件与前缀，提供匹配和允许方法查询。

不做：全局路由、反射扫描、控制器实例化、依赖注入、模板渲染、路由参数类型转换。

---

## 2. 设计逻辑

- 每个 `ApiRouter` 是一个独立实例；无全局 Router、无静态注册表。
- 路由模式以 `/` 分段；静态段与 `{name}` 单段参数；不支持通配符、正则、可选段、`CONNECT`。
- 前缀在注册时拼接到完整模式；`prefix()` 返回规范化前缀。
- `include` 把子路由的完整模式原样并入；父前缀不再追加到子路由。
- 添加顺序保留；匹配时静态段更多的模式优先，静态精确模式优先于参数模式。
- 重复 method+pattern 返回 `AlreadyExists`；非法模式返回 `InvalidArgument`。
- `HEAD` 匹配回退到 `GET`；路由器不自动生成 `OPTIONS`（由 `ApiServer` 决定）。
- 路由级中间件保存在 `ApiRoute`；路由器级中间件由 `ApiServer` 在分派时应用。
- 注册期可变；`ApiServer.bind` 取快照后不再修改。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_prefix` | `String` | 规范化前缀，空或 `/...` |
| `_routes` | `List<ApiRoute>` | 注册顺序 |
| `_middleware` | `List<ApiMiddleware>` | 路由器级中间件 |

不变量：prefix 不以 `/` 结尾（根前缀为空）；routes 中 method+pattern 唯一；每个 route 的 pattern 以 `/` 开头且无尾斜杠（根 `/` 除外）。

---

## 4. 生命周期

构造后注册；`bind` 取快照；无 close；注册期非线程安全；快照后只读。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ApiRouter()` | 无 | 空前缀 | 无 |
| `ApiRouter(String prefix)` | prefix | 空、`/` 或 `/segment...`；无尾斜杠 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。`_routes` 元素为 `ApiRoute` 引用；`routes()` 返回副本。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `route` | 注册任意方法 | `HttpMethod method, String pattern, ApiHandler handler` | `Result<ApiRoute, Error>` | `InvalidArgument`/`AlreadyExists` |
| `get` | 注册 GET | `String pattern, ApiHandler handler` | `Result<ApiRoute, Error>` | 同上 |
| `post` | 注册 POST | `String pattern, ApiHandler handler` | `Result<ApiRoute, Error>` | 同上 |
| `put` | 注册 PUT | `String pattern, ApiHandler handler` | `Result<ApiRoute, Error>` | 同上 |
| `patch` | 注册 PATCH | `String pattern, ApiHandler handler` | `Result<ApiRoute, Error>` | 同上 |
| `delete` | 注册 DELETE | `String pattern, ApiHandler handler` | `Result<ApiRoute, Error>` | 同上 |
| `head` | 注册 HEAD | `String pattern, ApiHandler handler` | `Result<ApiRoute, Error>` | 同上 |
| `options` | 注册 OPTIONS | `String pattern, ApiHandler handler` | `Result<ApiRoute, Error>` | 同上 |
| `include` | 合并子路由 | `ApiRouter child` | `Result<Unit, Error>` | `AlreadyExists` |
| `middleware` | 追加路由器中间件 | `ApiMiddleware middleware` | `ApiRouter` | null → panic |
| `middleware` | 中间件快照 | 无 | `List<ApiMiddleware>` | 无 |
| `prefix` | 规范前缀 | 无 | `String` | 无 |
| `routes` | 路由快照 | 无 | `List<ApiRoute>` | 无 |
| `routeCount` | 路由数 | 无 | `Int` | 无 |
| `match` | 匹配方法+路径 | `HttpMethod method, String path` | `ApiRoute?` | 无 |
| `allowedMethods` | 路径允许方法 | `String path` | `List<HttpMethod>` | 无 |

说明：

- `route` 校验模式后才创建 `ApiRoute`；重复注册失败时不改变路由表。
- `include` 复制子路由；子路由的完整 pattern 保留；原子路由器中间件按顺序前插到每条复制路由。
- `match` 只返回路由，不返回参数；参数由 `ApiRoute.extractPathParameters` 提取。
- `match` 对 HEAD 回退 GET；显式 HEAD 路由优先。
- `allowedMethods` 去重并按注册顺序返回；GET 存在时附带 HEAD；不自动附带 OPTIONS。
- `routes()` 返回 `ApiRoute.copy()` 列表；修改副本不影响路由器。

---

## 8. 使用的技术

- 线性路由表；
- 分段模式匹配；
- 静态优先评分；
- 前缀拼接；
- 路由复制与中间件前插；
- 无反射。

---

## 9. 需要的支撑

- 语言：class、List、String、Bool、Int、Result、Map；
- 运行时：无；
- 接口：`HttpMethod`、`ApiRoute`、`ApiHandler`、`ApiMiddleware`、`Error`、`BasicError`、`ErrorKind`、`httpMethodName`。

---

## 10. 依赖的特性/接口/类

`HttpMethod`、`ApiRoute`、`ApiHandler`、`ApiMiddleware`、`Error`、`BasicError`、`ErrorKind`、`httpMethodName`。

---

## 11. 所有权与并发

引用语义；注册期非线程安全；`routes()`/`middleware()` 返回副本；快照后只读；无资源；无取消点。

---

## 12. 示例与反例

正确：

```text
ApiRouter router = new ApiRouter("/api")
ApiRoute route = router.get("/users/{userId}", handler).value()
route.tag("users").operationName("getUser")
```

反例：

- 两个路由注册同一 method+pattern；
- 模式 `/users/{userId}/` 带尾斜杠；
- 模式 `/files/{path...}` 期望通配；
- 依赖注册顺序覆盖静态路由；
- 多个 router 同名而不 include，期望自动合并。

---

## 13. 测试/场景义务

空前缀/前缀/根路径；静态/单个参数/多参数；重复参数名；重复路由；非法字符/尾斜杠/空段；GET/POST/HEAD/OPTIONS；HEAD 回退；静态优先；allowedMethods；include 复制与中间件顺序；routes 快照独立；非法方法 null。

---

## 14. XNull 伪代码

> 非可执行设计伪代码。

```xnull
class ApiRouter {
    final String _prefix
    List<ApiRoute> _routes = []
    List<ApiMiddleware> _middleware = []

    ApiRouter() {
        _prefix = ""
    }

    ApiRouter(String prefix) {
        if prefix == null { throw "ApiRouter: null prefix" }
        _prefix = self.normalizePrefix(prefix)
    }

    private String normalizePrefix(String prefix) {
        if prefix == "" || prefix == "/" { return "" }
        if !prefix.startsWith("/") { throw "ApiRouter: prefix must start with slash" }
        if prefix.endsWith("/") { throw "ApiRouter: prefix trailing slash" }
        if prefix.indexOf("?") >= 0 || prefix.indexOf("#") >= 0 {
            throw "ApiRouter: invalid prefix"
        }
        return prefix
    }

    private Result<Unit, Error> validatePattern(String pattern) {
        if pattern == null || pattern == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument, "empty route pattern"))
        }
        if !pattern.startsWith("/") {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "route pattern must start with slash"))
        }
        if pattern != "/" {
            if pattern.endsWith("/") {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "route pattern trailing slash"))
            }
            if pattern.indexOf("?") >= 0 || pattern.indexOf("#") >= 0 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "route pattern has query or fragment"))
            }
        }
        if pattern == "/" { return Ok(unit) }
        List<String> segments = pattern.split("/")
        List<String> names = []
        Int index = 0
        while index < segments.length() {
            String segment = segments.get(index)
            if index == 0 && segment == "" {
                index = index + 1
                continue
            }
            if segment == "" {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "route pattern has empty segment"))
            }
            if segment == "." || segment == ".." {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "route pattern has dot segment"))
            }
            Bool hasOpen = segment.indexOf("{") >= 0
            Bool hasClose = segment.indexOf("}") >= 0
            if hasOpen || hasClose {
                if !(segment.startsWith("{") && segment.endsWith("}")) {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "route parameter must occupy a full segment"))
                }
                String name = segment.substring(1, segment.length() - 1)
                if name == "" || !self.isParameterName(name) {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "invalid route parameter name"))
                }
                if names.indexOf(name) >= 0 {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "duplicate route parameter name"))
                }
                names.push(name)
            }
            index = index + 1
        }
        return Ok(unit)
    }

    private Bool isParameterName(String name) {
        Int index = 0
        while index < name.length() {
            String character = name.substring(index, index + 1)
            if index == 0 {
                Bool alpha = (character >= "A" && character <= "Z")
                    || (character >= "a" && character <= "z")
                if !alpha { return false }
            } else {
                Bool valid = (character >= "A" && character <= "Z")
                    || (character >= "a" && character <= "z")
                    || (character >= "0" && character <= "9") || character == "_"
                if !valid { return false }
            }
            index = index + 1
        }
        return true
    }

    Result<ApiRoute, Error> route(HttpMethod method, String pattern,
                                  ApiHandler handler) {
        if method == null || handler == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "null route argument"))
        }
        if method == HttpMethod.Connect {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "CONNECT is not supported"))
        }
        Result<Unit, Error> valid = self.validatePattern(pattern)
        if valid.isErr() { return Err(valid.error()) }
        String fullPattern = self.combine(pattern)
        if self.hasRoute(method, fullPattern) {
            return Err(new BasicError(ErrorKind.AlreadyExists, "duplicate route"))
        }
        ApiRoute route = new ApiRoute(method, fullPattern, handler)
        _routes.push(route)
        return Ok(route)
    }

    private Bool hasRoute(HttpMethod method, String pattern) {
        Int index = 0
        while index < _routes.length() {
            ApiRoute route = _routes.get(index)
            if route.method() == method && route.pattern() == pattern {
                return true
            }
            index = index + 1
        }
        return false
    }

    private String combine(String pattern) {
        if _prefix == "" { return pattern }
        if pattern == "/" { return _prefix }
        return _prefix + pattern
    }

    Result<ApiRoute, Error> get(String pattern, ApiHandler handler) {
        return self.route(HttpMethod.Get, pattern, handler)
    }

    Result<ApiRoute, Error> post(String pattern, ApiHandler handler) {
        return self.route(HttpMethod.Post, pattern, handler)
    }

    Result<ApiRoute, Error> put(String pattern, ApiHandler handler) {
        return self.route(HttpMethod.Put, pattern, handler)
    }

    Result<ApiRoute, Error> patch(String pattern, ApiHandler handler) {
        return self.route(HttpMethod.Patch, pattern, handler)
    }

    Result<ApiRoute, Error> delete(String pattern, ApiHandler handler) {
        return self.route(HttpMethod.Delete, pattern, handler)
    }

    Result<ApiRoute, Error> head(String pattern, ApiHandler handler) {
        return self.route(HttpMethod.Head, pattern, handler)
    }

    Result<ApiRoute, Error> options(String pattern, ApiHandler handler) {
        return self.route(HttpMethod.Options, pattern, handler)
    }

    Result<Unit, Error> include(ApiRouter child) {
        if child == null { return Err(new BasicError(ErrorKind.InvalidArgument,
            "null child router")) }
        List<ApiRoute> incoming = child.routes()
        Int index = 0
        while index < incoming.length() {
            ApiRoute route = incoming.get(index)
            if self.hasRoute(route.method(), route.pattern()) {
                return Err(new BasicError(ErrorKind.AlreadyExists,
                    "duplicate included route"))
            }
            index = index + 1
        }
        List<ApiMiddleware> childMiddleware = child.middleware()
        index = 0
        while index < incoming.length() {
            ApiRoute copy = incoming.get(index).copy()
            Int middlewareIndex = childMiddleware.length() - 1
            while middlewareIndex >= 0 {
                copy.prependMiddleware(childMiddleware.get(middlewareIndex))
                middlewareIndex = middlewareIndex - 1
            }
            _routes.push(copy)
            index = index + 1
        }
        return Ok(unit)
    }

    ApiRouter middleware(ApiMiddleware middleware) {
        if middleware == null { throw "ApiRouter.middleware: null" }
        _middleware.push(middleware)
        return self
    }

    List<ApiMiddleware> middleware() { return _middleware.copy() }

    String prefix() { return _prefix }

    List<ApiRoute> routes() {
        List<ApiRoute> result = []
        Int index = 0
        while index < _routes.length() {
            result.push(_routes.get(index).copy())
            index = index + 1
        }
        return result
    }

    Int routeCount() { return _routes.length() }

    ApiRoute? match(HttpMethod method, String path) {
        if method == null || path == null || !path.startsWith("/") { return null }
        Int index = 0
        while index < _routes.length() {
            ApiRoute route = _routes.get(index)
            if route.method() == method && route.pattern() == path {
                return route
            }
            index = index + 1
        }
        if method == HttpMethod.Head {
            index = 0
            while index < _routes.length() {
                ApiRoute route = _routes.get(index)
                if route.method() == HttpMethod.Get && route.pattern() == path {
                    return route
                }
                index = index + 1
            }
        }
        ApiRoute? best = null
        Int bestStatic = -1
        Int bestPriority = -1
        index = 0
        while index < _routes.length() {
            ApiRoute route = _routes.get(index)
            Int priority = 0
            if route.method() == method {
                priority = 2
            } else if method == HttpMethod.Head && route.method() == HttpMethod.Get {
                priority = 1
            }
            if priority > 0 && route.matchesPath(path) {
                Int staticCount = self.staticSegmentCount(route.pattern())
                if staticCount > bestStatic
                    || (staticCount == bestStatic && priority > bestPriority) {
                    best = route
                    bestStatic = staticCount
                    bestPriority = priority
                }
            }
            index = index + 1
        }
        return best
    }

    private Int staticSegmentCount(String pattern) {
        List<String> segments = pattern.split("/")
        Int count = 0
        Int index = 0
        while index < segments.length() {
            String segment = segments.get(index)
            if segment != "" && !(segment.startsWith("{") && segment.endsWith("}")) {
                count = count + 1
            }
            index = index + 1
        }
        return count
    }

    List<HttpMethod> allowedMethods(String path) {
        List<HttpMethod> result = []
        if path == null || !path.startsWith("/") { return result }
        Int index = 0
        while index < _routes.length() {
            ApiRoute route = _routes.get(index)
            if route.matchesPath(path) {
                if result.indexOf(route.method()) < 0 {
                    result.push(route.method())
                }
                if route.method() == HttpMethod.Get
                    && result.indexOf(HttpMethod.Head) < 0 {
                    result.push(HttpMethod.Head)
                }
            }
            index = index + 1
        }
        return result
    }
}
```
