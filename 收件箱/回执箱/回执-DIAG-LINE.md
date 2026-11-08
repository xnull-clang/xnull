# 回执：DIAG-LINE 诊断映射（E4）

- 结论：**已落地**。生成 C 的语句前输出 `#line <行> "<源文件>"`，cc 诊断映射回 `.x:行`。
- 红：`evidence/DIAG-LINE/red.log`（无 `#line` 时指向 `prog.c:409`）。
- 绿：`evidence/DIAG-LINE/green.log`（`main.x:2`，`TestDiagLineMapping` PASS）。

## 实现

- `Options.SrcPath`：构建入口写入源路径；`emitC` 保存到 `gen.srcPath`。
- `scope.lineDirective`：按语句位置输出 `#line`；`stmtPos` 按具体语句类型读取
  `P`（`xfront.Stmt.Pos()` 当前返回空）。
- `emitBlock` 在每个语句前插入指令；路径中的 `\` / `"` 转义。
- 公开 `EmitC*` 无路径时只输出行号或省略，不改变既有调用面。

## 用例

`TestDiagLineMapping`：`.x` 中声明 `Int xn_t1`，与 codegen 内部临时 `xn_t1`
冲突，触发 cc 重定义；断言错误行指向 `main.x:2`，且 `error:` 行不含 `prog.c:`。
（附带的 `note:` 仍可能指向生成 C，属 cc 的“前一定义”提示。）

## 附带修复（同一提交）

- `Result<HttpResponse, ErrorKind>`：恢复 E5 net.xfb 的 `HttpResponse` 句柄与
  `xdkc_http_*` 符号；`resultCType` 支持句柄类型。
- 容器 typedef 顺序：先输出类前向 typedef，再输出容器 typedef，最后类/函数原型；
  预登记签名与 Result 成员容器；Map helper 尊重 `skipDecl`，避免重复 typedef。
- FFI String 返回：包装层用 `xrt_string *`（仅含 xrt.h 的支撑代码可编译），
  XNull 侧按 `rt_string *` 收取。

## 验证

```bash
cd impl
go test ./internal/codegen/ -run 'TestDiagLineMapping' -count=1   # PASS
go test ./internal/codegen/ -run 'TestS609' -count=1              # PASS
go test ./internal/codegen/ffi/ -count=1                          # PASS
go test ./internal/cli/ ./internal/interp/ ./internal/sema/ -count=1  # PASS
```

说明：codegen 全量包单次运行超过默认 10 分钟超时（`panic: test timed out`，
非用例失败）；分套件/定向运行均绿。
