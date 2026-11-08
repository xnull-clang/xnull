# S6-09 net sema 面冻结（E2 → E4/E5）

- 卡片：S6-09（ADR-009 B2 前置）
- 范围：sema 类型/签名；运行时与 `.xfb` 由 E5/E4 接。
- 稳定性：`@preview`。

## 类型

| 类型 | 说明 |
|---|---|
| `Socket` | 连接句柄（close 必达） |
| `Listener` | 监听句柄（close 必达） |
| `Response` | HTTP 响应（`status()/body()/header(String)`） |
| `Request` | 预留请求类型（首版不开放构造） |

## plain / Async（`Context` 首参）

```x
Result<Socket, Error>    connect(String host, Int port)
Result<Socket, Error>    connectAsync(Context ctx, String host, Int port)
Result<Listener, Error>  bind(String host, Int port)
Result<Listener, Error>  bindAsync(Context ctx, String host, Int port)

Socket.read(Bytes)                  -> Result<Int, Error>
Socket.readAsync(Context, Bytes)    -> Result<Int, Error>
Socket.write(Bytes)                 -> Result<Int, Error>
Socket.writeAsync(Context, Bytes)   -> Result<Int, Error>
Socket.close()                      -> Result<void, Error>

Listener.accept()                   -> Result<Socket, Error>
Listener.acceptAsync(Context)       -> Result<Socket, Error>
Listener.close()                    -> Result<void, Error>

Response.status()                   -> Int
Response.body()                     -> Bytes
Response.header(String)             -> String?
```

## `xdk.net.http`

```x
Result<Response, Error> get(String url)
Result<Response, Error> post(String url, Bytes body)
Result<Response, Error> getAsync(Context, String)
Result<Response, Error> postAsync(Context, String, Bytes)
```

`import xdk.net.http` 绑定全部符号；`import xdk.net.http.getAsync` 只绑单符号。

## 错误映射（E4 绑定合同）

- 全部可失败操作返回 `Result<_, Error>`；不 panic。
- 原生码映射：超时→`Timeout`、取消→`Cancelled`、连接/读写失败→`Io`/`Network`、地址非法→`InvalidArgument`；未知码→`Internal`（不得降级为 Ok）。
- Async 挂起点必须检查 `Context`；取消返回 `Cancelled`。

## 待接

1. E5：`rt_std_net.c`（plain socket + async 挂起点）。
2. E4：`bindings/xdk/net.xfb` + 调用点发射（`Socket`/`Listener` 句柄 close 幂等）。
3. 本卡只做 sema；E2E 用例在 E4/E5 合入后补 `tests/s6/xdk09_net.x`。
