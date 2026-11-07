# 回执：S7-FFI-01 修复（E4 codegen）

- 卡片：FFI-01（QA `验收-S7-FFI-01.md` P-01/P-02/P-03；S7 §7.1 / S4 §7.3）
- 提交：见本次 commit（仅 pod/e4-codegen）
- 顺序：先红后绿
  - 红：`evidence/S7-FFI01/red.log`（签名仍为原始码 + 出参，新调用点 GEN-103/TY-101）
  - 绿：`evidence/S7-FFI01/green.log`（TestS7_02* PASS）

## 一、结论

同步 FFI 非 close 的 `@errorCode` 入口改为返回 `Result<T, ErrorKind>`（QA 放行条件
中的“等价错误值”；E = `ErrorKind`，与 `Err(ErrorKind.NotFound)` 矩阵一致）。
`rc == 0 → Ok(value)`；非零 → `Err(id(rc))`：已知码按 `errorMap`，未知码 `Internal`，
`Cancelled`/`Timeout` 保持原分类不降级。

## 二、红 → 绿

| 项 | 修前（红） | 修后（绿） |
|---|---|---|
| 出参形态 `fileRead(..., code)` | `Int64` + `Int32 code` 出参 | `Result<Int64, ErrorKind> fileRead(...)`，code 形参从 XNull 签名移除 |
| 返回值即错误码 `fileWrite` | `Int32` 原始码 | `Result<void, ErrorKind>` |
| 调用点 | 依赖出参变量/原始码 | 直接 `Ok/Err`；`r.isOk()/value()/error()` |
| 映射 | 仅 helper | 调用点构造 `.err = xn_ffi_<region>_error_kind_id(rc)` |
| 未知码 | — | `Internal`，绝不 `Ok` |
| Cancelled/Timeout | — | 14/15 保持 `Cancelled`/`Timeout` |
| fatal | 已去 `exit(134)` | 保持不 fatal |

## 三、实现要点

- `ffi_gen.go`
  - `ffiReturnsResult`：非 close 的 `@errorCode`（出参或返回值）→ Result；
    close 保持 Bool（幂等关闭兼容面），无错误码入口形态不变（含 `.unaware`）。
  - `ffiResultXType`：`Result<T, ErrorKind>`；`codeParam=.result` 时 `T = void`。
  - `ffiCodeParamSkipped`：错误码出参不进入 XNull 签名/调用实参。
  - `ffiResultLines`：声明 Result 临时值，`ok=(rc==0)`，成功写 `v`，失败写
    `err=(ErrorKind)xn_ffi_<region>_error_kind_id(rc)`。
- `codegen.go`：`resultExpr` 识别 Result 返回的 FFI 调用；`fnRet` 登记 Result 实例。
- `s701.go` / `build.go`：sema 投射同步新签名，并登记 `ErrorKind` 可见性。
- 包装 ABI 不变：`int32_t xn_ffi_<entry>(...)` 仍以错误码返回，只改 XNull 语言面。

## 四、测试

- `TestS7_02ErrorCodeNoFatal`：出参形态 → `Result<Int64, ErrorKind>`，code=5 →
  `Err(NotFound)`。
- `TestS7_02ErrorCodeReturnNoFatal`：返回值即错误码 → `Result<void, ErrorKind>`。
- `TestS7_02ResultMapping`：Ok(42) / 已知 5 / 未知 99 / Cancelled 14 / Timeout 15。
- 既有 S4-04/S4-05/B0-07c 用例同步到 Result 形态。

## 五、验证

```bash
cd impl
go test ./internal/codegen/ ./internal/codegen/ffi/ ./internal/cli/ ./internal/interp/ ./internal/sema/ -count=1
```

全绿。

## 六、边界

- `@errorCode` close 仍以 `Bool` 暴露（`true` = 成功），避免破坏既有 B0-07c 调用面；
  若后续要求 `Result<void, ErrorKind>` 再单卡收敛。
- 异步/任务入口（`*Async`）继续沿用 S5/S6 的 Result 通道，不在本卡范围。
