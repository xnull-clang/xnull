# M6-B0-01（P-09）验收结论（执行侧自检，E5 会签未做）

卡片：codegen 把 `.xfb` 入口注入为包级可调用声明，调用点使用 `xn_ffi_<entry>`。
依据：死命令第 1 号 1.4 / 董事会判决 v1.9.0 第 3 条 / runtime-contract P-09（三条条件）。

| 验收项 | 判据 | 实测 |
| --- | --- | --- |
| 入口注入 | `.xfb` 入口在 sema 前成为包级函数声明 | 通过：`InjectFFI` 追加合成 `TopFunc`；注入后 `sema.Analyze` 零诊断 |
| 调用点改写 | 生成 C 调用 `xn_ffi_<entry>`，不是 `xn_<entry>` | 通过：`sample/prog.c` 中 `xn_ffi_ffiAdd` / `xn_ffi_ffiByteLen`；测试断言无普通函数定义 |
| 样例编译+运行 | 样例 `.xfb` 调用编译并运行正确 | 通过：`5\n5\n`，exit 0（手工链接原生符号；xnull build 链接清单属 P-10） |
| 双路径一致 | 与解释路径 stdout 一致 | 通过：等价纯 XNull oracle 解释输出逐字节相同（解释器无 FFI 面，属 E3 域） |
| P-09 条件 1 | 入口符号唯一 + 单元内重名防御 | 通过：`ffi.Load` FFI-111 跨块重名；`InjectFFI` 对单元内同名显式报错（`TestFFIInjectionDuplicateNameRejected`） |
| P-09 条件 2 | 错误码不隐藏 | 非零即 `fatal`（带 `xn_ffi_<region>_error_kind` 分类，未知码 Internal），退出 134；含 `@errorCode` 的入口本轮不注入（构建侧打印提示，调用报未定义） |
| P-09 条件 3 | 编组所有权 | String 入参 `.borrow` 只传 bytes/len、不 retain；返回 String 由包装产物移交调用方 |
| 确定性 | 同输入同输出 | 注册表排序由 ffi.Load 保证；注入按注册表顺序；支撑代码文本确定 |

## 覆盖面（本轮显式边界）

- 注入形态：返回 `void` / `Int`（Int/Int64）/ `String`；参数 `Int`（Int/Int64）与 `String`（`.borrow`）。
- 未注入（跳过并提示，不静默）：`handle`、`Bytes`、`Int32` 等标量、数组、`layout(c)`、含 `@errorCode` 的入口、`.reclaim`/close 入口。
- 原因：这些形态需要 Result 映射或跨边界对象/缓冲区语义，属 P-09 后续增量（B0 出口程序依赖 `bindings/xdk/sys.xfb`，其 handle/Bytes/errorCode 面尚未注入）。

## 未测项

1. 含 `@errorCode` 入口的 Result 映射（call site 错误分类 → `Result`）未实现。
2. 句柄/Bytes/数组/layout(c) 编组的调用点（包装层已具备，codegen 侧未接）。
3. `xnull build` 链接清单未纳入 `xrt_abi.c`/`rt_std_*.c`/`LinkArgs`（P-10，E6）；本卡样例手工链接。
4. 解释路径无 FFI 面（E3 域），双路径用等价纯 XNull oracle 对照。
5. 跨任务/调度器语义不在本卡。

## 声明

执行侧自检；E5 会签与 B0 门禁另判。
