# 接力棒：BYTES-RUNTIME

- **卡片ID**：BYTES-RUNTIME（B0-07c numeric 的 E5 侧前置：运行时可变 Bytes 对象）
- **输入**（上游产物/条款/接口）：
  - 条款：S1 §9.7（`Bytes` 成员：`fromString/get/set/push/append/slice/length`）、S3 §188（GC 对象，头 + 可变字节区，字节区免扫描）、S7 §3.4（长度权威、内嵌 NUL）
  - 测试包：`tests/b0-07c-numeric/cases/t04_bytes_surface`、`t05_file_read`、`t06_file_write`
  - ABI 状态：`impl/docs/runtime-contract.md` A0（候选冻结，转正判据为 numeric 端到端）
  - 既有边界类型：`impl/runtime/xrt.h` 的 `xrt_bytes{data,len}`（视图，保持不动）
- **输出文件**（精确路径）：
  - `impl/runtime/rt_std_bytes.c`（对象与全部原语实现）
  - `impl/runtime/xrt.h`（`xrt_bytes_buf` 与 10 个公开符号）
  - `impl/runtime/test_std.c`（`test_bytes` / `test_bytes_bounds` / `test_bytes_file_io`）
  - `impl/runtime/build_rt.sh`、`impl/internal/codegen/build.go`、`impl/internal/codegen/build_test.go`、`impl/internal/codegen/ffi/xdk_test.go`、`xdk_text_test.go`、`xdk_write_test.go`（链接清单纳入 `rt_std_bytes.c`）
  - `impl/docs/runtime-contract.md`（A0 候选期增补）
  - `evidence/B0-07c/bytes-runtime/`：`probe.c`、`probe.sh`、`probe.log`、`build_rt.log`
- **commit**：`ce1356c`（pod/e5-runtime）
- **验证命令**（可复制）：
  ```bash
  cd impl/runtime && sh build_rt.sh                      # 六套件，exit 0
  cd impl && go test ./internal/codegen/... -count=1      # codegen + ffi 全绿
  sh evidence/B0-07c/bytes-runtime/probe.sh               # len=7 first=65 ok=1
  bash tests/b0-07c-numeric/run.sh --root . --bin <xnull> # t04 仍由 SEMA-BYTES 阻断（E2）
  ```
- **E4 发射面契约（回签，2026-11-07）**：
  - 类型用 `xrt_bytes_obj *`（`xrt_bytes_buf *` 的别名）；**不要**用 `xrt_bytes *`——它是既有 FFI 边界视图 `{data,len}`，无分配头、不可 `rt_release`；
  - 构造 `xrt_bytes_from_string(const char*, size_t)` 已加为 `xrt_bytes_from_c` 的同签名别名；
  - 字段一律走访问器：`xrt_bytes_len(b)` / `xrt_bytes_data(b)`（对象头部在前，`b->len`/`b->data` 偏移不稳定）；
  - 读写走 `xrt_bytes_get/set`（越界 fatal），追加走 `xrt_bytes_push`；FFI 形参传 `(xrt_bytes_data(b), xrt_bytes_len(b))`。
- **已知缺口/风险**：
  - **分配种类暂用 ARC**（与 String/类/容器一致，生成代码按作用域 `xrt_release`）。S3 §188 要求 GC 对象；切换点唯一（`bytes_new_cap` 的 `XRT_KIND_ARC` → `XRT_KIND_GC` + 补 scan 空钩子），但前提是 codegen 整体切到 GC 根登记，不在 B0-07c 范围。已记入 `runtime-contract.md` A0。
  - `Bytes` 的**语言面尚未可见**：`Bytes.fromString` 仍报 `RES-101`（E2 的成员面），codegen 也还没有 `Bytes` 的 `cType`/方法降级与 FFI 形参编组（E4）。本卡只保证运行时就绪。
  - `fileRead(f, buf, code)` 写入的是 `buf` 的**容量**区间；`len` 不随读入字节数变化（调用方用返回值 `got` 界定有效前缀）。若后续要求“读后 length=实际字节数”，需要新增 `xrt_bytes_truncate/set_len` 并改夹具口径——当前 B0-06 夹具不依赖该语义。
  - 越界一律 `xrt_fatal`（abort），与 S1 §9.7“panic”一致；`test_bytes_bounds` 用 fork 验证，不污染主进程。
- **下一步**（谁接、做什么）：
  1. E2：把 `Bytes` 成员面注册进 sema（`fromString/get/set/push/append/slice/length`，`import xdk.text` 后可见）——解 `SEMA-BYTES`；
  2. E4：codegen 增 `Bytes` 的 `cType`（`xrt_bytes_buf *`）、静态 `fromString` 与方法降级到本卡符号、FFI `KindBytes` 形参按 `(xrt_bytes_data(b), xrt_bytes_len(b))` 编组——解 `CG-BYTES-ARG`；
  3. E4 复跑 `tests/b0-07c-numeric/run.sh`，t04/t05/t06 应从 `SEMA-BYTES` 转为 PASS 或下一层真实缺口；
  4. 全绿后 E5 会签官方夹具并执行 ABI v1 转正（`handoff/E5-ABI-v1.md`）。
- **上一棒**：`handoff/B0-07c.md`（commit `26bc80c`，numeric 测试包与补点清单）
- **下一棒**：`handoff/B0-07c.md`（回填 BYTES-RUNTIME 已完成）→ E4 的 `CG-*` 修复 → `handoff/E5-ABI-v1.md`
- **last-green**：`ce1356c`（`build_rt.sh` 六套件 exit 0；`go test ./internal/codegen/...` ok；`probe.sh` 通过，日志 `evidence/B0-07c/bytes-runtime/`）
