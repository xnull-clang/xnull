# M6-B0-07c 验收结论（执行侧自检）

卡片：FFI handle close 的 P-09 注入与绑定可见性（B0-06 numeric 变体报 `fileClose` 未定义）。
判据：handle 类型与 close 入口作为包级声明可见，样例编译并运行。

| 验收项 | 判据 | 实测 |
| --- | --- | --- |
| handle 类型可见 | `File`/`Dir` 可作为局部/参数类型 | 通过：`cType` 映射 `xrt_handle *`（注册表 Handles） |
| open 返回句柄 | handle 返回入口注入且可赋值 | 通过：`File f = fileOpenRead("in.txt")` |
| close 可见可调用 | `fileClose(f)` 通过 sema/codegen | 通过：错误码即返回值的 close 入口以 `Bool` 暴露，调用点 `xn_ffi_fileClose(...)` |
| 幂等关闭 | 运行时 close 成功登记 | 通过：生成 `xrt_handle_mark_closed`；原生 `xdkc_file_close` 幂等 |
| 样例编译运行 | `xnull build` + 运行 | 通过：stdout `closed`，exit 0 |
| 回归 | `go test ./...` | 通过（9 包 ok） |

## 实现

- `ffi_gen.go`：`ffiSupported` 放行 handle 形参/返回与「错误码即返回值的 close 入口」；`ffiParamXType`/`ffiRetXType` 增 handle 映射；close 注入为 `Bool`；合成函数体改 `while(true){}`（满足 sema 返回路径检查且不需可构造返回值）；`ffiCallLines` 增 handle 编组、String 字面量借用临时、ErrorCodeRet 语句化调用；新增 `handleExpr`/`isHandlePtr`。
- `codegen.go`：`handleNames` 注册；`cType` 识别 handle；FFI `fnRet` 增 handle/Bool；`emitLocalDecl`/`emitAssign` 增句柄分支（ARC release/retain）；语句化 close 调用。

## 未测项 / 边界

1. **运行时终结钩子缺陷（跨域，E5）**：`runtime/xrt_abi.c::handle_deinit` 把完整对象当 payload，成功 close 后 release 仍报“句柄泄漏”。独立复现见证据；不属 codegen 域，未改。
2. 其余错误码入口（`fileRead`/`fileWrite`/`dirRead` 等）仍要求 Result 映射，未注入（调用报未定义）；`Bytes` 类型面未接（B0-06 numeric 完整通过仍需后续卡）。
3. Bool 返回的非 close 入口（`pathExists`）、Int32 标量未接。
4. handle 的相等/判空、跨函数返回句柄（作为返回值）未接；句柄仅在局部声明/赋值/参数/close 中可用。

## 声明

执行侧自检；E5 会签待做。
