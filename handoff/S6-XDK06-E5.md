# 接力棒：S6-XDK06-E5

- **卡片ID**：S6-XDK06（QA `验收-S6-XDK-06` FAIL 的 E5 runtime 补口）
- **输入**：`收件箱/回执箱/验收-S6-XDK-06.md`、`evidence/S6-QA/XDK-06/`、
  S6 §4.4 / S1 §10.3、main `d4f0209`
- **输出文件**：
  - `impl/internal/codegen/codegen.go`（dumpTasks → `xdkc_dump_tasks`）
  - `impl/internal/codegen/s504.go`（删除生成侧 task 计数）
  - `impl/internal/codegen/build.go`（`rt_std_res_empty.c` 进 runtimeCSources）
  - `impl/internal/codegen/build_test.go`、`s6_02_test.go`（清单/输出期望）
  - `impl/internal/sema/xdksig.go`（dumpTasks 签名）
  - `impl/internal/sema/s6_01_test.go`、`diagpos_test.go`（旧负例）
  - `impl/internal/interp/runtime_xdk.go`（new）
  - `impl/internal/interp/interp.go`（exitSignal + 桥挂载）
  - `impl/internal/interp/tasks.go`（liveTasks）
  - `impl/internal/interp/s6_xdk06_test.go`（new）
  - `impl/runtime/rt_std_runtime.c`（exit flush）
  - `impl/runtime/rt_task.c`、`test_task.c`（dumpTasks 行格式）
  - `impl/runtime/rt_std_res_empty.c`（new，弱兜底）
  - `impl/runtime/test_std.c`（exit 前输出冲刷）
  - `impl/runtime/test_res_empty.c`（new）、`build_rt.sh`
  - `impl/docs/runtime-contract.md`
  - `evidence/S6-XDK06-E5/`
- **commit**：见本次提交（`pod/e5-runtime`）
- **验证命令**：
  ```bash
  cd impl && go test ./internal/codegen -count=1 -run 'TestS6_0[234]'
  cd impl && go test ./internal/interp -count=1 -run 'TestS6XDK06'
  cd impl && go test ./internal/sema -count=1 -run 'TestS601|TestAllDiagPositionsNonZero'
  cd impl/runtime && sh build_rt.sh
  xnull run /tmp/xdk06_core.x && xnull run --interp /tmp/xdk06_core.x
  xnull check /tmp/xdk06_dump.x && xnull run /tmp/xdk06_dump.x
  xnull run /tmp/xdk06_exit.x   # rc=7，stdout before，无 defer
  ```
- **已知缺口/风险**：
  - `go test ./internal/codegen` 仍有 2 项 main 既有失败（Char 未支持、text.x 依赖矩阵），
    已在 main `d4f0209` 复核，非本卡。
  - 解释器 `dumpTasks` 的 live 是同步语义（体内 1/体外 0），不承诺与编译路径同值。
  - `dumpTasks` 输出字段非承诺；如需机器解析，应另立稳定诊断 API。
- **下一步**：QA 重跑 XDK-06 矩阵；E2/E3 确认跨线改动（sema/interp）可接受；
  main 合并按单会话互斥执行。
- **上一棒**：`handoff/S6-04-E5.md`（`080d6e8`）
- **下一棒**：QA `验收-S6-XDK-06` 复验
- **last-green**：本次提交（S6_02/03/04 + interp + sema + build_rt 全绿）
