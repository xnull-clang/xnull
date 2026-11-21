# `OpenApiBuilder`

| 项 | 值 |
| --- | --- |
| 类型 | `class OpenApiBuilder` |
| 包 | `xdk.api` |
| 稳定性 | `preview` |
| 依赖 | `ApiRoute`、`ApiRouter`、`Authenticator`、`AuthScheme`、`OpenApiDocument`、`HttpStatus`、`JsonValue`、`JsonObject`、`JsonArray`、`JsonNumber`、`Error` |

---

## 1. 定位

OpenAPI 3.1 文档构建器：填写 `info`、`servers`、`tags`、安全方案、组件、webhooks，并把 `ApiRoute` 元数据转换为 path operation。

不做：反射生成、完整 JSON Schema 校验、`$ref` 解析、YAML、客户端代码生成、文档 UI。

---

## 2. 设计逻辑

- builder 模式；构建期可变，`build` 后生成不可变 `OpenApiDocument`。
- 路由来自 `addRoute` 或 `addRouter`；`addRouter` 对同一 router 幂等，重复调用不重复添加。
- `operationId` 来自 `ApiRoute.operationName`，否则由方法+路径确定性生成；必须唯一。
- 路径参数从 pattern 提取，`required=true`，schema 为 `{"type":"string"}`。
- 查询/头参数直接使用 `ApiRoute` 中的 OpenAPI 参数对象。
- 请求/响应 schema 来自 `ApiRoute`；媒体类型来自 `consumes`/`produces`，默认 `application/json`。
- 每个 operation 自动增加 `default` ProblemDetails 响应；`components.schemas.ProblemDetails` 自动补齐。
- 安全方案只支持 Basic/Bearer/API key；OAuth2/OIDC/mTLS 不生成。
- `publicAccess` 路由输出空 `security: []`，覆盖全局安全要求。
- 所有 schema 都是 `JsonValue`；不做类型映射/反射。
- 无 close；构建期非线程安全；`build` 后不应继续修改。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_title` | `String` | 非空 |
| `_version` | `String` | 非空 |
| `_summary` | `String` | 可空 |
| `_description` | `String` | 可空 |
| `_termsOfService` | `String` | 可空 |
| `_contact` | `JsonObject?` | 可选 |
| `_license` | `JsonObject?` | 可选 |
| `_jsonSchemaDialect` | `String` | 可空 |
| `_servers` | `JsonArray` | 服务器 |
| `_tags` | `JsonArray` | 标签 |
| `_schemas` | `JsonObject` | components.schemas |
| `_responses` | `JsonObject` | components.responses |
| `_parameters` | `JsonObject` | components.parameters |
| `_securitySchemes` | `JsonObject` | components.securitySchemes |
| `_security` | `JsonArray` | 全局安全要求 |
| `_paths` | `JsonObject` | 路径项 |
| `_webhooks` | `JsonObject` | webhooks |
| `_externalDocs` | `JsonObject?` | 可选 |
| `_includedRouters` | `List<ApiRouter>` | 已合并路由器 |
| `_operationNames` | `Map<String,Int>` | operationId 计数 |

不变量：title/version 非空；operationId 唯一；paths 的 path item 是对象；components 子对象非 null；构建期顺序稳定。

---

## 4. 生命周期

构造；链式配置/添加路由；`build` 生成文档；无 close；构建后不再修改。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `OpenApiBuilder(String title, String version)` | 非空 | 无换行 | 空/null → panic |

---

## 6. 字段表

见 §3；字段私有。`_operationNames` 只记录已生成的 operationId。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `summary` | 文档摘要 | `String text` | `OpenApiBuilder` | null → panic |
| `description` | 文档描述 | `String text` | `OpenApiBuilder` | null → panic |
| `termsOfService` | 服务条款 URL | `String url` | `OpenApiBuilder` | 空/null → panic |
| `contact` | 联系人 | `String name, String url, String email` | `OpenApiBuilder` | null/换行 → panic |
| `license` | 许可证 | `String name, String identifier, String url` | `OpenApiBuilder` | 空/null → panic |
| `jsonSchemaDialect` | schema 方言 | `String uri` | `OpenApiBuilder` | 空/null → panic |
| `externalDocs` | 外部文档 | `String url, String description` | `OpenApiBuilder` | 空/null → panic |
| `server` | 添加服务器 | `String url, String description` | `OpenApiBuilder` | 空/null → panic |
| `tag` | 添加标签 | `String name, String description` | `OpenApiBuilder` | 空/null → panic |
| `httpSecurityScheme` | Basic/Bearer 方案 | `String name, AuthScheme scheme, String description` | `OpenApiBuilder` | 非 HTTP 方案 → panic |
| `apiKeySecurityScheme` | API key 方案 | `String name, AuthScheme scheme, String parameterName, String description` | `OpenApiBuilder` | 非 API key 方案 → panic |
| `securitySchemeFor` | 从认证器添加方案 | `Authenticator authenticator, String description` | `OpenApiBuilder` | null → panic |
| `globalSecurity` | 添加全局要求 | `String schemeName, List<String> scopes` | `OpenApiBuilder` | 空/null → panic |
| `componentSchema` | 添加 schema 组件 | `String name, JsonValue schema` | `OpenApiBuilder` | 空/null → panic |
| `componentResponse` | 添加响应组件 | `String name, JsonValue response` | `OpenApiBuilder` | 空/null → panic |
| `componentParameter` | 添加参数组件 | `String name, JsonValue parameter` | `OpenApiBuilder` | 空/null → panic |
| `webhook` | 添加 webhook | `String name, JsonValue pathItem` | `OpenApiBuilder` | 空/null → panic |
| `addRoute` | 添加单条路由 | `ApiRoute route` | `Result<Unit, Error>` | `AlreadyExists`/`InvalidArgument` |
| `addRouter` | 合并路由器 | `ApiRouter router` | `Result<Unit, Error>` | 同上；幂等 |
| `operationCount` | 操作数 | 无 | `Int` | 无 |
| `build` | 构建文档 | 无 | `Result<OpenApiDocument, Error>` | `InvalidArgument`/`AlreadyExists` |

说明：

- `summary`/`description` 允许空串（表示省略）。
- `contact` 的 name/url/email 允许空串；构建时仅输出非空字段。
- `license` 的 name 非空；identifier/url 可空；构建时输出非空字段。
- `httpSecurityScheme` 只接受 `Basic`/`Bearer`；`apiKeySecurityScheme` 只接受三种 API key 位置。
- `securitySchemeFor` 根据 `Authenticator.scheme()` 分派，并使用 `parameterName()`；API key 参数名缺失是合同错误。
- `globalSecurity` 每个调用追加一个安全要求对象；scopes 仅对 OAuth2 有意义，Basic/Bearer/API key 通常传空列表。
- `addRoute` 重复 method+path 返回 `AlreadyExists`；显式 operationId 重复返回 `AlreadyExists`。
- `addRouter` 对同一 router 引用幂等；失败可能已加入部分操作，调用方应丢弃 builder 或重建。
- `build` 自动补齐 ProblemDetails schema，并生成 `default` 响应。

---

## 8. 使用的技术

- builder；
- JSON 对象/数组组装；
- 路由元数据转换；
- 确定性 operationId；
- 安全方案映射；
- 自动 ProblemDetails 组件。

---

## 9. 需要的支撑

- 语言：class、List、Map、String、Bool、Int、Result；
- 运行时：无；
- 接口：`ApiRoute`、`ApiRouter`、`Authenticator`、`AuthScheme`、`OpenApiDocument`、`HttpStatus`、`JsonValue`、`JsonObject`、`JsonArray`、`JsonNumber`、`Error`、`BasicError`、`ErrorKind`、`httpMethodName`、`authSchemeOpenApiType`、`authSchemeOpenApiLocation`。

---

## 10. 依赖的特性/接口/类

`ApiRoute`、`ApiRouter`、`Authenticator`、`AuthScheme`、`OpenApiDocument`、`HttpStatus`、`JsonValue`、`JsonObject`、`JsonArray`、`JsonNumber`、`Error`、`BasicError`、`ErrorKind`、`httpMethodName`、`authSchemeOpenApiType`、`authSchemeOpenApiLocation`。

---

## 11. 所有权与并发

引用语义；构建期非线程安全；`addRouter` 保存 router 引用用于幂等判断；`build` 后 builder 仍可变但不应再改；无资源；无取消点。

---

## 12. 示例与反例

正确：

```text
OpenApiBuilder builder = new OpenApiBuilder("Orders", "1.0.0")
    .description("Order API")
    .server("https://api.example.com", "production")
    .securitySchemeFor(bearerAuthenticator, "Bearer token")
    .globalSecurity("bearerAuth", [])
builder.addRouter(router).value()
ApiOptions options = new ApiOptions().openApi(builder)
```

反例：

- 显式 operationId 重复；
- 给 Basic 方案传 API key 参数名；
- 只设置 requestValidator 期望 OpenAPI 有请求 schema；
- 修改 `paths()` 期望文档变化；
- 期望自动生成 OAuth2 流程；
- 期望解析外部 `$ref`。

---

## 13. 测试/场景义务

info 字段；servers/tags；Basic/Bearer/API key 方案；全局安全；publicAccess；component schema/response/parameter；webhook；单路由/多路由；operationId 显式/自动/重复；路径/查询/头参数；请求/响应 schema；默认 ProblemDetails；addRouter 幂等；build 后快照；非法状态/媒体类型。

---

## 14. XNull 伪代码

> 非可执行设计伪代码。

```xnull
class OpenApiBuilder {
    final String _title
    final String _version
    String _summary = ""
    String _description = ""
    String _termsOfService = ""
    JsonObject? _contact = null
    JsonObject? _license = null
    String _jsonSchemaDialect = ""
    JsonArray _servers = new JsonArray()
    JsonArray _tags = new JsonArray()
    JsonObject _schemas = new JsonObject()
    JsonObject _responses = new JsonObject()
    JsonObject _parameters = new JsonObject()
    JsonObject _securitySchemes = new JsonObject()
    JsonArray _security = new JsonArray()
    JsonObject _paths = new JsonObject()
    JsonObject _webhooks = new JsonObject()
    JsonObject? _externalDocs = null
    List<ApiRouter> _includedRouters = []
    Map<String, Int> _operationNames = [:]

    OpenApiBuilder(String title, String version) {
        if title == null || title == "" || version == null || version == "" {
            throw "OpenApiBuilder: empty title or version"
        }
        if title.indexOf("\n") >= 0 || version.indexOf("\n") >= 0 {
            throw "OpenApiBuilder: multiline title or version"
        }
        _title = title
        _version = version
    }

    OpenApiBuilder summary(String text) {
        if text == null { throw "OpenApiBuilder.summary: null" }
        _summary = text
        return self
    }

    OpenApiBuilder description(String text) {
        if text == null { throw "OpenApiBuilder.description: null" }
        _description = text
        return self
    }

    OpenApiBuilder termsOfService(String url) {
        if url == null || url == "" { throw "OpenApiBuilder.termsOfService: empty" }
        _termsOfService = url
        return self
    }

    OpenApiBuilder contact(String name, String url, String email) {
        if name == null || url == null || email == null {
            throw "OpenApiBuilder.contact: null"
        }
        JsonObject value = new JsonObject()
        if name != "" { value.set("name", JsonValue.string(name)) }
        if url != "" { value.set("url", JsonValue.string(url)) }
        if email != "" { value.set("email", JsonValue.string(email)) }
        _contact = value
        return self
    }

    OpenApiBuilder license(String name, String identifier, String url) {
        if name == null || name == "" || identifier == null || url == null {
            throw "OpenApiBuilder.license: invalid argument"
        }
        JsonObject value = new JsonObject()
        value.set("name", JsonValue.string(name))
        if identifier != "" { value.set("identifier", JsonValue.string(identifier)) }
        if url != "" { value.set("url", JsonValue.string(url)) }
        _license = value
        return self
    }

    OpenApiBuilder jsonSchemaDialect(String uri) {
        if uri == null || uri == "" {
            throw "OpenApiBuilder.jsonSchemaDialect: empty"
        }
        _jsonSchemaDialect = uri
        return self
    }

    OpenApiBuilder externalDocs(String url, String description) {
        if url == null || url == "" || description == null {
            throw "OpenApiBuilder.externalDocs: invalid argument"
        }
        JsonObject value = new JsonObject()
        value.set("url", JsonValue.string(url))
        if description != "" {
            value.set("description", JsonValue.string(description))
        }
        _externalDocs = value
        return self
    }

    OpenApiBuilder server(String url, String description) {
        if url == null || url == "" || description == null {
            throw "OpenApiBuilder.server: invalid argument"
        }
        JsonObject value = new JsonObject()
        value.set("url", JsonValue.string(url))
        if description != "" {
            value.set("description", JsonValue.string(description))
        }
        _servers.add(JsonValue.object(value))
        return self
    }

    OpenApiBuilder tag(String name, String description) {
        if name == null || name == "" || description == null {
            throw "OpenApiBuilder.tag: invalid argument"
        }
        JsonObject value = new JsonObject()
        value.set("name", JsonValue.string(name))
        if description != "" {
            value.set("description", JsonValue.string(description))
        }
        _tags.add(JsonValue.object(value))
        return self
    }

    OpenApiBuilder httpSecurityScheme(String name, AuthScheme scheme,
                                      String description) {
        if name == null || name == "" || description == null {
            throw "OpenApiBuilder.httpSecurityScheme: invalid argument"
        }
        if scheme != AuthScheme.Basic && scheme != AuthScheme.Bearer {
            throw "OpenApiBuilder.httpSecurityScheme: not HTTP auth"
        }
        JsonObject value = new JsonObject()
        value.set("type", JsonValue.string(authSchemeOpenApiType(scheme)))
        if scheme == AuthScheme.Basic {
            value.set("scheme", JsonValue.string("basic"))
        } else {
            value.set("scheme", JsonValue.string("bearer"))
        }
        if description != "" {
            value.set("description", JsonValue.string(description))
        }
        _securitySchemes.set(name, JsonValue.object(value))
        return self
    }

    OpenApiBuilder apiKeySecurityScheme(String name, AuthScheme scheme,
                                        String parameterName, String description) {
        if name == null || name == "" || parameterName == null
            || parameterName == "" || description == null {
            throw "OpenApiBuilder.apiKeySecurityScheme: invalid argument"
        }
        if scheme != AuthScheme.ApiKeyHeader && scheme != AuthScheme.ApiKeyQuery
            && scheme != AuthScheme.ApiKeyCookie {
            throw "OpenApiBuilder.apiKeySecurityScheme: not API key"
        }
        JsonObject value = new JsonObject()
        value.set("type", JsonValue.string(authSchemeOpenApiType(scheme)))
        value.set("name", JsonValue.string(parameterName))
        value.set("in", JsonValue.string(authSchemeOpenApiLocation(scheme)))
        if description != "" {
            value.set("description", JsonValue.string(description))
        }
        _securitySchemes.set(name, JsonValue.object(value))
        return self
    }

    OpenApiBuilder securitySchemeFor(Authenticator authenticator,
                                     String description) {
        if authenticator == null || description == null {
            throw "OpenApiBuilder.securitySchemeFor: null argument"
        }
        if authenticator.scheme() == AuthScheme.Basic
            || authenticator.scheme() == AuthScheme.Bearer {
            return self.httpSecurityScheme(authenticator.name(),
                authenticator.scheme(), description)
        }
        return self.apiKeySecurityScheme(authenticator.name(),
            authenticator.scheme(), authenticator.parameterName(), description)
    }

    OpenApiBuilder globalSecurity(String schemeName, List<String> scopes) {
        if schemeName == null || schemeName == "" || scopes == null {
            throw "OpenApiBuilder.globalSecurity: invalid argument"
        }
        JsonArray scopeValues = new JsonArray()
        Int index = 0
        while index < scopes.length() {
            scopeValues.add(JsonValue.string(scopes.get(index)))
            index = index + 1
        }
        JsonObject requirement = new JsonObject()
        requirement.set(schemeName, JsonValue.array(scopeValues))
        _security.add(JsonValue.object(requirement))
        return self
    }

    OpenApiBuilder componentSchema(String name, JsonValue schema) {
        if name == null || name == "" || schema == null {
            throw "OpenApiBuilder.componentSchema: invalid argument"
        }
        _schemas.set(name, schema)
        return self
    }

    OpenApiBuilder componentResponse(String name, JsonValue response) {
        if name == null || name == "" || response == null {
            throw "OpenApiBuilder.componentResponse: invalid argument"
        }
        _responses.set(name, response)
        return self
    }

    OpenApiBuilder componentParameter(String name, JsonValue parameter) {
        if name == null || name == "" || parameter == null {
            throw "OpenApiBuilder.componentParameter: invalid argument"
        }
        _parameters.set(name, parameter)
        return self
    }

    OpenApiBuilder webhook(String name, JsonValue pathItem) {
        if name == null || name == "" || pathItem == null {
            throw "OpenApiBuilder.webhook: invalid argument"
        }
        _webhooks.set(name, pathItem)
        return self
    }

    Result<Unit, Error> addRouter(ApiRouter router) {
        if router == null { return Err(new BasicError(ErrorKind.InvalidArgument,
            "null router")) }
        if _includedRouters.indexOf(router) >= 0 { return Ok(unit) }
        List<ApiRoute> routes = router.routes()
        Int index = 0
        while index < routes.length() {
            Result<Unit, Error> added = self.addRoute(routes.get(index))
            if added.isErr() { return Err(added.error()) }
            index = index + 1
        }
        _includedRouters.push(router)
        return Ok(unit)
    }

    Result<Unit, Error> addRoute(ApiRoute route) {
        if route == null { return Err(new BasicError(ErrorKind.InvalidArgument,
            "null route")) }
        JsonValue? itemValue = _paths.getOrNull(route.pattern())
        JsonObject item = new JsonObject()
        if itemValue != null {
            if itemValue.asObject() == null {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "path item is not an object"))
            }
            item = (itemValue.asObject() as JsonObject).copy()
        }
        String method = httpMethodName(route.method()).toLower()
        if item.has(method) {
            return Err(new BasicError(ErrorKind.AlreadyExists,
                "duplicate path operation"))
        }
        String operationName = self.generateOperationName(route)
        String? explicitName = route.operationName()
        if explicitName != null {
            if _operationNames.has(explicitName) {
                return Err(new BasicError(ErrorKind.AlreadyExists,
                    "duplicate operationId"))
            }
            operationName = explicitName
        }
        _operationNames.put(operationName, 1)
        JsonArray parameters = new JsonArray()
        List<String> pathNames = route.pathParameterNames()
        Int pathIndex = 0
        while pathIndex < pathNames.length() {
            JsonObject schema = new JsonObject()
            schema.set("type", JsonValue.string("string"))
            JsonObject parameter = new JsonObject()
            parameter.set("name", JsonValue.string(pathNames.get(pathIndex)))
            parameter.set("in", JsonValue.string("path"))
            parameter.set("required", JsonValue.bool(true))
            parameter.set("schema", JsonValue.object(schema))
            parameters.add(JsonValue.object(parameter))
            pathIndex = pathIndex + 1
        }
        JsonArray queryParameters = route.queryParameters()
        Int parameterIndex = 0
        while parameterIndex < queryParameters.length() {
            parameters.add(queryParameters.get(parameterIndex))
            parameterIndex = parameterIndex + 1
        }
        JsonArray headerParameters = route.headerParameters()
        parameterIndex = 0
        while parameterIndex < headerParameters.length() {
            parameters.add(headerParameters.get(parameterIndex))
            parameterIndex = parameterIndex + 1
        }
        JsonObject operation = new JsonObject()
        if route.summary() != null && (route.summary() as String) != "" {
            operation.set("summary", JsonValue.string(route.summary() as String))
        }
        if route.description() != null && (route.description() as String) != "" {
            operation.set("description", JsonValue.string(route.description() as String))
        }
        operation.set("operationId", JsonValue.string(operationName))
        if !route.tags().isEmpty() {
            JsonArray tags = new JsonArray()
            Int tagIndex = 0
            while tagIndex < route.tags().length() {
                tags.add(JsonValue.string(route.tags().get(tagIndex)))
                tagIndex = tagIndex + 1
            }
            operation.set("tags", JsonValue.array(tags))
        }
        if route.isDeprecated() {
            operation.set("deprecated", JsonValue.bool(true))
        }
        if parameters.length() > 0 {
            operation.set("parameters", JsonValue.array(parameters))
        }
        JsonValue? requestSchema = route.requestSchema()
        if requestSchema != null {
            JsonValue schemaValue = requestSchema as JsonValue
            List<String> consumes = route.consumes()
            if consumes.isEmpty() { consumes.push("application/json") }
            JsonObject content = new JsonObject()
            Int consumeIndex = 0
            while consumeIndex < consumes.length() {
                JsonObject media = new JsonObject()
                media.set("schema", schemaValue)
                content.set(consumes.get(consumeIndex), JsonValue.object(media))
                consumeIndex = consumeIndex + 1
            }
            JsonObject requestBody = new JsonObject()
            requestBody.set("required", JsonValue.bool(true))
            requestBody.set("content", JsonValue.object(content))
            operation.set("requestBody", JsonValue.object(requestBody))
        }
        JsonObject responses = new JsonObject()
        JsonArray responseCodes = route.responseCodes()
        if responseCodes.isEmpty() { responseCodes.push(200) }
        Int responseIndex = 0
        while responseIndex < responseCodes.length() {
            Int status = responseCodes.get(responseIndex)
            String responseDescription = route.responseDescription(status)
            if responseDescription == "" {
                responseDescription = HttpStatus.of(status).reason()
            }
            if responseDescription == "" {
                responseDescription = "HTTP " + str(status)
            }
            JsonObject response = new JsonObject()
            response.set("description", JsonValue.string(responseDescription))
            JsonValue? responseSchema = route.responseSchema(status)
            if responseSchema != null && status != 204 && status != 304 {
                JsonValue schemaValue = responseSchema as JsonValue
                List<String> produces = route.produces()
                if produces.isEmpty() { produces.push("application/json") }
                JsonObject content = new JsonObject()
                Int produceIndex = 0
                while produceIndex < produces.length() {
                    JsonObject media = new JsonObject()
                    media.set("schema", schemaValue)
                    content.set(produces.get(produceIndex), JsonValue.object(media))
                    produceIndex = produceIndex + 1
                }
                response.set("content", JsonValue.object(content))
            }
            responses.set(str(status), JsonValue.object(response))
            responseIndex = responseIndex + 1
        }
        if !responses.has("default") {
            JsonObject reference = new JsonObject()
            reference.set("$ref", JsonValue.string("#/components/schemas/ProblemDetails"))
            JsonObject media = new JsonObject()
            media.set("schema", JsonValue.object(reference))
            JsonObject content = new JsonObject()
            content.set("application/problem+json", JsonValue.object(media))
            JsonObject problem = new JsonObject()
            problem.set("description", JsonValue.string("Problem details"))
            problem.set("content", JsonValue.object(content))
            responses.set("default", JsonValue.object(problem))
        }
        operation.set("responses", JsonValue.object(responses))
        if route.isPublicAccess() {
            operation.set("security", JsonValue.array(new JsonArray()))
        } else if route.authenticator() != null {
            Authenticator authenticator = route.authenticator() as Authenticator
            self.securitySchemeFor(authenticator, "Route authentication")
            JsonArray security = new JsonArray()
            JsonObject requirement = new JsonObject()
            requirement.set(authenticator.name(), JsonValue.array(new JsonArray()))
            security.add(JsonValue.object(requirement))
            operation.set("security", JsonValue.array(security))
        }
        item.set(method, JsonValue.object(operation))
        _paths.set(route.pattern(), JsonValue.object(item))
        return Ok(unit)
    }

    private String generateOperationName(ApiRoute route) {
        String method = httpMethodName(route.method()).toLower()
        String base = method
        String pattern = route.pattern()
        Int index = 0
        while index < pattern.length() {
            String character = pattern.substring(index, index + 1)
            Bool alpha = (character >= "A" && character <= "Z")
                || (character >= "a" && character <= "z")
            Bool digit = character >= "0" && character <= "9"
            if alpha || digit {
                base = base + character
            } else {
                base = base + "_"
            }
            index = index + 1
        }
        String candidate = base
        Int suffix = 2
        while _operationNames.has(candidate) {
            candidate = base + "_" + str(suffix)
            suffix = suffix + 1
        }
        return candidate
    }

    Int operationCount() { return _operationNames.length() }

    Result<OpenApiDocument, Error> build() {
        if !_schemas.has("ProblemDetails") {
            JsonObject properties = new JsonObject()
            JsonObject typeProperty = new JsonObject()
            typeProperty.set("type", JsonValue.string("string"))
            typeProperty.set("format", JsonValue.string("uri-reference"))
            properties.set("type", JsonValue.object(typeProperty))
            JsonObject titleProperty = new JsonObject()
            titleProperty.set("type", JsonValue.string("string"))
            properties.set("title", JsonValue.object(titleProperty))
            JsonObject statusProperty = new JsonObject()
            statusProperty.set("type", JsonValue.string("integer"))
            statusProperty.set("minimum", JsonValue.number(new JsonNumber("100")))
            statusProperty.set("maximum", JsonValue.number(new JsonNumber("599")))
            properties.set("status", JsonValue.object(statusProperty))
            JsonObject detailProperty = new JsonObject()
            detailProperty.set("type", JsonValue.string("string"))
            properties.set("detail", JsonValue.object(detailProperty))
            JsonObject instanceProperty = new JsonObject()
            instanceProperty.set("type", JsonValue.string("string"))
            instanceProperty.set("format", JsonValue.string("uri-reference"))
            properties.set("instance", JsonValue.object(instanceProperty))
            JsonArray required = new JsonArray()
            required.add(JsonValue.string("type"))
            required.add(JsonValue.string("title"))
            required.add(JsonValue.string("status"))
            JsonObject schema = new JsonObject()
            schema.set("type", JsonValue.string("object"))
            schema.set("properties", JsonValue.object(properties))
            schema.set("required", JsonValue.array(required))
            _schemas.set("ProblemDetails", JsonValue.object(schema))
        }
        JsonObject info = new JsonObject()
        info.set("title", JsonValue.string(_title))
        info.set("version", JsonValue.string(_version))
        if _summary != "" { info.set("summary", JsonValue.string(_summary)) }
        if _description != "" { info.set("description", JsonValue.string(_description)) }
        if _termsOfService != "" {
            info.set("termsOfService", JsonValue.string(_termsOfService))
        }
        if _contact != null { info.set("contact", JsonValue.object(
            (_contact as JsonObject).copy())) }
        if _license != null { info.set("license", JsonValue.object(
            (_license as JsonObject).copy())) }
        JsonObject root = new JsonObject()
        root.set("openapi", JsonValue.string("3.1.0"))
        root.set("info", JsonValue.object(info))
        if _jsonSchemaDialect != "" {
            root.set("jsonSchemaDialect", JsonValue.string(_jsonSchemaDialect))
        }
        if _servers.length() > 0 {
            root.set("servers", JsonValue.array(_servers.copy()))
        }
        root.set("paths", JsonValue.object(_paths.copy()))
        if _webhooks.length() > 0 {
            root.set("webhooks", JsonValue.object(_webhooks.copy()))
        }
        JsonObject components = new JsonObject()
        if _schemas.length() > 0 {
            components.set("schemas", JsonValue.object(_schemas.copy()))
        }
        if _responses.length() > 0 {
            components.set("responses", JsonValue.object(_responses.copy()))
        }
        if _parameters.length() > 0 {
            components.set("parameters", JsonValue.object(_parameters.copy()))
        }
        if _securitySchemes.length() > 0 {
            components.set("securitySchemes",
                JsonValue.object(_securitySchemes.copy()))
        }
        if components.length() > 0 {
            root.set("components", JsonValue.object(components))
        }
        if _security.length() > 0 {
            root.set("security", JsonValue.array(_security.copy()))
        }
        if _tags.length() > 0 {
            root.set("tags", JsonValue.array(_tags.copy()))
        }
        if _externalDocs != null {
            root.set("externalDocs", JsonValue.object(
                (_externalDocs as JsonObject).copy()))
        }
        return OpenApiDocument.fromJson(JsonValue.object(root))
    }
}
```
