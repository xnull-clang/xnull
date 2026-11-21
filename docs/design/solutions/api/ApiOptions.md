# `ApiOptions`

| 项 | 值 |
| --- | --- |
| 类型 | `class ApiOptions` |
| 包 | `xdk.api` |
| 稳定性 | `preview` |
| 依赖 | `ApiMiddleware`、`Authenticator`、`RateLimitPolicy`、`CorsPolicy`、`OpenApiBuilder`、`Error` |

---

## 1. 定位

API 层全局配置：中间件、认证器、限流策略、CORS、请求体/SSE 上限、错误 detail 开关、自动 OPTIONS、ProblemDetails 类型前缀、OpenAPI 构建器与端点路径。

不做：HTTP 服务器选项（由 `HttpServerOptions` 负责）、路由注册、TLS、进程/线程池配置、模板/ORM。

---

## 2. 设计逻辑

- 可变构建期；`ApiServer.bind` 时复制为快照。
- 中间件按添加顺序保存，先添加者在外层。
- 认证器、限流策略按引用共享：认证器通常无状态；限流策略持计数器，复制会重置限流状态，因此显式共享。
- CORS 策略在快照时复制，避免 bind 后被外部修改。
- OpenAPI 构建器按引用共享；`bind` 时读取并构建文档，之后修改只影响后续 bind；同一个 builder 被多个不同 router 的 bind 复用会累积路径，建议每个服务独立 builder。
- `problemTypeBase` 为空表示使用 `urn:xdk:api:*`；非空时作为应用问题类型前缀。
- 默认值：body 8 MiB、SSE 缓冲 1 MiB、自动 OPTIONS 开、错误 detail 关、OpenAPI 路径 `/openapi.json`。
- 无 close；非线程安全（构建期单线程使用）。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_middleware` | `List<ApiMiddleware>` | 全局中间件 |
| `_authenticator` | `Authenticator?` | 全局认证器 |
| `_rateLimitPolicy` | `RateLimitPolicy?` | 全局限流策略 |
| `_corsPolicy` | `CorsPolicy?` | CORS 策略 |
| `_maximumBodyBytes` | `Long` | 请求体上限，>0 |
| `_sseBufferBytes` | `Long` | SSE 缓冲上限，>0 |
| `_includeErrorDetail` | `Bool` | 是否暴露内部错误 detail |
| `_autoOptions` | `Bool` | 是否自动 OPTIONS |
| `_problemTypeBase` | `String` | 问题类型前缀，可空 |
| `_openApiBuilder` | `OpenApiBuilder?` | OpenAPI 构建器 |
| `_openApiPath` | `String` | OpenAPI 端点路径，可空 |

不变量：列表非 null；上限 >0；`_problemTypeBase` 为空或以 `urn:`/`http://`/`https://` 开头且不以 `/` 结尾；`_openApiPath` 为空或以 `/` 开头。

---

## 4. 生命周期

构造后可变；`ApiServer.bind` 复制；无 close；可被多个 bind 读取。构建完成后建议不再修改。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ApiOptions()` | 无 | 默认值 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `use` | 追加全局中间件 | `ApiMiddleware middleware` | `ApiOptions` | null → panic |
| `middleware` | 中间件快照 | 无 | `List<ApiMiddleware>` | 无 |
| `authenticator` | 设置全局认证器 | `Authenticator authenticator` | `ApiOptions` | null → panic |
| `authenticator` | 读取认证器 | 无 | `Authenticator?` | 无 |
| `rateLimitPolicy` | 设置全局限流 | `RateLimitPolicy policy` | `ApiOptions` | null → panic |
| `rateLimitPolicy` | 读取限流 | 无 | `RateLimitPolicy?` | 无 |
| `corsPolicy` | 设置 CORS | `CorsPolicy policy` | `ApiOptions` | null → panic |
| `corsPolicy` | 读取 CORS | 无 | `CorsPolicy?` | 无 |
| `maximumBodyBytes` | 设置 body 上限 | `Long value` | `ApiOptions` | ≤0 → panic |
| `maximumBodyBytes` | 读取 body 上限 | 无 | `Long` | 无 |
| `sseBufferBytes` | 设置 SSE 缓冲 | `Long value` | `ApiOptions` | ≤0 → panic |
| `sseBufferBytes` | 读取 SSE 缓冲 | 无 | `Long` | 无 |
| `includeErrorDetail` | 设置 detail 开关 | `Bool value` | `ApiOptions` | 无 |
| `isIncludeErrorDetail` | 读取 detail 开关 | 无 | `Bool` | 无 |
| `autoOptions` | 设置自动 OPTIONS | `Bool value` | `ApiOptions` | 无 |
| `isAutoOptions` | 读取自动 OPTIONS | 无 | `Bool` | 无 |
| `problemTypeBase` | 设置问题类型前缀 | `String value` | `ApiOptions` | 非法 → panic |
| `problemTypeBase` | 读取前缀 | 无 | `String` | 无 |
| `openApi` | 设置构建器 | `OpenApiBuilder builder` | `ApiOptions` | null → panic |
| `openApiBuilder` | 读取构建器 | 无 | `OpenApiBuilder?` | 无 |
| `openApiPath` | 设置端点路径 | `String value` | `ApiOptions` | 非法 → panic |
| `openApiPath` | 读取端点路径 | 无 | `String` | 无 |
| `copy` | 独立快照 | 无 | `ApiOptions` | 无 |

说明：

- `use` 追加到末尾；顺序即外层到内层。
- `openApiPath("")` 关闭内置端点，即使设置了 builder。
- `copy` 复制中间件列表与 CORS；共享认证器、限流策略、OpenAPI 构建器。
- `copy` 后修改原对象不影响快照的标量/列表/CORS；构建器与限流状态按共享语义处理。

---

## 8. 使用的技术

- builder 模式；
- 选项快照；
- 引用共享与复制分离；
- 上限/路径校验。

---

## 9. 需要的支撑

- 语言：class、List、Long、Bool、String、Result；
- 运行时：无；
- 接口：`ApiMiddleware`、`Authenticator`、`RateLimitPolicy`、`CorsPolicy`、`OpenApiBuilder`。

---

## 10. 依赖的特性/接口/类

`ApiMiddleware`、`Authenticator`、`RateLimitPolicy`、`CorsPolicy`、`OpenApiBuilder`。

---

## 11. 所有权与并发

引用语义；构建期非线程安全；bind 读取时调用方不得并发修改。`copy` 后标量独立；中间件列表独立；CORS 独立；认证器/限流策略/构建器共享。无资源。

---

## 12. 示例与反例

正确：

```text
ApiOptions options = new ApiOptions()
    .use(requestLogMiddleware)
    .maximumBodyBytes(4_194_304)
    .autoOptions(true)
    .corsPolicy(cors)
    .rateLimitPolicy(limit)
```

反例：

- 0 或负上限；
- `problemTypeBase` 以 `/` 结尾；
- bind 后修改 options 期望已绑定服务器变化；
- 指望 `copy` 重置限流计数；
- OpenAPI 路径与业务路由冲突。

---

## 13. 测试/场景义务

默认值；每个 setter 的合法/非法输入；中间件顺序；copy 独立性/共享性；OpenAPI 空路径关闭；problemTypeBase 校验；多个 bind 复用同一 options；limit 策略共享计数。

---

## 14. XNull 伪代码

> 非可执行设计伪代码。

```xnull
class ApiOptions {
    List<ApiMiddleware> _middleware = []
    Authenticator? _authenticator = null
    RateLimitPolicy? _rateLimitPolicy = null
    CorsPolicy? _corsPolicy = null
    Long _maximumBodyBytes = 8388608
    Long _sseBufferBytes = 1048576
    Bool _includeErrorDetail = false
    Bool _autoOptions = true
    String _problemTypeBase = ""
    OpenApiBuilder? _openApiBuilder = null
    String _openApiPath = "/openapi.json"

    ApiOptions() {
    }

    ApiOptions use(ApiMiddleware middleware) {
        if middleware == null { throw "ApiOptions.use: null middleware" }
        _middleware.push(middleware)
        return self
    }

    List<ApiMiddleware> middleware() { return _middleware.copy() }

    ApiOptions authenticator(Authenticator authenticator) {
        if authenticator == null { throw "ApiOptions.authenticator: null" }
        _authenticator = authenticator
        return self
    }

    Authenticator? authenticator() { return _authenticator }

    ApiOptions rateLimitPolicy(RateLimitPolicy policy) {
        if policy == null { throw "ApiOptions.rateLimitPolicy: null" }
        _rateLimitPolicy = policy
        return self
    }

    RateLimitPolicy? rateLimitPolicy() { return _rateLimitPolicy }

    ApiOptions corsPolicy(CorsPolicy policy) {
        if policy == null { throw "ApiOptions.corsPolicy: null" }
        _corsPolicy = policy
        return self
    }

    CorsPolicy? corsPolicy() { return _corsPolicy }

    ApiOptions maximumBodyBytes(Long value) {
        if value <= 0 { throw "ApiOptions.maximumBodyBytes: invalid" }
        _maximumBodyBytes = value
        return self
    }

    Long maximumBodyBytes() { return _maximumBodyBytes }

    ApiOptions sseBufferBytes(Long value) {
        if value <= 0 { throw "ApiOptions.sseBufferBytes: invalid" }
        _sseBufferBytes = value
        return self
    }

    Long sseBufferBytes() { return _sseBufferBytes }

    ApiOptions includeErrorDetail(Bool value) {
        _includeErrorDetail = value
        return self
    }

    Bool isIncludeErrorDetail() { return _includeErrorDetail }

    ApiOptions autoOptions(Bool value) {
        _autoOptions = value
        return self
    }

    Bool isAutoOptions() { return _autoOptions }

    ApiOptions problemTypeBase(String value) {
        if value == null { throw "ApiOptions.problemTypeBase: null" }
        if value != "" {
            Bool valid = value.startsWith("urn:") || value.startsWith("http://")
                || value.startsWith("https://")
            if !valid || value.endsWith("/") {
                throw "ApiOptions.problemTypeBase: invalid prefix"
            }
        }
        _problemTypeBase = value
        return self
    }

    String problemTypeBase() { return _problemTypeBase }

    ApiOptions openApi(OpenApiBuilder builder) {
        if builder == null { throw "ApiOptions.openApi: null builder" }
        _openApiBuilder = builder
        return self
    }

    OpenApiBuilder? openApiBuilder() { return _openApiBuilder }

    ApiOptions openApiPath(String value) {
        if value == null { throw "ApiOptions.openApiPath: null" }
        if value != "" {
            if !value.startsWith("/") || value.indexOf("?") >= 0
                || value.indexOf("#") >= 0 {
                throw "ApiOptions.openApiPath: invalid path"
            }
            if value.endsWith("/") && value != "/" {
                throw "ApiOptions.openApiPath: trailing slash"
            }
        }
        _openApiPath = value
        return self
    }

    String openApiPath() { return _openApiPath }

    ApiOptions copy() {
        ApiOptions result = new ApiOptions()
        result._middleware = _middleware.copy()
        result._authenticator = _authenticator
        result._rateLimitPolicy = _rateLimitPolicy
        result._maximumBodyBytes = _maximumBodyBytes
        result._sseBufferBytes = _sseBufferBytes
        result._includeErrorDetail = _includeErrorDetail
        result._autoOptions = _autoOptions
        result._problemTypeBase = _problemTypeBase
        result._openApiBuilder = _openApiBuilder
        result._openApiPath = _openApiPath
        if _corsPolicy != null {
            result._corsPolicy = (_corsPolicy as CorsPolicy).copy()
        }
        return result
    }
}
```
