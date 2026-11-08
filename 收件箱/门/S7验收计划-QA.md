# S7 验收计划（QA1）：S7-02 / S7-03

> **版本**：v0.1（验收准备）　**日期**：2026-11-08
> **性质**：用例、命令、证据路径与判定口径；**尚未执行验收，不签 PASS**
> **范围**：S7-02（FFI 错误码 → Result）、S7-03（trampoline 集成）
> **规范映射**：S7-02 → FFI-01（错误码/合同面）；S7-03 → FFI-05（trampoline）
> **依据**：`XNull解决方案-第7部分-FFI-v1.0.0.md` §5/§7/§10、S4 §7.3、S3 §19/§22、S2 §14.5
> **执行前置**：E4 codegen 错误码→Result 与 trampoline 集成、E5 runtime callback env/根登记落地；S7-01/S7-05 已签。

## 0. 先给结论（当前状态）

| 卡片 | 锚点 | 当前状态 | 原因 |
|---|---|---|---|
| **S7-02** | FFI-01 | **BLOCKED** | `emit.go` 对非零错误码仍走 `fprintf + exit(134)`，未构造 `Err(ErrorKind)`；`errorMap` 只生成分类 helper，未交付 Result |
| **S7-03** | FFI-05 | **PARTIAL / BLOCKED** | `EmitTrampoline` 可生成 `xn_tramp_*` 与 `xrt_callback_env_*` 支撑；尚无 XNull 回调参数/闭包集成，也无“注销后调用检测”的端到端用例 |

> 本计划不把“已生成 helper / 已有 C 原语”记 PASS；只有 A/R/M/D 用例全部可执行并通过才签。

## 1. 分层与判定口径

| 层 | 验什么 | 入口 |
|---|---|---|
| 合同层 | `.xfb` 解析、`@errorCode`/租约/闭包参数合法性、拒绝面 | `go test ./internal/codegen/ffi/` |
| 发射层 | 生成 C 的错误码→Result、trampoline 符号与根登记 | `EmitCWithFFI` / `EmitTrampoline` |
| 运行时层 | `xrt_callback_env_*`、根登记/注销、注销后调用 fatal、panic fatal | `sh impl/runtime/build_rt.sh` |
| 端到端 | `.x` → `xnull build` → 运行；错误码/回调行为与期望一致 | `xnull build`/`run` + C stub |

**PASS**：该卡片全部 A/R/M/D 用例通过；未知码不降级；无 panic/exit 误用；证据五件套齐全。  
**BLOCKED**：E4/E5 依赖未落地；不得以“未支持”诊断记 PASS。  
**FAIL**：已可执行但行为不符（映射错、trampoline 生命周期错、注销后调用未被检测等）。

## 2. S7-02（FFI 错误码 → Result）

### 2.1 用例矩阵

| ID | 类型 | 夹具 | 期望 |
|---|---|---|---|
| `S7-02-A01` | A | `errorMap { 5 = NotFound }`；C stub 返回 0 + 值 | 返回 `Ok(v)`；不进入错误分支 |
| `S7-02-A02` | A | 同 A01；C stub 返回 5 | 返回 `Err(ErrorKind.NotFound)`；`kind()` 稳定 |
| `S7-02-A03` | A | 同 A01；C stub 返回 99（未登记） | 返回 `Err(ErrorKind.Internal)`；**绝不 Ok** |
| `S7-02-A04` | A | `errorMap { 14 = Cancelled, 15 = Timeout }`；C 返回 14/15 | `Err(Cancelled)` / `Err(Timeout)`；不降级 Internal |
| `S7-02-A05` | A | 多入口/多 errorMap（乱序声明） | 映射确定；重复码取首个/按冻结规则；两次构建 hash 一致 |
| `S7-02-A06` | A | `Err` 值携带业务错误类型 | `join`/普通调用把 `Err(E)` 原样交付；`kind()/describe()` 不被改写 |
| `S7-02-R01` | R | `@errorCode(codeParam = .nope)` / 缺 `@errorCode` 但入口非 0 错误 | `FFI-105/106` + 位置；合同拒绝 |
| `S7-02-R02` | R | `.xfb` 签名含 `Result` | `FFI-105`（S7 §3.6 / BOUND-02） |
| `S7-02-R03` | R | C 返回非零且无 errorMap 条目 | 运行期 `Err(Internal)`，不得 Ok/静默成功 |
| `S7-02-M01` | M | 非零错误码后进程状态 | 不再 `exit(134)`；调用方决定观测/传播；无资源泄漏 |
| `S7-02-D01` | D | A01/A02/A03 | 同一 `.x` 两次构建生成 C 的映射一致；运行输出一致 |

### 2.2 夹具结构（待落盘）

```text
tests/s7/s7_02/
  bindings/native.xfb      # errorMap + @ffiEntry + @errorCode + @lease
  stub.c                   # int32_t native_call(int32_t in, int32_t *out)
  ok.x / err.x / unknown.x # 调用入口并按 Result 分支观测
  expect/*.txt
```

### 2.3 命令

```bash
cd impl
go test ./internal/codegen/ffi -run 'TestErrorKindEnumHelper|TestXdkWrappersRun|TestContractNegatives' -count=1 -v
sh impl/runtime/build_rt.sh

# 端到端（待 E4 落地）
X=/tmp/xnull-s7-02
(cd impl && go build -o "$X" ./cmd/xnull)
"$X" build tests/s7/s7_02/ok.x -o /tmp/s7_02_ok
/tmp/s7_02_ok
```

### 2.4 证据路径

```text
evidence/S7-QA/S7-02/<case>/
  cmd.txt
  source/                 # .x + .xfb + stub.c
  stdout.txt / stderr.txt
  exit_code.txt
  generated.c             # EmitC 产物（如可得）
  sha.txt                 # main sha + 二进制 sha256
evidence/S7-QA/S7-02/matrix.tsv
evidence/S7-QA/S7-02/ffi-tests.log
```

## 3. S7-03（trampoline 集成）

### 3.1 用例矩阵

| ID | 类型 | 夹具 | 期望 |
|---|---|---|---|
| `S7-03-A01` | A | `.xfb` 入口含回调参数；`EmitTrampoline` | 生成 `xn_tramp_<entry>_new/destroy`、`int32_t xn_tramp_<entry>(env,args,n,res)`；env 创建登记根 |
| `S7-03-A02` | A | C stub 持有 callback env 并调用 | XNull 闭包被执行，返回值/错误码正确回传 |
| `S7-03-A03` | A | 回调内产生错误码 14/15/未知 | `Err(Cancelled/Timeout/Internal)`；取消/超时不降级 |
| `S7-03-A04` | A | `destroy` 后弱读 env | 根注销：弱读 NULL；原生再调用 `xn_tramp_*` → 进程 fatal（非静默） |
| `S7-03-A05` | A | 回调内 `throw`/panic | 进程终止（rc=134）；无任务级隔离 |
| `S7-03-R01` | R | 回调参数缺租约/签名非法 | `FFI-105/106` + 位置 |
| `S7-03-M01` | M | trampoline 存活期间 GC 压力 | env/closure 不被提前回收；destroy 后可回收 |
| `S7-03-D01` | T | 同源两次构建 | 生成 C 的 trampoline 符号/根操作一致；运行输出一致 |

### 3.2 夹具结构

```text
tests/s7/s7_03/
  bindings/native.xfb      # 回调参数 + @lease + @errorCode
  host.c                   # 接收 callback env，调用 1 次/2 次/注销后再调用
  main.x                   # 创建闭包，交原生调用，断言语义
  destroy_after.x          # 注销后调用 → 期望 fatal
  panic.x                  # 回调内 throw → 期望 134
```

### 3.3 命令

```bash
cd impl
go test ./internal/codegen/ffi -run 'TestTrampolineGenerated' -count=1 -v
sh impl/runtime/build_rt.sh          # test_abi_link / test_std callback env

# 端到端（待 E4/E5 落地）
X=/tmp/xnull-s7-03
(cd impl && go build -o "$X" ./cmd/xnull)
"$X" build tests/s7/s7_03/main.x -o /tmp/s7_03_host
/tmp/s7_03_host
```

### 3.4 证据路径

```text
evidence/S7-QA/S7-03/<case>/
  cmd.txt
  source/                 # .x + .xfb + host.c
  stdout.txt / stderr.txt / exit_code.txt
  generated.c
  sha.txt
evidence/S7-QA/S7-03/matrix.tsv
evidence/S7-QA/S7-03/runtime-build.log
```

## 4. 执行顺序（E4/E5 落地后）

1. 记录 main sha 与 E4/E5 提交；`git log` 由执行时的 QA 流程记录（本计划不执行 git）。
2. 跑合同层：`go test ./internal/codegen/ffi/...`；失败先归合同层。
3. 跑运行时：`sh impl/runtime/build_rt.sh`；callback env/根登记必须绿。
4. 跑 S7-02 A01–A06/R01–R03/M01/D01；再跑 S7-03 A01–A05/R01/M01/D01。
5. 每个用例落五件套；在 `matrix.tsv` 记 `id/anchor/mode/expect/actual/verdict`。
6. 全部通过才写：
   - `收件箱/回执箱/验收-S7-02.md`（或 `验收-S7-FFI-01.md`，按门命名口径）
   - `收件箱/回执箱/验收-S7-03.md`（或 `验收-S7-FFI-05.md`）
7. 任一依赖未落地 → 对应卡片 `BLOCKED`，不得以“未支持/未实现”诊断记 PASS。

## 5. 当前阻塞与技术债

| # | 阻塞 | 证据 | 归属 |
|---:|---|---|---|
| B-01 | FFI 非零错误码仍 `exit(134)`，无 Result | `impl/internal/codegen/ffi/emit.go` 包装尾部 | E4 S7-02 |
| B-02 | `errorMap` 只生成分类 helper；未知码 `Internal` 未接到 XNull `Err` | `emitErrorKind` + `xn_ffi_*_error_kind_id` | E4 |
| B-03 | trampoline 只有 helper，无 XNull 回调参数/闭包集成 | `EmitTrampoline`；`test_abi_link` 仅 raw env | E4/E5 S7-03 |
| B-04 | 注销后调用/panic 的端到端进程级用例未落盘 | `test_abi_link` 有 raw fatal 用例 | QA/E5 |

## 6. 证据与签字规则

- 证据统一落 `evidence/S7-QA/S7-02/`、`evidence/S7-QA/S7-03/`（不覆盖 S7-01/S7-05）。
- 每例必须有 `cmd.txt/stdout.txt/stderr.txt/exit_code.txt/sha.txt`；C 端失败附 `generated.c`。
- 负例断言 `file:line:col` + `FFI-*` 码；禁止只断言“失败”。
- 未实现项标 `BLOCKED`，不得用“未支持”诊断当 PASS。
- 本计划只准备用例与命令；执行后另写根验收文件，不在此文件内签 PASS。
