# B0-07c numeric 前置测试包

给 E4（codegen）的最小可执行验收面：把 B0-06 numeric 夹具（`wt/qa-1/evidence/M6-B0-06/program/read_parse_write.x`）
依赖的六项能力拆成互不掩盖的小用例，构建失败按诊断标签分层，避免“一跑就是 0/2，不知道卡在哪”。

- 卡片：B0-07c（numeric 变体前置）
- owner：E5 出包；E4 修 codegen；E2 修 sema 面；E5 修运行时/包装层
- 语义依据：S1 §9.7（Bytes）、S6 §3/§4.7（文件句柄）、S7 §3.4/§5.1/§7.1（Bytes 借用、包装 ABI、错误码）、
  `impl/docs/ffi-contract.md` §5.1、`impl/docs/runtime-contract.md` P-09 条件 2

## 用法

```bash
# 在被测树上构建 xnull 并跑全部用例（只读，不修改被测树）
bash tests/b0-07c-numeric/run.sh --root /path/to/repo

# 用现成二进制 / 指定运行时源码目录 / 只跑某个用例
bash tests/b0-07c-numeric/run.sh --root /path/to/repo --bin /tmp/xnull
bash tests/b0-07c-numeric/run.sh --root /path/to/repo --runtime /path/to/impl/runtime --case t03
```

退出码：`0` 全 PASS；`3` 有 BLOCKED（构建失败，已归类）；`1` 有 FAIL（构建通过但行为不符）。

## 用例

| 用例 | 覆盖 | 当前阻塞标签 | 归属 |
| --- | --- | --- | --- |
| `t00_sanity_text` | `readFileText`/`writeFileText` 文本变体（B0-07b 已可用） | — | E5（基线护栏） |
| `t01_handle_open_close` | `File` 返回 + `fileClose` 返回 `Bool` | — | E4（已实现，回归护栏） |
| `t02_option_handle` | `File?` + `f == null` + 守卫内收窄为 `File`；失败打开必须回 null | `SEMA-NARROW`；其后 `CG-OPTION-HANDLE` | E2（收窄）/ E4（可空 handle 代码生成）/ E5（包装层 NULL） |
| `t03_scalars` | `Int32`/`Int64` 变量、字面量、算术、比较 | `CG-INT32`（随后 `CG-INT64`） | E4 |
| `t04_bytes_surface` | `Bytes.fromString/push/get/length`（无 FFI） | `SEMA-BYTES` | E2（成员面）/ E5（运行时对象）/ E4（代码生成） |
| `t05_file_read` | `Bytes` 缓冲 + `@errorCode` 出参 + `Int64` 返回 | `SEMA-BYTES` `CG-ERRORCODE` `SEMA-NARROW` | E4 + E5 |
| `t06_file_write` | `File?` 写打开 + `Bytes` 实参 + `Int32` 返回 + `@errorCode`；产物逐字节 `41 00 42` | `SEMA-BYTES` `CG-ERRORCODE` `SEMA-NARROW` | E4 + E5 |

标签只表示**第一层**阻塞（sema 先于 codegen）；同一用例去掉前一层后会暴露下一层。

## 标签表

| 标签 | 诊断特征 | 含义 |
| --- | --- | --- |
| `CG-INT32` / `CG-INT64` | `类型 Int32/Int64 未支持（M4.1 范围）` | `codegen.cType` 未映射 32/64 位标量 |
| `CG-OPTION-HANDLE` | `可空类型 xrt_handle * 未支持` | `containers.go::optName` 未支持可空句柄 |
| `CG-BYTES-ARG` | `参数 buf 类型 Bytes 未纳入` | FFI 注入未接受 `Bytes` 形参 |
| `CG-ERRORCODE` | `未定义的名称 fileRead/fileWrite`（因 `@errorCode` 被跳过注入） | 非 close 的错误码通道未接 |
| `CG-INT32-RET` | `返回标量 Int32 未纳入` | 标量返回宽度未接 |
| `SEMA-BYTES` | ``未定义的名称 `Bytes` `` | `Bytes` 成员面（fromString 等）未进入名字空间 |
| `SEMA-NARROW` | `实参 1 类型 File? 不能赋给形参 File` | null 守卫后未收窄 |

## 语义口径（写用例时就按这个，不按实现现状）

1. **句柄与可空**：打开失败返回 `null`，不 panic（S6 §3 第 1 条）。
   包装层必须把原生 `NULL` 原样回 `NULL`；包成 `native == NULL` 的句柄会让 `f == null` 永远为假（已修，见 `impl/internal/codegen/ffi/emit.go` 的 handle 返回通道）。
2. **Bytes**：`fromString` 复制字节；`push` 追加单字节；`get` 按索引；`length` 返回字节数；
   允许内嵌 NUL，长度权威（S1 §9.7 / S7 §3.4）。FFI 实参按 `(data, len)` 借出，canary 校验越界写。
3. **@errorCode 出参**：`@errorCode(codeParam = .code)` 的形参不出现在包装签名里（ffi-contract §5.1）；
   B0-06 夹具的调用形态是 `Int64 got = fileRead(f, buf, code)`——调用后 `code` 必须是归一后的错误码（0=成功）。
   非零码不得静默吞掉（P-09 条件 2）；是否进一步映射为 `Result` 属决策点，见 `handoff/B0-07c.md`。
4. **Int32/Int64**：`Int32` 为 32 位有符号、`Int64` 为 64 位有符号；包装层返回出参必须是 `int32_t*`/`int64_t*`，
   不能一律用 `int64_t`（`ffi_gen.go` 现有实现对所有标量用 `int64_t`，需按声明宽度分派）。

## 基线（2026-11-07，E4 `d948276` + 未套 E5 修复）

```
PASS=2  BLOCKED=5  FAIL=0
t00 PASS / t01 PASS
t02 SEMA-NARROW / t03 CG-INT32 / t04 SEMA-BYTES / t05 SEMA-BYTES+CG-ERRORCODE+SEMA-NARROW
t06 SEMA-BYTES+CG-ERRORCODE+SEMA-NARROW
```

原始输出：`evidence/B0-07c/numeric-pack-baseline.log`。

## 复跑前置（重要）

- `impl/runtime/xrt_abi.c` 必须含 `e83f93c`（`handle_deinit` 用 `rt_payload(payload)`）。
  没有它，close 后仍打印 `xrt: 句柄泄漏`，t01/t02 会被误判。执行器会在预检里警告。
- 包装层 NULL 修复（`emit.go` handle 返回通道）必须在被测树内，否则 t02 的“失败打开”检查会 FAIL。
