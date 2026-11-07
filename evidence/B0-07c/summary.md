# B0-07c（E5 运行时侧）证据：fileClose 假泄漏修复 + numeric 变体现状

- 日期：2026-11-07
- 卡：B0-07c（E4 主责 codegen；E5 会签 runtime/FFI）
- 工作树：`wt/e5-runtime`（pod/e5-runtime），基线 `main` = `548a06d`
- 结论：**E5 侧缺陷已修**（句柄 deinit 误读分配头导致 close 后仍报“句柄泄漏”）；numeric 变体仍被 E4/E2 面阻塞（Bytes/`@errorCode`/`Option<handle>`/Bool），未越界代做。

## 1. 缺陷与修复

- 现象（E4 独立复现）：`xrt_handle_mark_closed` 后再 `xrt_release`，stderr 仍输出
  `xrt: 句柄泄漏：未显式 close（S7 §4.3）`。
- 根因：`rt.c` 的终结链把**完整对象指针**传给 `rt_type.deinit`（`rt.h` 约定，与 scan 同），
  而 `xrt_abi.c::handle_deinit` 直接把该指针当 `handle_payload*` 读，读到的是 `rt_header`。
- 修复：`handle_deinit` 先取 `rt_payload(payload)`（1 行语义修复 + 注释）。
- 未改：`rt.c` 的 deinit 约定（M3 冻结段）、`xrt.h` 签名、`handle_payload` 布局。

## 2. 先红后绿

| 阶段 | 命令 | 结果 |
| --- | --- | --- |
| 红 | 用修复前的 `xrt_abi.c` 编 `test_abi` | 2 项 FAIL（`test_abi.c:129`/`:135`：close/mark_closed 后 deinit 仍写 stderr） |
| 绿 | 修复后同命令 | `abi 测试通过` exit 0 |
| E4 复现程序 | `xrt-handle-deinit-repro.c` + 修复后运行时 | 无泄漏输出，exit 0 |

原始日志：`before.build.log`、`before.run.log`、`repro.after.log`、`build_rt.log`。

## 3. 回归

`sh impl/runtime/build_rt.sh` → **exit 0**，六套件全过（rt/gc/hard/abi/std/res），`-Werror` 零警告。

## 4. numeric 变体端到端现状（E4 分支 + 本修复，只读验证）

方法：detached worktree 取 `pod/e4-codegen`（`0d8c985`，已合 main），套用本修复，跑
`evidence/M6-B0-06/run.sh --bin <xnull>`（完整命令 `numeric-command.md`）。

结果：`PASS=0 FAIL=2`（in1.x / in2.x 均 BUILD FAILED），**句柄相关错误已消失**
（`fileOpenRead`/`fileOpenWrite`/`fileClose` 不再报未定义），剩余阻塞：

| 残留错误 | 出现次数 | 归属 |
| --- | --- | --- |
| `未定义的名称 Bytes`（RES-101） | 6 | E4 codegen（Bytes 类型面未接） |
| `fileRead`/`fileWrite 含错误码通道（@errorCode）未接入 Result 映射` | 2 提示 ×2 fixture | E4 codegen |
| `实参 1 类型 File? 不能赋给形参 File`（TY-101） | 4 | E2/E4（Option<handle> 面） |

`pathExists` 的 Bool 返回已不再阻塞。原始日志：`numeric-after.log`（sha256 `58f1caab…`）。

## 5. 边界

- 本卡 E5 只改 `impl/runtime/xrt_abi.c` 与 `impl/runtime/test_abi.c`；未改 codegen/sema/xfront，未改测试期望、未删测试。
- 未提交 E4 分支内容；numeric 端到端判据转由 E4 完成后复跑，E5 会签。
- ABI v1 仍为“候选冻结”，转正判据（numeric/句柄端到端通过）尚不满足。
