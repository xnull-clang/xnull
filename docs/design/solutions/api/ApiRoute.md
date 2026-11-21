# `ApiRoute`

| 项 | 值 |
| --- | --- |
| 类型 | `class ApiRoute` |
| 包 | `xdk.api` |
| 稳定性 | `preview` |
| 依赖 | `HttpMethod`、`ApiHandler`、`ApiMiddleware`、`Authenticator`、`RateLimitPolicy`、`Validator`、`JsonValue`、`JsonArray`、`Map`、`Error` |

---

## 1. 定位

单条路由：方法、路径模式、处理器，以及路由级中间件、认证、限流、请求校验、OpenAPI 元数据和响应声明。

不做：路由表存储（`ApiRouter`）、全局配置、请求执行、反射参数绑定、自动响应。

---

## 2. 设计逻辑

- method/pattern/handler 在构造时固定；路径参数名从 pattern 解析并缓存。
- 元数据与策略通过链式方法在构建期追加；`copy` 产生独立快照。
- 路径模式只支持 `/` 分段和整段 `{name}`；不支持通配符、正则、可选段；`CONNECT` 方法被拒绝。
- `extractPathParameters` 先按原始 `/` 分段，再逐段百分号解码；`%2F` 不改变分段。
- 静态段按原始文本比较；参数段解码后不得为空、不得含 NUL。
- `requestValidator` 触发 `ApiServer` 自动校验 JSON body；`requestSchema` 只用于 OpenAPI，不参与运行时校验。
- `consumes`/`produces` 是媒体类型声明；前者参与 415，后者参与 406 与 `Vary: Accept`。
- `publicAccess` 跳过全局/路由认证；`withoutRateLimit` 跳过全局/路由限流。
- 路由级认证器/限流策略覆盖全局值；没有“只关闭认证但保留全局认证”的隐式开关，必须显式 `publicAccess`。
- 无 close；构建后只读；处理器可被并发调用。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_method` | `HttpMethod` | final |
| `_pattern` | `String` | final，完整模式 |
| `_handler` | `ApiHandler` | final |
| `_pathParameterNames` | `List<String>` | final，按出现顺序 |
| `_middleware` | `List<ApiMiddleware>` | 路由级中间件 |
| `_authenticator` | `Authenticator?` | 路由覆盖 |
| `_rateLimitPolicy` | `RateLimitPolicy?` | 路由覆盖 |
| `_rateLimitDisabled` | `Bool` | 显式跳过限流 |
| `_publicAccess` | `Bool` | 显式跳过认证 |
| `_requestValidator` | `Validator?` | 运行时校验器 |
| `_requestSchema` | `JsonValue?` | OpenAPI 请求 schema |
| `_operationName` | `String?` | OpenAPI operationId 来源 |
| `_summary` | `String?` | 摘要 |
| `_description` | `String?` | 描述 |
| `_tags` | `List<String>` | 标签 |
| `_deprecated` | `Bool` | 是否弃用 |
| `_consumes` | `List<String>` | 请求媒体类型 |
| `_produces` | `List<String>` | 响应媒体类型 |
| `_queryParameters` | `JsonArray` | OpenAPI 查询参数对象 |
| `_headerParameters` | `JsonArray` | OpenAPI 头参数对象 |
| `_responseCodes` | `List<Int>` | 响应状态顺序 |
| `_responseDescriptions` | `Map<Int, String>` | 响应描述 |
| `_responseSchemas` | `Map<Int, JsonValue>` | 响应 schema |

不变量：method/pattern/handler 非 null；pattern 以 `/` 开头、无尾斜杠（根除外）、参数名唯一；`_responseCodes` 无重复；响应描述/schema 的键都在 codes 中。

---

## 4. 生命周期

构造；链式配置；`ApiRouter.routes()`/`ApiServer.bind` 复制；无 close；构建后只读；处理器每次请求独立调用。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ApiRoute(HttpMethod method, String pattern, ApiHandler handler)` | 全部非 null | pattern 合法 | 非法 → panic |

主要供 `ApiRouter.route` 使用；业务代码通常不直接构造。

---

## 6. 字段表

见 §3；字段私有。`_pathParameterNames` 是构造时快照；`_queryParameters`/`_headerParameters` 是可变 JsonArray，对外返回副本。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `method` | 方法 | 无 | `HttpMethod` | 无 |
| `pattern` | 完整模式 | 无 | `String` | 无 |
| `handler` | 处理器 | 无 | `ApiHandler` | 无 |
| `pathParameterNames` | 参数名快照 | 无 | `List<String>` | 无 |
| `matchesPath` | 路径是否匹配 | `String path` | `Bool` | 无 |
| `extractPathParameters` | 提取参数 | `String path` | `Result<Map<String,String>, Error>` | `NotFound`/`DataCorrupted` |
| `middleware` | 追加路由中间件 | `ApiMiddleware middleware` | `ApiRoute` | null → panic |
| `prependMiddleware` | 前插路由中间件 | `ApiMiddleware middleware` | `ApiRoute` | null → panic |
| `middleware` | 中间件快照 | 无 | `List<ApiMiddleware>` | 无 |
| `authenticator` | 路由认证器 | `Authenticator authenticator` | `ApiRoute` | null → panic |
| `authenticator` | 读取认证器 | 无 | `Authenticator?` | 无 |
| `publicAccess` | 跳过认证 | 无 | `ApiRoute` | 无 |
| `isPublicAccess` | 是否公开 | 无 | `Bool` | 无 |
| `rateLimitPolicy` | 路由限流 | `RateLimitPolicy policy` | `ApiRoute` | null → panic |
| `rateLimitPolicy` | 读取限流 | 无 | `RateLimitPolicy?` | 无 |
| `withoutRateLimit` | 跳过限流 | 无 | `ApiRoute` | 无 |
| `isRateLimitDisabled` | 是否跳过限流 | 无 | `Bool` | 无 |
| `requestValidator` | 运行时校验器 | `Validator validator` | `ApiRoute` | null → panic |
| `requestValidator` | 读取校验器 | 无 | `Validator?` | 无 |
| `requestSchema` | OpenAPI 请求 schema | `JsonValue schema` | `ApiRoute` | null → panic |
| `requestSchema` | 读取请求 schema | 无 | `JsonValue?` | 无 |
| `operationName` | operationId 来源 | `String name` | `ApiRoute` | 空/null → panic |
| `operationName` | 读取 | 无 | `String?` | 无 |
| `summary` | 摘要 | `String text` | `ApiRoute` | null → panic |
| `summary` | 读取 | 无 | `String?` | 无 |
| `description` | 描述 | `String text` | `ApiRoute` | null → panic |
| `description` | 读取 | 无 | `String?` | 无 |
| `tag` | 追加标签 | `String name` | `ApiRoute` | 空/null → panic |
| `tags` | 标签快照 | 无 | `List<String>` | 无 |
| `deprecated` | 弃用标记 | `Bool value` | `ApiRoute` | 无 |
| `isDeprecated` | 是否弃用 | 无 | `Bool` | 无 |
| `consumes` | 追加请求类型 | `String mediaType` | `ApiRoute` | 非法 → panic |
| `produces` | 追加响应类型 | `String mediaType` | `ApiRoute` | 非法 → panic |
| `consumes` | 请求类型快照 | 无 | `List<String>` | 无 |
| `produces` | 响应类型快照 | 无 | `List<String>` | 无 |
| `queryParameter` | 声明查询参数 | `String name, String description, Bool required, JsonValue schema` | `ApiRoute` | 非法/重复 → panic |
| `headerParameter` | 声明头参数 | `String name, String description, Bool required, JsonValue schema` | `ApiRoute` | 非法/重复 → panic |
| `queryParameters` | 查询参数快照 | 无 | `JsonArray` | 无 |
| `headerParameters` | 头参数快照 | 无 | `JsonArray` | 无 |
| `response` | 声明响应 | `Int status, String description` | `ApiRoute` | 越界/null → panic |
| `response` | 声明响应+schema | `Int status, String description, JsonValue schema` | `ApiRoute` | 越界/null → panic |
| `responseCodes` | 响应码快照 | 无 | `List<Int>` | 无 |
| `responseDescription` | 响应描述 | `Int status` | `String` | 无（缺失返回空串） |
| `responseSchema` | 响应 schema | `Int status` | `JsonValue?` | 无 |
| `copy` | 独立快照 | 无 | `ApiRoute` | 无 |

说明：

- `matchesPath` 等价于 `extractPathParameters(path).isOk()`；不分配参数 Map 的实现可内部优化。
- `extractPathParameters` 不匹配返回 `NotFound`；非法百分号编码返回 `DataCorrupted`。
- `queryParameter`/`headerParameter` 生成 OpenAPI 参数对象；同名同位置重复是合同错误。
- `response` 对同一状态码重复调用时更新描述，带 schema 的调用同时更新 schema。
- `consumes`/`produces` 去重，保持首次添加顺序；媒体类型由 `MediaType.parse` 校验；`consumes` 只在请求声明了 body 时参与 415。
- `requestSchema` 只影响 OpenAPI；运行时校验必须设置 `requestValidator`。
- `copy` 复制全部元数据与中间件列表，处理器引用共享。

---

## 8. 使用的技术

- 路径分段与参数提取；
- 百分号解码；
- 链式构建器；
- OpenAPI 元数据 JSON；
- 策略覆盖；
- 快照复制。

---

## 9. 需要的支撑

- 语言：class、List、Map、String、Bool、Int、Result；
- 运行时：`percentDecode`；
- 接口：`HttpMethod`、`ApiHandler`、`ApiMiddleware`、`Authenticator`、`RateLimitPolicy`、`Validator`、`MediaType`、`JsonValue`、`JsonObject`、`JsonArray`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`HttpMethod`、`ApiHandler`、`ApiMiddleware`、`Authenticator`、`RateLimitPolicy`、`Validator`、`MediaType`、`JsonValue`、`JsonObject`、`JsonArray`、`percentDecode`、`Error`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

引用语义；构建期非线程安全；快照后只读；`handler` 可被并发调用；`queryParameters`/`headerParameters` 返回浅拷贝；无资源；无取消点。

---

## 12. 示例与反例

正确：

```text
ApiRoute route = router.get("/users/{userId}", handler).value()
route.operationName("getUser")
    .tag("users")
    .requestValidator(schema)
    .response(200, "OK", userSchema)
    .response(404, "Not found")
```

反例：

- 参数名重复 `/users/{userId}/{userId}`；
- 模式含 `{id` 或 `{userId...}`；
- 只设置 `requestSchema` 期望运行时校验；
- 同时调用 `publicAccess` 与 `authenticator` 并期望认证；
- 修改 `queryParameters()` 返回值期望路由变化。

---

## 13. 测试/场景义务

构造/非法模式；参数名解析；静态/参数/多参数匹配；空段/尾斜杠；百分号解码与非法 `%`；NUL 参数；`%2F` 不跨段；中间件顺序/前插；认证/公开访问；限流/跳过；requestValidator/requestSchema；consumes/produces 去重与非法媒体类型；query/header 参数重复；响应更新/顺序；copy 独立性。

---

## 14. XNull 伪代码

> 非可执行设计伪代码。

```xnull
class ApiRoute {
    final HttpMethod _method
    final String _pattern
    final ApiHandler _handler
    final List<String> _pathParameterNames
    List<ApiMiddleware> _middleware = []
    Authenticator? _authenticator = null
    RateLimitPolicy? _rateLimitPolicy = null
    Bool _rateLimitDisabled = false
    Bool _publicAccess = false
    Validator? _requestValidator = null
    JsonValue? _requestSchema = null
    String? _operationName = null
    String? _summary = null
    String? _description = null
    List<String> _tags = []
    Bool _deprecated = false
    List<String> _consumes = []
    List<String> _produces = []
    JsonArray _queryParameters = new JsonArray()
    JsonArray _headerParameters = new JsonArray()
    List<Int> _responseCodes = []
    Map<Int, String> _responseDescriptions = [:]
    Map<Int, JsonValue> _responseSchemas = [:]

    ApiRoute(HttpMethod method, String pattern, ApiHandler handler) {
        if method == null || pattern == null || handler == null {
            throw "ApiRoute: null argument"
        }
        if method == HttpMethod.Connect {
            throw "ApiRoute: CONNECT is not supported"
        }
        if !pattern.startsWith("/") {
            throw "ApiRoute: pattern must start with slash"
        }
        if pattern != "/" && pattern.endsWith("/") {
            throw "ApiRoute: pattern trailing slash"
        }
        if pattern.indexOf("?") >= 0 || pattern.indexOf("#") >= 0 {
            throw "ApiRoute: pattern has query or fragment"
        }
        _method = method
        _pattern = pattern
        _handler = handler
        _pathParameterNames = ApiRoute.parseParameterNames(pattern)
    }

    private static List<String> parseParameterNames(String pattern) {
        List<String> result = []
        if pattern == "/" { return result }
        List<String> segments = pattern.split("/")
        Int index = 0
        while index < segments.length() {
            String segment = segments.get(index)
            if index == 0 && segment == "" {
                index = index + 1
                continue
            }
            if segment == "" {
                throw "ApiRoute: empty pattern segment"
            }
            Bool hasOpen = segment.indexOf("{") >= 0
            Bool hasClose = segment.indexOf("}") >= 0
            if hasOpen || hasClose {
                if !(segment.startsWith("{") && segment.endsWith("}")) {
                    throw "ApiRoute: parameter must occupy full segment"
                }
                String name = segment.substring(1, segment.length() - 1)
                if name == "" || !ApiRoute.isParameterName(name) {
                    throw "ApiRoute: invalid parameter name"
                }
                if result.indexOf(name) >= 0 {
                    throw "ApiRoute: duplicate parameter name"
                }
                result.push(name)
            }
            index = index + 1
        }
        return result
    }

    private static Bool isParameterName(String name) {
        if name == "" { return false }
        Int index = 0
        while index < name.length() {
            String character = name.substring(index, index + 1)
            Bool alpha = (character >= "A" && character <= "Z")
                || (character >= "a" && character <= "z")
            Bool digit = character >= "0" && character <= "9"
            if index == 0 {
                if !alpha { return false }
            } else {
                if !alpha && !digit && character != "_" { return false }
            }
            index = index + 1
        }
        return true
    }

    HttpMethod method() { return _method }
    String pattern() { return _pattern }
    ApiHandler handler() { return _handler }
    List<String> pathParameterNames() { return _pathParameterNames.copy() }

    Bool matchesPath(String path) {
        return self.extractPathParameters(path).isOk()
    }

    Result<Map<String, String>, Error> extractPathParameters(String path) {
        if path == null || !path.startsWith("/") {
            return Err(new BasicError(ErrorKind.NotFound, "route did not match"))
        }
        List<String> patternSegments = self.splitSegments(_pattern)
        List<String> pathSegments = self.splitSegments(path)
        if patternSegments.length() != pathSegments.length() {
            return Err(new BasicError(ErrorKind.NotFound, "route did not match"))
        }
        Map<String, String> result = [:]
        Int index = 0
        while index < patternSegments.length() {
            String patternSegment = patternSegments.get(index)
            String pathSegment = pathSegments.get(index)
            if pathSegment == "" {
                return Err(new BasicError(ErrorKind.NotFound, "empty path segment"))
            }
            if patternSegment.startsWith("{") && patternSegment.endsWith("}") {
                String name = patternSegment.substring(1, patternSegment.length() - 1)
                Result<String, Error> decoded = percentDecode(pathSegment)
                if decoded.isErr() { return Err(decoded.error()) }
                String value = decoded.value()
                if value == "" {
                    return Err(new BasicError(ErrorKind.NotFound, "empty path parameter"))
                }
                if value.indexOf("\u0000") >= 0 {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "path parameter contains NUL"))
                }
                result.put(name, value)
            } else {
                if patternSegment != pathSegment {
                    return Err(new BasicError(ErrorKind.NotFound, "route did not match"))
                }
            }
            index = index + 1
        }
        return Ok(result)
    }

    private List<String> splitSegments(String path) {
        List<String> result = []
        if path == "/" { return result }
        String text = path
        if text.startsWith("/") { text = text.substring(1) }
        if text == "" { return result }
        List<String> parts = text.split("/")
        Int index = 0
        while index < parts.length() {
            result.push(parts.get(index))
            index = index + 1
        }
        return result
    }

    ApiRoute middleware(ApiMiddleware middleware) {
        if middleware == null { throw "ApiRoute.middleware: null" }
        _middleware.push(middleware)
        return self
    }

    ApiRoute prependMiddleware(ApiMiddleware middleware) {
        if middleware == null { throw "ApiRoute.prependMiddleware: null" }
        List<ApiMiddleware> next = []
        next.push(middleware)
        Int index = 0
        while index < _middleware.length() {
            next.push(_middleware.get(index))
            index = index + 1
        }
        _middleware = next
        return self
    }

    List<ApiMiddleware> middleware() { return _middleware.copy() }

    ApiRoute authenticator(Authenticator authenticator) {
        if authenticator == null { throw "ApiRoute.authenticator: null" }
        _authenticator = authenticator
        return self
    }

    Authenticator? authenticator() { return _authenticator }

    ApiRoute publicAccess() {
        _publicAccess = true
        return self
    }

    Bool isPublicAccess() { return _publicAccess }

    ApiRoute rateLimitPolicy(RateLimitPolicy policy) {
        if policy == null { throw "ApiRoute.rateLimitPolicy: null" }
        _rateLimitPolicy = policy
        return self
    }

    RateLimitPolicy? rateLimitPolicy() { return _rateLimitPolicy }

    ApiRoute withoutRateLimit() {
        _rateLimitDisabled = true
        return self
    }

    Bool isRateLimitDisabled() { return _rateLimitDisabled }

    ApiRoute requestValidator(Validator validator) {
        if validator == null { throw "ApiRoute.requestValidator: null" }
        _requestValidator = validator
        return self
    }

    Validator? requestValidator() { return _requestValidator }

    ApiRoute requestSchema(JsonValue schema) {
        if schema == null { throw "ApiRoute.requestSchema: null" }
        _requestSchema = schema
        return self
    }

    JsonValue? requestSchema() { return _requestSchema }

    ApiRoute operationName(String name) {
        if name == null || name == "" { throw "ApiRoute.operationName: empty" }
        _operationName = name
        return self
    }

    String? operationName() { return _operationName }

    ApiRoute summary(String text) {
        if text == null { throw "ApiRoute.summary: null" }
        _summary = text
        return self
    }

    String? summary() { return _summary }

    ApiRoute description(String text) {
        if text == null { throw "ApiRoute.description: null" }
        _description = text
        return self
    }

    String? description() { return _description }

    ApiRoute tag(String name) {
        if name == null || name == "" { throw "ApiRoute.tag: empty" }
        if _tags.indexOf(name) < 0 { _tags.push(name) }
        return self
    }

    List<String> tags() { return _tags.copy() }

    ApiRoute deprecated(Bool value) {
        _deprecated = value
        return self
    }

    Bool isDeprecated() { return _deprecated }

    ApiRoute consumes(String mediaType) {
        if mediaType == null || mediaType == "" {
            throw "ApiRoute.consumes: empty media type"
        }
        Result<MediaType, Error> parsed = MediaType.parse(mediaType)
        if parsed.isErr() { throw "ApiRoute.consumes: invalid media type" }
        if _consumes.indexOf(mediaType) < 0 { _consumes.push(mediaType) }
        return self
    }

    ApiRoute produces(String mediaType) {
        if mediaType == null || mediaType == "" {
            throw "ApiRoute.produces: empty media type"
        }
        Result<MediaType, Error> parsed = MediaType.parse(mediaType)
        if parsed.isErr() { throw "ApiRoute.produces: invalid media type" }
        if _produces.indexOf(mediaType) < 0 { _produces.push(mediaType) }
        return self
    }

    List<String> consumes() { return _consumes.copy() }
    List<String> produces() { return _produces.copy() }

    ApiRoute queryParameter(String name, String description, Bool required,
                            JsonValue schema) {
        if name == null || name == "" {
            throw "ApiRoute.queryParameter: empty name"
        }
        if description == null || schema == null {
            throw "ApiRoute.queryParameter: null argument"
        }
        if self.hasParameter(_queryParameters, name) {
            throw "ApiRoute.queryParameter: duplicate name"
        }
        JsonObject parameter = new JsonObject()
        parameter.set("name", JsonValue.string(name))
        parameter.set("in", JsonValue.string("query"))
        parameter.set("required", JsonValue.bool(required))
        parameter.set("description", JsonValue.string(description))
        parameter.set("schema", schema)
        _queryParameters.add(JsonValue.object(parameter))
        return self
    }

    ApiRoute headerParameter(String name, String description, Bool required,
                             JsonValue schema) {
        if name == null || name == "" {
            throw "ApiRoute.headerParameter: empty name"
        }
        if description == null || schema == null {
            throw "ApiRoute.headerParameter: null argument"
        }
        if self.hasParameter(_headerParameters, name) {
            throw "ApiRoute.headerParameter: duplicate name"
        }
        JsonObject parameter = new JsonObject()
        parameter.set("name", JsonValue.string(name))
        parameter.set("in", JsonValue.string("header"))
        parameter.set("required", JsonValue.bool(required))
        parameter.set("description", JsonValue.string(description))
        parameter.set("schema", schema)
        _headerParameters.add(JsonValue.object(parameter))
        return self
    }

    private Bool hasParameter(JsonArray parameters, String name) {
        Int index = 0
        while index < parameters.length() {
            JsonObject parameter = parameters.get(index).asObject() as JsonObject
            JsonValue? existing = parameter.getOrNull("name")
            if existing != null && existing.asString() == name { return true }
            index = index + 1
        }
        return false
    }

    JsonArray queryParameters() { return _queryParameters.copy() }
    JsonArray headerParameters() { return _headerParameters.copy() }

    ApiRoute response(Int status, String description) {
        if status < 100 || status > 599 || description == null {
            throw "ApiRoute.response: invalid argument"
        }
        if _responseCodes.indexOf(status) < 0 { _responseCodes.push(status) }
        _responseDescriptions.put(status, description)
        return self
    }

    ApiRoute response(Int status, String description, JsonValue schema) {
        if schema == null { throw "ApiRoute.response: null schema" }
        self.response(status, description)
        _responseSchemas.put(status, schema)
        return self
    }

    List<Int> responseCodes() { return _responseCodes.copy() }

    String responseDescription(Int status) {
        return _responseDescriptions.getOr(status, "")
    }

    JsonValue? responseSchema(Int status) {
        if !_responseSchemas.has(status) { return null }
        return _responseSchemas.getOr(status, JsonValue.nullValue())
    }

    ApiRoute copy() {
        ApiRoute result = new ApiRoute(_method, _pattern, _handler)
        result._middleware = _middleware.copy()
        result._authenticator = _authenticator
        result._rateLimitPolicy = _rateLimitPolicy
        result._rateLimitDisabled = _rateLimitDisabled
        result._publicAccess = _publicAccess
        result._requestValidator = _requestValidator
        result._requestSchema = _requestSchema
        result._operationName = _operationName
        result._summary = _summary
        result._description = _description
        result._tags = _tags.copy()
        result._deprecated = _deprecated
        result._consumes = _consumes.copy()
        result._produces = _produces.copy()
        result._queryParameters = _queryParameters.copy()
        result._headerParameters = _headerParameters.copy()
        result._responseCodes = _responseCodes.copy()
        result._responseDescriptions = _responseDescriptions.copy()
        result._responseSchemas = _responseSchemas.copy()
        return result
    }
}
```
