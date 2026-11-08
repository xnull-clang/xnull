# B3-08 证据：FFI / XDK 面

## 结论

- `.xfb` 注册表投影由 `tests/b3/xfb-projection.py` 生成（B3 只消费注册表，不在 xnullc 内重写 `.xfb` 解析）。
- xnullc 消费注册表后生成：
  - 绑定层支撑代码（固定头 + canary、错误码分类、原生符号声明）；
  - `xn_ffi_<entry>` 包装（标量/String/Text/Bytes/句柄、`@errorCode` 通道）；
  - P-09 调用点：同步直调、String 编组、`@unaware + @longRunning` 伴生路由（`xrt_companion_submit/wait` + thunk）；
  - S4 错误码映射（`xn_ffi_<region>_error_kind[_id]`）。
- XDK 内建面：`xdk.runtime` 的 `env/nowMono/nowWall/diagnose/dumpTasks` 与 `exit` 发射面对齐。

## 验收

```text
PASS ffi-cases/basic/add.x
PASS ffi-cases/err/wrap.x
PASS ffi-cases/comp/exec.x
PASS fixtures/xdk/runtime.x
PASS fixtures/xdk/exit.x
xnullc-ffi 汇总：PASS=5 FAIL=0
```

- 先红：空 stub `PASS=0`（`red.out`）；绿 `PASS=5 FAIL=0`（`green.out`）。
- `hashes.out`：5 个锚点 Go `--emit-c` 与 XNull C SHA-256 相同；两次生成 SHA-256 相同。
- 双路径：Go 生成 C 与 xnullc 生成 C 用同一 cc/运行时（FFI 附原生 `.c`）编译运行，stdout/退出码一致；伴生用例带 `XNULL_COMPANIONS=1`。
- `bash tests/b3/run.sh` 全绿（`run-all.out`）。

## 边界（明确遗留）

- `xdk.sync` / `xdk.tasks` / `xdk.collections` / `xdk.text` 依赖 import 闭包（多文件 AST 合并），xnullc 当前只接收入口文件 AST，本卡未覆盖 S5/这些 XDK 源码面。
- 错误码调用点 `Result<T, ErrorKind>` 需要 `import xdk.errors`（会引入 `CauseError` 等类），本卡只验证包装文本与错误分类，不验证该调用点整文件 C。
- 未改 Go codegen/oracle、未改 `xparser.x` 语义。
