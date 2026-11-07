# 回执：S6 XDK-08 收口（E4 codegen）

- 卡片：XDK-08 编译路径（Char/Format；text.xfb parse/UTF 编组）
- 提交：`8800a1a`（仅 pod/e4-codegen；已同步 main 的 XDK-05 同步签名）
- 顺序：先红后绿：`evidence/S6-XDK08/red.log`（`codegen：类型 Char 未支持`）；
  `green.log`（`TestS6XDK08CompiledE2E` PASS）。

## 一、红 → 绿

| 项 | 修前（红） | 修后（绿） |
|---|---|---|
| `Format.int(7).width(4).pad('0').build()` | `类型 Char 未支持` | 输出 `0007`（链式构造/方法/Char 插值） |
| `parseInt("42")` | 编译面阻塞（Double/Error 协议/泛型） | `42` |
| `parseFloat("1.5")` | 同上 | `1.5` |
| `utf8ToUtf16` / `utf16ToUtf8` | 同上 | `true` / `true`（List<UInt16> 编组） |
| `check` + `run` | BYPASS | 同口径：check 通过、编译运行输出一致 |

`TestS6XDK08CompiledE2E`：`42 / 1.5 / true / true / 0007`。

## 二、实现要点

- **Char**：`xn_char`（int32）类型；`CharLitExpr` 字面量/exprType/intExpr；
  字符串插值走 `xn_str_char`（UTF-8 编码）；类字段 8 字节槽语义保留。
- **Double/Float + 定宽整数**：cType、FloatLit、算术/比较、print、插值、
  返回发射；`List<UInt16>` 容器 mangle/元素逆映射。
- **Error 协议**：codegen 恒合成 `Error` 协议（`kind/describe` 槽）并恒注入
  ErrorKind 枚举，保证 `xn_proto_Error`/`ErrorKind` 类型有定义。
- **Result<_,Error> 表示**：资源工程（`import xdk.sys`）用 `xrt_error_kind`
  值通道（E5 rt_std_res ABI）；其余工程用 Error 协议值（text/errors 源码单元）。
- **表达式补口**：类方法返回 String（链式 receiver，如 `Format.build`）、协议
  `describe` 的 strExpr 发射、有实参时优先方法而非同名字段、Result.value()
  作为容器实参。
- **text.xfb**：Regex 保持 FFI 原语；parseInt/parseFloat/UTF 经 XNull 单元
  编译路径端到端（不跨 FFI，故无需 out 参数 marshalling）；文件头已更新说明。

## 三、边界

- 资源工程与非资源工程对 `Result<_,Error>` 采用不同 C 表示；同一工程同时使用
  `xdk.sys` 资源与 `xdk.errors` 协议值错误面时需统一（后续卡/规范裁决）。
- `mutex/channel` 引用元素 ops、并发 GC（S3-06）仍不在本卡。
- interp 路径不受影响（E3 执行同一份 text.x）。

## 四、验证

```bash
cd impl
go test ./internal/cli/ -run TestS6XDK08 -count=1 -v
go test ./internal/codegen/ ./internal/codegen/ffi/ ./internal/cli/ ./internal/interp/ ./internal/sema/ -count=1
```

全绿（codegen / ffi / cli / interp / sema）。
