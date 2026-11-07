# 回执：S7-FFI-07 codegen（E4）

- 卡片：FFI-07（QA `验收-S7-FFI-07.md` 两项 FAIL；S7 §7.3 / FFI-07）
- 提交：见本次 commit（仅 pod/e4-codegen；前置 FFI-01 修复 `2f1bdf2`）
- 顺序：先红后绿
  - 红：`evidence/S7-FFI07/red.log`（无 companion thunk；清单按命名推导；跨文件误报）
  - 绿：`evidence/S7-FFI07/green.log`（TestFFI07* PASS）

## 一、结论

1. `.unaware + @longRunning` 的**调用点**现在生成 `xrt_companion_submit/wait` 路由：
   原生阻塞调用在伴生 worker 上执行，等待完成后在主/载体线程构造结果。
2. `BlockingManifest` 的 `Companion` 只报告**注册表实际存在**的 `submit<Entry>`；
   `Load` 增加全局（跨文件）companion 存在性校验，缺失 → `FFI-107` 构建失败。

## 二、红 → 绿

| 项 | 修前（红） | 修后（绿） |
|---|---|---|
| 调用点路由 | 直接 `xn_ffi_<entry>`，占载体线程 | 生成伴生 thunk + `xrt_companion_submit/wait` |
| companion 结构 | 无 | `xn_companion_<entry>_{args,thunk}`（typed 参数/结果槽） |
| 清单 Companion | 按 `"submit"+Name` 推导 | 查 `Registry.Entry`，未注册则为空 |
| 缺失校验 | 仅区域内检查，跨文件误报/漏报 | `Load` 全局校验，跨文件可见；缺失 `FFI-107` |
| 取消 | — | `xrt_companion_wait` 非 0 直接作为 rc（Cancelled 不降级） |

## 三、实现要点

- `ffi/emit.go`
  - `Entry.NeedsCompanion()`：`LongRunning && BlockingUnaware`。
  - `CompanionArgFields/CompanionOutC/CompanionThunkArgExprs`：按包装 ABI 生成参数结构，
    覆盖标量/String/Text/Bytes/layout/数组/句柄与 `.transfer` 句柄 out。
  - `emitCompanion`：`thunk` 只调用冻结包装 `xn_ffi_<entry>`（worker 上不触碰 GC API）。
  - `BlockingManifest`：companion 必须命中注册表。
- `ffi/load.go`：汇总全部区域后校验 `.unaware+@longRunning` 的 `submit<Entry>`，
  缺失报 `FFI-107` 并带文件/行/列（`Entry` 新增 File/Line/Col）。
- `codegen/ffi_gen.go`
  - `ffiInvokeLines`：伴生路由生成
    `args = {...}; future = submit(thunk,&args); wait(future,NULL,&dummy); release(future); rc=wait?wait:args.rc;`
    非伴生入口保持原直接调用。
  - Result 入口在 wait 之后照常构造 `Result<T, ErrorKind>`；String 临时在 wait 后释放。

## 四、端到端证据

`TestFFI07CompanionRoutingEndToEnd`：

- 生成 C 含 `xrt_companion_submit(`、`xrt_companion_wait(`、`xn_companion_ffiExec_thunk`、
  `xrt_release(`。
- 原生 stub 在 `xrt_companion_on_worker()` 为真时返回 `x`；运行输出 `7`
  （`XNULL_COMPANIONS=1`），证明调用在伴生 worker 上执行。
- `TestFFI07ManifestCompanionRegistry`：companion 存在/缺失/跨文件/不按命名推导四例。

## 五、验证

```bash
cd impl
go test ./internal/codegen/ -run 'TestFFI07' -count=1 -v
go test ./internal/codegen/ ./internal/codegen/ffi/ ./internal/cli/ ./internal/interp/ ./internal/sema/ -count=1
cd .. && sh impl/runtime/build_rt.sh
```

五套件全绿；运行时套件由 E5 维护（本次未改 runtime）。

## 六、边界

- 伴生 thunk 复用冻结包装 `xn_ffi_<entry>`；编组仍发生在调用线程，worker 只做原生阻塞调用。
- 无 `Context` 的现有语言面使用 `xrt_companion_wait(..., NULL, ...)`；任务级取消接入后
  可把当前 `Context` 传入，路由结构不变。
- `submit<Entry>` 只做合同存在性/清单校验，不改变用户调用面（用户仍调用原入口）。
