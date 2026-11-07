# 回执：S6-XDK06（E5 runtime）

- 执行位：运行时线 E5
- 基线：main `d4f0209`
- 结论：**完成**——`dumpTasks` 走运行时计数、`exit` 保留既有输出、资源符号弱兜底、
  解释器补齐 runtime 桥；XDK-06 的 compiled/interp/check/gotest 四类证据均转绿
- 证据：`evidence/S6-XDK06-E5/`；接力棒 `handoff/S6-XDK06-E5.md`

## 修复对照（QA 失败项）

| QA 失败项 | 处理 |
| --- | --- |
| `dumpTasks` TY-229 | sema 增签名；删除旧负例 |
| `dumpTasks` 未用运行时 | codegen 改发 `xdkc_dump_tasks()`；删除生成侧计数 |
| 解释路径 rc=1（nowMono） | interp 新增 nowMono/nowWall/env/dumpTasks/exit 桥 |
| `exit` 丢既有输出 | `xdkc_exit` 先 `fflush(NULL)` 再 `_Exit` |
| Exit 测试缺资源符号 | `rt_std_res_empty.c` 弱兜底（强表覆盖） |

## 先红

- `xnull check dump.x` → `TY-229 XDK API dumpTasks 尚未支持`。
- `xnull run --interp core.x` → `未定义的函数：nowMono`。
- `go test ./internal/codegen -run TestS6_02` → RuntimeSurface/DumpTasks 红。

## 后绿

- compiled/interp `core.x`：rc=0，`true/true/true`，diagnose 单行。
- `xnull check dump.x`：rc=0。
- compiled `dump.x`：`tasks: live=0 spawned=0 settled=0 carrier=0`；
  interp `dump.x`：`tasks: live=0`。
- compiled/interp `exit.x`：stdout `before`，rc=7，无 defer。
- `TestS6_0[234]` 9/9 PASS；`TestS6XDK06` 3/3 PASS；sema 目标用例 PASS；
  `TestBuild*` PASS；`sh impl/runtime/build_rt.sh` 全套 exit 0（含 empty fallback）。

## 透明项

`go test ./internal/codegen` 全量仍有 2 项失败：`TestXdkSeedUnitCompiles`
（Char 未支持）、`TestXdkPackageSkeletons`（text.x 依赖矩阵）。已在 main `d4f0209`
干净工作树复核同样失败，非本卡引入；证据 `main-preexisting-failures.log`。

## 跨线改动（需 E2/E3 确认）

本次为解 XDK-06 门禁，直接改了 `sema/xdksig.go`（dumpTasks 签名）与
`interp/runtime_xdk.go`（runtime 桥）；如与 E2/E3 分支冲突，以本卡证据为准重放即可。
